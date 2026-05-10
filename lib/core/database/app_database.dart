// ============================================================
//  lib/core/database/app_database.dart
//
//  Drift ORM — SQLite lokal (offline-first)
//  Jalankan: dart run build_runner build --delete-conflicting-outputs
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

part 'app_database.g.dart';


// ============================================================
//  ENUMS
// ============================================================
enum DiscountType { percent, flat }


// ============================================================
//  TABLE: Categories
// ============================================================
class Categories extends Table {
  TextColumn get id          => text().clientDefault(_uuid)();
  TextColumn get userId      => text()();
  TextColumn get name        => text()();
  TextColumn get icon        => text().withDefault(const Constant('category'))();
  TextColumn get color       => text().withDefault(const Constant('#888888'))();
  BoolColumn get isDefault   => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


// ============================================================
//  TABLE: Transactions
// ============================================================
class Transactions extends Table {
  TextColumn get id           => text().clientDefault(_uuid)();
  TextColumn get userId       => text()();
  DateTimeColumn get date     => dateTime()();
  TextColumn get placeName    => text().nullable()();
  TextColumn get notes        => text().nullable()();
  RealColumn get totalAmount  => real().withDefault(const Constant(0.0))();
  TextColumn get deviceId     => text().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


// ============================================================
//  TABLE: TransactionItems
// ============================================================
class TransactionItems extends Table {
  TextColumn get id             => text().clientDefault(_uuid)();
  TextColumn get transactionId  => text().references(Transactions, #id)();
  TextColumn get categoryId     => text().nullable()();   // references Categories
  TextColumn get name           => text()();
  RealColumn get unitPrice      => real().withDefault(const Constant(0.0))();
  RealColumn get quantity       => real().withDefault(const Constant(1.0))();
  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();
  RealColumn get subtotal       => real().withDefault(const Constant(0.0))();
  // subtotal = (unitPrice * quantity) - discountAmount  ← dihitung di app layer
  TextColumn get notes          => text().nullable()();
  DateTimeColumn get createdAt  => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt  => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


// ============================================================
//  TABLE: BillSessions
// ============================================================
class BillSessions extends Table {
  TextColumn get id             => text().clientDefault(_uuid)();
  TextColumn get userId         => text()();
  TextColumn get title          => text()();
  DateTimeColumn get date       => dateTime()();
  TextColumn get placeName      => text().nullable()();
  TextColumn get discountType   => text().withDefault(const Constant('flat'))();
  // 'percent' | 'flat'
  RealColumn get discountValue  => real().withDefault(const Constant(0.0))();
  RealColumn get taxPercent     => real().withDefault(const Constant(0.0))();
  RealColumn get totalAmount    => real().withDefault(const Constant(0.0))();
  TextColumn get linkedTxId     => text().nullable()();  // references Transactions
  DateTimeColumn get createdAt  => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt  => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


// ============================================================
//  TABLE: BillParticipants
// ============================================================
class BillParticipants extends Table {
  TextColumn get id             => text().clientDefault(_uuid)();
  TextColumn get billSessionId  => text().references(BillSessions, #id)();
  TextColumn get name           => text()();
  BoolColumn get isSelf         => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt  => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


// ============================================================
//  TABLE: BillItems
// ============================================================
class BillItems extends Table {
  TextColumn get id             => text().clientDefault(_uuid)();
  TextColumn get billSessionId  => text().references(BillSessions, #id)();
  TextColumn get name           => text()();
  RealColumn get unitPrice      => real().withDefault(const Constant(0.0))();
  IntColumn get quantity        => integer().withDefault(const Constant(1))();
  RealColumn get subtotal       => real().withDefault(const Constant(0.0))();
  // subtotal = unitPrice * quantity
  DateTimeColumn get createdAt  => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


// ============================================================
//  TABLE: BillItemParticipants
// ============================================================
class BillItemParticipants extends Table {
  TextColumn get id             => text().clientDefault(_uuid)();
  TextColumn get billItemId     => text().references(BillItems, #id)();
  TextColumn get participantId  => text().references(BillParticipants, #id)();
  RealColumn get shareQty       => real().withDefault(const Constant(1.0))();
  RealColumn get shareAmount    => real().withDefault(const Constant(0.0))();
  // shareAmount = porsi setelah diskon & pajak dibagi

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {billItemId, participantId},
  ];
}


// ============================================================
//  TABLE: Devices
// ============================================================
class Devices extends Table {
  TextColumn get id           => text().clientDefault(_uuid)();
  TextColumn get userId       => text()();
  TextColumn get deviceName   => text()();
  TextColumn get platform     => text()();
  // 'android' | 'ios' | 'windows' | 'macos' | 'linux'
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  DateTimeColumn get createdAt  => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}


// ============================================================
//  TABLE: SyncQueue  ← khusus lokal, tidak ada di Supabase
//  Menyimpan perubahan lokal yang belum ter-sync
// ============================================================
enum SyncOperation { insert, update, delete }

class SyncQueue extends Table {
  IntColumn get id          => integer().autoIncrement()();
  TextColumn get targetTable => text().named('table_name')();       // nama tabel yang berubah
  TextColumn get recordId   => text()();       // id record yang berubah
  TextColumn get operation  => text()();       // 'insert' | 'update' | 'delete'
  TextColumn get payload    => text()();       // JSON dari record
  DateTimeColumn get queuedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get retryCount  => integer().withDefault(const Constant(0))();
}


// ============================================================
//  DATABASE
// ============================================================
@DriftDatabase(tables: [
  Categories,
  Transactions,
  TransactionItems,
  BillSessions,
  BillParticipants,
  BillItems,
  BillItemParticipants,
  Devices,
  SyncQueue,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedDefaultCategories();
    },
    onUpgrade: (m, from, to) async {
      // Tambahkan migration di sini saat schema berubah
      // if (from < 2) { await m.addColumn(...); }
    },
  );

  // Seed kategori default untuk user baru (lokal)
  Future<void> _seedDefaultCategories() async {
    // userId akan di-set setelah login; gunakan placeholder dulu
    // SyncService akan update userId setelah auth
  }
}

// ============================================================
//  DATABASE CONNECTION
// ============================================================
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'finance_app.db'));
    return NativeDatabase.createInBackground(file);
  });
}

// Helper UUID generator (gunakan package uuid)
String _uuid() {
  // tambahkan package: uuid: ^4.0.0 di pubspec.yaml
  // import 'package:uuid/uuid.dart';
  // String _uuid() => const Uuid().v4();
  throw UnimplementedError('Import package uuid dan implementasi di sini');
}


// ============================================================
//  DATA ACCESS OBJECTS (DAOs)
// ============================================================

// ---- TransactionDao ----
@DriftAccessor(tables: [Transactions, TransactionItems, Categories])
class TransactionDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionDaoMixin {
  TransactionDao(super.db);

  // Semua transaksi milik user, urut terbaru
  Future<List<Transaction>> getAllByUser(String userId) =>
      (select(transactions)
        ..where((t) => t.userId.equals(userId))
        ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .get();

  // Transaksi per bulan
  Future<List<Transaction>> getByMonth(String userId, int year, int month) {
    final start = DateTime(year, month, 1);
    final end   = DateTime(year, month + 1, 1);
    return (select(transactions)
      ..where((t) =>
          t.userId.equals(userId) &
          t.date.isBiggerOrEqualValue(start) &
          t.date.isSmallerThanValue(end))
      ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
  }

  // Insert transaksi + items sekaligus (dalam satu transaksi DB)
  Future<void> insertFull({
    required TransactionsCompanion header,
    required List<TransactionItemsCompanion> items,
  }) =>
      transaction(() async {
        await into(transactions).insert(header);
        await batch((b) => b.insertAll(transactionItems, items));
      });

  // Update total_amount dari jumlah semua items
  Future<void> recalculateTotal(String txId) async {
    final rows = await (select(transactionItems)
          ..where((i) => i.transactionId.equals(txId)))
        .get();
 
    final total = rows.fold(0.0, (sum, r) => sum + r.subtotal);
 
    await (update(transactions)..where((t) => t.id.equals(txId)))
        .write(TransactionsCompanion(
          totalAmount: Value(total),
          updatedAt:   Value(DateTime.now()),
        ));
  }
 
  // Hitung ulang semua transaksi milik user sekaligus.
  // Panggil ini sekali setelah cleanup selesai.
  Future<void> recalculateAllTotals(String userId) async {
    final allTx = await (select(transactions)
          ..where((t) => t.userId.equals(userId)))
        .get();
 
    for (final tx in allTx) {
      await recalculateTotal(tx.id);
    }
  }

  // Ringkasan per kategori dalam satu bulan
  Future<List<CategorySummary>> getMonthlyCategorySummary(
      String userId, int year, int month) async {
    final start = DateTime(year, month, 1);
    final end   = DateTime(year, month + 1, 1);
 
    final query = select(transactionItems).join([
      innerJoin(
        transactions,
        transactions.id.equalsExp(transactionItems.transactionId),
      ),
      leftOuterJoin(
        categories,
        categories.id.equalsExp(transactionItems.categoryId),
      ),
    ])
      ..where(
        transactions.userId.equals(userId) &
        transactions.date.isBiggerOrEqualValue(start) &
        transactions.date.isSmallerThanValue(end),
      )
      // groupBy ini yang sebelumnya hilang — tanpanya semua item
      // dijumlah jadi satu baris dengan kategori yang kebetulan pertama
      ..groupBy([
        transactionItems.categoryId,
        categories.id,
        categories.name,
        categories.icon,
        categories.color,
      ])
      ..addColumns([transactionItems.subtotal.sum()]);
 
    final rows = await query.get();
 
    return rows.map((row) {
      final cat = row.readTableOrNull(categories);
      return CategorySummary(
        categoryId:   cat?.id,
        categoryName: cat?.name ?? 'Tanpa Kategori',
        icon:         cat?.icon ?? 'category',
        color:        cat?.color ?? '#888888',
        total:        row.read(transactionItems.subtotal.sum()) ?? 0.0,
      );
    }).toList();
  }

  // Hapus transaksi beserta items-nya (cascade via FK)
  Future<void> deleteTransaction(String txId) =>
      (delete(transactions)..where((t) => t.id.equals(txId))).go();

  // Ambil semua items milik satu transaksi
  Future<List<TransactionItem>> getItemsByTxId(String txId) =>
      (select(transactionItems)
            ..where((i) => i.transactionId.equals(txId))
            ..orderBy([(i) => OrderingTerm.asc(i.createdAt)]))
          .get();
 
  Future<void> deleteItemsByTxId(String txId) =>
      (delete(transactionItems)
            ..where((i) => i.transactionId.equals(txId)))
          .go();
 
  Future<void> updateHeaderAndItems({
    required String txId,
    required TransactionsCompanion header,
    required List<TransactionItemsCompanion> items,
  }) =>
      transaction(() async {
        await (update(transactions)..where((t) => t.id.equals(txId)))
            .write(header);
        await batch((b) => b.insertAll(transactionItems, items));
      });
  // Semua transaksi milik user tanpa filter bulan — untuk halaman history.
  // Kita limit default 200 baris karena realistically orang jarang scroll
  // lebih dari itu. Kalau nanti butuh pagination baru kita tambah offset.
  Future<List<Transaction>> getAllTransactions(
    String userId, {
    int limit = 200,
  }) =>
      (select(transactions)
            ..where((t) => t.userId.equals(userId))
            ..orderBy([(t) => OrderingTerm.desc(t.date)])
            ..limit(limit))
          .get();
 
  // Cari transaksi berdasarkan nama tempat.
  // Kenapa tidak search by nama item sekalian? Karena query JOIN
  // untuk itu lebih berat — kita handle filter nama item di sisi Dart
  // setelah data sudah dimuat. Untuk dataset pribadi (ratusan baris)
  // ini jauh lebih simpel dan cukup cepat.
  Future<List<Transaction>> searchByPlace(
    String userId,
    String keyword,
  ) =>
      (select(transactions)
            ..where((t) =>
                t.userId.equals(userId) &
                t.placeName.like('%$keyword%'))
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .get();
 
  // Return transaksi beserta amount khusus kategori yang dipilih.
  // Satu transaksi bisa punya item dari banyak kategori — kita hanya
  // jumlahkan subtotal item yang categoryId-nya sesuai.
  Future<List<TransactionWithCategoryAmount>> getTransactionsByCategory(
    String userId,
    String categoryId,
  ) async {
    // Ambil semua item dari kategori ini
    final itemRows = await (select(transactionItems)
          ..where((i) => i.categoryId.equals(categoryId)))
        .get();
 
    if (itemRows.isEmpty) return [];
 
    // Group by transaction_id dan sum subtotalnya
    final amountByTxId = <String, double>{};
    for (final item in itemRows) {
      amountByTxId[item.transactionId] =
          (amountByTxId[item.transactionId] ?? 0) + item.subtotal;
    }
 
    // Ambil transaksi yang terkait, filter by userId
    final txIds = amountByTxId.keys.toList();
    final txRows = await (select(transactions)
          ..where((t) =>
              t.userId.equals(userId) & t.id.isIn(txIds))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
 
    // Gabungkan: transaksi + amount kategorinya saja
    return txRows.map((tx) => TransactionWithCategoryAmount(
          transaction:     tx,
          categoryAmount:  amountByTxId[tx.id] ?? 0,
        )).toList();
  }
  
  // Transaksi per kategori — untuk drill-down dari report ke list.
  // Harus JOIN ke transaction_items karena kategori ada di level item,
  // bukan di level transaksi header.
  Future<List<Transaction>> getByCategory(
    String userId,
    String categoryId,
  ) async {
    final itemRows = await (select(transactionItems)
          ..where((i) => i.categoryId.equals(categoryId)))
        .get();
 
    final txIds = itemRows.map((i) => i.transactionId).toSet().toList();
    if (txIds.isEmpty) return [];
 
    return (select(transactions)
          ..where((t) =>
              t.userId.equals(userId) & t.id.isIn(txIds))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
  }
 
  // Data untuk bar chart: total pengeluaran per bulan.
  // Kita ambil N bulan ke belakang dari sekarang.
  // Return List<MonthlyTotal> yang sudah diurutkan dari bulan terlama.
  Future<List<MonthlyTotal>> getMonthlyTotals(
    String userId, {
    int monthsBack = 6,
  }) async {
    final now   = DateTime.now();
    // Mulai dari awal bulan N bulan yang lalu
    final start = DateTime(now.year, now.month - monthsBack + 1, 1);
 
    // Query semua transaksi dalam rentang itu
    final rows = await (select(transactions)
          ..where((t) =>
              t.userId.equals(userId) &
              t.date.isBiggerOrEqualValue(start))
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .get();
 
    // Group di sisi Dart — lebih mudah daripada raw SQL grouping di Drift
    final map = <String, double>{};
    for (final tx in rows) {
      final key = '${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}';
      map[key] = (map[key] ?? 0) + tx.totalAmount;
    }
 
    // Pastikan semua bulan dalam range ada (termasuk yang 0 transaksi)
    final result = <MonthlyTotal>[];
    for (var i = monthsBack - 1; i >= 0; i--) {
      final d   = DateTime(now.year, now.month - i, 1);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      result.add(MonthlyTotal(
        year:  d.year,
        month: d.month,
        total: map[key] ?? 0,
      ));
    }
    return result;
  }
 
  // Statistik ringkas untuk satu bulan — ditampilkan di bagian atas ReportScreen.
  Future<MonthlyStats> getMonthlyStats(
    String userId,
    int year,
    int month,
  ) async {
    final start = DateTime(year, month, 1);
    final end   = DateTime(year, month + 1, 1);
 
    final rows = await (select(transactions)
          ..where((t) =>
              t.userId.equals(userId) &
              t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end)))
        .get();
 
    if (rows.isEmpty) {
      return MonthlyStats.empty(year: year, month: month);
    }
 
    final total   = rows.fold(0.0, (s, t) => s + t.totalAmount);
    final daysInMonth = end.difference(start).inDays;
 
    // Cari hari paling boros: group by date, cari max
    final byDate = <DateTime, double>{};
    for (final tx in rows) {
      final d = DateTime(tx.date.year, tx.date.month, tx.date.day);
      byDate[d] = (byDate[d] ?? 0) + tx.totalAmount;
    }
    final busiestEntry = byDate.entries
        .reduce((a, b) => a.value > b.value ? a : b);
 
    return MonthlyStats(
      year:          year,
      month:         month,
      totalSpent:    total,
      txCount:       rows.length,
      avgPerDay:     total / daysInMonth,
      busiestDay:    busiestEntry.key,
      busiestAmount: busiestEntry.value,
    );
  }
}


// ---- BillDao ----
@DriftAccessor(tables: [
  BillSessions, BillParticipants, BillItems, BillItemParticipants
])
class BillDao extends DatabaseAccessor<AppDatabase> with _$BillDaoMixin {
  BillDao(super.db);

  Future<List<BillSession>> getAllByUser(String userId) =>
      (select(billSessions)
        ..where((b) => b.userId.equals(userId))
        ..orderBy([(b) => OrderingTerm.desc(b.date)]))
          .get();
  
  Future<List<BillSession>> getAllSessions(String userId) =>
      (select(billSessions)
            ..where((b) => b.userId.equals(userId))
            ..orderBy([(b) => OrderingTerm.desc(b.date)]))
          .get();

  Future<void> deleteSession(String sessionId) =>
      transaction(() async {
        // Hapus splits dulu (paling dalam), lalu naik ke atas
        final items = await (select(billItems)
              ..where((i) => i.billSessionId.equals(sessionId)))
            .get();
 
        for (final item in items) {
          await (delete(billItemParticipants)
                ..where((s) => s.billItemId.equals(item.id)))
              .go();
        }
 
        await (delete(billItems)
              ..where((i) => i.billSessionId.equals(sessionId)))
            .go();
 
        await (delete(billParticipants)
              ..where((p) => p.billSessionId.equals(sessionId)))
            .go();
 
        await (delete(billSessions)
              ..where((b) => b.id.equals(sessionId)))
            .go();
      });

  Future<void> insertFullBillSession({
    required BillSessionsCompanion session,
    required List<BillParticipantsCompanion> participants,
    required List<BillItemsCompanion> items,
    required List<BillItemParticipantsCompanion> splits,
  }) =>
      transaction(() async {
        await into(billSessions).insert(session);
 
        await batch((b) {
          b.insertAll(billParticipants, participants);
          b.insertAll(billItems, items);
          b.insertAll(billItemParticipants, splits);
        });
      });

  Future<void> linkToTransaction(String sessionId, String txId) =>
      (update(billSessions)..where((b) => b.id.equals(sessionId))).write(
        BillSessionsCompanion(linkedTxId: Value(txId)),
      );

  // Insert sesi bill lengkap dalam satu transaksi DB
  Future<void> insertFullSession({
    required BillSessionsCompanion session,
    required List<BillParticipantsCompanion> participants,
    required List<BillItemsCompanion> items,
    required List<BillItemParticipantsCompanion> itemParticipants,
  }) =>
      transaction(() async {
        await into(billSessions).insert(session);
        await batch((b) {
          b.insertAll(billParticipants, participants);
          b.insertAll(billItems, items);
          b.insertAll(billItemParticipants, itemParticipants);
        });
      });

  // Ambil semua data satu sesi (untuk tampil hasil split)
  Future<BillSessionDetail> getSessionDetail(String sessionId) async {
    final session = await (select(billSessions)
          ..where((b) => b.id.equals(sessionId)))
        .getSingle();
    final parts = await (select(billParticipants)
          ..where((p) => p.billSessionId.equals(sessionId)))
        .get();
    final items = await (select(billItems)
          ..where((i) => i.billSessionId.equals(sessionId)))
        .get();
    final splits = await (select(billItemParticipants).join([
      innerJoin(billItems,
          billItems.id.equalsExp(billItemParticipants.billItemId)),
    ])
          ..where(billItems.billSessionId.equals(sessionId)))
        .get();

    return BillSessionDetail(
      session:      session,
      participants: parts,
      items:        items,
      splits:       splits
          .map((r) => r.readTable(billItemParticipants))
          .toList(),
    );
  }
}


// ---- CategoryDao ----
@DriftAccessor(tables: [Categories])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  CategoryDao(super.db);

  Future<List<Category>> getAll(String userId) =>
      (select(categories)
        ..where((c) => c.userId.equals(userId))
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .get();

  Future<void> upsert(CategoriesCompanion cat) =>
      into(categories).insertOnConflictUpdate(cat);

  // Insert atau update kategori (upsert by id)
  Future<void> upsertCategory(CategoriesCompanion cat) =>
      into(categories).insertOnConflictUpdate(cat);
 
  // Seed kategori default untuk user baru (dipanggil setelah login)
  Future<void> seedDefaultsIfEmpty(
    String userId, {
    SyncQueueDao? syncQueueDao,
  }) async {
    final existing = await (select(categories)
          ..where((c) => c.userId.equals(userId)))
        .get();
 
    if (existing.isNotEmpty) return;
 
    const defaults = [
      ('Makan',     'restaurant',            '#EF9F27'),
      ('Transport', 'directions_car',         '#378ADD'),
      ('Kebutuhan', 'shopping_bag',           '#1D9E75'),
      ('Laundry',   'local_laundry_service',  '#D4537E'),
    ];
 
    final now      = DateTime.now();
    final newCats  = defaults.map((d) {
      final id = const Uuid().v4();
      return CategoriesCompanion.insert(
        id:        Value(id),
        userId:    userId,
        name:      d.$1,
        icon:      Value(d.$2),
        color:     Value(d.$3),
        isDefault: const Value(true),
        createdAt: Value(now),
        updatedAt: Value(now),
      );
    }).toList();
 
    // Insert ke SQLite lokal
    await batch((b) => b.insertAll(categories, newCats));
 
    // FIX: Enqueue ke SyncQueue supaya ter-push ke Supabase.
    // Kalau tidak di-enqueue, device lain tidak dapat kategori ini
    // dan semua transaksi akan muncul sebagai "Tanpa Kategori".
    if (syncQueueDao != null) {
      final inserted = await (select(categories)
            ..where((c) => c.userId.equals(userId)))
          .get();
 
      for (final cat in inserted) {
        await syncQueueDao.enqueue(SyncQueueCompanion(
          targetTable: const Value('categories'),
          recordId:    Value(cat.id),
          operation:   const Value('insert'),
          payload:     Value(jsonEncode({
            'id':         cat.id,
            'user_id':    cat.userId,
            'name':       cat.name,
            'icon':       cat.icon,
            'color':      cat.color,
            'is_default': cat.isDefault,
            'created_at': cat.createdAt.toIso8601String(),
            'updated_at': cat.updatedAt.toIso8601String(),
          })),
          queuedAt:    Value(now),
          retryCount:  const Value(0),
        ));
      }
    }
  }
}


// ---- SyncQueueDao ----
@DriftAccessor(tables: [SyncQueue])
 class SyncQueueDao extends DatabaseAccessor<AppDatabase>
     with _$SyncQueueDaoMixin {
   SyncQueueDao(super.db);

   // Ambil antrian yang belum dikirim, urut dari yang paling lama masuk
   Future<List<SyncQueueData>> getPending({int limit = 50}) =>
       (select(syncQueue)
             ..orderBy([(q) => OrderingTerm.asc(q.queuedAt)])
             ..limit(limit))
           .get();

   Future<void> enqueue(SyncQueueCompanion entry) =>
       into(syncQueue).insert(entry);

   Future<void> deleteById(int id) =>
       (delete(syncQueue)..where((q) => q.id.equals(id))).go();

   // Increment retry count — dipanggil kalau push ke Supabase gagal
   Future<void> incrementRetry(int id) async {
     final row = await (select(syncQueue)..where((q) => q.id.equals(id)))
         .getSingleOrNull();
     if (row == null) return;
     await (update(syncQueue)..where((q) => q.id.equals(id)))
         .write(SyncQueueCompanion(retryCount: Value(row.retryCount + 1)));
   }
 }


// ============================================================
//  HELPER DATA CLASSES (bukan Drift generated)
// ============================================================
class CategorySummary {
  final String? categoryId;
  final String  categoryName;
  final String  icon;
  final String  color;
  final double  total;

  const CategorySummary({
    required this.categoryId,
    required this.categoryName,
    required this.icon,
    required this.color,
    required this.total,
  });
}

class TransactionWithCategoryAmount {
  final Transaction transaction;
  // Hanya jumlah dari item kategori ini, bukan total seluruh transaksi
  final double      categoryAmount;
 
  const TransactionWithCategoryAmount({
    required this.transaction,
    required this.categoryAmount,
  });
}

class MonthlyTotal {
  final int    year;
  final int    month;
  final double total;
 
  const MonthlyTotal({
    required this.year,
    required this.month,
    required this.total,
  });
 
  // Label pendek untuk sumbu X chart: "Jan", "Feb", dst
  String get shortLabel {
    const labels = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return labels[month];
  }
}
 
class MonthlyStats {
  final int      year;
  final int      month;
  final double   totalSpent;
  final int      txCount;
  final double   avgPerDay;
  final DateTime busiestDay;
  final double   busiestAmount;
 
  const MonthlyStats({
    required this.year,
    required this.month,
    required this.totalSpent,
    required this.txCount,
    required this.avgPerDay,
    required this.busiestDay,
    required this.busiestAmount,
  });
 
  factory MonthlyStats.empty({required int year, required int month}) =>
      MonthlyStats(
        year:          year,
        month:         month,
        totalSpent:    0,
        txCount:       0,
        avgPerDay:     0,
        busiestDay:    DateTime(year, month, 1),
        busiestAmount: 0,
      );
}

class BillSessionDetail {
  final BillSession               session;
  final List<BillParticipant>     participants;
  final List<BillItem>            items;
  final List<BillItemParticipant> splits;

  const BillSessionDetail({
    required this.session,
    required this.participants,
    required this.items,
    required this.splits,
  });

  // Total tagihan per peserta (map participantId → amount)
  Map<String, double> get totalPerParticipant {
    final map = <String, double>{};
    for (final split in splits) {
      map[split.participantId] =
          (map[split.participantId] ?? 0) + split.shareAmount;
    }
    return map;
  }
}

class BillSummary {
  final String   sessionId;
  final String   title;
  final DateTime date;
  final String?  placeName;
  final double   totalAmount;
  final int      participantCount;
  final bool     linkedToTransaction;
 
  const BillSummary({
    required this.sessionId,
    required this.title,
    required this.date,
    required this.placeName,
    required this.totalAmount,
    required this.participantCount,
    required this.linkedToTransaction,
  });
}