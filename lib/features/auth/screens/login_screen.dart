// Satu screen untuk login dan register — pakai toggle tab di atas.
// Sengaja tidak dipisah jadi dua screen karena form-nya hampir identik,
// dan memisahkan justru bikin navigasi lebih ribet tanpa manfaat nyata.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/auth/auth_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // Controllers form — pakai satu set, field berbeda per tab
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _nameCtrl     = TextEditingController(); // hanya untuk register
  final _formKey      = GlobalKey<FormState>();

  bool _isLoading    = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _isRegisterTab => _tabCtrl.index == 1;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),

              // ── Logo / header ────────────────────────
              Icon(Icons.account_balance_wallet_outlined,
                  size: 48, color: cs.primary),
              const SizedBox(height: 16),
              Text('Finance App',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 6),
              Text(
                'Catat pengeluaranmu, kendalikan keuanganmu.',
                style: TextStyle(
                    color: cs.onSurface.withOpacity(0.5), fontSize: 14),
              ),
              const SizedBox(height: 40),

              // ── Tab masuk / daftar ───────────────────
              Container(
                decoration: BoxDecoration(
                  color:        cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller:   _tabCtrl,
                  indicator:    BoxDecoration(
                    color:        cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize:   TabBarIndicatorSize.tab,
                  dividerColor:    Colors.transparent,
                  labelColor:      cs.onPrimaryContainer,
                  unselectedLabelColor: cs.onSurface.withOpacity(0.5),
                  labelStyle:      const TextStyle(fontWeight: FontWeight.w600),
                  onTap:           (_) => setState(() {}),
                  tabs: const [
                    Tab(text: 'Masuk'),
                    Tab(text: 'Daftar'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Form ─────────────────────────────────
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Nama (hanya register)
                    if (_isRegisterTab) ...[
                      _FormField(
                        controller:  _nameCtrl,
                        label:       'Nama lengkap',
                        icon:        Icons.person_outline,
                        validator:   (v) =>
                            v == null || v.trim().isEmpty
                                ? 'Nama tidak boleh kosong'
                                : null,
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Email
                    _FormField(
                      controller:  _emailCtrl,
                      label:       'Email',
                      icon:        Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator:   (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Email tidak boleh kosong';
                        }
                        if (!v.contains('@')) {
                          return 'Format email tidak valid';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Password
                    TextFormField(
                      controller:    _passCtrl,
                      obscureText:   !_showPassword,
                      decoration:    InputDecoration(
                        labelText:   'Password',
                        prefixIcon:  const Icon(Icons.lock_outline, size: 20),
                        suffixIcon:  IconButton(
                          icon:      Icon(
                            _showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                        border:        OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: cs.outline.withOpacity(0.4))),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Password tidak boleh kosong';
                        }
                        if (_isRegisterTab && v.length < 8) {
                          return 'Password minimal 8 karakter';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Tombol submit
                    FilledButton(
                      onPressed:  _isLoading ? null : _submit,
                      style:      FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: _isLoading
                          ? const SizedBox(
                              width:  20,
                              height: 20,
                              child:  CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color:       Colors.white),
                            )
                          : Text(
                              _isRegisterTab ? 'Buat Akun' : 'Masuk',
                              style: const TextStyle(
                                  fontSize:   16,
                                  fontWeight: FontWeight.w600),
                            ),
                    ),
                  ],
                ),
              ),

              // ── Hint untuk dev/testing ───────────────
              const SizedBox(height: 32),
              Center(
                child: Text(
                  'Data tersimpan aman di Supabase\ndan tersinkronisasi ke semua device kamu',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      color:    cs.onSurface.withOpacity(0.35)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    try {
      final auth  = ref.read(authServiceProvider);
      final email = _emailCtrl.text.trim();
      final pass  = _passCtrl.text;

      if (_isRegisterTab) {
        // Daftar akun baru
        await auth.signUpWithEmail(
            email, pass, _nameCtrl.text.trim());

        if (mounted) {
          // Beberapa Supabase project perlu email verification dulu.
          // Tampilkan info ini ke user.
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:  Text(
                'Akun dibuat! Cek email untuk verifikasi, lalu masuk.'),
            duration: Duration(seconds: 5),
          ));
          // Pindah ke tab login
          _tabCtrl.animateTo(0);
          setState(() {});
        }
      } else {
        // Login
        await auth.signInWithEmail(email, pass);

        // AuthGate akan otomatis routing ke HomeShell karena
        // authStateProvider emit event baru setelah login berhasil.
        // Kita tidak perlu Navigator.push di sini.

        // Register device dan trigger initial sync
        await auth.registerDevice();
      }
    } on AuthException catch (e) {
      if (mounted) _showError(_friendlyAuthError(e.message));
    } catch (e) {
      if (mounted) _showError('Terjadi kesalahan: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg),
      backgroundColor: Theme.of(context).colorScheme.error,
      behavior:        SnackBarBehavior.floating,
    ));
  }

  // Terjemahkan pesan error Supabase yang teknis jadi bahasa manusia
  String _friendlyAuthError(String raw) {
    if (raw.contains('Invalid login credentials')) {
      return 'Email atau password salah';
    }
    if (raw.contains('Email not confirmed')) {
      return 'Verifikasi email dulu sebelum masuk';
    }
    if (raw.contains('User already registered')) {
      return 'Email ini sudah terdaftar, silakan masuk';
    }
    if (raw.contains('Password should be at least')) {
      return 'Password terlalu pendek (minimal 8 karakter)';
    }
    return raw;
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String                label;
  final IconData              icon;
  final TextInputType?        keyboardType;
  final String? Function(String?)? validator;
  final TextCapitalization    textCapitalization;

  const _FormField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextFormField(
      controller:         controller,
      keyboardType:       keyboardType,
      textCapitalization: textCapitalization,
      validator:          validator,
      decoration: InputDecoration(
        labelText:    label,
        prefixIcon:   Icon(icon, size: 20),
        border:        OutlineInputBorder(
            borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:   BorderSide(color: cs.outline.withOpacity(0.4))),
      ),
    );
  }
}