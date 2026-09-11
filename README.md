# Finance App — Aplikasi Pencatat Keuangan Pribadi

Aplikasi pencatat keuangan pribadi yang berjalan di laptop dan smartphone, dengan data yang tersinkronisasi otomatis antar kedua device melalui Supabase.

---

## Deskripsi Masalah

Banyak orang mencatat pengeluaran hariannya secara tidak konsisten — tercecer di catatan HP, aplikasi note, atau tidak dicatat sama sekali. Aplikasi pencatat keuangan yang tersedia di pasaran umumnya:

- Hanya bisa diakses dari satu device, sehingga pencatatan terhambat kalau device utama tidak dibawa
- Tidak punya fitur split bill yang terintegrasi dengan pencatatan keuangan, padahal pengeluaran patungan (makan bareng, transportasi bersama) adalah pengeluaran yang sering terjadi
- Kategorisasi pengeluaran kaku dan tidak sesuai kebutuhan personal pengguna

Masalah inti yang ingin diselesaikan: **pengguna butuh satu tempat untuk mencatat pengeluaran harian secara detail (termasuk hasil patungan), yang bisa diakses dari laptop maupun HP tanpa perlu mencatat ulang di kedua device.**

---

## Profil Target Pengguna

**Pengguna utama:** Individu (personal use), khususnya mahasiswa atau pekerja muda yang:

- Rutin melakukan pengeluaran harian kecil (makan, transport, kebutuhan sehari-hari, laundry)
- Sering terlibat transaksi patungan dengan teman — makan bersama, split ongkos, dll
- Menggunakan lebih dari satu device (laptop untuk kerja/kuliah, HP untuk mobilitas) dan ingin pencatatan tetap konsisten di kedua device
- Terbiasa dengan aplikasi digital dan tidak keberatan melakukan setup akun untuk mendapat manfaat sinkronisasi

**Bukan target:** Tim finance perusahaan, akuntan profesional, atau kebutuhan pembukuan bisnis multi-user dengan approval workflow.

---

## Manfaat Aplikasi

1. **Satu sumber kebenaran** — semua pengeluaran tercatat di satu tempat, tidak tercecer di banyak aplikasi atau catatan manual.
2. **Akses fleksibel lintas device** — mulai mencatat dari HP saat di jalan, lanjut cek laporan dari laptop, tanpa perlu re-entry data.
3. **Split bill terintegrasi** — hasil hitung patungan bisa langsung dicatat sebagai transaksi keuangan pribadi, tidak perlu pindah aplikasi atau hitung manual dua kali.
4. **Visibilitas pola pengeluaran** — laporan dan riwayat membantu pengguna sadar ke mana uangnya pergi tiap bulan, per kategori.
5. **Tetap berfungsi tanpa internet** — pencatatan offline-first, sinkronisasi terjadi otomatis begitu koneksi tersedia.

---

## Daftar Fitur Inti

Fitur berikut adalah cakupan realistis yang diselesaikan dalam 12 pertemuan pengembangan:

| # | Fitur | Deskripsi Singkat |
|---|-------|--------------------|
| 1 | **Pencatatan transaksi** | Input tanggal, tempat, nama item, harga satuan, jumlah, dan diskon (Rp atau %) per item |
| 2 | **Kategorisasi** | 4 kategori: Makan, Transport, Kebutuhan, Laundry — satu transaksi bisa berisi item dari kategori berbeda |
| 3 | **Ringkasan bulanan** | Total pengeluaran bulan berjalan, breakdown per kategori, navigasi antar bulan |
| 4 | **Riwayat & pencarian** | Daftar seluruh transaksi lintas bulan, dengan search, filter kategori, dan sortir |
| 5 | **Laporan visual** | Grafik tren pengeluaran 3–6 bulan terakhir dan pie chart breakdown kategori per bulan |
| 6 | **Split bill** | Kalkulator patungan: input item, assign ke peserta, atur diskon dan pajak, hasil rincian per orang, opsi simpan bagian sendiri ke pencatatan keuangan |
| 7 | **Edit & hapus** | Transaksi maupun sesi split bill dapat diedit atau dihapus kapan saja |
| 8 | **Autentikasi** | Login/register dengan email, sesi tersimpan di device |
| 9 | **Sinkronisasi offline-first** | Data tersimpan lokal (SQLite) terlebih dahulu, lalu disinkronkan ke server (Supabase) secara otomatis saat online, dengan dukungan realtime antar device |
| 10 | **Manajemen data** | Pull ulang dari server dan perbaikan data lokal sebagai mekanisme pemulihan |

---

## Fitur yang Tidak Dikerjakan

Untuk menjaga cakupan tetap realistis dalam 12 pertemuan, fitur berikut secara sadar **tidak** dimasukkan ke dalam scope:

- Pencatatan pemasukan (income) — aplikasi fokus pada pengeluaran saja
- Budget/anggaran per kategori dengan notifikasi batas
- Transaksi berulang (recurring/subscription tracker)
- Scan struk otomatis (OCR)
- Export laporan ke PDF atau Excel
- Kategori custom buatan pengguna (kategori dibatasi 4 dan bersifat tetap)
- PIN/biometric lock pada aplikasi
- Widget home screen
- Fitur kolaborasi multi-user (berbagi akun, approval, dll)
- Manajemen device terdaftar (lihat/hapus device dari akun)

---

## Kriteria Aplikasi Dinyatakan Berhasil

Aplikasi dianggap berhasil apabila memenuhi seluruh kriteria berikut:

1. **Pencatatan akurat** — transaksi yang diinput tersimpan dengan benar, termasuk perhitungan subtotal, diskon, dan total yang sesuai antara header transaksi dan rincian item.
2. **Konsistensi data lintas device** — transaksi yang dibuat di satu device (laptop atau HP) muncul di device lain dalam waktu wajar (di bawah beberapa detik saat online), tanpa duplikasi maupun kehilangan data.
3. **Fungsi offline yang andal** — pengguna tetap dapat mencatat transaksi baru saat tanpa koneksi internet, dan data tersebut tersinkronisasi otomatis begitu koneksi kembali tersedia.
4. **Laporan yang benar secara matematis** — total per kategori, per bulan, dan grafik tren mencerminkan data transaksi yang sebenarnya, termasuk untuk transaksi yang memiliki item dari lebih dari satu kategori.
5. **Split bill terhitung tepat** — pembagian tagihan antar peserta proporsional dan akurat, termasuk distribusi diskon dan pajak, dengan total keseluruhan yang sama dengan jumlah tagihan asli.
6. **Dapat digunakan sehari-hari tanpa hambatan** — alur menambah, mengedit, dan menghapus transaksi maupun sesi split bill dapat dilakukan dengan jumlah langkah yang wajar dan tanpa error yang mengganggu.
