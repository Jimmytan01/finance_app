// Halaman profil / settings — tab keempat di bottom nav.
// Berisi info akun, status sync, daftar device, dan tombol logout.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../features/transactions/providers/transaction_providers.dart';
import '../../../features/transactions/services/transaction_service.dart';
 
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user       = ref.watch(currentUserProvider);
    final syncStatus = ref.watch(syncStatusProvider);
 
    return Scaffold(
      appBar: AppBar(
        title:       const Text('Profil & Pengaturan'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProfileCard(user: user),
          const SizedBox(height: 16),
 
          _SyncStatusCard(statusAsync: syncStatus),
          const SizedBox(height: 16),
 
          _SyncActions(),
          const SizedBox(height: 24),
 
          _SettingsSection(
            title: 'Akun',
            tiles: [
              _SettingsTile(
                icon:     Icons.email_outlined,
                title:    'Email',
                subtitle: user?.email ?? '-',
              ),
            ],
          ),
          const SizedBox(height: 16),
 
          _SettingsSection(
            title: 'Data',
            tiles: [
              _SettingsTile(
                icon:     Icons.cloud_download_outlined,
                title:    'Pull ulang dari server',
                subtitle: 'Timpa data lokal dengan data dari server',
                onTap:    () => _confirmFullPull(context, ref),
                color:    Theme.of(context).colorScheme.tertiary,
              ),
              _SettingsTile(
                icon:     Icons.build_circle_outlined,
                title:    'Perbaiki data lokal',
                subtitle: 'Hitung ulang total semua transaksi',
                onTap:    () => _repairLocalData(context, ref),
                color:    Theme.of(context).colorScheme.secondary,
              ),
            ],
          ),
          const SizedBox(height: 24),
 
          OutlinedButton.icon(
            onPressed: () => _confirmLogout(context, ref),
            icon:  const Icon(Icons.logout, size: 18),
            label: const Text('Keluar'),
            style: OutlinedButton.styleFrom(
              minimumSize:     const Size.fromHeight(48),
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .error
                      .withOpacity(0.5)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
 
  // Perbaiki data lokal: recalculate semua total dari sum items
  Future<void> _repairLocalData(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Perbaiki data lokal?'),
        content: const Text(
            'Ini akan menghitung ulang total semua transaksi '
            'berdasarkan item yang ada. Proses ini aman dan '
            'tidak menghapus data apapun.'),
        actions: [
          TextButton(
              onPressed:  () => Navigator.pop(ctx, false),
              child:      const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:     const Text('Perbaiki'),
          ),
        ],
      ),
    );
 
    if (confirmed != true || !context.mounted) return;
 
    // Tampilkan loading
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:  Text('Memperbaiki data...'),
      duration: Duration(seconds: 30),
    ));
 
    try {
      final dao    = ref.read(transactionDaoProvider);
      final userId = ref.read(currentUserIdProvider);
 
      // Recalculate semua total
      await dao.recalculateAllTotals(userId);
 
      // Invalidate semua provider supaya UI refresh
      ref.invalidate(monthlyTransactionsProvider);
      ref.invalidate(monthlyCategorySummaryProvider);
      ref.invalidate(monthlyTotalProvider);
 
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:         Text('Data berhasil diperbaiki!'),
          backgroundColor: Colors.green,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Gagal: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }
 
  void _confirmFullPull(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Pull ulang dari server?'),
        content: const Text(
            'Data lokal akan diganti dengan data dari server. '
            'Perubahan lokal yang belum tersync akan hilang. Lanjutkan?'),
        actions: [
          TextButton(
              onPressed:  () => Navigator.pop(ctx),
              child:      const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.pop(ctx);
              final service =
                  ref.read(syncNotifierProvider).valueOrNull;
              if (service == null) return;
 
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:  Text('Memuat ulang data dari server...'),
                    duration: Duration(seconds: 30),
                  ));
 
              final result = await service.initialPull();
 
              if (context.mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(result.success
                      ? 'Data berhasil dimuat ulang (${result.pulledCount} record)'
                      : result.errorMessage ?? 'Gagal'),
                  backgroundColor: result.success
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ));
 
                // Kalau berhasil pull, langsung repair total juga
                if (result.success) {
                  final dao    = ref.read(transactionDaoProvider);
                  final userId = ref.read(currentUserIdProvider);
                  await dao.recalculateAllTotals(userId);
                  ref.invalidate(monthlyTransactionsProvider);
                  ref.invalidate(monthlyCategorySummaryProvider);
                  ref.invalidate(monthlyTotalProvider);
                }
              }
            },
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
  }
 
  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Keluar dari akun?'),
        content: const Text(
            'Kamu akan keluar dari akun ini. '
            'Data lokal tetap tersimpan di device.'),
        actions: [
          TextButton(
              onPressed:  () => Navigator.pop(ctx),
              child:      const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authServiceProvider).signOut();
            },
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
  }
}
 
// ─────────────────────────────────────────────────────────────
// Widgets (tidak berubah dari versi sebelumnya)
// ─────────────────────────────────────────────────────────────
 
class _ProfileCard extends StatelessWidget {
  final dynamic user;
  const _ProfileCard({required this.user});
 
  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final name    = user?.userMetadata?['name'] as String? ?? 'Pengguna';
    final email   = user?.email ?? '-';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
 
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.secondaryContainer],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius:          30,
            backgroundColor: cs.primary,
            child: Text(initial,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize:   24,
                    color:      cs.onPrimary)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(email,
                    style: TextStyle(
                        fontSize: 13,
                        color:    cs.onSurface.withOpacity(0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
 
class _SyncStatusCard extends StatelessWidget {
  final AsyncValue<SyncResult> statusAsync;
  const _SyncStatusCard({required this.statusAsync});
 
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return statusAsync.when(
      loading: () => _StatusBox(
          color:    cs.surfaceContainerHighest,
          icon:     Icons.sync,
          label:    'Menghubungkan...',
          sublabel: '',
          spinning: true),
      error: (_, __) => _StatusBox(
          color:     cs.errorContainer,
          icon:      Icons.sync_problem_outlined,
          label:     'Gagal terhubung',
          sublabel:  'Periksa koneksi internet',
          iconColor: cs.onErrorContainer),
      data: (result) {
        switch (result.status) {
          case SyncStatus.syncing:
            return _StatusBox(
                color:     cs.primaryContainer,
                icon:      Icons.sync,
                label:     'Menyinkronkan...',
                sublabel:  '',
                spinning:  true,
                iconColor: cs.onPrimaryContainer);
          case SyncStatus.success:
            return _StatusBox(
                color:     cs.tertiaryContainer,
                icon:      Icons.cloud_done_outlined,
                label:     'Tersinkronisasi',
                sublabel:  'Terakhir: ${TransactionService.formatDate(result.timestamp)}'
                    ' · ${result.pushedCount} push, ${result.pulledCount} pull',
                iconColor: cs.onTertiaryContainer);
          case SyncStatus.error:
            return _StatusBox(
                color:     cs.errorContainer,
                icon:      Icons.cloud_off_outlined,
                label:     'Sync gagal',
                sublabel:  result.errorMessage ?? 'Coba lagi nanti',
                iconColor: cs.onErrorContainer);
          case SyncStatus.idle:
            return _StatusBox(
                color:     cs.surfaceContainerHighest,
                icon:      Icons.cloud_outlined,
                label:     'Siap sync',
                sublabel:  'Offline — perubahan disimpan lokal',
                iconColor: cs.onSurface.withOpacity(0.5));
        }
      },
    );
  }
}
 
class _StatusBox extends StatelessWidget {
  final Color   color;
  final IconData icon;
  final String  label, sublabel;
  final Color?  iconColor;
  final bool    spinning;
  const _StatusBox({
    required this.color,
    required this.icon,
    required this.label,
    required this.sublabel,
    this.iconColor,
    this.spinning = false,
  });
 
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding:    const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        spinning
            ? SizedBox(
                width:  20,
                height: 20,
                child:  CircularProgressIndicator(
                    strokeWidth: 2,
                    color:       iconColor ?? cs.primary))
            : Icon(icon, size: 22, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            if (sublabel.isNotEmpty)
              Text(sublabel,
                  style: TextStyle(
                      fontSize: 11,
                      color:    cs.onSurface.withOpacity(0.5))),
          ]),
        ),
      ]),
    );
  }
}
 
class _SyncActions extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSyncing = ref.watch(syncStatusProvider).valueOrNull?.status ==
        SyncStatus.syncing;
    return OutlinedButton.icon(
      onPressed: isSyncing
          ? null
          : () => ref.read(syncNotifierProvider.notifier).sync(),
      icon: Icon(Icons.sync,
          size:  18,
          color: isSyncing
              ? Theme.of(context).colorScheme.onSurface.withOpacity(0.3)
              : null),
      label: Text(isSyncing ? 'Sedang sync...' : 'Sync sekarang'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        shape:       RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
 
class _SettingsSection extends StatelessWidget {
  final String       title;
  final List<Widget> tiles;
  const _SettingsSection({required this.title, required this.tiles});
 
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color:      Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.5),
                  )),
        ),
        Container(
          decoration: BoxDecoration(
            color:        Theme.of(context)
                .colorScheme
                .surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: tiles),
        ),
      ],
    );
  }
}
 
class _SettingsTile extends StatelessWidget {
  final IconData     icon;
  final String       title, subtitle;
  final VoidCallback? onTap;
  final Color?       color;
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.color,
  });
 
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon,
          size:  20,
          color: color ?? cs.onSurface.withOpacity(0.6)),
      title:    Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12, color: cs.onSurface.withOpacity(0.45))),
      trailing: onTap != null
          ? Icon(Icons.chevron_right,
              size: 16, color: cs.onSurface.withOpacity(0.3))
          : null,
      onTap: onTap,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
    );
  }
}