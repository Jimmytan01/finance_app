# Finance App — Architecture

Aplikasi pencatat keuangan pribadi, offline-first, multi-device (desktop + mobile) dengan sinkronisasi otomatis via Supabase.

---

## Tech Stack

| Layer | Teknologi | Alasan |
|---|---|---|
| UI framework | Flutter | Satu codebase untuk Windows, macOS, Linux, Android, iOS |
| State management | Riverpod | Reactive, testable, tidak ada boilerplate berlebihan |
| Database lokal | Drift (SQLite) | Offline-first, type-safe query builder |
| Backend | Supabase (PostgreSQL + Auth + Realtime) | Auth, database, dan realtime dalam satu paket |
| Chart | fl_chart | Bar chart & pie chart di halaman Laporan |

---

## Prinsip Arsitektur: Local-First, Sync Second

Semua baca dan tulis data **selalu** lewat SQLite lokal terlebih dahulu. Supabase adalah *source of truth* untuk sinkronisasi antar device, bukan jalur utama tempat UI mengambil data.

```
WRITE:  UI → SQLite lokal → SyncQueue → Supabase (kalau online)
READ:   UI ← SQLite lokal (selalu, tanpa syarat online)
PULL:   App start / reconnect / realtime event → Supabase → SQLite lokal
PUSH:   SyncQueue flusher → Supabase (debounced 500ms setelah tiap write)
```

Konsekuensi dari prinsip ini: app tetap 100% berfungsi tanpa internet. Transaksi, split bill, dan laporan semuanya bisa dibuat dan dilihat offline. Sync hanya menambahkan lapisan konsistensi antar device di atas itu.

---

## Struktur Folder

```
lib/
├── main.dart                          # Entry point, AuthGate, provider overrides
│
├── core/
│   ├── database/
│   │   ├── app_database.dart          # Semua Drift table + DAO
│   │   └── app_database.g.dart        # Generated (jangan diedit manual)
│   ├── providers/
│   │   └── database_providers.dart    # Expose AppDatabase & DAO ke Riverpod
│   ├── auth/
│   │   ├── auth_service.dart          # Wrapper Supabase auth + device registration
│   │   └── auth_providers.dart        # Auth state, SyncNotifier
│   └── sync/
│       ├── sync_service.dart          # Engine sync: push, pull, reconcile delete
│       ├── sync_aware_service.dart    # Wrapper TransactionService + auto-enqueue
│       └── sync_aware_bill_service.dart # Wrapper BillService + auto-enqueue
│
└── features/
    ├── transactions/    # Catat pengeluaran, form dinamis per item
    ├── history/         # Riwayat lintas bulan, search & filter
    ├── report/          # Bar chart bulanan, pie chart kategori, drill-down
    ├── bill/             # Split bill 3-step, kalkulasi proporsional
    ├── auth/             # Login/register screen
    └── settings/         # Profil, status sync, pull ulang, perbaiki data lokal
```

Tiap feature folder konsisten punya sub-folder `services/`, `providers/`, `screens/`.

---

## Skema Database

### Tabel utama (Supabase & Drift identik strukturnya)

```
categories              — Makan, Transport, Kebutuhan, Laundry (4 kategori tetap)
transactions            — header pengeluaran (tanggal, tempat, total)
transaction_items       — rincian per item (nama, harga satuan, qty, diskon, kategori)
bill_sessions           — sesi split bill (diskon, pajak, link ke transaksi)
bill_participants       — peserta dalam satu sesi split bill
bill_items              — item dalam sesi split bill
bill_item_participants  — pivot: siapa pesan apa, berapa porsi
devices                 — registry device per user (untuk tracking last_sync_at)
```

### Tabel khusus lokal (hanya di SQLite, tidak ada di Supabase)

```
sync_queue  — antrian perubahan yang belum ter-push ke Supabase
             (target_table, record_id, operation, payload JSON, retry_count)
```

Catatan penamaan: kolom `target_table` (bukan `table_name`) karena Drift punya getter internal bernama `tableName` di tiap class Table — nama kolom yang sama akan konflik dan gagal di-generate.

---

## Alur Sync — Detail

### 1. Setiap kali user menyimpan data (`SyncAware*Service`)

```
1. Tulis ke SQLite lokal via parent service (TransactionService / BillService)
2. Ambil kembali data yang baru tersimpan dari DB
   (penting: UUID final di-assign oleh parent, bukan dari input form —
    kalau enqueue pakai UUID dari input, akan mismatch dengan yang di lokal
    dan menyebabkan data dobel saat pull)
3. Enqueue ke sync_queue untuk tiap tabel terkait
4. Kalau online, langsung flush queue setelah debounce 500ms
```

### 2. Update transaksi/bill yang sudah ada

```
1. Ambil item/child records LAMA dari DB (sebelum parent hapus & insert ulang)
2. Panggil parent (hapus lokal lama, insert lokal baru dengan UUID baru)
3. Enqueue DELETE untuk setiap item lama (supaya Supabase ikut hapus versi lama)
4. Ambil item BARU dari DB, enqueue INSERT
```

Ini poin krusial yang pernah jadi bug: kalau step 3 dilewati, Supabase akan punya item lama + item baru sekaligus, dan saat pull, keduanya masuk ke lokal → data dobel.

### 3. Pull dari Supabase (`pullDelta`)

```
Tabel parent (punya user_id): categories, transactions, bill_sessions
  → filter .eq('user_id', userId), lalu .gt('updated_at', lastSync) kalau ada

Tabel child (tidak punya user_id): transaction_items, bill_participants,
bill_items, bill_item_participants
  → filter via ID parent yang sudah ada di lokal (.inFilter())
  → tidak bisa filter langsung by user_id karena kolom itu tidak ada
```

### 4. Reconcile delete (`_reconcileDeletes`)

Dipanggil setelah setiap pull. Membandingkan ID transaksi/bill_session di Supabase vs lokal — yang ada di lokal tapi tidak di server berarti sudah dihapus dari device lain, lalu dihapus juga di lokal (cascade manual ke child-nya).

Tanpa langkah ini, delete dari satu device tidak akan pernah terlihat di device lain.

### 5. Realtime

Supabase Postgres Changes subscription pada tabel `transactions`, filter `user_id = current user`. Setiap event trigger `fullSync()` (bukan cuma `pullDelta()`) supaya reconcile delete juga ikut jalan.

### 6. `syncTickProvider` — jembatan sync ke UI

Riverpod provider tidak otomatis tahu kalau SQLite berubah dari proses sync di background. `syncTickProvider` adalah counter yang di-increment setiap kali `fullSync()` sukses. Semua `FutureProvider` yang menyajikan data ke UI (`monthlyTransactionsProvider`, `monthlyCategorySummaryProvider`, `billSessionListProvider`, dll) melakukan `ref.watch(syncTickProvider)` di awal — begitu counter naik, provider itu di-invalidate dan query ulang dari SQLite.

---

## Kalkulasi Split Bill

Logika inti ada di `BillService.calculate()`, pure Dart tanpa dependency Flutter:

```
1. raw_share tiap peserta = jumlah subtotal item yang mereka pesan,
   proporsional terhadap porsi (share_qty) yang diambil
2. subtotal_total = sum semua raw_share
3. discount_amount = subtotal_total × persen ATAU nilai flat (clamp ke subtotal)
4. tax_amount = (subtotal_total − discount_amount) × persen pajak
5. Per peserta:
     proportion = raw_share / subtotal_total
     discount_share = discount_amount × proportion
     tax_share      = tax_amount × proportion
     final_amount   = raw_share − discount_share + tax_share
```

Diskon dan pajak didistribusikan proporsional — peserta yang pesan lebih mahal menanggung porsi diskon/pajak yang lebih besar juga. Hasil akhir dibulatkan ke Rp 1 terdekat.

---

## Kategori & Laporan

- Hanya 4 kategori tetap: **Makan, Transport, Kebutuhan, Laundry** — di-seed otomatis saat user baru register (trigger Postgres `seed_default_categories`), dan enqueue ke sync_queue supaya UUID kategori konsisten di semua device.
- `getMonthlyCategorySummary()` **wajib** pakai `groupBy` di level query Drift — tanpa ini, semua item di-`SUM()` jadi satu baris dan kategori yang muncul adalah yang pertama secara kebetulan (bug yang pernah terjadi).
- Satu transaksi bisa berisi item dari kategori berbeda (misal: satu perjalanan Gojek + jajan sekaligus dicatat dalam satu transaksi). Halaman drill-down kategori (`CategoryReportScreen`) menampilkan **porsi kategori itu saja** (`categoryAmount`) dari tiap transaksi, bukan `total_amount` penuh — supaya angka tidak salah hitung ganda.

---

## Fitur Perawatan Data (Settings)

| Fitur | Fungsi |
|---|---|
| Sync sekarang | Trigger `fullSync()` manual |
| Pull ulang dari server | Push dulu (amankan data lokal ke server) → hapus lokal → pull semua dari Supabase. Menolak jalan kalau offline atau masih ada queue yang gagal push |
| Perbaiki data lokal | Hitung ulang `total_amount` di header transaksi dari `SUM(subtotal)` item — dipakai setelah cleanup data dobel di Supabase |

---

## Known Failure Modes yang Sudah Diperbaiki

Dicatat supaya tidak terulang kalau ada refactor di masa depan:

1. **UUID mismatch saat create** — enqueue payload menggunakan UUID dari input form, padahal parent service assign UUID baru saat insert ke DB. Fix: selalu ambil ulang record dari DB setelah `super.saveTransaction()`/`saveSession()` sebelum enqueue.
2. **UUID mismatch saat update** — item lama tidak di-enqueue delete saat update, hanya item baru yang di-insert. Fix: ambil item lama sebelum panggil parent, enqueue delete untuk semuanya.
3. **Child table tanpa `user_id`** — tabel seperti `transaction_items` tidak punya kolom `user_id`, sehingga tidak bisa langsung difilter di `pullDelta`. Fix: pull child table via `.inFilter()` menggunakan ID parent yang sudah ada di lokal.
4. **Delete tidak propagate** — `pullDelta` hanya menangkap record baru/updated, bukan yang dihapus. Fix: `_reconcileDeletes()` yang membandingkan ID di server vs lokal.
5. **`tableName` konflik dengan getter Drift** — kolom di `SyncQueue` sempat dinamai `tableName`, bentrok dengan getter internal Drift. Fix: rename ke `target_table`.
6. **UI tidak refresh setelah sync background** — Riverpod provider punya cache sendiri yang tidak tahu SQLite berubah dari proses sync. Fix: `syncTickProvider` sebagai sinyal reaktif ke semua provider data.
7. **`getMonthlyCategorySummary` tanpa `groupBy`** — semua item ke-`SUM` jadi satu angka dengan kategori yang salah. Fix: tambahkan `groupBy` di kolom kategori.

---
