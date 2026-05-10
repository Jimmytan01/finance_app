// Layar utama tab Split Bill — menampilkan riwayat sesi yang sudah disimpan,
// plus tombol FAB untuk membuat sesi baru.
// Dibuat simpel: tidak ada search/filter karena orang jarang punya
// ratusan sesi split bill. Kalau nanti dibutuhkan bisa ditambah.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../features/transactions/services/transaction_service.dart';
import '../providers/bill_providers.dart';
import '../services/bill_service.dart';
import 'add_bill_screen.dart';
 
class BillListScreen extends ConsumerWidget {
  const BillListScreen({super.key});
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(billSessionListProvider);
 
    return Scaffold(
      appBar: AppBar(title: const Text('Split Bill'), centerTitle: true),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (sessions) => sessions.isEmpty
            ? const _EmptyBillState()
            : _SessionList(sessions: sessions),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ref.read(billFormProvider.notifier).reset();
          ref.read(billCalcResultProvider.notifier).state = null;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:  (_) => const AddBillScreen(),
              settings: const RouteSettings(name: '/split-bill'),
            ),
          );
        },
        icon:  const Icon(Icons.receipt_long_outlined),
        label: const Text('Split Bill Baru'),
      ),
    );
  }
}
 
class _SessionList extends StatelessWidget {
  final List<BillSession> sessions;
  const _SessionList({required this.sessions});
 
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding:     const EdgeInsets.only(bottom: 100),
      itemCount:   sessions.length,
      itemBuilder: (ctx, i) => _SessionTile(session: sessions[i]),
    );
  }
}
 
class _SessionTile extends ConsumerWidget {
  final BillSession session;
  const _SessionTile({required this.session});
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs          = Theme.of(context).colorScheme;
    final detailAsync = ref.watch(billSessionDetailProvider(session.id));
 
    return Card(
      margin:    const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      elevation: 0,
      shape:     RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap:        () => _openDetail(context, ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(children: [
            // Kalender kecil
            Container(
              width:  44,
              height: 44,
              decoration: BoxDecoration(
                color:        cs.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(session.date.day.toString(),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize:   16,
                            color:      cs.onSecondaryContainer)),
                    Text(_shortMonth(session.date.month),
                        style: TextStyle(
                            fontSize: 10,
                            color: cs.onSecondaryContainer.withOpacity(0.6))),
                  ]),
            ),
            const SizedBox(width: 12),
 
            // Info sesi
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(session.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  if (session.placeName?.isNotEmpty == true) ...[
                    Icon(Icons.place_outlined,
                        size: 11, color: cs.onSurface.withOpacity(0.4)),
                    const SizedBox(width: 2),
                    Text(session.placeName!,
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withOpacity(0.45))),
                    const SizedBox(width: 8),
                  ],
                  detailAsync.maybeWhen(
                    data: (d) => Row(children: [
                      Icon(Icons.group_outlined,
                          size: 11, color: cs.onSurface.withOpacity(0.4)),
                      const SizedBox(width: 2),
                      Text('${d.participants.length} orang',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withOpacity(0.45))),
                    ]),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ]),
                if (session.linkedTxId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:        cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('✓ Tercatat di keuangan',
                          style: TextStyle(
                              fontSize:   10,
                              fontWeight: FontWeight.w500,
                              color:      cs.onTertiaryContainer)),
                    ),
                  ),
              ]),
            ),
 
            // Total + menu
            Text(TransactionService.formatCurrency(session.totalAmount),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize:   14,
                    color:      cs.primary)),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  size: 20, color: cs.onSurface.withOpacity(0.5)),
              onSelected: (val) async {
                if (val == 'edit') {
                  await _editSession(context, ref);
                } else if (val == 'delete') {
                  _confirmDelete(context, ref);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ])),
                PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline,
                          size:  18,
                          color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 8),
                      Text('Hapus',
                          style: TextStyle(
                              color:
                                  Theme.of(context).colorScheme.error)),
                    ])),
              ],
            ),
          ]),
        ),
      ),
    );
  }
 
  void _openDetail(BuildContext context, WidgetRef ref) {
    ref.read(billSessionDetailProvider(session.id).future).then((detail) {
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => BillDetailScreen(
                session: session, detail: detail)),
      );
    });
  }
 
  Future<void> _editSession(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(billFormProvider.notifier);
    ref.read(billCalcResultProvider.notifier).state = null;
    try {
      final detail = await ref
          .read(billSessionDetailProvider(session.id).future);
      await notifier.loadFromSession(detail);
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:  (_) => const AddBillScreen(),
            settings: const RouteSettings(name: '/split-bill'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Gagal load sesi: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }
 
  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Hapus sesi ini?'),
        content: const Text(
            'Semua data split bill akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed:  () => Navigator.pop(ctx),
              child:      const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.pop(ctx);
              // Pakai sync-aware delete supaya ter-push ke Supabase
              final service = ref.read(billServiceProvider);
              await service.deleteSessionWithSync(session.id);
              ref.invalidate(billSessionListProvider);
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}
 
// ── Detail screen ─────────────────────────────────────────────
class BillDetailScreen extends ConsumerWidget {
  final BillSession       session;
  final BillSessionDetail detail;
  const BillDetailScreen(
      {super.key, required this.session, required this.detail});
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs      = Theme.of(context).colorScheme;
    final totals  = detail.totalPerParticipant;
    final partMap = {for (final p in detail.participants) p.id: p};
    final sortedIds = totals.keys.toList()
      ..sort((a, b) => (totals[b] ?? 0).compareTo(totals[a] ?? 0));
 
    return Scaffold(
      appBar: AppBar(
        title:       Text(session.title),
        centerTitle: true,
        actions: [
          IconButton(
            icon:      const Icon(Icons.edit_outlined),
            tooltip:   'Edit',
            onPressed: () => _editSession(context, ref),
          ),
          IconButton(
            icon:      Icon(Icons.delete_outline, color: cs.error),
            tooltip:   'Hapus',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info + total
          Container(
            padding:    const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color:        cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Icon(Icons.calendar_today,
                    size: 14, color: cs.onSurface.withOpacity(0.5)),
                const SizedBox(width: 6),
                Text(TransactionService.formatDate(session.date),
                    style: const TextStyle(fontSize: 13)),
              ]),
              if (session.placeName?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.place_outlined,
                      size: 14, color: cs.onSurface.withOpacity(0.5)),
                  const SizedBox(width: 6),
                  Text(session.placeName!,
                      style: const TextStyle(fontSize: 13)),
                ]),
              ],
              const Divider(height: 16),
              _SummaryRow('Subtotal',
                  TransactionService.formatCurrency(
                      detail.items.fold(0.0, (s, i) => s + i.subtotal))),
              const Divider(height: 12),
              _SummaryRow(
                  'Total',
                  TransactionService.formatCurrency(session.totalAmount),
                  isBold: true,
                  color:  cs.primary),
              if (session.linkedTxId != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color:        cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(
                      '✓ Bagian saya sudah dicatat di keuangan',
                      style: TextStyle(
                          fontSize:   11,
                          fontWeight: FontWeight.w500,
                          color:      cs.onTertiaryContainer)),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 20),
 
          Text('Tagihan per orang',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
 
          ...sortedIds.map((id) {
            final p      = partMap[id];
            final amount = totals[id] ?? 0;
            return Card(
              margin:    const EdgeInsets.only(bottom: 8),
              elevation: 0,
              color:     p?.isSelf == true
                  ? cs.primaryContainer.withOpacity(0.5)
                  : cs.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: p?.isSelf == true
                    ? BorderSide(color: cs.primary.withOpacity(0.4))
                    : BorderSide.none,
              ),
              child: ListTile(
                leading: CircleAvatar(
                  radius:          18,
                  backgroundColor: p?.isSelf == true
                      ? cs.primary
                      : cs.secondaryContainer,
                  child: Text(
                    p?.name.trim().isEmpty == true
                        ? '?'
                        : p!.name.trim()[0].toUpperCase(),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize:   13,
                        color:      p?.isSelf == true
                            ? cs.onPrimary
                            : cs.onSecondaryContainer),
                  ),
                ),
                title: Text(
                  p?.isSelf == true
                      ? '${p?.name ?? 'Saya'} (saya)'
                      : p?.name ?? 'Peserta',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                trailing: Text(
                  TransactionService.formatCurrency(amount),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize:   15,
                      color:      cs.primary),
                ),
              ),
            );
          }),
 
          const SizedBox(height: 20),
          Text('Rincian item',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
 
          ...detail.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                      child: Text(item.name,
                          style: const TextStyle(fontSize: 13))),
                  Text(
                      '${TransactionService.formatCurrency(item.unitPrice)} × ${item.quantity}',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.5))),
                  const SizedBox(width: 12),
                  Text(TransactionService.formatCurrency(item.subtotal),
                      style: const TextStyle(
                          fontSize:   13,
                          fontWeight: FontWeight.w500)),
                ]),
              )),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
 
  Future<void> _editSession(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(billFormProvider.notifier);
    ref.read(billCalcResultProvider.notifier).state = null;
    await notifier.loadFromSession(detail);
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:  (_) => const AddBillScreen(),
          settings: const RouteSettings(name: '/split-bill'),
        ),
      );
    }
  }
 
  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Hapus sesi ini?'),
        content: const Text(
            'Semua data split bill akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed:  () => Navigator.pop(ctx),
              child:      const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.error),
            onPressed: () async {
              final service = ref.read(billServiceProvider);
              await service.deleteSessionWithSync(session.id);
              ref.invalidate(billSessionListProvider);
              if (context.mounted) {
                Navigator.of(context).pop(); // tutup dialog
                Navigator.of(context).pop(); // kembali ke list
              }
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}
 
class _SummaryRow extends StatelessWidget {
  final String label, value;
  final bool   isBold;
  final Color? color;
  const _SummaryRow(this.label, this.value,
      {this.isBold = false, this.color});
 
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Text(label,
          style: TextStyle(
              fontSize:   isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal)),
      const Spacer(),
      Text(value,
          style: TextStyle(
              fontSize:   isBold ? 16 : 12,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.normal,
              color:      color)),
    ]);
  }
}
 
class _EmptyBillState extends StatelessWidget {
  const _EmptyBillState();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.receipt_long_outlined,
            size: 64, color: cs.outlineVariant),
        const SizedBox(height: 16),
        Text('Belum ada sesi split bill',
            style:
                TextStyle(color: cs.onSurface.withOpacity(0.45))),
        const SizedBox(height: 6),
        Text('Ketuk tombol di bawah untuk mulai',
            style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withOpacity(0.3))),
      ]),
    );
  }
}
 
String _shortMonth(int m) {
  const n = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];
  return n[m];
}