import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/transactions/services/transaction_service.dart';
import '../providers/bill_providers.dart';
import '../services/bill_service.dart';
import 'bill_result_screen.dart';

class AddBillScreen extends ConsumerStatefulWidget {
  const AddBillScreen({super.key});

  @override
  ConsumerState<AddBillScreen> createState() => _AddBillScreenState();
}

class _AddBillScreenState extends ConsumerState<AddBillScreen> {
  final _pageCtrl = PageController();

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    ref.read(billFormProvider.notifier).goToStep(page);
    _pageCtrl.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve:    Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final form    = ref.watch(billFormProvider);
    final step    = form.currentStep;
    final cs      = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title:   const Text('Split Bill'),
        leading: IconButton(
          icon:      const Icon(Icons.close),
          onPressed: () {
            // Konfirmasi kalau form sudah diisi
            if (form.participants.isNotEmpty || form.items.isNotEmpty) {
              _confirmDiscard(context);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _StepIndicator(
            currentStep: step,
            onTap:       _goToPage,
            isStep0Done: form.step0Valid,
            isStep1Done: form.step1Valid,
          ),
        ),
      ),
      body: PageView(
        controller:   _pageCtrl,
        // Tidak izinkan swipe manual — harus lewat tombol Next/Back
        // karena validasi per step harus berjalan dulu
        physics:      const NeverScrollableScrollPhysics(),
        children: [
          _Step0InfoPeserta(onNext: () {
            if (!form.step0Valid) {
              _showError(context, 'Lengkapi judul dan tambah peserta dulu');
              return;
            }
            _goToPage(1);
          }),
          _Step1Items(
            onBack: () => _goToPage(0),
            onNext: () {
              if (!form.step1Valid) {
                _showError(context,
                    'Pastikan semua item sudah diisi dan di-assign ke peserta');
                return;
              }
              _goToPage(2);
            },
          ),
          _Step2DiskonHitung(
            onBack:    () => _goToPage(1),
            onHitung:  () => _hitung(context),
          ),
        ],
      ),
    );
  }

  void _hitung(BuildContext context) {
    final form    = ref.read(billFormProvider);
    final service = ref.read(billServiceProvider);

    final error = service.validate(form);
    if (error != null) {
      _showError(context, error);
      return;
    }

    final result = service.calculate(form);
    ref.read(billCalcResultProvider.notifier).state = result;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BillResultScreen()),
    );
  }

  void _confirmDiscard(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Buang perubahan?'),
        content: const Text('Data yang sudah diisi akan hilang.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Lanjut isi')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(billFormProvider.notifier).reset();
              Navigator.pop(context);
            },
            child: const Text('Buang'),
          ),
        ],
      ),
    );
  }

  void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg),
      backgroundColor: Theme.of(context).colorScheme.error,
      behavior:        SnackBarBehavior.floating,
    ));
  }
}

// ─────────────────────────────────────────────────────────────
// Indikator langkah di bagian atas
// ─────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int          currentStep;
  final Function(int) onTap;
  final bool         isStep0Done;
  final bool         isStep1Done;

  const _StepIndicator({
    required this.currentStep,
    required this.onTap,
    required this.isStep0Done,
    required this.isStep1Done,
  });

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final labels = ['Info & Peserta', 'Item', 'Diskon & Pajak'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: List.generate(3, (i) {
          final isDone    = (i == 0 && isStep0Done) ||
                            (i == 1 && isStep1Done);
          final isActive  = i == currentStep;
          final canGoBack = i < currentStep;

          return Expanded(
            child: GestureDetector(
              // Hanya boleh tap ke step sebelumnya, tidak lompat ke depan
              onTap: canGoBack ? () => onTap(i) : null,
              child: Row(
                children: [
                  // Lingkaran nomor langkah
                  Container(
                    width:  26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? cs.primary
                          : isDone
                              ? cs.primaryContainer
                              : cs.surfaceContainerHighest,
                    ),
                    child: Center(
                      child: isDone && !isActive
                          ? Icon(Icons.check, size: 14,
                              color: cs.onPrimaryContainer)
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize:   12,
                                fontWeight: FontWeight.w700,
                                color:      isActive
                                    ? cs.onPrimary
                                    : cs.onSurface.withOpacity(0.5),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Label langkah — hanya tampil yang aktif biar tidak sesak
                  if (isActive)
                    Flexible(
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          fontSize:   11,
                          fontWeight: FontWeight.w600,
                          color:      cs.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  // Garis penghubung antar langkah
                  if (i < 2) ...[
                    const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        height: 1,
                        color:  i < currentStep
                            ? cs.primary.withOpacity(0.5)
                            : cs.outline.withOpacity(0.2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════
// STEP 0 — Info Dasar & Peserta
// ═════════════════════════════════════════════════════════════

class _Step0InfoPeserta extends ConsumerWidget {
  final VoidCallback onNext;
  const _Step0InfoPeserta({required this.onNext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form     = ref.watch(billFormProvider);
    final notifier = ref.read(billFormProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Judul sesi ──────────────────────────────
          TextFormField(
            initialValue: form.title,
            onChanged:    notifier.setTitle,
            decoration:   _inputDec(context, 'Judul sesi *',
                hint: 'Contoh: Makan malam ulang tahun Budi'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),

          // ── Tanggal ──────────────────────────────────
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: form.date,
                firstDate:   DateTime(2020),
                lastDate:    DateTime.now(),
              );
              if (picked != null) notifier.setDate(picked);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                border:       Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withOpacity(0.5)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(TransactionService.formatDate(form.date)),
                  const Spacer(),
                  Icon(Icons.chevron_right,
                      size: 18,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.4)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Tempat ───────────────────────────────────
          TextFormField(
            initialValue: form.placeName,
            onChanged:    notifier.setPlace,
            decoration:   _inputDec(context, 'Tempat (opsional)',
                icon: Icons.place_outlined),
          ),
          const SizedBox(height: 24),

          // ── Daftar peserta ───────────────────────────
          Row(
            children: [
              Text('Peserta',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${form.participants.length} orang',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.45))),
            ],
          ),
          const SizedBox(height: 8),

          ...form.participants.asMap().entries.map((e) =>
              _ParticipantRow(
                index:     e.key,
                input:     e.value,
                onChanged: (updated) =>
                    notifier.updateParticipant(e.key, updated),
                onRemove:  () => notifier.removeParticipant(e.key),
              )),

          // Tombol tambah peserta
          OutlinedButton.icon(
            onPressed: () => notifier.addParticipant(
              BillParticipantInput(name: ''),
            ),
            icon:  const Icon(Icons.person_add_outlined, size: 18),
            label: const Text('Tambah peserta'),
            style: OutlinedButton.styleFrom(
              minimumSize:    const Size.fromHeight(44),
              shape:          RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 24),

          // Tombol Next
          FilledButton(
            onPressed:    onNext,
            style:        FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            child: const Text('Lanjut → Input Item'),
          ),
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatefulWidget {
  final int                    index;
  final BillParticipantInput   input;
  final ValueChanged<BillParticipantInput> onChanged;
  final VoidCallback           onRemove;

  const _ParticipantRow({
    required this.index,
    required this.input,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_ParticipantRow> createState() => _ParticipantRowState();
}

class _ParticipantRowState extends State<_ParticipantRow> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.input.name);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Checkbox "Ini saya"
          Tooltip(
            message: 'Tandai sebagai saya',
            child: GestureDetector(
              onTap: () => widget.onChanged(
                  widget.input.copyWith(isSelf: !widget.input.isSelf)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width:  32,
                height: 32,
                decoration: BoxDecoration(
                  color:        widget.input.isSelf
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.input.isSelf ? Icons.person : Icons.person_outline,
                  size:  18,
                  color: widget.input.isSelf
                      ? cs.primary
                      : cs.onSurface.withOpacity(0.4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller:   _ctrl,
              onChanged:    (v) =>
                  widget.onChanged(widget.input.copyWith(name: v)),
              decoration:   InputDecoration(
                hintText:   'Nama peserta ${widget.index + 1}',
                isDense:    true,
                border:     OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon:          Icon(Icons.remove_circle_outline,
                color: cs.error, size: 20),
            onPressed:     widget.onRemove,
            visualDensity: VisualDensity.compact,
            padding:       EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════
// STEP 1 — Item & Pembagian
// ═════════════════════════════════════════════════════════════

class _Step1Items extends ConsumerWidget {
  final VoidCallback onBack;
  final VoidCallback onNext;
  const _Step1Items({required this.onBack, required this.onNext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form     = ref.watch(billFormProvider);
    final notifier = ref.read(billFormProvider.notifier);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Total sementara
              if (form.items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:        Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withOpacity(0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Text('Subtotal sementara',
                          style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer
                                  .withOpacity(0.7))),
                      const Spacer(),
                      Text(
                        TransactionService.formatCurrency(
                          form.items.fold(0.0, (s, i) => s + i.subtotal),
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize:   15,
                          color:      Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              if (form.items.isNotEmpty) const SizedBox(height: 12),

              // Daftar item
              ...form.items.asMap().entries.map((e) => _BillItemCard(
                    index:        e.key,
                    item:         e.value,
                    participants: form.participants,
                    onChanged:    (updated) =>
                        notifier.updateItem(e.key, updated),
                    onRemove:     () => notifier.removeItem(e.key),
                    onSplitEqual: () => notifier.splitItemEqually(e.key),
                    onTogglePart: (pid) =>
                        notifier.toggleParticipantOnItem(e.key, pid),
                  )),

              // Tombol tambah item
              OutlinedButton.icon(
                onPressed: () => notifier.addItem(BillItemInput(name: '')),
                icon:      const Icon(Icons.add_shopping_cart_outlined,
                    size: 18),
                label: const Text('Tambah item'),
                style: OutlinedButton.styleFrom(
                  minimumSize:    const Size.fromHeight(44),
                  shape:          RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),

        // Tombol navigasi
        _StepNavButtons(
          onBack:       onBack,
          onNext:       onNext,
          nextLabel:    'Lanjut → Diskon & Pajak',
        ),
      ],
    );
  }
}

class _BillItemCard extends StatefulWidget {
  final int                   index;
  final BillItemInput         item;
  final List<BillParticipantInput> participants;
  final ValueChanged<BillItemInput> onChanged;
  final VoidCallback          onRemove;
  final VoidCallback          onSplitEqual;
  final ValueChanged<String>  onTogglePart;

  const _BillItemCard({
    required this.index,
    required this.item,
    required this.participants,
    required this.onChanged,
    required this.onRemove,
    required this.onSplitEqual,
    required this.onTogglePart,
  });

  @override
  State<_BillItemCard> createState() => _BillItemCardState();
}

class _BillItemCardState extends State<_BillItemCard> {
  late TextEditingController _nameCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _qtyCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.item.name);
    _priceCtrl = TextEditingController(
        text: widget.item.unitPrice > 0
            ? widget.item.unitPrice.toStringAsFixed(0)
            : '');
    _qtyCtrl   = TextEditingController(
        text: widget.item.quantity.toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final item = widget.item;

    return Card(
      margin:    const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape:     RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: item.isAssigned
                ? cs.outlineVariant.withOpacity(0.5)
                : cs.error.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header kartu item
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color:        cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Item ${widget.index + 1}',
                      style: TextStyle(
                          fontSize:   11,
                          fontWeight: FontWeight.w600,
                          color:      cs.onSecondaryContainer)),
                ),
                const Spacer(),
                // Tanda peringatan kalau item belum di-assign
                if (!item.isAssigned)
                  Tooltip(
                    message: 'Item ini belum di-assign ke siapapun',
                    child: Icon(Icons.warning_amber_rounded,
                        size: 18, color: cs.error),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon:          Icon(Icons.delete_outline,
                      size: 18, color: cs.error),
                  onPressed:     widget.onRemove,
                  visualDensity: VisualDensity.compact,
                  padding:       EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Nama item
            TextField(
              controller:   _nameCtrl,
              onChanged:    (v) =>
                  widget.onChanged(item.copyWith(name: v)),
              decoration:   _inputDec(context, 'Nama item *'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),

            // Harga & qty
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller:    _priceCtrl,
                    onChanged:     (v) => widget.onChanged(
                        item.copyWith(unitPrice: double.tryParse(v) ?? 0)),
                    keyboardType:  TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration:    _inputDec(context, 'Harga (Rp) *',
                        icon: Icons.payments_outlined),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller:    _qtyCtrl,
                    onChanged:     (v) => widget.onChanged(
                        item.copyWith(quantity: int.tryParse(v) ?? 1)),
                    keyboardType:  TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration:    _inputDec(context, 'Qty'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Subtotal item
            Text(
              'Subtotal: ${TransactionService.formatCurrency(item.subtotal)}',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize:   13,
                  color:      cs.primary),
            ),
            const SizedBox(height: 10),

            // Section assign ke peserta
            Row(
              children: [
                Text('Siapa yang memesan?',
                    style: TextStyle(
                        fontSize:   12,
                        fontWeight: FontWeight.w500,
                        color:      cs.onSurface.withOpacity(0.7))),
                const Spacer(),
                // Tombol bagi rata semua
                if (widget.participants.length > 1)
                  GestureDetector(
                    onTap: widget.onSplitEqual,
                    child: Text(
                      'Bagi rata semua',
                      style: TextStyle(
                          fontSize:   11,
                          color:      cs.primary,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // Chip tiap peserta — tap untuk toggle
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: widget.participants.map((p) {
                final isSelected = item.shares.containsKey(p.id);
                final shareQty   = item.shares[p.id] ?? 0.0;
                return GestureDetector(
                  onTap: () => widget.onTogglePart(p.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:  const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color:        isSelected
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      border:       Border.all(
                        color: isSelected
                            ? cs.primary.withOpacity(0.6)
                            : cs.outline.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          p.isSelf ? 'Saya' : p.name.isEmpty
                              ? 'Peserta'
                              : p.name,
                          style: TextStyle(
                            fontSize:   12,
                            fontWeight: FontWeight.w500,
                            color:      isSelected
                                ? cs.onPrimaryContainer
                                : cs.onSurface.withOpacity(0.5),
                          ),
                        ),
                        // Tampilkan porsi kalau lebih dari 1 peserta
                        if (isSelected && widget.participants.length > 1) ...[
                          const SizedBox(width: 4),
                          Text(
                            '×${shareQty % 1 == 0 ? shareQty.toInt() : shareQty.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 11,
                              color:    cs.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════
// STEP 2 — Diskon & Pajak
// ═════════════════════════════════════════════════════════════

class _Step2DiskonHitung extends ConsumerWidget {
  final VoidCallback onBack;
  final VoidCallback onHitung;
  const _Step2DiskonHitung({required this.onBack, required this.onHitung});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form     = ref.watch(billFormProvider);
    final notifier = ref.read(billFormProvider.notifier);
    final subtotal = form.items.fold(0.0, (s, i) => s + i.subtotal);
    final cs       = Theme.of(context).colorScheme;

    // Preview kalkulasi diskon & pajak secara realtime
    double discountAmt = 0;
    if (form.discountType == 'percent') {
      discountAmt = subtotal * (form.discountValue / 100);
    } else {
      discountAmt = form.discountValue.clamp(0, subtotal);
    }
    final afterDiscount = subtotal - discountAmt;
    final taxAmt        = afterDiscount * (form.taxPercent / 100);
    final grandTotal    = afterDiscount + taxAmt;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Diskon ──────────────────────────────
                Text('Diskon',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),

                // Toggle tipe diskon
                Row(
                  children: [
                    Expanded(
                      child: _TypeToggle(
                        label:     'Flat (Rp)',
                        isActive:  form.discountType == 'flat',
                        onTap:     () => notifier.setDiscountType('flat'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TypeToggle(
                        label:     'Persen (%)',
                        isActive:  form.discountType == 'percent',
                        onTap:     () => notifier.setDiscountType('percent'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                _NumberField(
                  initialValue: form.discountValue > 0
                      ? form.discountValue.toStringAsFixed(
                          form.discountType == 'percent' ? 1 : 0)
                      : '',
                  label:   form.discountType == 'flat'
                      ? 'Nilai diskon (Rp)'
                      : 'Persentase diskon (%)',
                  icon:    Icons.discount_outlined,
                  onChanged: (v) =>
                      notifier.setDiscountValue(double.tryParse(v) ?? 0),
                ),
                const SizedBox(height: 24),

                // ── Pajak ────────────────────────────────
                Text('Pajak / Service',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _NumberField(
                  initialValue: form.taxPercent > 0
                      ? form.taxPercent.toStringAsFixed(1)
                      : '',
                  label:     'Pajak (%)',
                  icon:      Icons.receipt_outlined,
                  onChanged: (v) =>
                      notifier.setTaxPercent(double.tryParse(v) ?? 0),
                ),
                const SizedBox(height: 24),

                // ── Preview total ────────────────────────
                Container(
                  padding:    const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color:        cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _PreviewRow('Subtotal',
                          TransactionService.formatCurrency(subtotal),
                          context),
                      if (discountAmt > 0) ...[
                        const Divider(height: 12),
                        _PreviewRow(
                          'Diskon${form.discountType == 'percent' ? ' (${form.discountValue.toStringAsFixed(0)}%)' : ''}',
                          '- ${TransactionService.formatCurrency(discountAmt)}',
                          context,
                          color: Colors.green.shade600,
                        ),
                      ],
                      if (taxAmt > 0) ...[
                        const Divider(height: 12),
                        _PreviewRow(
                          'Pajak (${form.taxPercent.toStringAsFixed(0)}%)',
                          '+ ${TransactionService.formatCurrency(taxAmt)}',
                          context,
                          color: cs.error,
                        ),
                      ],
                      const Divider(height: 16),
                      _PreviewRow('TOTAL',
                          TransactionService.formatCurrency(grandTotal),
                          context,
                          isBold: true,
                          color:  cs.primary),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        _StepNavButtons(
          onBack:    onBack,
          onNext:    onHitung,
          nextLabel: 'Hitung Split',
          nextIcon:  Icons.calculate_outlined,
        ),
      ],
    );
  }
}

class _TypeToggle extends StatelessWidget {
  final String   label;
  final bool     isActive;
  final VoidCallback onTap;
  const _TypeToggle({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:  const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color:        isActive ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(
            color: isActive
                ? cs.primary.withOpacity(0.5)
                : cs.outline.withOpacity(0.2),
          ),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize:   13,
              color:      isActive
                  ? cs.onPrimaryContainer
                  : cs.onSurface.withOpacity(0.5),
            )),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label, value;
  final BuildContext ctx;
  final bool isBold;
  final Color? color;
  const _PreviewRow(this.label, this.value, this.ctx,
      {this.isBold = false, this.color});

  @override
  Widget build(BuildContext ctx2) {
    return Row(
      children: [
        Text(label,
            style: TextStyle(
                fontSize: isBold ? 15 : 13,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.normal)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontSize:   isBold ? 16 : 13,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                color:      color)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────

class _NumberField extends StatelessWidget {
  final String          initialValue;
  final String          label;
  final IconData        icon;
  final ValueChanged<String> onChanged;

  const _NumberField({
    required this.initialValue,
    required this.label,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue:  initialValue,
      onChanged:     onChanged,
      keyboardType:  const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
      ],
      decoration: _inputDec(context, label, icon: icon),
    );
  }
}

class _StepNavButtons extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onNext;
  final String       nextLabel;
  final IconData?    nextIcon;

  const _StepNavButtons({
    required this.onBack,
    required this.onNext,
    required this.nextLabel,
    this.nextIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed:    onBack,
            icon:         const Icon(Icons.chevron_left, size: 18),
            label:        const Text('Kembali'),
            style:        OutlinedButton.styleFrom(
              minimumSize:    const Size(100, 48),
              shape:          RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed:  onNext,
              icon:       Icon(nextIcon ?? Icons.chevron_right, size: 18),
              label:      Text(nextLabel),
              style:      FilledButton.styleFrom(
                minimumSize:    const Size.fromHeight(48),
                shape:          RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _inputDec(
  BuildContext context,
  String label, {
  String? hint,
  IconData? icon,
}) =>
    InputDecoration(
      labelText:   label,
      hintText:    hint,
      prefixIcon:  icon != null ? Icon(icon, size: 18) : null,
      isDense:     true,
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
          horizontal: 12, vertical: 12),
    );