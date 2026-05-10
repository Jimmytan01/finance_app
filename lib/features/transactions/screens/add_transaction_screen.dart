// Form input transaksi: tanggal, tempat, list item dinamis.
// Setiap item punya nama, kategori, harga satuan, jumlah, diskon.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../providers/transaction_providers.dart';
import '../services/transaction_service.dart';

class AddTransactionScreen extends ConsumerWidget {
  final String? editTxId;
  const AddTransactionScreen({super.key, this.editTxId});
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final input           = ref.watch(addTransactionProvider);
    final notifier        = ref.read(addTransactionProvider.notifier);
    final categoriesAsync = ref.watch(categoriesProvider);
    final isEdit          = editTxId != null;
 
    return Scaffold(
      appBar: AppBar(
        title:       Text(isEdit ? 'Edit Transaksi' : 'Tambah Transaksi'),
        centerTitle: true,
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (categories) => _FormWithSaveButton(
          input:      input,
          notifier:   notifier,
          categories: categories,
          isEdit:     isEdit,
          editTxId:   editTxId,
        ),
      ),
    );
  }
}
 
// ─────────────────────────────────────────────────────────────
// Wrapper Column: scroll area (form) + sticky bar bawah
// ─────────────────────────────────────────────────────────────
 
class _FormWithSaveButton extends ConsumerWidget {
  final TransactionInput       input;
  final AddTransactionNotifier notifier;
  final List<Category>         categories;
  final bool                   isEdit;
  final String?                editTxId;
 
  const _FormWithSaveButton({
    required this.input,
    required this.notifier,
    required this.categories,
    required this.isEdit,
    required this.editTxId,
  });
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
 
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            children: [
              _HeaderSection(input: input, notifier: notifier),
              const SizedBox(height: 24),
 
              Row(
                children: [
                  Text('Item Pengeluaran',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${input.items.length} item',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.45))),
                ],
              ),
              const SizedBox(height: 8),
 
              ...input.items.asMap().entries.map((e) => _ItemCard(
                    index:      e.key,
                    item:       e.value,
                    categories: categories,
                    onChanged:  (updated) =>
                        notifier.updateItem(e.key, updated),
                    onRemove:   input.items.length > 1
                        ? () => notifier.removeItem(e.key)
                        : null,
                  )),
 
              OutlinedButton.icon(
                onPressed:  notifier.addItem,
                icon:       const Icon(Icons.add, size: 18),
                label:      const Text('Tambah Item'),
                style:      OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape:       RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        _StickyBottomBar(
            input: input, isEdit: isEdit, editTxId: editTxId),
      ],
    );
  }
}
 
// ─────────────────────────────────────────────────────────────
// Sticky bar bawah: total + tombol simpan
// ─────────────────────────────────────────────────────────────
 
class _StickyBottomBar extends ConsumerWidget {
  final TransactionInput input;
  final bool             isEdit;
  final String?          editTxId;
  const _StickyBottomBar(
      {required this.input, required this.isEdit, required this.editTxId});
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs      = Theme.of(context).colorScheme;
    final hasItems = input.items.any((i) => i.unitPrice > 0);
 
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
              color:      Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset:     const Offset(0, -3)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Total',
                  style: TextStyle(
                      fontSize: 14,
                      color:    cs.onSurface.withOpacity(0.6))),
              const Spacer(),
              Text(
                TransactionService.formatCurrency(input.total),
                style: TextStyle(
                  fontSize:   18,
                  fontWeight: FontWeight.w700,
                  color:      hasItems
                      ? cs.primary
                      : cs.onSurface.withOpacity(0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: hasItems ? () => _save(context, ref) : null,
            icon:  Icon(
                isEdit ? Icons.check_circle_outline : Icons.save_outlined,
                size: 20),
            label: Text(
              isEdit ? 'Simpan Perubahan' : 'Simpan Transaksi',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape:       RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              disabledBackgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          if (!hasItems)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Isi minimal satu item dengan harga lebih dari 0',
                style: TextStyle(
                    fontSize: 11,
                    color:    cs.onSurface.withOpacity(0.35)),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
 
  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final service = ref.read(transactionServiceProvider);
    final input   = ref.read(addTransactionProvider);
 
    try {
      if (isEdit && editTxId != null) {
        await service.updateTransaction(editTxId!, input);
      } else {
        await service.saveTransaction(input);
      }
 
      ref.invalidate(monthlyTransactionsProvider);
      ref.invalidate(monthlyCategorySummaryProvider);
      ref.invalidate(monthlyTotalProvider);
 
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    }
  }
}
 
// ─────────────────────────────────────────────────────────────
// Header: tanggal, tempat, catatan
// ─────────────────────────────────────────────────────────────
 
class _HeaderSection extends StatelessWidget {
  final TransactionInput       input;
  final AddTransactionNotifier notifier;
  const _HeaderSection({required this.input, required this.notifier});
 
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context:     context,
              initialDate: input.date,
              firstDate:   DateTime(2020),
              lastDate:    DateTime.now(),
            );
            if (picked != null) notifier.setDate(picked);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border:       Border.all(
                  color: cs.outline.withOpacity(0.5)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 18, color: cs.primary),
                const SizedBox(width: 12),
                Text(TransactionService.formatDate(input.date),
                    style: Theme.of(context).textTheme.bodyMedium),
                const Spacer(),
                Icon(Icons.chevron_right,
                    size: 18,
                    color: cs.onSurface.withOpacity(0.4)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: input.placeName,
          onChanged:    notifier.setPlaceName,
          decoration:   _inputDec(context, 'Tempat (opsional)',
              icon: Icons.place_outlined),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: input.notes,
          onChanged:    notifier.setNotes,
          maxLines:     2,
          decoration:   _inputDec(context, 'Catatan (opsional)',
              icon: Icons.notes),
        ),
      ],
    );
  }
}
 
// ─────────────────────────────────────────────────────────────
// Kartu satu item — dengan toggle diskon Rp / %
// ─────────────────────────────────────────────────────────────
 
class _ItemCard extends StatefulWidget {
  final int                              index;
  final TransactionItemInput             item;
  final List<Category>                   categories;
  final ValueChanged<TransactionItemInput> onChanged;
  final VoidCallback?                    onRemove;
 
  const _ItemCard({
    required this.index,
    required this.item,
    required this.categories,
    required this.onChanged,
    this.onRemove,
  });
 
  @override
  State<_ItemCard> createState() => _ItemCardState();
}
 
class _ItemCardState extends State<_ItemCard> {
  late TextEditingController _nameCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _discCtrl;
 
  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.item.name);
    _priceCtrl = TextEditingController(
        text: widget.item.unitPrice > 0
            ? widget.item.unitPrice.toStringAsFixed(0)
            : '');
    _qtyCtrl = TextEditingController(
        text: widget.item.quantity
            .toStringAsFixed(widget.item.quantity % 1 == 0 ? 0 : 2));
    _discCtrl = TextEditingController(
        text: widget.item.discountValue > 0
            ? widget.item.discountValue
                .toStringAsFixed(widget.item.discountType == 'percent' ? 1 : 0)
            : '');
  }
 
  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _discCtrl.dispose();
    super.dispose();
  }
 
  void _emitBasic() {
    widget.onChanged(widget.item.copyWith(
      name:          _nameCtrl.text,
      unitPrice:     double.tryParse(_priceCtrl.text) ?? 0,
      quantity:      double.tryParse(_qtyCtrl.text) ?? 1,
      discountValue: double.tryParse(_discCtrl.text) ?? 0,
    ));
  }
 
  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final item = widget.item;
 
    final allowedNames = ['Makan', 'Transport', 'Kebutuhan', 'Laundry'];
    final filteredCats = widget.categories
        .where((c) => allowedNames
            .any((n) => n.toLowerCase() == c.name.toLowerCase()))
        .toList()
      ..sort((a, b) =>
          allowedNames.indexWhere(
              (n) => n.toLowerCase() == a.name.toLowerCase()) -
          allowedNames.indexWhere(
              (n) => n.toLowerCase() == b.name.toLowerCase()));
 
    // Preview diskon dalam Rp untuk ditampilkan
    final discountRp      = item.discountAmount;
    final hasDiscount     = discountRp > 0;
    final grossSubtotal   = item.unitPrice * item.quantity;
 
    return Card(
      margin:    const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape:     RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header kartu
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color:        cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Item ${widget.index + 1}',
                      style: TextStyle(
                          fontSize:   12,
                          fontWeight: FontWeight.w600,
                          color:      cs.onSecondaryContainer)),
                ),
                const Spacer(),
                if (widget.onRemove != null)
                  IconButton(
                    icon:          Icon(Icons.delete_outline,
                        size: 20, color: cs.error),
                    onPressed:     widget.onRemove,
                    visualDensity: VisualDensity.compact,
                    padding:       EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 10),
 
            // Nama barang
            TextFormField(
              controller:         _nameCtrl,
              onChanged:          (_) => _emitBasic(),
              decoration:         _inputDec(context, 'Nama barang / jasa *'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 10),
 
            // Kategori chips
            Text('Kategori',
                style: TextStyle(
                    fontSize: 12,
                    color:    cs.onSurface.withOpacity(0.6))),
            const SizedBox(height: 6),
            Row(
              children: filteredCats.map((cat) {
                final isSelected = item.categoryId == cat.id;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => widget.onChanged(item.copyWith(
                        categoryId:    isSelected ? null : cat.id,
                        clearCategory: isSelected,
                      )),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding:  const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _hexToColor(cat.color).withOpacity(0.15)
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? _hexToColor(cat.color)
                                : cs.outline.withOpacity(0.2),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(_iconFromString(cat.icon),
                                size:  18,
                                color: isSelected
                                    ? _hexToColor(cat.color)
                                    : cs.onSurface.withOpacity(0.4)),
                            const SizedBox(height: 3),
                            Text(cat.name,
                                style: TextStyle(
                                  fontSize:   10,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? _hexToColor(cat.color)
                                      : cs.onSurface.withOpacity(0.55),
                                ),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
 
            // Harga satuan + jumlah
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller:      _priceCtrl,
                    onChanged:       (_) => _emitBasic(),
                    keyboardType:    TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration: _inputDec(context, 'Harga satuan (Rp) *',
                        icon: Icons.payments_outlined),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller:   _qtyCtrl,
                    onChanged:    (_) => _emitBasic(),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,3}'))
                    ],
                    decoration: _inputDec(context, 'Jumlah *'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
 
            // ── Diskon dengan toggle Rp / % ───────────────
            Text('Diskon (opsional)',
                style: TextStyle(
                    fontSize: 12,
                    color:    cs.onSurface.withOpacity(0.6))),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Toggle Rp / %
                Container(
                  decoration: BoxDecoration(
                    color:        cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: ['flat', 'percent'].map((type) {
                      final isActive = item.discountType == type;
                      final label    = type == 'flat' ? 'Rp' : '%';
                      return GestureDetector(
                        onTap: () {
                          // Saat ganti tipe, reset nilai diskon ke 0
                          // supaya tidak ada miskomunikasi "50" yang tadinya
                          // Rp 50 tiba-tiba jadi 50%
                          _discCtrl.clear();
                          widget.onChanged(item.copyWith(
                            discountType:  type,
                            discountValue: 0,
                          ));
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding:  const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            color:        isActive
                                ? cs.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize:   13,
                              color:      isActive
                                  ? cs.onPrimaryContainer
                                  : cs.onSurface.withOpacity(0.45),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(width: 8),
                // Input nilai diskon
                Expanded(
                  child: TextFormField(
                    controller:   _discCtrl,
                    onChanged:    (_) => _emitBasic(),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'))
                    ],
                    decoration: _inputDec(
                      context,
                      item.discountType == 'flat'
                          ? 'Jumlah diskon (Rp)'
                          : 'Persentase (0–100)',
                    ),
                  ),
                ),
              ],
            ),
 
            // Preview diskon dalam Rp (tampil kalau ada diskon)
            if (hasDiscount)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.discount_outlined,
                        size: 13, color: Colors.green.shade600),
                    const SizedBox(width: 4),
                    Text(
                      'Hemat ${TransactionService.formatCurrency(discountRp)}',
                      style: TextStyle(
                          fontSize:   12,
                          color:      Colors.green.shade600,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
 
            // Subtotal
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:        cs.primaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text('Subtotal',
                      style: TextStyle(
                          fontSize: 13,
                          color:    cs.onSurface.withOpacity(0.6))),
                  const Spacer(),
                  // Kalau ada diskon, tampilkan harga coret
                  if (hasDiscount) ...[
                    Text(
                      TransactionService.formatCurrency(grossSubtotal),
                      style: TextStyle(
                        fontSize:   11,
                        color:      cs.onSurface.withOpacity(0.35),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    TransactionService.formatCurrency(item.subtotal),
                    style: TextStyle(
                        fontSize:   14,
                        fontWeight: FontWeight.w700,
                        color:      cs.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
 
// ── Helpers ──────────────────────────────────────────────────
InputDecoration _inputDec(BuildContext context, String label,
    {IconData? icon}) =>
    InputDecoration(
      labelText:   label,
      prefixIcon:  icon != null ? Icon(icon, size: 20) : null,
      border:      OutlineInputBorder(
          borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .outline
                  .withOpacity(0.5))),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 12),
      isDense: true,
    );
 
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
  };
  return map[name] ?? Icons.category;
}