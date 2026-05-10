// lib/features/report/screens/report_screen.dart
//
// Halaman laporan visual. Ada 3 bagian utama:
// 1. Stat cards ringkasan bulan ini
// 2. Bar chart pengeluaran 6 bulan terakhir
// 3. Breakdown per kategori (pie chart + list)
//
// fl_chart dipilih karena API-nya cukup intuitif dan
// tidak butuh setup native. Satu-satunya gotcha: semua
// value di fl_chart pakai double, jadi kita perlu cast.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../features/transactions/providers/transaction_providers.dart';
import '../../../features/transactions/services/transaction_service.dart';
import '../providers/report_providers.dart';
import 'category_report_screen.dart';

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month       = ref.watch(selectedMonthProvider);
    final statsAsync  = ref.watch(monthlyStatsProvider);
    final totalsAsync = ref.watch(monthlyTotalsProvider);
    final summaryAsync = ref.watch(monthlyCategorySummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan'),
        // Toggle rentang chart — 3 atau 6 bulan
        actions: [
          Consumer(builder: (_, ref, __) {
            final range = ref.watch(reportRangeProvider);
            return TextButton(
              onPressed: () => ref
                  .read(reportRangeProvider.notifier)
                  .set(range == 6 ? 3 : 6),
              child: Text('${range == 6 ? 3 : 6} bln'),
            );
          }),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Navigasi bulan (sama seperti home) ────────
          _MonthSelectorRow(month: month),
          const SizedBox(height: 16),

          // ── Stat cards ────────────────────────────────
          statsAsync.when(
            loading: () => const _LoadingCard(height: 100),
            error:   (e, _) => const SizedBox.shrink(),
            data:    (stats) => _StatCards(stats: stats),
          ),
          const SizedBox(height: 24),

          // ── Bar chart ─────────────────────────────────
          Text(
            'Tren pengeluaran',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Consumer(builder: (_, ref, __) {
            final range = ref.watch(reportRangeProvider);
            return Text(
              '$range bulan terakhir',
              style: TextStyle(
                fontSize: 12,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
              ),
            );
          }),
          const SizedBox(height: 12),
          totalsAsync.when(
            loading: () => const _LoadingCard(height: 200),
            error:   (e, _) => const SizedBox.shrink(),
            data:    (totals) => _MonthlyBarChart(totals: totals),
          ),
          const SizedBox(height: 24),

          // ── Pie chart + list kategori ─────────────────
          Text(
            'Per kategori — ${TransactionService.formatMonth(month.year, month.month)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          summaryAsync.when(
            loading: () => const _LoadingCard(height: 300),
            error:   (e, _) => const SizedBox.shrink(),
            data:    (summaries) {
              if (summaries.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Tidak ada data kategori bulan ini',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.4),
                      ),
                    ),
                  ),
                );
              }
              return _CategoryBreakdown(summaries: summaries);
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Navigasi bulan — identik dengan home, tapi di-extract ulang
// karena context-nya berbeda (report bisa bebas pilih bulan mana saja)
// ─────────────────────────────────────────────────────────────

class _MonthSelectorRow extends ConsumerWidget {
  final SelectedMonth month;
  const _MonthSelectorRow({required this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(selectedMonthProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          icon:  const Icon(Icons.chevron_left),
          onPressed: notifier.goPrev,
          style: IconButton.styleFrom(
              backgroundColor: cs.surfaceContainerHighest),
        ),
        Expanded(
          child: Text(
            TransactionService.formatMonth(month.year, month.month),
            textAlign:  TextAlign.center,
            style:      Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        IconButton(
          icon:  const Icon(Icons.chevron_right),
          onPressed: month.isCurrentMonth ? null : notifier.goNext,
          style: IconButton.styleFrom(
            backgroundColor: month.isCurrentMonth
                ? cs.surfaceContainerHighest.withOpacity(0.4)
                : cs.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Stat cards — 3 angka penting dalam satu row
// ─────────────────────────────────────────────────────────────

class _StatCards extends StatelessWidget {
  final MonthlyStats stats;
  const _StatCards({required this.stats});

  @override
  Widget build(BuildContext context) {
    // Hari paling boros — format ringkas "Sel, 14 Jan"
    final busiestLabel =
        '${_dayName(stats.busiestDay.weekday)}, '
        '${stats.busiestDay.day} '
        '${_shortMonth(stats.busiestDay.month)}';

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Total bulan ini',
            value: TransactionService.formatCurrency(stats.totalSpent),
            icon:  Icons.wallet_outlined,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Rata-rata/hari',
            value: TransactionService.formatCurrency(stats.avgPerDay),
            icon:  Icons.today_outlined,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Hari terboros',
            value: busiestLabel,
            icon:  Icons.local_fire_department_outlined,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String   label, value;
  final IconData icon;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding:    const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color:    cs.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Bar chart — satu bar per bulan
//
// fl_chart bekerja dengan index (0, 1, 2...) bukan dengan value sumbu X,
// jadi kita mapping index ke data manual di titlesData.
// ─────────────────────────────────────────────────────────────

class _MonthlyBarChart extends StatelessWidget {
  final List<MonthlyTotal> totals;
  const _MonthlyBarChart({required this.totals});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Cari nilai max untuk skala sumbu Y — tambah 10% biar bar tidak
    // mepet ke atas dan kelihatan lebih lega
    final maxVal = totals.isEmpty
        ? 1.0
        : totals.map((t) => t.total).reduce((a, b) => a > b ? a : b) * 1.1;

    // Bulan aktif yang sedang dilihat user — highlight dengan warna berbeda
    final now = DateTime.now();

    final bars = totals.asMap().entries.map((e) {
      final isCurrentMonth =
          e.value.year == now.year && e.value.month == now.month;
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY:      e.value.total,
            color:    isCurrentMonth ? cs.primary : cs.primary.withOpacity(0.4),
            width:    22,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6)),
          ),
        ],
      );
    }).toList();

    return Container(
      height:     220,
      padding:    const EdgeInsets.fromLTRB(0, 16, 16, 0),
      decoration: BoxDecoration(
        color:        cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: BarChart(
        BarChartData(
          maxY:      maxVal,
          barGroups: bars,
          gridData: FlGridData(
            show:                  true,
            drawVerticalLine:      false,
            getDrawingHorizontalLine: (val) => FlLine(
              color:       cs.outline.withOpacity(0.15),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            // Label bulan di bawah
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles:   true,
                reservedSize: 28,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx < 0 || idx >= totals.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      totals[idx].shortLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color:    cs.onSurface.withOpacity(0.5),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Sembunyikan label sumbu yang tidak perlu
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles:  const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                TransactionService.formatCurrency(rod.toY),
                TextStyle(
                  color:      cs.onPrimary,
                  fontSize:   12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Breakdown kategori — pie chart + list yang bisa di-tap
// Pie chart di fl_chart tidak punya built-in legend,
// jadi kita bikin sendiri di sebelah kanannya
// ─────────────────────────────────────────────────────────────

class _CategoryBreakdown extends StatefulWidget {
  final List<CategorySummary> summaries;
  const _CategoryBreakdown({required this.summaries});

  @override
  State<_CategoryBreakdown> createState() => _CategoryBreakdownState();
}

class _CategoryBreakdownState extends State<_CategoryBreakdown> {
  // Index yang sedang di-hover/touch di pie chart
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final total = widget.summaries.fold(0.0, (s, c) => s + c.total);
    final sorted = [...widget.summaries]
      ..sort((a, b) => b.total.compareTo(a.total));

    final sections = sorted.asMap().entries.map((e) {
      final isTouched = e.key == _touchedIndex;
      final pct       = total > 0 ? (e.value.total / total) : 0.0;
      return PieChartSectionData(
        value:  e.value.total,
        color:  _hexToColor(e.value.color),
        radius: isTouched ? 64 : 56,
        // Tampilkan persen hanya kalau porsinya cukup besar (> 5%)
        // biar label tidak saling tumpuk
        title:  pct > 0.05 ? '${(pct * 100).round()}%' : '',
        titleStyle: TextStyle(
          fontSize:   11,
          fontWeight: FontWeight.w700,
          color:      Colors.white.withOpacity(0.9),
        ),
      );
    }).toList();

    return Column(
      children: [
        // Pie chart + legend berdampingan
        SizedBox(
          height: 180,
          child: Row(
            children: [
              // Pie chart
              Expanded(
                flex: 2,
                child: PieChart(
                  PieChartData(
                    sections:         sections,
                    centerSpaceRadius: 36,
                    sectionsSpace:    2,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              response?.touchedSection == null) {
                            _touchedIndex = null;
                          } else {
                            _touchedIndex = response!
                                .touchedSection!.touchedSectionIndex;
                          }
                        });
                      },
                    ),
                  ),
                ),
              ),
              // Legend
              Expanded(
                flex: 3,
                child: ListView(
                  shrinkWrap: true,
                  physics:    const NeverScrollableScrollPhysics(),
                  children:   sorted.asMap().entries.map((e) {
                    final pct = total > 0
                        ? (e.value.total / total * 100).round()
                        : 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width:  10,
                            height: 10,
                            decoration: BoxDecoration(
                              color:        _hexToColor(e.value.color),
                              shape:        BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e.value.categoryName,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '$pct%',
                            style: TextStyle(
                              fontSize:   11,
                              fontWeight: FontWeight.w600,
                              color:      cs.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // List kategori — bisa di-tap untuk drill-down
        ...sorted.map((s) => _CategoryTile(
              summary: s,
              total:   total,
            )),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final CategorySummary summary;
  final double          total;
  const _CategoryTile({required this.summary, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final pct = total > 0 ? summary.total / total : 0.0;

    return Card(
      margin:    const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color:     cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: summary.categoryId == null
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryReportScreen(
                      categoryId:   summary.categoryId!,
                      categoryName: summary.categoryName,
                      color:        _hexToColor(summary.color),
                    ),
                  ),
                ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    _iconFromString(summary.icon),
                    size:  18,
                    color: _hexToColor(summary.color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      summary.categoryName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                  ),
                  Text(
                    TransactionService.formatCurrency(summary.total),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(width: 4),
                  // Panah hanya tampil kalau ada categoryId (bisa di-tap)
                  if (summary.categoryId != null)
                    Icon(Icons.chevron_right,
                        size: 16,
                        color: cs.onSurface.withOpacity(0.3)),
                ],
              ),
              const SizedBox(height: 8),
              // Progress bar porsi dari total
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value:           pct,
                  minHeight:       5,
                  backgroundColor: cs.outline.withOpacity(0.12),
                  valueColor:      AlwaysStoppedAnimation<Color>(
                      _hexToColor(summary.color)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shimmer placeholder sederhana ────────────────────────────
class _LoadingCard extends StatelessWidget {
  final double height;
  const _LoadingCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height:     height,
      decoration: BoxDecoration(
        color:        Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────
String _dayName(int weekday) {
  const names = ['', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  return names[weekday];
}

String _shortMonth(int month) {
  const names = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  return names[month];
}

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