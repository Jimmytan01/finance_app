import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../features/transactions/providers/transaction_providers.dart';
import '../../../features/transactions/services/transaction_service.dart';
import '../providers/bill_providers.dart';
import '../services/bill_service.dart';
 
class BillResultScreen extends ConsumerWidget {
  const BillResultScreen({super.key});
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(billCalcResultProvider);
    final form   = ref.watch(billFormProvider);
 
    if (result == null) {
      return const Scaffold(
          body: Center(child: Text('Tidak ada hasil kalkulasi')));
    }
 
    final hasSelf = form.participants.any((p) => p.isSelf);
 
    return Scaffold(
      appBar: AppBar(
        title:       Text(form.title.isNotEmpty ? form.title : 'Hasil Split'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (form.placeName?.isNotEmpty == true)
                  _InfoHeader(form: form),
                const SizedBox(height: 12),
                _TotalSummaryCard(result: result),
                const SizedBox(height: 20),
                Text('Tagihan per orang',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                ...result.participants.map((p) => _ParticipantResultCard(
                      result:      p,
                      hasDiscount: result.discountAmount > 0,
                      hasTax:      result.taxAmount > 0,
                    )),
              ],
            ),
          ),
          _SaveButtons(
            hasSelf:      hasSelf,
            onSave:       () => _save(context, ref, form, result, false),
            onSaveWithTx: hasSelf
                ? () => _save(context, ref, form, result, true)
                : null,
          ),
        ],
      ),
    );
  }
 
  Future<void> _save(
    BuildContext   context,
    WidgetRef      ref,
    BillFormState  form,
    BillCalcResult result,
    bool           saveToKeuangan,
  ) async {
    final service          = ref.read(billServiceProvider);
    final categories       = ref.read(categoriesProvider).valueOrNull ?? [];
    final notifier         = ref.read(billFormProvider.notifier);
    final editingSessionId = notifier.editingSessionId;
 
    try {
      // Mode edit: hapus sesi lama via sync-aware delete
      if (editingSessionId != null) {
        await service.deleteSessionWithSync(editingSessionId);
      }
 
      final sessionId = await service.saveSession(form, result);
 
      if (saveToKeuangan) {
        await service.saveMyShareToTransaction(
          sessionId:  sessionId,
          form:       form,
          result:     result,
          categories: categories,
        );
        ref.invalidate(monthlyTransactionsProvider);
        ref.invalidate(monthlyCategorySummaryProvider);
        ref.invalidate(monthlyTotalProvider);
      }
 
      ref.invalidate(billSessionListProvider);
      notifier.reset();
      ref.read(billCalcResultProvider.notifier).state = null;
 
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(saveToKeuangan
              ? 'Tersimpan! Tagihan saya sudah dicatat ke keuangan.'
              : editingSessionId != null
                  ? 'Sesi split bill berhasil diperbarui.'
                  : 'Sesi split bill tersimpan.'),
          backgroundColor: Colors.green.shade700,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Gagal menyimpan: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }
}
 
class _InfoHeader extends StatelessWidget {
  final BillFormState form;
  const _InfoHeader({required this.form});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(Icons.calendar_today, size: 14,
          color: cs.onSurface.withOpacity(0.4)),
      const SizedBox(width: 4),
      Text(TransactionService.formatDate(form.date),
          style: TextStyle(fontSize: 12,
              color: cs.onSurface.withOpacity(0.5))),
      if (form.placeName?.isNotEmpty == true) ...[
        Text('  ·  ',
            style: TextStyle(color: cs.onSurface.withOpacity(0.3))),
        Icon(Icons.place_outlined, size: 14,
            color: cs.onSurface.withOpacity(0.4)),
        const SizedBox(width: 4),
        Text(form.placeName!,
            style: TextStyle(fontSize: 12,
                color: cs.onSurface.withOpacity(0.5))),
      ],
    ]);
  }
}
 
class _TotalSummaryCard extends StatelessWidget {
  final BillCalcResult result;
  const _TotalSummaryCard({required this.result});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding:    const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        _Line('Subtotal',
            TransactionService.formatCurrency(result.subtotalBeforeDiscount),
            cs.onPrimaryContainer.withOpacity(0.7)),
        if (result.discountAmount > 0) ...[
          const SizedBox(height: 6),
          _Line('Diskon',
              '- ${TransactionService.formatCurrency(result.discountAmount)}',
              Colors.green.shade700),
        ],
        if (result.taxAmount > 0) ...[
          const SizedBox(height: 6),
          _Line('Pajak',
              '+ ${TransactionService.formatCurrency(result.taxAmount)}',
              cs.error),
        ],
        Divider(
            color: cs.onPrimaryContainer.withOpacity(0.15), height: 16),
        _Line('Total',
            TransactionService.formatCurrency(result.grandTotal),
            cs.onPrimaryContainer, bold: true),
      ]),
    );
  }
}
 
class _Line extends StatelessWidget {
  final String label, value;
  final Color  color;
  final bool   bold;
  const _Line(this.label, this.value, this.color, {this.bold = false});
  @override
  Widget build(BuildContext context) => Row(children: [
        Text(label,
            style: TextStyle(
                fontSize:   bold ? 15 : 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                color:      color)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontSize:   bold ? 17 : 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color:      color)),
      ]);
}
 
class _ParticipantResultCard extends StatefulWidget {
  final ParticipantResult result;
  final bool              hasDiscount, hasTax;
  const _ParticipantResultCard(
      {required this.result,
      required this.hasDiscount,
      required this.hasTax});
  @override
  State<_ParticipantResultCard> createState() =>
      _ParticipantResultCardState();
}
 
class _ParticipantResultCardState
    extends State<_ParticipantResultCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final p      = widget.result;
    final isSelf = p.participant.isSelf;
    return Card(
      margin:    const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color:     isSelf
          ? cs.primaryContainer.withOpacity(0.5)
          : cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelf
            ? BorderSide(color: cs.primary.withOpacity(0.4))
            : BorderSide.none,
      ),
      child: Column(children: [
        InkWell(
          onTap:        () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              CircleAvatar(
                radius:          18,
                backgroundColor: isSelf ? cs.primary : cs.secondaryContainer,
                child: Text(_initial(p.participant.name, isSelf),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color:      isSelf
                            ? cs.onPrimary
                            : cs.onSecondaryContainer)),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        isSelf
                            ? '${p.participant.name.isEmpty ? 'Saya' : p.participant.name} (saya)'
                            : p.participant.name.isEmpty
                                ? 'Peserta'
                                : p.participant.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    Text('${p.itemBreakdown.length} item',
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withOpacity(0.45))),
                  ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(TransactionService.formatCurrency(p.finalAmount),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize:   16,
                        color:      isSelf ? cs.primary : null)),
                if (widget.hasDiscount && p.discountShare > 0)
                  Text(
                      'hemat ${TransactionService.formatCurrency(p.discountShare)}',
                      style: TextStyle(
                          fontSize: 10, color: Colors.green.shade600)),
              ]),
              const SizedBox(width: 4),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: cs.onSurface.withOpacity(0.4)),
            ]),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(children: [
              ...p.itemBreakdown.map((s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(
                          child: Text(s.item.name,
                              style: const TextStyle(fontSize: 12))),
                      Text(
                          '×${s.shareQty % 1 == 0 ? s.shareQty.toInt() : s.shareQty.toStringAsFixed(1)}',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withOpacity(0.45))),
                      const SizedBox(width: 12),
                      Text(
                          TransactionService.formatCurrency(s.shareAmount),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500)),
                    ]),
                  )),
              if (widget.hasDiscount || widget.hasTax)
                Divider(
                    height: 12, color: cs.outline.withOpacity(0.15)),
              if (widget.hasDiscount && p.discountShare > 0)
                _DetailRow(
                    'Diskon',
                    '- ${TransactionService.formatCurrency(p.discountShare)}',
                    Colors.green.shade600),
              if (widget.hasTax && p.taxShare > 0)
                _DetailRow(
                    'Pajak',
                    '+ ${TransactionService.formatCurrency(p.taxShare)}',
                    cs.error),
            ]),
          ),
      ]),
    );
  }
 
  String _initial(String name, bool isSelf) {
    if (isSelf && name.isEmpty) return 'S';
    if (name.isEmpty) return '?';
    return name.trim()[0].toUpperCase();
  }
}
 
class _DetailRow extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _DetailRow(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize:   11,
                  fontWeight: FontWeight.w500,
                  color:      color)),
        ]),
      );
}
 
class _SaveButtons extends StatelessWidget {
  final bool          hasSelf;
  final VoidCallback  onSave;
  final VoidCallback? onSaveWithTx;
  const _SaveButtons(
      {required this.hasSelf, required this.onSave, this.onSaveWithTx});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color:  Theme.of(context).scaffoldBackgroundColor,
        border: Border(
            top: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (hasSelf && onSaveWithTx != null)
          FilledButton.icon(
            onPressed: onSaveWithTx,
            icon:      const Icon(Icons.savings_outlined, size: 18),
            label:     const Text('Simpan & catat ke keuangan saya'),
            style:     FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        if (hasSelf) const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onSave,
          icon:      const Icon(Icons.bookmark_border, size: 18),
          label: Text(hasSelf ? 'Simpan sesi saja' : 'Simpan sesi split bill'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]),
    );
  }
}