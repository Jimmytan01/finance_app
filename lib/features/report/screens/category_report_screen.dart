// lib/features/report/screens/category_report_screen.dart
//
// Screen drill-down: semua transaksi dalam satu kategori.
// Di-push dari ReportScreen waktu user tap salah satu kategori.
// Sengaja dibuat simple — tidak ada filter tambahan di sini,
// karena kalau mau filter lebih lanjut user bisa balik ke History.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/database_providers.dart';
import '../../../features/transactions/providers/transaction_providers.dart';
import '../../../features/transactions/screens/transaction_detail_screen.dart';
import '../../../features/transactions/services/transaction_service.dart';

class CategoryReportScreen extends ConsumerWidget {
  final String categoryId;
  final String categoryName;
  final Color  color;

  const CategoryReportScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId  = ref.watch(currentUserIdProvider);
    final txAsync = ref.watch(_categoryTxProvider(
        _CategoryParams(userId: userId, categoryId: categoryId)));
 
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width:  10,
              height: 10,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle),
            ),
            Text(categoryName),
          ],
        ),
        centerTitle: true,
      ),
      body: txAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(
                'Tidak ada transaksi di kategori ini',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.4),
                ),
              ),
            );
          }
 
          // Total hanya dari porsi kategori ini — bukan sum total transaksi
          final total = items.fold(0.0, (s, i) => s + i.categoryAmount);
 
          return Column(
            children: [
              // Header: jumlah transaksi + total kategori
              Container(
                width:   double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                color:   Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${items.length} transaksi',
                      style: TextStyle(
                        fontSize: 12,
                        color:    Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      TransactionService.formatCurrency(total),
                      style: const TextStyle(
                        fontSize:   22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
 
              // Daftar transaksi dengan amount per-kategori
              Expanded(
                child: ListView.builder(
                  padding:     const EdgeInsets.only(top: 8, bottom: 32),
                  itemCount:   items.length,
                  itemBuilder: (ctx, i) => _TxTile(item: items[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
 
// ── Tile per transaksi ────────────────────────────────────────
class _TxTile extends StatelessWidget {
  final TransactionWithCategoryAmount item;
  const _TxTile({required this.item});
 
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tx = item.transaction;
 
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 4),
      title: Text(
        tx.placeName?.isNotEmpty == true ? tx.placeName! : 'Tanpa tempat',
        style: const TextStyle(
            fontWeight: FontWeight.w500, fontSize: 14),
      ),
      subtitle: Text(
        TransactionService.formatDate(tx.date),
        style: TextStyle(
          fontSize: 12,
          color:    cs.onSurface.withOpacity(0.45),
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Amount dari kategori ini saja
          Text(
            TransactionService.formatCurrency(item.categoryAmount),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize:   14,
              color:      cs.primary,
            ),
          ),
          // Kalau transaksi punya kategori lain juga, tampilkan info
          if (tx.totalAmount != item.categoryAmount)
            Text(
              'dari ${TransactionService.formatCurrency(tx.totalAmount)}',
              style: TextStyle(
                fontSize: 10,
                color:    cs.onSurface.withOpacity(0.35),
              ),
            ),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => TransactionDetailScreen(txId: tx.id)),
      ),
    );
  }
}
 
// ── Provider ──────────────────────────────────────────────────
class _CategoryParams {
  final String userId;
  final String categoryId;
  const _CategoryParams({required this.userId, required this.categoryId});
 
  @override
  bool operator ==(Object other) =>
      other is _CategoryParams &&
      other.userId == userId &&
      other.categoryId == categoryId;
 
  @override
  int get hashCode => Object.hash(userId, categoryId);
}
 
final _categoryTxProvider = FutureProvider.autoDispose
    .family<List<TransactionWithCategoryAmount>, _CategoryParams>(
        (ref, params) async {
  // Watch syncTick supaya refresh kalau ada data baru dari sync
  ref.watch(syncTickProvider);
 
  final dao = ref.watch(transactionDaoProvider);
  return dao.getTransactionsByCategory(params.userId, params.categoryId);
});