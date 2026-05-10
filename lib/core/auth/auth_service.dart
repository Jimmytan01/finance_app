import 'package:device_info_plus/device_info_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
 
const _uuid = Uuid();
 
class AuthService {
  final SupabaseClient _supabase;
  final AppDatabase   _db;
 
  AuthService({required SupabaseClient supabase, required AppDatabase db})
      : _supabase = supabase,
        _db       = db;
 
  // Shortcut — sering dipakai di berbagai tempat
  User? get currentUser => _supabase.auth.currentUser;
  bool  get isLoggedIn  => currentUser != null;
 
  // Stream auth state — dipakai di AuthGate untuk reactive routing.
  // Emit setiap kali user login, logout, atau token refresh.
  Stream<AuthState> get authStateStream =>
      _supabase.auth.onAuthStateChange;
 
  // ── Login ─────────────────────────────────────────────────
  Future<AuthResponse> signInWithEmail(String email, String password) =>
      _supabase.auth.signInWithPassword(
        email:    email,
        password: password,
      );
 
  Future<AuthResponse> signUpWithEmail(
    String email,
    String password,
    String displayName,
  ) async {
    final res = await _supabase.auth.signUp(
      email:    email,
      password: password,
      data:     {'name': displayName},
    );
    return res;
  }
 
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    // Kita tidak hapus data lokal saat logout karena user mungkin
    // offline dan ingin tetap akses datanya. Data akan di-clear
    // hanya kalau user eksplisit memilih "Hapus data lokal" di settings.
  }
 
  // ── Device registration ────────────────────────────────────
  // Dipanggil sekali setelah login berhasil. Kalau device ini sudah
  // pernah register sebelumnya (ada di DB lokal), skip saja.
  Future<String> registerDevice() async {
    final userId = currentUser?.id;
    if (userId == null) throw Exception('Harus login dulu');
 
    // Cek apakah device ini sudah pernah di-register
    final existing = await (_db.select(_db.devices)
          ..where((d) => d.userId.equals(userId)))
        .get();
 
    if (existing.isNotEmpty) {
      return existing.first.id;
    }
 
    // Ambil info device
    final info     = DeviceInfoPlugin();
    String deviceName, platform;
 
    if (kIsWeb) {
      deviceName = 'Browser';
      platform   = 'web';
    } else {
      try {
        if (defaultTargetPlatform == TargetPlatform.android) {
          final d  = await info.androidInfo;
          deviceName = '${d.manufacturer} ${d.model}';
          platform   = 'android';
        } else if (defaultTargetPlatform == TargetPlatform.iOS) {
          final d  = await info.iosInfo;
          deviceName = d.name;
          platform   = 'ios';
        } else if (defaultTargetPlatform == TargetPlatform.windows) {
          final d  = await info.windowsInfo;
          deviceName = d.computerName;
          platform   = 'windows';
        } else if (defaultTargetPlatform == TargetPlatform.macOS) {
          final d  = await info.macOsInfo;
          deviceName = d.computerName;
          platform   = 'macos';
        } else {
          final d  = await info.linuxInfo;
          deviceName = d.prettyName;
          platform   = 'linux';
        }
      } catch (_) {
        // Kalau gagal ambil info device, pakai fallback
        deviceName = 'Unknown Device';
        platform   = defaultTargetPlatform.name.toLowerCase();
      }
    }
 
    final deviceId = _uuid.v4();
    final now      = DateTime.now();
 
    // Simpan ke local DB
    await _db.into(_db.devices).insert(DevicesCompanion(
      id:         Value(deviceId),
      userId:     Value(userId),
      deviceName: Value(deviceName),
      platform:   Value(platform),
      createdAt:  Value(now),
    ));
 
    // Simpan juga ke Supabase supaya device terdaftar di semua device lain
    await _supabase.from('devices').upsert({
      'id':          deviceId,
      'user_id':     userId,
      'device_name': deviceName,
      'platform':    platform,
      'created_at':  now.toIso8601String(),
    });
 
    return deviceId;
  }
 
  // Ambil deviceId yang sudah tersimpan di local DB.
  // Return null kalau belum pernah register (seharusnya tidak terjadi setelah login).
  Future<String?> getLocalDeviceId() async {
    final userId = currentUser?.id;
    if (userId == null) return null;
 
    final row = await (_db.select(_db.devices)
          ..where((d) => d.userId.equals(userId))
          ..limit(1))
        .getSingleOrNull();
 
    return row?.id;
  }
}