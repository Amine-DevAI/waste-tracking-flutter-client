import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';
import 'package:waste_tracking/config/app_config.dart';
import 'package:waste_tracking/ffi/services/weighing_service.dart';
import 'package:waste_tracking/ffi/services/scale_service.dart';
import 'package:waste_tracking/ffi/services/catalog_service.dart';
import 'package:waste_tracking/ffi/models/material_type.dart' as wt;
import 'package:waste_tracking/ffi/models/product.dart';
import 'package:waste_tracking/ffi/models/weighing.dart';
import 'package:waste_tracking/ffi/utils/ticket_printer.dart';
import 'package:waste_tracking/theme/app_theme.dart';

class WeighScreen extends StatefulWidget {
  const WeighScreen({super.key});
  @override
  State<WeighScreen> createState() => _WeighScreenState();
}

class _WeighScreenState extends State<WeighScreen> {
  wt.MaterialType? _selectedType;
  Product? _selectedProduct;
  String _lotNumber = '';
  double _gross = 0.0;
  double _lastScaleValue = 0.0;
  double _tare = 0.0;
  double _capturedGross = 0.0;
  bool _isStable = false;
  bool _busy = false;
  bool _tareCaptured = false;
  bool _grossCaptured = false;

  late final ScaleService _scale;
  StreamSubscription? _scaleSub;

  int _step = 0;
  String _sampleStatus = 'Waiting for calibration';

  bool _loadingCatalog = true;
  List<wt.MaterialType> _types = const [];
  List<Product> _products = const [];

  final TextEditingController _lotNumberController = TextEditingController();
  DateTime? _lastScaleUpdate;

  bool _loadingHistory = true;
  List<Weighing> _history = const [];

  @override
  void initState() {
    super.initState();
    _scale = ScaleService(
        portName: AppConfig.scalePort, baudRate: AppConfig.scaleBaud);
    _startScale();
    _loadCatalog();
    _refreshHistory();
  }

  void _startScale() {
    _scaleSub = _scale.continuousStream.listen(
      (event) {
        final now = DateTime.now();
        if (_lastScaleUpdate != null &&
            now.difference(_lastScaleUpdate!).inMilliseconds < 150) return;
        _lastScaleUpdate = now;
        final normalized = _scaleRawToKg(event.weight);
        final newVal = double.parse(normalized.toStringAsFixed(3));
        final newStable = event.isStable;

        // Only rebuild if something actually changed
        if (newVal == _lastScaleValue && newStable == _isStable) return;

        setState(() {
          _gross = newVal;
          _lastScaleValue = newVal;
          _isStable = newStable;
        });
      },
      onError: (error) {
        _showError('Scale error: $error');
        setState(() {
          _isStable = false;
          _busy = false;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _isStable = false;
          _busy = false;
        });
      },
      cancelOnError: true,
    );
  }

  double _scaleRawToKg(String raw) {
    final p = _parseRawWeight(raw);
    return p > 100.0 ? p / 1000.0 : p;
  }

  double _parseRawWeight(String raw) {
    final t = raw.trim();
    return t.isEmpty ? 0.0 : (double.tryParse(t) ?? 0.0);
  }

  Future<void> _readScale() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _sampleStatus = 'Reading scale...';
    });
    try {
      final reading = await _scale.readOnce(timeoutMs: 5000);
      if (!reading.isSuccess) {
        _showError(
            'Scale read failed: ${reading.errorMessage ?? reading.errorCode}');
        return;
      }
      final normalized = _scaleRawToKg(reading.weight);
      setState(() {
        _lastScaleValue = double.parse(normalized.toStringAsFixed(3));
        _sampleStatus =
            'Current read: ${_lastScaleValue.toStringAsFixed(3)} kg';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadCatalog() async {
    setState(() => _loadingCatalog = true);
    try {
      final types = await CatalogService.instance.listTypes();
      final products = await CatalogService.instance.listProducts();
      if (!mounted) return;
      setState(() {
        _types = types;
        _products = products;
      });
    } finally {
      if (mounted) setState(() => _loadingCatalog = false);
    }
  }

  Future<void> _refreshHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final list = await WeighingService.instance.myList();
      if (!mounted) return;
      setState(() => _history = list);
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedType == null) {
      _showError('Please select a material type');
      return;
    }
    if (_selectedType!.requiresLot && _lotNumber.trim().isEmpty) {
      _showError('Lot number is required for this type');
      return;
    }
    if (_selectedType!.requiresProduct && _selectedProduct == null) {
      _showError('Product is required for this type');
      return;
    }
    if (!_tareCaptured) {
      _showError('Please capture tare before submitting');
      return;
    }
    if (!_grossCaptured) {
      _showError('Please capture gross before submitting');
      return;
    }

    final grossR = double.parse(_capturedGross.toStringAsFixed(3));
    final tareR = double.parse(_tare.toStringAsFixed(3));
    if (grossR - tareR <= 0) {
      _showError('Net weight must be positive');
      return;
    }

    setState(() => _busy = true);
    try {
      final uuid = await WeighingService.instance.create(
        typeId: _selectedType!.id,
        productId: _selectedProduct?.id ?? 0,
        gross: grossR,
        tare: tareR,
        lot: _lotNumber,
      );
      if (uuid != null) {
        final printed = await _showTicket(uuid);
        if (!printed) {
          _showError('Printing is required to complete the weighing');
          return;
        }
        _showSuccess(uuid);
        _reset();
        await _refreshHistory();
      } else {
        _showError('Server rejected weighing. Check logs.');
      }
    } finally {
      setState(() => _busy = false);
    }
  }

  double get _net => _capturedGross > _tare ? _capturedGross - _tare : 0.0;
  String _formatWeight(double v) => NumberFormat('00.000').format(v);

  Future<bool> _showTicket(String uuid) async {
    final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final data = WeighingTicketData(
      uuid: uuid,
      serial: DateTime.now().millisecondsSinceEpoch.toString(),
      operatorName: AuthService.instance.session?.username ?? 'unknown',
      material: _selectedType?.name ?? '',
      product: _selectedProduct?.name ?? '',
      lot: _lotNumber,
      gross: _capturedGross,
      tare: _tare,
      net: _net,
      createdAt: now,
    );
    if (!mounted) return false;
    final printed = await showDialog<bool>(
        context: context, builder: (_) => _TicketDialog(data: data));
    return printed ?? false;
  }

  void _reset() {
    setState(() {
      _selectedType = null;
      _selectedProduct = null;
      _lotNumber = '';
      _lotNumberController.clear();
      _tare = 0.0;
      _capturedGross = 0.0;
      _tareCaptured = false;
      _grossCaptured = false;
      _step = 0;
      _sampleStatus = 'Waiting for calibration';
    });
  }

  void _showSuccess(String uuid) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Weighing Recorded! UUID: $uuid'),
          backgroundColor: AppTheme.success));

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.error));

  @override
  void dispose() {
    _scaleSub?.cancel();
    _lotNumberController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(builder: (context, constraints) {
          // Keep history in sidebar for wide layouts, and stacked for narrow.
          final isWide = constraints.maxWidth >= 800;

          // FIX 1 — wrap in SingleChildScrollView so stepper never overflows
          final leftContent = SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Weighing (4 steps)', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                _buildScaleDisplay(),
                const SizedBox(height: 16),
                _buildStepper(theme),
                const SizedBox(height: 16),
                _buildStepActions(),
                const SizedBox(height: 24),
              ],
            ),
          );

          final rightContent = _buildHistory(theme);

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: leftContent),
                const SizedBox(width: 24),
                ConstrainedBox(
                  constraints:
                      const BoxConstraints(minWidth: 300, maxWidth: 420),
                  child: rightContent,
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: leftContent),
              const SizedBox(height: 24),
              rightContent,
            ],
          );
        }),
      ),
    );
  }

  Widget _buildStepper(ThemeData theme) {
    return Stepper(
      currentStep: _step,
      onStepTapped: _busy ? null : (i) => setState(() => _step = i),
      controlsBuilder: (_, __) => const SizedBox.shrink(),
      steps: [
        Step(
          title: const Text('Select'),
          isActive: _step >= 0,
          content: _buildForm(),
        ),
        Step(
          title: const Text('Tare'),
          isActive: _step >= 1,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Weight of the empty container.',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Row(children: [
                ElevatedButton(
                    onPressed: _busy ? null : _readScale,
                    child: const Text('Read the Scale')),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _busy || _lastScaleValue <= 0
                      ? null
                      : () => setState(() {
                            _tare = _lastScaleValue;
                            _tareCaptured = true;
                            _sampleStatus =
                                'Tare set to ${_tare.toStringAsFixed(3)} kg';
                          }),
                  child: const Text('Set tare'),
                ),
              ]),
              const SizedBox(height: 12),
              Text('Last reading: ${_formatWeight(_lastScaleValue)} kg',
                  style: theme.textTheme.bodyMedium),
              Text('Tare: ${_formatWeight(_tare)} kg',
                  style: theme.textTheme.bodyMedium),
              Text('Status: $_sampleStatus', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        Step(
          title: const Text('Gross'),
          isActive: _step >= 2,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total weight with full container.',
                  style: theme.textTheme.bodyMedium),
              Text('Wait for stability before capturing.',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Row(children: [
                ElevatedButton(
                    onPressed: _busy ? null : _readScale,
                    child: const Text('Read the Scale')),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _busy || _lastScaleValue <= 0
                      ? null
                      : () => setState(() {
                            _capturedGross = _lastScaleValue;
                            _grossCaptured = true;
                            _sampleStatus =
                                'Gross set to ${_capturedGross.toStringAsFixed(3)} kg';
                          }),
                  child: const Text('Set gross'),
                ),
              ]),
              const SizedBox(height: 12),
              Text('Last reading: ${_formatWeight(_lastScaleValue)} kg',
                  style: theme.textTheme.bodyMedium),
              Text('Gross captured: ${_formatWeight(_capturedGross)} kg',
                  style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        Step(
          title: const Text('Confirm & print'),
          isActive: _step >= 3,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tare:  ${_formatWeight(_tare)} kg',
                  style: theme.textTheme.bodyMedium),
              Text('Gross: ${_formatWeight(_capturedGross)} kg',
                  style: theme.textTheme.bodyMedium),
              Text('Net:   ${_formatWeight(_net)} kg',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Net = gross − tare. You must print QR to finish.',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
            
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepActions() {
    bool ok0() => _selectedType != null;
    bool ok1() => _tareCaptured;
    bool ok2() => _grossCaptured;
    bool canSubmit() => _step == 3 && _grossCaptured && _tareCaptured && !_busy;

    return Row(
      children: [
        TextButton(
          onPressed: _busy || _step == 0 ? null : () => setState(() => _step--),
          child: const Text('Back'),
        ),
        const SizedBox(width: 8),
        if (_step < 3)
          ElevatedButton(
            onPressed: _busy
                ? null
                : () {
                    final valid = _step == 0
                        ? ok0()
                        : _step == 1
                            ? ok1()
                            : ok2();
                    if (valid) setState(() => _step++);
                  },
            child: const Text('Next'),
          )
        else
          ElevatedButton(
            onPressed: canSubmit() ? _submit : null,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('CREATE + PRINT'),
          ),
        const SizedBox(width: 12),
        TextButton(
            onPressed: _busy ? null : _reset, child: const Text('Reset')),
      ],
    );
  }

  Widget _buildScaleDisplay() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _isStable
            ? AppTheme.success.withOpacity(0.1)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('SCALE WEIGHT', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text('${_formatWeight(_lastScaleValue)} kg',
                    style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: _isStable
                            ? AppTheme.success
                            : AppTheme.primaryBlue)),
              ),
                Text(_isStable ? 'Stable' : '',
                  style: TextStyle(
                      color: _isStable ? AppTheme.success : AppTheme.warning,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Status: $_sampleStatus',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _readScale,
                  icon: const Icon(Icons.repeat),
                  label: const Text('Read now'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () {
                        _scaleSub?.cancel();
                        _startScale();
                        setState(() => _sampleStatus = 'Reconnecting scale...');
                      },
                child: const Text('Reconnect'),
              ),
            ],
          ),
          if (_lastScaleValue == 0.0 &&
              _sampleStatus == 'Waiting for calibration')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Scale is not connected or no data yet.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      children: [
        Align(
            alignment: Alignment.centerLeft,
            child: Text('Material type',
                style: Theme.of(context).textTheme.labelMedium)),
        const SizedBox(height: 6),
        DropdownButtonFormField<wt.MaterialType>(
          value: _selectedType,
          isExpanded: true,
          hint: Text(_loadingCatalog ? 'Loading…' : 'Select material type'),
          items: _types
              .map((t) => DropdownMenuItem(
                  value: t, child: Text('${t.code} — ${t.name}')))
              .toList(),
          onChanged: _loadingCatalog
              ? null
              : (v) => setState(() {
                    _selectedType = v;
                    _selectedProduct = null;
                    _tare = 0.0;
                    _sampleStatus = 'Ready to read scale';
                  }),
        ),
        const SizedBox(height: 6),
        if (_selectedType?.requiresProduct ?? false) ...[
          Align(
              alignment: Alignment.centerLeft,
              child: Text('Product',
                  style: Theme.of(context).textTheme.labelMedium)),
          const SizedBox(height: 6),
          DropdownButtonFormField<Product>(
            value: _selectedProduct,
            isExpanded: true,
            hint: Text(_loadingCatalog ? 'Loading…' : 'Select product'),
            items: _products
                .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                .toList(),
            onChanged: _loadingCatalog
                ? null
                : (v) => setState(() {
                      _selectedProduct = v;
                      _tare = 0.0;
                    }),
          ),
          const SizedBox(height: 12),
        ],
        if (_selectedType?.requiresLot ?? false)
          TextField(
            controller: _lotNumberController,
            decoration: const InputDecoration(labelText: 'Lot Number'),
            onChanged: (v) => _lotNumber = v,
          ),
      ],
    );
  }

  // ── HISTORY — compact: #id + createdAt only ──────────────────────────────
  Widget _buildHistory(ThemeData theme) {
    return LayoutBuilder(builder: (context, constraints) {
      final listHeight = (constraints.maxHeight.isFinite
              ? (constraints.maxHeight - 120).clamp(220.0, 420.0)
              : 420.0)
          .toDouble();

      return Card(
        elevation: 8,
        clipBehavior: Clip.hardEdge,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text('My history',
                          style: theme.textTheme.titleLarge)),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _loadingHistory ? null : _refreshHistory,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loadingHistory)
                const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()))
              else if (_history.isEmpty)
                const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Center(child: Text('No weighings yet')))
              else
                SizedBox(
                  height: listHeight,
                  child: ListView.separated(
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final w = _history[i];
                      return ListTile(
                        dense: true,
                        title: Row(children: [
                          Text('#${w.id}',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          if (w.isFlagged) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.flag,
                                color: AppTheme.warning, size: 14),
                          ],
                        ]),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(w.createdAtFormatted,
                                style: theme.textTheme.bodySmall),
                            if (w.typeCode.isNotEmpty)
                              Text('Type code: ${w.typeCode}',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: Colors.grey)),
                            if (w.zoneName.isNotEmpty)
                              Text('Zone: ${w.zoneName}',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: Colors.grey)),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => _openWeighingDetails(w),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _openWeighingDetails(Weighing w) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) =>
          _WeighingDetailsDialog(weighing: w, onCorrected: _refreshHistory),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TICKET DIALOG
// ═══════════════════════════════════════════════════════════════════════════
class _TicketDialog extends StatelessWidget {
  final WeighingTicketData data;
  const _TicketDialog({required this.data});

  @override
  Widget build(BuildContext context) {
    final payload = jsonEncode({
      'serial': data.serial,
      'material': data.material,
      'product': data.product,
      'operator': data.operatorName,
      'gross': data.gross,
      'tare': data.tare,
      'net': data.net,
      'lot': data.lot,
      'created_at': data.createdAt,
      'uuid': data.uuid,
    });

    return AlertDialog(
      title: const Text('Ticket preview'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                  dense: true,
                  title: const Text('UUID'),
                  subtitle: Text(data.uuid)),
              ListTile(
                  dense: true,
                  title: const Text('QR payload'),
                  subtitle: Text(payload)),
              const SizedBox(height: 4),
              Center(
                  child: QrImageView(
                      data: payload, size: 180, backgroundColor: Colors.white)),
              const SizedBox(height: 8),
              Center(
                  child: QrImageView(
                      data: data.uuid,
                      size: 180,
                      backgroundColor: Colors.white)),
              const SizedBox(height: 8),
              ListTile(
                  dense: true,
                  title: const Text('Serial'),
                  subtitle: Text(data.serial.isEmpty ? '-' : data.serial)),
              ListTile(
                  dense: true,
                  title: const Text('Operator'),
                  subtitle: Text(
                      data.operatorName.isEmpty ? '-' : data.operatorName)),
              ListTile(
                  dense: true,
                  title: const Text('Material'),
                  subtitle: Text(data.material.isEmpty ? '-' : data.material)),
              ListTile(
                  dense: true,
                  title: const Text('Product'),
                  subtitle: Text(data.product.isEmpty ? '-' : data.product)),
              ListTile(
                  dense: true,
                  title: const Text('Lot'),
                  subtitle: Text(data.lot.isEmpty ? '-' : data.lot)),
              ListTile(
                  dense: true,
                  title: const Text('Gross / Tare / Net'),
                  subtitle: Text(
                      '${data.gross.toStringAsFixed(3)} / ${data.tare.toStringAsFixed(3)} / ${data.net.toStringAsFixed(3)} kg')),
              ListTile(
                  dense: true,
                  title: const Text('Created At'),
                  subtitle: Text(data.createdAt)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close')),
        ElevatedButton(
          onPressed: () async {
            final doc = TicketPrinter.buildWeighingTicket(data);
            await Printing.layoutPdf(onLayout: (_) async => doc.save());
            Navigator.of(context).pop(true);
          },
          child: const Text('Print'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WEIGHING DETAILS DIALOG
// ═══════════════════════════════════════════════════════════════════════════
class _WeighingDetailsDialog extends StatefulWidget {
  final Weighing weighing;
  final Future<void> Function() onCorrected;

  const _WeighingDetailsDialog(
      {required this.weighing, required this.onCorrected});

  @override
  State<_WeighingDetailsDialog> createState() => _WeighingDetailsDialogState();
}

class _WeighingDetailsDialogState extends State<_WeighingDetailsDialog> {
  // ── catalog ──────────────────────────────────────────────────────────────
  bool _loadingCatalog = true;
  List<wt.MaterialType> _types = const [];
  List<Product> _products = const [];
  wt.MaterialType? _selectedType;
  Product? _selectedProduct;

  // ── lot / reason ─────────────────────────────────────────────────────────
  late final TextEditingController _lotCtrl =
      TextEditingController(text: widget.weighing.lotNumber);
  final TextEditingController _reasonCtrl = TextEditingController();

  // ── scale ─────────────────────────────────────────────────────────────────
  late final ScaleService _scale;
  StreamSubscription? _scaleSub;
  double _lastScaleValue = 0.0;
  bool _isStable = false;
  DateTime? _lastScaleUpdate;

  // ── captured weights ───────────────────────────────────────────────────
  double _tare = 0.0;
  double _capturedGross = 0.0;
  bool _tareCaptured = false;
  bool _grossCaptured = false;
  String _scaleStatus = 'Waiting for scale…';

  bool _busy = false;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _scale = ScaleService(
        portName: AppConfig.scalePort, baudRate: AppConfig.scaleBaud);
    _startScale();
    _loadCatalogData();
  }

  @override
  void dispose() {
    _scaleSub?.cancel();
    _lotCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  // ── scale stream ────────────────────────────────────────────────────────
  void _startScale() {
    _scaleSub = _scale.continuousStream.listen(
      (event) {
        final now = DateTime.now();
        if (_lastScaleUpdate != null &&
            now.difference(_lastScaleUpdate!).inMilliseconds < 150) return;
        _lastScaleUpdate = now;

        final kg = _scaleRawToKg(event.weight);
        final newVal = double.parse(kg.toStringAsFixed(3));
        final newStable = event.isStable;

        if (newVal == _lastScaleValue && newStable == _isStable) return;
        setState(() {
          _lastScaleValue = newVal;
          _isStable = newStable;
        });
      },
      onError: (_) => setState(() {
        _isStable = false;
      }),
      cancelOnError: true,
    );
  }

  double _scaleRawToKg(String raw) {
    final t = raw.trim();
    final v = t.isEmpty ? 0.0 : (double.tryParse(t) ?? 0.0);
    return v > 100.0 ? v / 1000.0 : v;
  }

  Future<void> _readScale() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _scaleStatus = 'Reading scale…';
    });
    try {
      final reading = await _scale.readOnce(timeoutMs: 5000);
      if (!reading.isSuccess) {
        _snack(
            'Scale read failed: ${reading.errorMessage ?? reading.errorCode}',
            isError: true);
        return;
      }
      final kg = _scaleRawToKg(reading.weight);
      setState(() {
        _lastScaleValue = double.parse(kg.toStringAsFixed(3));
        _scaleStatus = 'Read: ${_lastScaleValue.toStringAsFixed(3)} kg';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── catalog ───────────────────────────────────────────────────────────────
  Future<void> _loadCatalogData() async {
    setState(() => _loadingCatalog = true);
    try {
      final types = await CatalogService.instance.listTypes();
      final products = await CatalogService.instance.listProducts();
      if (!mounted) return;

      wt.MaterialType? selType;
      try {
        selType = types.firstWhere((t) =>
            t.code == widget.weighing.typeCode ||
            t.name == widget.weighing.typeName);
      } catch (_) {}

      Product? selProd;
      if (widget.weighing.productName.isNotEmpty) {
        try {
          selProd =
              products.firstWhere((p) => p.name == widget.weighing.productName);
        } catch (_) {}
      }

      setState(() {
        _types = types;
        _products = products;
        _selectedType = selType;
        _selectedProduct = selProd;
      });
    } finally {
      if (mounted) setState(() => _loadingCatalog = false);
    }
  }

  // ── submit ────────────────────────────────────────────────────────────────
  Future<void> _submitCorrection() async {
    if (!_tareCaptured) {
      _snack('Please capture tare from the scale', isError: true);
      return;
    }
    if (!_grossCaptured) {
      _snack('Please capture gross from the scale', isError: true);
      return;
    }

    final net = _capturedGross - _tare;
    if (net <= 0) {
      _snack('Net weight must be positive (gross must exceed tare)',
          isError: true);
      return;
    }

    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      _snack('Reason is required', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final changes = <String, dynamic>{
        'gross_weight': double.parse(_capturedGross.toStringAsFixed(3)),
        'tare_weight': double.parse(_tare.toStringAsFixed(3)),
        'lot_number': _lotCtrl.text.trim(),
        if (_selectedType != null) 'type_id': _selectedType!.id,
        if (_selectedProduct != null) 'product_id': _selectedProduct!.id,
      };
      final code = await WeighingService.instance.correct(
          weighingId: widget.weighing.id, reason: reason, changes: changes);
      if (!mounted) return;
      if (code == 0) {
        _snack('Correction submitted', isError: false);
        await widget.onCorrected();
        if (mounted) Navigator.of(context).pop();
      } else {
        _snack('Correction failed (code $code)', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reprintTicket() async {
    if (!_tareCaptured || !_grossCaptured) {
      _snack('Capture tare and gross before reprinting', isError: true);
      return;
    }
    final data = WeighingTicketData(
      uuid: widget.weighing.qrCodeData,
      serial: DateTime.now().millisecondsSinceEpoch.toString(),
      operatorName: widget.weighing.operatorName.isEmpty
          ? 'unknown'
          : widget.weighing.operatorName,
      material: _selectedType?.name ?? widget.weighing.typeName,
      product: _selectedProduct?.name ?? widget.weighing.productName,
      lot: _lotCtrl.text.trim(),
      gross: _capturedGross,
      tare: _tare,
      net: _capturedGross - _tare,
      createdAt: widget.weighing.createdAtFormatted,
    );
    final doc = TicketPrinter.buildWeighingTicket(data);
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  void _snack(String msg, {required bool isError}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: isError ? AppTheme.error : AppTheme.success));

  String _fmt(double v) => NumberFormat('00.000').format(v);

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 110,
                child: Text(label,
                    style: const TextStyle(fontSize: 11, color: Colors.grey))),
            Expanded(
                child: Text(value.isEmpty ? '—' : value,
                    style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = widget.weighing;

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Weighing details')),
          if (w.isFlagged)
            Chip(
              avatar: const Icon(Icons.flag, color: AppTheme.warning, size: 14),
              label: const Text('Flagged',
                  style: TextStyle(color: AppTheme.warning, fontSize: 11)),
              backgroundColor: Colors.transparent,
              side: const BorderSide(color: AppTheme.warning),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── READ-ONLY INFO ─────────────────────────────────────────
              Card(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row('ID', w.id.toString()),
                      _row('Status', w.status),
                      _row('Created at', w.createdAtFormatted),
                      _row('UUID', w.qrCodeData),
                      _row('Operator', w.operatorName),
                      _row('Zone', w.zoneName),
                      _row('Material', w.typeName),
                      _row('Type code', w.typeCode),
                      if (w.productName.isNotEmpty)
                        _row('Product', w.productName),
                      if (w.lotNumber.isNotEmpty) _row('Lot', w.lotNumber),
                      _row('Gross (original)',
                          '${w.grossWeight.toStringAsFixed(3)} kg'),
                      _row('Tare (original)',
                          '${w.tareWeight.toStringAsFixed(3)} kg'),
                      _row('Net (original)',
                          '${w.netWeight.toStringAsFixed(3)} kg'),
                      if (w.isFlagged && (w.flagReason?.isNotEmpty ?? false))
                        _row('Flag reason', w.flagReason!),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── LIVE SCALE DISPLAY ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isStable
                      ? AppTheme.success.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('SCALE', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            '${_fmt(_lastScaleValue)} kg',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: _isStable
                                  ? AppTheme.success
                                  : AppTheme.primaryBlue,
                            ),
                          ),
                        ),
                        Text(_isStable ? 'Stable' : '',
                            style: TextStyle(
                                color: _isStable
                                    ? AppTheme.success
                                    : AppTheme.warning,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Status: $_scaleStatus',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _busy ? null : _readScale,
                            icon: const Icon(Icons.repeat, size: 16),
                            label: const Text('Read now'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  _scaleSub?.cancel();
                                  _startScale();
                                  setState(
                                      () => _scaleStatus = 'Reconnecting…');
                                },
                          child: const Text('Reconnect'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── CAPTURE BUTTONS ───────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy || _lastScaleValue <= 0
                          ? null
                          : () => setState(() {
                                _tare = _lastScaleValue;
                                _tareCaptured = true;
                                _scaleStatus =
                                    'Tare set: ${_tare.toStringAsFixed(3)} kg';
                              }),
                      child: Text(_tareCaptured
                          ? 'Tare ✓  ${_fmt(_tare)} kg'
                          : 'Set tare'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy || _lastScaleValue <= 0
                          ? null
                          : () => setState(() {
                                _capturedGross = _lastScaleValue;
                                _grossCaptured = true;
                                _scaleStatus =
                                    'Gross set: ${_capturedGross.toStringAsFixed(3)} kg';
                              }),
                      child: Text(_grossCaptured
                          ? 'Gross ✓  ${_fmt(_capturedGross)} kg'
                          : 'Set gross'),
                    ),
                  ),
                ],
              ),

              // ── NET PREVIEW ───────────────────────────────────────────────
              if (_tareCaptured && _grossCaptured) ...[
                const SizedBox(height: 8),
                Text(
                  'Net: ${_fmt(_capturedGross - _tare)} kg',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],

              const SizedBox(height: 16),

              // ── CORRECTION FIELDS ───────────────────────────────────────────
              const Text('Correction details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),

              if (_loadingCatalog)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()))
              else ...[
                DropdownButtonFormField<wt.MaterialType>(
                  value: _selectedType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Material type'),
                  items: _types
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text('${t.code} · ${t.name}')))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedType = v),
                ),
                const SizedBox(height: 8),
                if (_selectedType?.requiresProduct ?? false) ...[
                  DropdownButtonFormField<Product>(
                    value: _selectedProduct,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Product'),
                    items: _products
                        .map((p) =>
                            DropdownMenuItem(value: p, child: Text(p.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedProduct = v),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                    controller: _lotCtrl,
                    decoration: const InputDecoration(labelText: 'Lot number')),
                const SizedBox(height: 8),
                TextField(
                    controller: _reasonCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Reason for correction (mandatory)')),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _reprintTicket,
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Reprint QR ticket'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Close')),
        ElevatedButton(
          onPressed: _busy ? null : _submitCorrection,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Submit correction'),
        ),
      ],
    );
  }
}
