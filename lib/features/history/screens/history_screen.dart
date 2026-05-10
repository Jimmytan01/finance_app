// lib/features/history/screens/history_screen.dart
//
// Halaman riwayat transaksi — lintas bulan, bisa search dan filter.
// Desain UI-nya sengaja lebih "dense" dari home screen karena
// orang yang buka history biasanya lagi nyari sesuatu yang spesifik,
// bukan sekedar lihat ringkasan.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../features/transactions/providers/transaction_providers.dart';
import '../../../features/transactions/screens/transaction_detail_screen.dart';
import '../../../features/transactions/services/transaction_service.dart';
import '../providers/history_providers.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter  = ref.watch(historyFilterProvider);
    final grouped = ref.watch(groupedHistoryProvider);
    final cats    = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _SearchBar(
            controller: _searchCtrl,
            onChanged: (q) =>
                ref.read(historyFilterProvider.notifier).setSearch(q),
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Chip filter ──────────────────────────────
          cats.when(
            loading: () => const SizedBox.shrink(),
            error:   (_, __) => const SizedBox.shrink(),
            data:    (categories) => _FilterChips(
              categories:   categories,
              activeFilter: filter,
            ),
          ),

          // ── Jumlah hasil + sort button ────────────────
          grouped.when(
            loading: () => const SizedBox.shrink(),
            error:   (_, __) => const SizedBox.shrink(),
            data:    (groups) {
              final count =
                  groups.values.fold(0, (s, list) => s + list.length);
              return _ResultBar(
                count:       count,
                sortOrder:   filter.sortOrder,
                isFiltered:  filter.isFiltered,
                onClearAll:  () {
                  _searchCtrl.clear();
                  ref.read(historyFilterProvider.notifier).clearAll();
                },
              );
            },
          ),

          // ── Daftar transaksi ──────────────────────────
          Expanded(
            child: grouped.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error:   (e, _) => Center(child: Text('Terjadi error: $e')),
              data:    (groups) {
                if (groups.isEmpty ||
                    groups.values.every((l) => l.isEmpty)) {
                  return _EmptyHistory(isFiltered: filter.isFiltered);
                }
                return _GroupedList(groups: groups);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Search bar — sengaja taruh di AppBar bottom bukan di body
// supaya tidak ter-scroll waktu user scroll list ke bawah
// ─────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>  onChanged;
  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        controller:   controller,
        onChanged:    onChanged,
        decoration:   InputDecoration(
          hintText:        'Cari tempat atau catatan...',
          prefixIcon:      const Icon(Icons.search, size: 20),
          suffixIcon:      controller.text.isNotEmpty
              ? IconButton(
                  icon:     const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          isDense:         true,
          filled:          true,
          fillColor:       Theme.of(context).colorScheme.surfaceContainerHighest,
          border:          OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:   BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 10),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Filter chips — satu chip per kategori + chip "Semua"
// Pakai horizontal scroll biar bisa muat banyak kategori
// ─────────────────────────────────────────────────────────────

class _FilterChips extends ConsumerWidget {
  final List<Category> categories;
  final HistoryFilter  activeFilter;
  const _FilterChips({required this.categories, required this.activeFilter});
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(historyFilterProvider.notifier);
 
    // hanya tampilkan 4 kategori ini, dengan urutan yang konsisten
    const allowedNames = ['Makan', 'Transport', 'Kebutuhan', 'Laundry'];
    final filteredCats = categories
        .where((c) => allowedNames
            .any((n) => n.toLowerCase() == c.name.toLowerCase()))
        .toList()
      ..sort((a, b) =>
          allowedNames.indexWhere(
              (n) => n.toLowerCase() == a.name.toLowerCase()) -
          allowedNames.indexWhere(
              (n) => n.toLowerCase() == b.name.toLowerCase()));
 
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding:         const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Chip "Semua" selalu ada di paling kiri
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label:     const Text('Semua'),
              selected:  activeFilter.categoryId == null,
              onSelected: (_) => notifier.setCategory(null),
            ),
          ),
          ...filteredCats.map((c) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  avatar: Icon(
                    _iconFromString(c.icon),
                    size:  14,
                    color: _hexToColor(c.color),
                  ),
                  label:     Text(c.name),
                  selected:  activeFilter.categoryId == c.id,
                  onSelected: (_) => notifier.setCategory(
                    activeFilter.categoryId == c.id ? null : c.id,
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Bar hasil pencarian + tombol sort + tombol clear filter
// ─────────────────────────────────────────────────────────────

class _ResultBar extends ConsumerWidget {
  final int       count;
  final SortOrder sortOrder;
  final bool      isFiltered;
  final VoidCallback onClearAll;
  const _ResultBar({
    required this.count,
    required this.sortOrder,
    required this.isFiltered,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Text(
            '$count transaksi',
            style: TextStyle(
              fontSize: 13,
              color:    cs.onSurface.withOpacity(0.5),
            ),
          ),
          if (isFiltered) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onClearAll,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:        cs.errorContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Hapus filter',
                  style: TextStyle(
                    fontSize:   11,
                    color:      cs.onErrorContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
          const Spacer(),
          // Dropdown sort
          PopupMenuButton<SortOrder>(
            initialValue: sortOrder,
            onSelected: (order) =>
                ref.read(historyFilterProvider.notifier).setSortOrder(order),
            itemBuilder: (_) => SortOrder.values
                .map((o) => PopupMenuItem(
                      value: o,
                      child: Row(
                        children: [
                          Icon(
                            o == sortOrder
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size:  16,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(o.label),
                        ],
                      ),
                    ))
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.sort, size: 16,
                      color: cs.onSurface.withOpacity(0.6)),
                  const SizedBox(width: 4),
                  Text(
                    sortOrder.label,
                    style: TextStyle(
                      fontSize: 13,
                      color:    cs.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// List yang dikelompokkan by bulan
// Kalau sort by amount (bukan by date), groups hanya punya 1 key kosong
// dan kita skip section header-nya
// ─────────────────────────────────────────────────────────────

class _GroupedList extends StatelessWidget {
  final Map<String, List<Transaction>> groups;
  const _GroupedList({required this.groups});

  @override
  Widget build(BuildContext context) {
    final showSectionHeader =
        !(groups.length == 1 && groups.keys.first.isEmpty);

    return ListView.builder(
      padding:    const EdgeInsets.only(bottom: 32),
      itemCount:  groups.length,
      itemBuilder: (ctx, i) {
        final monthLabel = groups.keys.elementAt(i);
        final txs        = groups[monthLabel]!;
        final monthTotal = txs.fold(0.0, (s, t) => s + t.totalAmount);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header per bulan
            if (showSectionHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Row(
                  children: [
                    Text(
                      monthLabel,
                      style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.55),
                          ),
                    ),
                    const Spacer(),
                    Text(
                      TransactionService.formatCurrency(monthTotal),
                      style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.55),
                          ),
                    ),
                  ],
                ),
              ),
            ...txs.map((tx) => _HistoryTile(tx: tx)),
          ],
        );
      },
    );
  }
}

// Tile transaksi di history — sedikit lebih compact dari home screen
// karena kita tampilkan lebih banyak info sekaligus (tanggal + jumlah)
class _HistoryTile extends StatelessWidget {
  final Transaction tx;
  const _HistoryTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense:          true,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 2),
      leading: Container(
        width:  38,
        height: 38,
        decoration: BoxDecoration(
          color:        cs.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            // Tampilkan tanggal sebagai "icon" — lebih informatif
            // daripada ikon generik
            tx.date.day.toString(),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize:   15,
              color:      cs.onSecondaryContainer,
            ),
          ),
        ),
      ),
      title: Text(
        tx.placeName?.isNotEmpty == true ? tx.placeName! : 'Tanpa tempat',
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        TransactionService.formatDate(tx.date),
        style: TextStyle(
          fontSize: 11,
          color:    cs.onSurface.withOpacity(0.45),
        ),
      ),
      trailing: Text(
        TransactionService.formatCurrency(tx.totalAmount),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize:   14,
          color:      cs.primary,
        ),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => TransactionDetailScreen(txId: tx.id)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Empty state — beda teks kalau kosong karena filter vs memang kosong
// ─────────────────────────────────────────────────────────────

class _EmptyHistory extends StatelessWidget {
  final bool isFiltered;
  const _EmptyHistory({required this.isFiltered});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFiltered ? Icons.search_off : Icons.history_outlined,
            size:  56,
            color: cs.outlineVariant,
          ),
          const SizedBox(height: 12),
          Text(
            isFiltered
                ? 'Tidak ada transaksi yang cocok'
                : 'Belum ada riwayat transaksi',
            style: TextStyle(
                color: cs.onSurface.withOpacity(0.45)),
          ),
          if (isFiltered) ...[
            const SizedBox(height: 4),
            Text(
              'Coba ubah filter atau kata kunci pencarian',
              style: TextStyle(
                fontSize: 12,
                color:    cs.onSurface.withOpacity(0.3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Helpers (sama dengan di file lain, nanti bisa di-extract ke utils) ──
Color _hexToColor(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return Colors.grey;
  }
}

IconData _iconFromString(String name) {
  const map = <String, IconData>{
    'restaurant':            Icons.restaurant,
    'directions_car':        Icons.directions_car,
    'shopping_bag':          Icons.shopping_bag,
    'local_laundry_service': Icons.local_laundry_service,
    'movie':                 Icons.movie,
    'local_hospital':        Icons.local_hospital,
    'more_horiz':            Icons.more_horiz,
  };
  return map[name] ?? Icons.category;
}