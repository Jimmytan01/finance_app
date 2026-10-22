# Rancangan: Anggaran dan Bukti Struk

Tanggal: 2026-10-22

## Tujuan

Menambah dua fitur yang relevan untuk pencatatan keuangan, sambil mempertahankan pola aplikasi yang sudah ada: Riverpod untuk state, Drift sebagai penyimpanan lokal utama, dan Supabase untuk sinkronisasi antarperangkat.

Fitur autentikasi Supabase yang sudah ada tetap menjadi fitur lanjutan ketiga.

## Keputusan desain

### 1. Anggaran bulanan per kategori dan peringatan

- Pengguna dapat membuat, mengubah, dan menghapus batas anggaran untuk satu kategori pada bulan tertentu.
- Anggaran disimpan lokal terlebih dahulu dan disinkronkan ke tabel Supabase baru dengan kepemilikan per user.
- Halaman Laporan menampilkan kartu anggaran, progres pemakaian, sisa batas, dan status belum ada anggaran.
- Pengguna dapat mengaktifkan atau mematikan notifikasi anggaran. Saat pengeluaran mencapai 80% lalu 100%, aplikasi mengirim masing-masing satu peringatan per kategori dan bulan. Evaluasi dilakukan setelah transaksi lokal tersimpan dan setelah data hasil sync masuk. Pencatatan tanda peringatan dilakukan lokal per perangkat agar sync tidak memunculkan notifikasi berulang.
- Notifikasi sistem digunakan pada platform yang mendukung dan izinnya diminta saat pengguna mengaktifkan notifikasi. Jika izin ditolak, anggaran tetap berfungsi dan peringatan tetap terlihat di aplikasi.

### 2. Lampiran foto struk pada transaksi

- Form tambah/edit transaksi menerima satu foto opsional. Pengguna dapat mengganti atau menghapus foto yang sudah dilampirkan.
- Android/iOS menyediakan kamera dan pemilihan foto. Windows menyediakan pemilihan berkas gambar agar fitur dapat didemokan di desktop.
- Saat transaksi disimpan, foto disalin ke penyimpanan aplikasi lokal lebih dahulu. Transaksi tetap bisa disimpan tanpa internet; unggahan dimasukkan ke antrean.
- Foto yang sudah diunggah disimpan di bucket Supabase Storage privat. Database menyimpan metadata dan storage path, bukan URL publik atau path lokal.
- Perangkat lain dapat mengunduh foto memakai sesi Supabase aktif dan menyimpan cache lokal.
- Tidak ada OCR pada lingkup ini; pengguna tetap mengisi form transaksi.

## Arsitektur dan sinkronisasi

- Tambahkan tabel Drift untuk anggaran dan metadata lampiran, serta antrean lokal untuk unggahan foto.
- Tambahkan migrasi Supabase untuk tabel anggaran/lampiran, indeks dan batas unik yang diperlukan, RLS per user, bucket privat, dan kebijakan akses objek berdasarkan folder user.
- Anggaran mengikuti queue/sync parent yang sudah dipakai aplikasi.
- Sinkronisasi lampiran harus mengunggah objek sebelum mengirim metadata. Kegagalan unggah mempertahankan antrean untuk retry dan tidak membuat metadata seolah foto sudah tersedia.
- Sinkronisasi transaksi tetap berjalan jika lampiran gagal. Antrean lampiran dapat dicoba ulang tanpa membuat transaksi duplikat.
- Perubahan schema Drift menaikkan versi database dan mempertahankan data pengguna yang sudah ada.

## State UI dan penanganan izin

- Anggaran: loading, belum ada data, data berhasil, error dengan retry, validasi batas harus lebih dari nol, serta loading saat simpan agar tidak terjadi double tap.
- Peringatan: progres terlihat di laporan; kegagalan izin notifikasi tidak menghalangi penyimpanan anggaran.
- Lampiran: pilihan kamera/berkas, izin ditolak, pengguna membatalkan picker (form tetap seperti semula), loading/sedang unggah, foto tersedia, foto menunggu sinkronisasi offline, error dengan retry, dan hapus lampiran.
- Penolakan izin kamera ditampilkan dengan aksi untuk membuka pengaturan bila izin tidak dapat diminta lagi.

## Platform

- Satu implementasi Flutter untuk Windows, Android, dan iOS.
- Windows menggunakan pemilih berkas untuk foto; tidak mengandalkan kamera desktop untuk demo.
- Kamera dan permintaan izin kamera diuji pada Android/iOS. Izin notifikasi mengikuti perilaku platform masing-masing.
- Backend perlu bucket dan kebijakan Supabase dari migrasi. Penerapan migrasi pada proyek Supabase dilakukan dengan kredensial proyek yang tersedia; rahasia tidak disimpan di source.

## Pengujian dan kriteria selesai

- Unit test perhitungan persentase/sisa anggaran, validasi input, aturan ambang dan deduplikasi peringatan.
- Unit test repository/sync untuk simpan lokal, upload sukses, HTTP/storage gagal dan retry.
- Widget test untuk state anggaran, form invalid/saving, pemilihan foto berhasil, pembatalan, izin ditolak, dan kegagalan upload/retry.
- Test yang memakai Supabase/Storage live memerlukan konfigurasi proyek; test default memakai fake/mock agar dapat berjalan tanpa jaringan.
- Seluruh test yang ada tetap lulus, dan aplikasi Windows tetap dapat dibuka serta memilih lampiran dari file lokal.

## Di luar lingkup

- OCR atau ekstraksi otomatis isi struk.
- Mengharuskan jaringan untuk menyimpan transaksi atau anggaran.
- Membagikan foto melalui URL publik.
