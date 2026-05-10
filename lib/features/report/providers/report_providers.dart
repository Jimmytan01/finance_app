// Provider untuk semua data yang ditampilkan di ReportScreen.
// Sengaja tidak digabung ke transaction_providers karena report
// bekerja dengan rentang multi-bulan, bukan single bulan.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/database_providers.dart';
import '../../transactions/providers/transaction_providers.dart';

export '../../transactions/providers/transaction_providers.dart'
    show monthlyCategorySummaryProvider, selectedMonthProvider;

// ─────────────────────────────────────────────────────────────
// Berapa bulan ke belakang yang ditampilkan di bar chart.
// Defaultnya 6 bulan — cukup untuk lihat tren tanpa terlalu ramai.
// User bisa ganti via toggle nanti.
// ─────────────────────────────────────────────────────────────

class ReportRangeNotifier extends Notifier<int> {
  @override
  int build() => 6;
  void set(int months) => state = months;
}

final reportRangeProvider =
    NotifierProvider<ReportRangeNotifier, int>(ReportRangeNotifier.new);

// ─────────────────────────────────────────────────────────────
// Data bar chart — total per bulan
// ─────────────────────────────────────────────────────────────

final monthlyTotalsProvider =
    FutureProvider.autoDispose<List<MonthlyTotal>>((ref) async {
  ref.watch(syncTickProvider);
 
  final dao        = ref.watch(transactionDaoProvider);
  final userId     = ref.watch(currentUserIdProvider);
  final monthsBack = ref.watch(reportRangeProvider);
  return dao.getMonthlyTotals(userId, monthsBack: monthsBack);
});

// ─────────────────────────────────────────────────────────────
// Statistik bulan yang dipilih di selectedMonthProvider
// (sama dengan bulan yang sedang dilihat di home screen)
// ─────────────────────────────────────────────────────────────

final monthlyStatsProvider =
    FutureProvider.autoDispose<MonthlyStats>((ref) async {
  ref.watch(syncTickProvider);
 
  final dao    = ref.watch(transactionDaoProvider);
  final userId = ref.watch(currentUserIdProvider);
  final month  = ref.watch(selectedMonthProvider);
  return dao.getMonthlyStats(userId, month.year, month.month);
});

// ─────────────────────────────────────────────────────────────
// Breakdown kategori — data untuk pie chart.
// Kita reuse monthlyCategorySummaryProvider dari transaction_providers
// karena data-nya sudah sama persis yang dibutuhkan.
// Tidak perlu bikin provider baru hanya untuk ganti nama.
// ─────────────────────────────────────────────────────────────
// Export ulang di sini supaya ReportScreen tidak perlu import
// dari 2 tempat yang berbeda: