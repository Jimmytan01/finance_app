import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../transactions/providers/transaction_providers.dart';
import '../../transactions/services/transaction_service.dart';
import '../models/budget_models.dart';
import '../providers/budget_providers.dart';

class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  String? _categoryId;
  String? _editingId;
  bool _notificationsEnabled = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(budgetMonthProvider);
    final budgetsAsync = ref.watch(budgetListProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Anggaran kategori')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MonthRow(month: month),
          const SizedBox(height: 20),
          Text('Atur batas pengeluaran',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildForm(
            categoriesAsync,
            budgetsAsync.isLoading,
            budgetsAsync.isLoading && budgetsAsync.hasValue,
          ),
          const SizedBox(height: 24),
          Text('Anggaran bulan ini',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildBudgets(budgetsAsync),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildForm(
    AsyncValue<List<Category>> categoriesAsync,
    bool isBusy,
    bool isSaving,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              categoriesAsync.when(
                loading: () => const Text('Memuat kategori...'),
                error: (_, __) => Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => ref.invalidate(categoriesProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Gagal memuat kategori. Coba lagi'),
                  ),
                ),
                data: (categories) {
                  final categoryId = categories.any((c) => c.id == _categoryId)
                      ? _categoryId
                      : categories.firstOrNull?.id;
                  return DropdownButtonFormField<String>(
                    key: ValueKey(categoryId),
                    initialValue: categoryId,
                    decoration: const InputDecoration(
                      labelText: 'Kategori',
                      border: OutlineInputBorder(),
                    ),
                    items: categories
                        .map((category) => DropdownMenuItem(
                              value: category.id,
                              child: Text(category.name),
                            ))
                        .toList(),
                    onChanged: isBusy
                        ? null
                        : (value) => setState(() => _categoryId = value),
                    validator: (value) =>
                        value == null ? 'Pilih kategori' : null,
                  );
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('budget-amount'),
                controller: _amountController,
                enabled: !isBusy,
                decoration: const InputDecoration(
                  labelText: 'Batas anggaran (Rp)',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                validator: (value) {
                  final amount = double.tryParse(
                    (value ?? '').trim().replaceAll(',', '.'),
                  );
                  if (amount == null || !amount.isFinite || amount <= 0) {
                    return 'Anggaran harus lebih besar dari nol';
                  }
                  return null;
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notifikasi anggaran'),
                subtitle: const Text('Peringatan saat mencapai 80% dan 100%'),
                value: _notificationsEnabled,
                onChanged: isBusy
                    ? null
                    : (value) => setState(() => _notificationsEnabled = value),
              ),
              FilledButton(
                onPressed: isBusy ? null : _save,
                child: isSaving
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Menyimpan...'),
                        ],
                      )
                    : Text(_editingId == null
                        ? 'Simpan Anggaran'
                        : 'Perbarui Anggaran'),
              ),
              if (_editingId != null)
                TextButton(
                  onPressed: isBusy ? null : _resetForm,
                  child: const Text('Batal edit'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBudgets(AsyncValue<List<BudgetSummary>> budgetsAsync) {
    if (!budgetsAsync.hasValue) {
      if (budgetsAsync.hasError) {
        return Column(
          children: [
            const Icon(Icons.cloud_off_outlined),
            const SizedBox(height: 8),
            const Text('Gagal memuat anggaran'),
            TextButton.icon(
              onPressed: () => ref.invalidate(budgetListProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi'),
            ),
          ],
        );
      }
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final budgets = budgetsAsync.value ?? const <BudgetSummary>[];
    if (budgets.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('Belum ada anggaran untuk bulan ini')),
      );
    }
    return Column(
      children: budgets.map(_budgetCard).toList(),
    );
  }

  Widget _budgetCard(BudgetSummary budget) {
    final ratio = budget.progress.usageRatio;
    final threshold = budget.progress.reachedThresholds;
    final alert = threshold.contains(100)
        ? 'Batas anggaran tercapai'
        : threshold.contains(80)
            ? 'Anggaran hampir habis'
            : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(budget.categoryName,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: 'Edit anggaran',
                  onPressed: () => _edit(budget),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Hapus anggaran',
                  onPressed: () => _confirmDelete(budget),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Text(
              '${TransactionService.formatCurrency(budget.spentAmount)} dari ${TransactionService.formatCurrency(budget.limitAmount)}',
            ),
            const SizedBox(height: 4),
            Text('${(ratio * 100).round()}% terpakai'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: ratio.clamp(0.0, 1.0)),
            const SizedBox(height: 6),
            Text(
              'Sisa ${TransactionService.formatCurrency(budget.progress.remainingAmount)}',
            ),
            if (alert != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(alert),
                ],
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notifikasi sistem'),
              value: budget.notificationsEnabled,
              onChanged: (value) => _setNotifications(budget, value),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final categories = ref.read(categoriesProvider).valueOrNull ?? const [];
    final categoryId = categories.any((c) => c.id == _categoryId)
        ? _categoryId
        : categories.firstOrNull?.id;
    if (categoryId == null) return;
    final amount =
        double.parse(_amountController.text.trim().replaceAll(',', '.'));
    final month = ref.read(budgetMonthProvider);
    final userId = ref.read(currentUserIdProvider);
    try {
      final permissionGranted =
          await ref.read(budgetListProvider.notifier).save(
                BudgetInput(
                  id: _editingId,
                  userId: userId,
                  categoryId: categoryId,
                  year: month.year,
                  month: month.month,
                  limitAmount: amount,
                  notificationsEnabled: _notificationsEnabled,
                ),
              );
      if (!mounted) return;
      if (_notificationsEnabled && !permissionGranted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Izin notifikasi ditolak. Progres anggaran tetap tampil di aplikasi.'),
        ));
      }
      _resetForm();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Anggaran gagal disimpan. Coba lagi.'),
      ));
    }
  }

  Future<void> _setNotifications(BudgetSummary budget, bool enabled) async {
    try {
      final granted = await ref
          .read(budgetListProvider.notifier)
          .setNotificationsEnabled(budget, enabled);
      if (!mounted || !enabled || granted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Izin notifikasi ditolak. Progres anggaran tetap tampil di aplikasi.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pengaturan anggaran gagal disimpan. Coba lagi.'),
      ));
    }
  }

  void _edit(BudgetSummary budget) {
    setState(() {
      _editingId = budget.id;
      _categoryId = budget.categoryId;
      _amountController.text = budget.limitAmount.toStringAsFixed(0);
      _notificationsEnabled = budget.notificationsEnabled;
    });
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _categoryId = null;
      _amountController.clear();
      _notificationsEnabled = false;
    });
  }

  Future<void> _confirmDelete(BudgetSummary budget) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus anggaran?'),
        content: Text('Anggaran ${budget.categoryName} akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(budgetListProvider.notifier).delete(budget.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Anggaran gagal dihapus. Coba lagi.'),
      ));
    }
  }
}

class _MonthRow extends ConsumerWidget {
  const _MonthRow({required this.month});
  final SelectedMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(selectedMonthProvider.notifier);
    return Row(
      children: [
        IconButton(
          tooltip: 'Bulan sebelumnya',
          onPressed: notifier.goPrev,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            TransactionService.formatMonth(month.year, month.month),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: 'Bulan berikutnya',
          onPressed: month.isCurrentMonth ? null : notifier.goNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
