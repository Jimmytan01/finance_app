// lib/features/transactions/screens/transaction_list_screen.dart
//
// Screen utama: ringkasan bulan + daftar transaksi.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../providers/transaction_providers.dart';
import '../services/transaction_service.dart';
import 'add_transaction_screen.dart';
import 'transaction_detail_screen.dart';

class TransactionListScreen extends ConsumerWidget {
  const TransactionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month        = ref.watch(selectedMonthProvider);
    final txAsync      = ref.watch(monthlyTransactionsProvider);
    final summaryAsync = ref.watch(monthlyCategorySummaryProvider);
    final totalAsync   = ref.watch(monthlyTotalProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header bulan ──────────────────────────────
            _MonthHeader(month: month),

            // ── Total & ringkasan kategori ─────────────────
            summaryAsync.when(
              loading: () => const _SummaryShimmer(),
              error:   (e, _) => const SizedBox.shrink(),
              data:    (summaries) => totalAsync.when(
                loading: () => const _SummaryShimmer(),
                error:   (e, _) => const SizedBox.shrink(),
                data:    (total) => _MonthlySummaryCard(
                  summaries: summaries,
                  total:     total,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Daftar transaksi ──────────────────────────
            Expanded(
              child: txAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error:   (e, _) => Center(child: Text('Error: $e')),
                data:    (txs) => txs.isEmpty
                    ? const _EmptyState()
                    : _TransactionList(transactions: txs),
              ),
            ),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ref.read(addTransactionProvider.notifier).reset();
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AddTransactionScreen()));
        },
        icon:  const Icon(Icons.add),
        label: const Text('Tambah'),
      ),
    );
  }
}

// ── Month header dengan navigasi ──────────────────────────
class _MonthHeader extends ConsumerWidget {
  final SelectedMonth month;
  const _MonthHeader({required this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(selectedMonthProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: notifier.goPrev,
            style: IconButton.styleFrom(
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: month.isCurrentMonth ? null : notifier.goToNow,
              child: Column(
                children: [
                  Text(
                    TransactionService.formatMonth(month.year, month.month),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  if (!month.isCurrentMonth)
                    Text(
                      'Kembali ke bulan ini',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.primary,
                          ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: month.isCurrentMonth ? null : notifier.goNext,
            style: IconButton.styleFrom(
              backgroundColor: month.isCurrentMonth
                  ? cs.surfaceContainerHighest.withOpacity(0.4)
                  : cs.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Kartu ringkasan bulanan ────────────────────────────────
class _MonthlySummaryCard extends StatelessWidget {
  final List<CategorySummary> summaries;
  final double total;
  const _MonthlySummaryCard({required this.summaries, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sorted = [...summaries]
      ..sort((a, b) => b.total.compareTo(a.total));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Total bulan ini',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onPrimaryContainer.withOpacity(0.7),
                      )),
              const Spacer(),
              Text(
                TransactionService.formatCurrency(total),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer,
                    ),
              ),
            ],
          ),
          if (sorted.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Progress bar tiap kategori
            ...sorted.map((s) => _CategoryBar(
                  summary: s,
                  total:   total,
                  onPrimaryContainer: cs.onPrimaryContainer,
                )),
          ],
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final CategorySummary summary;
  final double total;
  final Color onPrimaryContainer;
  const _CategoryBar({
    required this.summary,
    required this.total,
    required this.onPrimaryContainer,
  });

  @override
  Widget build(BuildContext context) {
    final pct   = total > 0 ? (summary.total / total).clamp(0.0, 1.0) : 0.0;
    final color = _hexToColor(summary.color);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _iconFromString(summary.icon),
                size: 14,
                color: onPrimaryContainer.withOpacity(0.8),
              ),
              const SizedBox(width: 6),
              Text(
                summary.categoryName,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: onPrimaryContainer.withOpacity(0.8),
                    ),
              ),
              const Spacer(),
              Text(
                TransactionService.formatCurrency(summary.total),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:           pct,
              minHeight:       6,
              backgroundColor: onPrimaryContainer.withOpacity(0.15),
              valueColor:      AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Daftar transaksi grouped by date ──────────────────────
class _TransactionList extends StatelessWidget {
  final List<Transaction> transactions;
  const _TransactionList({required this.transactions});

  @override
  Widget build(BuildContext context) {
    // Group by date
    final Map<String, List<Transaction>> grouped = {};
    for (final tx in transactions) {
      final key = TransactionService.formatDate(tx.date);
      grouped.putIfAbsent(key, () => []).add(tx);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: grouped.length,
      itemBuilder: (ctx, i) {
        final date = grouped.keys.elementAt(i);
        final txs  = grouped[date]!;
        final dayTotal = txs.fold(0.0, (s, t) => s + t.totalAmount);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tanggal header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    date,
                    style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(ctx).colorScheme.onSurface
                              .withOpacity(0.6),
                        ),
                  ),
                  const Spacer(),
                  Text(
                    TransactionService.formatCurrency(dayTotal),
                    style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurface
                              .withOpacity(0.6),
                        ),
                  ),
                ],
              ),
            ),
            ...txs.map((tx) => _TransactionTile(tx: tx)),
          ],
        );
      },
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Transaction tx;
  const _TransactionTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.receipt_long,
              color: cs.onSecondaryContainer, size: 22),
        ),
        title: Text(
          tx.placeName?.isNotEmpty == true
              ? tx.placeName!
              : 'Tanpa tempat',
          style: const TextStyle(fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: tx.notes?.isNotEmpty == true
            ? Text(tx.notes!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.5)))
            : null,
        trailing: Text(
          TransactionService.formatCurrency(tx.totalAmount),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => TransactionDetailScreen(txId: tx.id)),
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('Belum ada transaksi bulan ini',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.5),
                  )),
          const SizedBox(height: 8),
          Text('Ketuk tombol + untuk menambah',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.35),
                  )),
        ],
      ),
    );
  }
}

// ── Shimmer loading state ──────────────────────────────────
class _SummaryShimmer extends StatelessWidget {
  const _SummaryShimmer();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 80,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────
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