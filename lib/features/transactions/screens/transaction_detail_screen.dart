// lib/features/transactions/screens/transaction_detail_screen.dart
//
// Tampil detail satu transaksi: semua item, subtotal per item,
// total, dan opsi edit / hapus.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../providers/transaction_providers.dart';
import '../services/transaction_service.dart';
import 'add_transaction_screen.dart';

class TransactionDetailScreen extends ConsumerWidget {
  final String txId;
  const TransactionDetailScreen({super.key, required this.txId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ambil data transaksi dari list yang sudah di-load
    final txAsync    = ref.watch(monthlyTransactionsProvider);
    final itemsAsync = ref.watch(transactionItemsProvider(txId));
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Transaksi'),
        centerTitle: true,
        actions: [
          txAsync.whenData((txs) {
            final tx = txs.where((t) => t.id == txId).firstOrNull;
            if (tx == null) return const SizedBox.shrink();
            return PopupMenuButton<String>(
              onSelected: (val) async {
                if (val == 'edit') {
                  final items = await ref.read(
                      transactionItemsProvider(txId).future);
                  if (context.mounted) {
                    ref.read(addTransactionProvider.notifier)
                        .loadExisting(tx, items);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              AddTransactionScreen(editTxId: txId)),
                    );
                  }
                } else if (val == 'delete') {
                  _confirmDelete(context, ref);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ])),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 18,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 8),
                    Text('Hapus',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ]),
                ),
              ],
            );
          }).valueOrNull ?? const SizedBox.shrink(),
        ],
      ),
      body: txAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (txs) {
          final tx = txs.where((t) => t.id == txId).firstOrNull;
          if (tx == null) {
            return const Center(child: Text('Transaksi tidak ditemukan'));
          }
          return itemsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error:   (e, _) => Center(child: Text('Error: $e')),
            data:    (items) => categoriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error:   (e, _) => Center(child: Text('Error: $e')),
              data:    (categories) => _DetailBody(
                tx:         tx,
                items:      items,
                categories: categories,
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Hapus transaksi?'),
        content: const Text(
            'Semua item dalam transaksi ini akan ikut terhapus. '
            'Tindakan ini tidak bisa dibatalkan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:     const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.pop(ctx); // tutup dialog
              final service = ref.read(transactionServiceProvider);
              await service.deleteTransaction(txId);
              ref.invalidate(monthlyTransactionsProvider);
              ref.invalidate(monthlyCategorySummaryProvider);
              ref.invalidate(monthlyTotalProvider);
              if (context.mounted) Navigator.pop(context); // kembali ke list
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Transaction         tx;
  final List<TransactionItem> items;
  final List<Category>      categories;

  const _DetailBody({
    required this.tx,
    required this.items,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final catMap = {for (final c in categories) c.id: c};

    // Group items by category
    final Map<String, List<TransactionItem>> grouped = {};
    for (final item in items) {
      final key = item.categoryId ?? '__none__';
      grouped.putIfAbsent(key, () => []).add(item);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Info header ────────────────────────────────
        Card(
          elevation: 0,
          color:     cs.surfaceContainerHighest,
          shape:     RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _InfoRow(Icons.calendar_today,
                    TransactionService.formatDate(tx.date)),
                if (tx.placeName?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  _InfoRow(Icons.place_outlined, tx.placeName!),
                ],
                if (tx.notes?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  _InfoRow(Icons.notes, tx.notes!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Items grouped by category ──────────────────
        Text('Rincian Item',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                )),
        const SizedBox(height: 10),

        ...grouped.entries.map((entry) {
          final cat = entry.key == '__none__'
              ? null
              : catMap[entry.key];
          final catItems  = entry.value;
          final catTotal  = catItems.fold(0.0, (s, i) => s + i.subtotal);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Kategori label
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      cat != null
                          ? _iconFromString(cat.icon)
                          : Icons.category_outlined,
                      size:  16,
                      color: cat != null
                          ? _hexToColor(cat.color)
                          : cs.onSurface.withOpacity(0.4),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cat?.name ?? 'Tanpa Kategori',
                      style: TextStyle(
                          fontSize:   13,
                          fontWeight: FontWeight.w500,
                          color:      cat != null
                              ? _hexToColor(cat.color)
                              : cs.onSurface.withOpacity(0.5)),
                    ),
                    const Spacer(),
                    Text(TransactionService.formatCurrency(catTotal),
                        style: TextStyle(
                            fontSize:   13,
                            fontWeight: FontWeight.w600,
                            color:      cs.onSurface.withOpacity(0.7))),
                  ],
                ),
              ),

              // Items dalam kategori ini
              ...catItems.map((item) => _ItemRow(item: item)),
              const Divider(height: 16),
            ],
          );
        }),

        const SizedBox(height: 8),

        // ── Total ──────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('TOTAL',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
            Text(
              TransactionService.formatCurrency(tx.totalAmount),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color:      cs.primary,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 60),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  final TransactionItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final hasDisc  = item.discountAmount > 0;
    final grossSub = item.unitPrice * item.quantity;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(
                  '${TransactionService.formatCurrency(item.unitPrice)}'
                  ' × ${_fmtQty(item.quantity)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withOpacity(0.5)),
                ),
                if (hasDisc)
                  Text(
                    'Diskon: -${TransactionService.formatCurrency(item.discountAmount)}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.green.shade600),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(TransactionService.formatCurrency(item.subtotal),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (hasDisc)
                Text(
                  TransactionService.formatCurrency(grossSub),
                  style: TextStyle(
                      fontSize:  11,
                      color:     cs.onSurface.withOpacity(0.35),
                      decoration: TextDecoration.lineThrough),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtQty(double q) =>
      q % 1 == 0 ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
        const SizedBox(width: 10),
        Expanded(child: Text(text,
            style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────
Color _hexToColor(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return Colors.grey;
  }
}

IconData _iconFromString(String name) {
  const map = <String, IconData>{
    'restaurant':               Icons.restaurant,
    'directions_car':           Icons.directions_car,
    'shopping_bag':             Icons.shopping_bag,
    'local_laundry_service':    Icons.local_laundry_service,
    'movie':                    Icons.movie,
    'local_hospital':           Icons.local_hospital,
    'more_horiz':               Icons.more_horiz,
  };
  return map[name] ?? Icons.category;
}