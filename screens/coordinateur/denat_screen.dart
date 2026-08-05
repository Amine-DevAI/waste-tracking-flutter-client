import 'dart:async';
import 'package:flutter/material.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';

import 'package:waste_tracking/ffi/engine.dart';
import 'package:waste_tracking/ffi/services/denaturation_service.dart';
import 'package:waste_tracking/ffi/services/scanner_service.dart';
import 'package:waste_tracking/ffi/services/pending_service.dart';
import 'package:waste_tracking/ffi/services/scale_service.dart';
import 'package:waste_tracking/config/app_config.dart';
import 'package:waste_tracking/ffi/models/denaturation.dart';
import 'package:waste_tracking/ffi/models/pending_reco.dart';
import 'package:waste_tracking/ffi/widgets/scan_indicator.dart';
import 'package:waste_tracking/theme/app_theme.dart' hide SectionHeader;
import 'package:waste_tracking/ffi/screens/shared/section_header.dart';

// ============================================================================
// DENAT SCREEN — 3-column layout (mirrors ShipmentScreen)
//
//  ┌─────────────────┬────────────────────────┬────────────────┐
//  │  Pending Queue  │   Workflow (phases)     │  My History    │
//  │  (left, 260px)  │   (middle, flex)        │  (right, 280px)│
//  └─────────────────┴────────────────────────┴────────────────┘
// ============================================================================

enum DenatPhase { waiting, reviewing, done }

class DenatScreen extends StatefulWidget {
  const DenatScreen({super.key});

  @override
  State<DenatScreen> createState() => _DenatScreenState();
}

class _DenatScreenState extends State<DenatScreen> {
  DenatPhase _phase = DenatPhase.waiting;

  Denaturation? _active;
  bool _submitting = false;
  String _error = '';

  // ── Scanner ──────────────────────────────────────────────────────────────
  StreamSubscription<String>? _scanSub;

  // ── Pending queue ────────────────────────────────────────────────────────
  List<PendingItem> _pendingQueue = [];
  StreamSubscription? _pendingSub;

  // ── History ──────────────────────────────────────────────────────────────
  List<Denaturation> _history = [];
  bool _histLoading = false;

  // ── Scale ─────────────────────────────────────────────────────────────
  ScaleService? _scale;
  StreamSubscription? _scaleSub;
  double _lastScaleValue = 0.0;
  bool _isStable = false;
  DateTime? _lastScaleUpdate;
  String _scaleStatus = 'Waiting for scale…';

  // ── captured weights ─────────────────────────────────────────────────
  double _capturedBrut = 0.0;
  double _capturedNet = 0.0;
  bool _brutCaptured = false;
  bool _netCaptured = false;
  bool _bagVerified = false;

  // ── scanned QR (stored separately since scan response doesn't include it) ─
  String _scannedQr = '';

  // ── Form controllers ─────────────────────────────────────────────────────
  final _noteCtrl = TextEditingController();
  final _manualCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scanSub = ScannerService.instance.denatScans.listen(_onScan);
    _pendingSub =
        PendingService.instance.denatQueue.listen((List<PendingItem> items) {
      if (mounted) setState(() => _pendingQueue = items);
    });
    PendingService.instance.refreshDenatQueue();
    Future.delayed(const Duration(milliseconds: 100), _loadHistory);
  }

  // ── QR received ──────────────────────────────────────────────────────────
  Future<void> _onScan(String qr) async {
    final trimmed = qr.trim();
    if (trimmed.isEmpty) return;

    if (_phase == DenatPhase.waiting) {
      await _lookupQR(trimmed);
    } else if (_phase == DenatPhase.reviewing && !_bagVerified) {
      await _verifyPhysicalBag(trimmed);
    }
  }

  Future<void> _verifyPhysicalBag(String scanned) async {
    if (_active == null) return;

    final expected = _active!.qrCode;
    if (scanned == expected) {
      setState(() {
        _bagVerified = true;
        _error = '';
      });
    } else {
      setState(() {
        _bagVerified = false;
        _error = 'BAG MISMATCH — Expected $expected, got $scanned';
      });
    }
  }

  Future<void> _lookupQR(String qr) async {
    if (qr.isEmpty) return;
    setState(() {
      _error = '';
      _scaleStatus = 'Waiting for scale…';
    });

    final denat = await DenaturationService.instance.scanByQR(qr);
    if (!mounted) return;

    if (denat == null) {
      setState(() => _error = 'No pending denaturation found for this QR');
      return;
    }

    setState(() {
      _active = denat;
      _scannedQr = qr;
      _bagVerified = false;
      _capturedBrut = 0.0;
      _capturedNet = 0.0;
      _brutCaptured = false;
      _netCaptured = false;
      _noteCtrl.clear();
      _phase = DenatPhase.reviewing;
    });

    _startScale();
  }

  // ── Scale helpers ───────────────────────────────────────────────────
  void _startScale() {
    _scaleSub?.cancel();
    _scale = ScaleService(
        portName: AppConfig.scalePort, baudRate: AppConfig.scaleBaud);
    _scaleSub = _scale!.continuousStream.listen(
      (event) {
        final now = DateTime.now();
        if (_lastScaleUpdate != null &&
            now.difference(_lastScaleUpdate!).inMilliseconds < 150) return;
        _lastScaleUpdate = now;
        final kg = _scaleRawToKg(event.weight);
        final newVal = double.parse(kg.toStringAsFixed(3));
        final stable = event.isStable;
        if (newVal == _lastScaleValue && stable == _isStable) return;
        setState(() {
          _lastScaleValue = newVal;
          _isStable = stable;
        });
      },
      onError: (_) => setState(() => _isStable = false),
      cancelOnError: true,
    );
  }

  void _stopScale() {
    _scaleSub?.cancel();
    _scale?.stop();
  }

  double _scaleRawToKg(String raw) {
    final t = raw.trim();
    final v = t.isEmpty ? 0.0 : (double.tryParse(t) ?? 0.0);
    return v > 100.0 ? v / 1000.0 : v;
  }

  Future<void> _readScale() async {
    if (_submitting) return;
    setState(() {
      _scaleStatus = 'Reading scale…';
    });
    try {
      final reading = await _scale!.readOnce(timeoutMs: 5000);
      if (!reading.isSuccess) {
        setState(() => _error =
            'Scale read failed: ${reading.errorMessage ?? reading.errorCode}');
        return;
      }
      final kg = _scaleRawToKg(reading.weight);
      setState(() {
        _lastScaleValue = double.parse(kg.toStringAsFixed(3));
        _scaleStatus = 'Read: ${_lastScaleValue.toStringAsFixed(3)} kg';
      });
    } catch (e) {
      setState(() => _error = 'Scale error: $e');
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    final d = _active;
    if (d == null) return;

    if (!_brutCaptured) {
      setState(() => _error = 'Please capture brut weight from the scale');
      return;
    }
    if (!_netCaptured) {
      setState(() => _error = 'Please capture net weight from the scale');
      return;
    }
    if (_capturedBrut <= 0 || _capturedNet <= 0) {
      setState(() => _error = 'Both weights must be positive');
      return;
    }
    if (_scannedQr.isEmpty) {
      setState(() => _error = 'QR code missing — please re-scan the bag');
      return;
    }

    setState(() {
      _submitting = true;
      _error = '';
    });

    try {
      final code = await DenaturationService.instance.submit(
        denatId: d.id,
        brutAfter: double.parse(_capturedBrut.toStringAsFixed(3)),
        netAfter: double.parse(_capturedNet.toStringAsFixed(3)),
        qrScanned: _scannedQr,
        note: _noteCtrl.text.trim(),
      );

      if (!mounted) return;

      if (code == 0) {
        _stopScale();
        setState(() => _phase = DenatPhase.done);
        _loadHistory();
        PendingService.instance.refreshDenatQueue();
        _scheduleReset();
      } else {
        setState(() => _error = 'Submit failed (code $code)');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Reset ──────────────────────────────────────────────────────────────────
  void _scheduleReset() => Future.delayed(const Duration(seconds: 4), () {
        if (mounted) _resetToWaiting();
      });

  void _resetToWaiting() {
    _stopScale();
    if (mounted)
      setState(() {
        _phase = DenatPhase.waiting;
        _active = null;
        _scannedQr = '';
        _bagVerified = false;
        _submitting = false;
        _error = '';
        _lastScaleValue = 0.0;
        _isStable = false;
        _capturedBrut = 0.0;
        _capturedNet = 0.0;
        _brutCaptured = false;
        _netCaptured = false;
        _scaleStatus = 'Waiting for scale…';
        _noteCtrl.clear();
      });
  }

  // ── History ────────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    setState(() => _histLoading = true);
    try {
      final list = await DenaturationService.instance.myList();
      if (mounted) setState(() => _history = list);
    } finally {
      if (mounted) setState(() => _histLoading = false);
    }
  }

  // ── Open pending item with scan verification ──────────────────────────────
  Future<void> _openPendingWithScan(PendingItem item) async {
    final startDenat = await showDialog<bool>(
      context: context,
      builder: (_) => _DenatPendingVerifyDialog(
        item: item,
        onConfirmed: () {},
      ),
    );
    if (startDenat == true && mounted && _phase == DenatPhase.waiting) {
      _lookupQR(item.qrCode);
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _pendingSub?.cancel();
    _scaleSub?.cancel();
    _noteCtrl.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 260, child: _buildPendingQueue(isDark)),
          Container(width: 1, color: dividerColor),
          Expanded(
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
                  child: SectionHeader(
                    title: 'Denaturation',
                    subtitle: _phaseSubtitle(),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(
                      key: ValueKey(_phase),
                      child: _buildPhase(isDark),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          Container(width: 1, color: dividerColor),
          SizedBox(width: 280, child: _buildHistory(isDark)),
        ],
      ),
    );
  }

  String _phaseSubtitle() {
    switch (_phase) {
      case DenatPhase.waiting:
        return 'Scan QR or enter UUID manually';
      case DenatPhase.reviewing:
        return 'Enter final weights then confirm';
      case DenatPhase.done:
        return 'Recorded — resetting…';
    }
  }

  Widget _buildPhase(bool isDark) {
    switch (_phase) {
      case DenatPhase.waiting:
        return _buildWaiting(isDark);
      case DenatPhase.reviewing:
        return _buildReviewing(isDark);
      case DenatPhase.done:
        return _buildDone();
    }
  }

  // ============================================================
  // PHASE 1 — WAITING
  // ============================================================
  Widget _buildWaiting(bool isDark) {
    return Column(children: [
      const SizedBox(height: 16),
      _InfoCard(
        icon: Icons.science_outlined,
        title: 'Ready for scan',
        message: 'Scan the QR or barcode on the bag with the hardware scanner, '
            'or enter the UUID manually below.',
        isDark: isDark,
        color: AppTheme.error,
      ),
      const SizedBox(height: 28),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _manualCtrl,
            decoration: InputDecoration(
              labelText: 'Enter UUID manually',
              prefixIcon: const Icon(Icons.keyboard_outlined, size: 18),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) {
                _lookupQR(v.trim());
                _manualCtrl.clear();
              }
            },
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: () {
            final v = _manualCtrl.text.trim();
            if (v.isNotEmpty) {
              _lookupQR(v);
              _manualCtrl.clear();
            }
          },
          icon: const Icon(Icons.search_rounded, size: 18),
          label: const Text('Look up'),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
        ),
      ]),
      const SizedBox(height: 32),
      const ScanIndicator(message: 'Waiting for scan...'),
      if (_error.isNotEmpty) ...[
        const SizedBox(height: 16),
        _ErrorBanner(error: _error),
      ],
    ]);
  }

  // ============================================================
  // PHASE 2 — REVIEWING
  // ============================================================
  Widget _buildReviewing(bool isDark) {
    final d = _active!;
    final fmt = (double v) => v.toStringAsFixed(3);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      _SuccessBanner(
          message: 'Bag identified — capture final weights from scale'),
      const SizedBox(height: 20),

      // Detail card
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        child: Column(children: [
          _DetailRow('Denat ID', '#${d.id}'),
          _DetailRow('Material', d.material.isNotEmpty ? d.material : '—'),
          _DetailRow('QR', d.qrCode),
          _DetailRow('Status', d.status),
          const Divider(height: 20),
          Row(children: [
            Expanded(
                child: _WeightMini(
              label: 'Before',
              value: d.weightBefore,
              color: AppTheme.warning,
            )),
          ]),
        ]),
      ),

      const SizedBox(height: 20),

      // Live scale display
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isStable
              ? AppTheme.success.withOpacity(0.08)
              : Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('SCALE',
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Text('${fmt(_lastScaleValue)} kg',
                  style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: _isStable ? AppTheme.success : AppTheme.error)),
            ),
            Text(_isStable ? 'Stable' : '',
                style: TextStyle(
                    color: _isStable ? AppTheme.success : AppTheme.warning,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text('Status: $_scaleStatus',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _readScale,
                icon: const Icon(Icons.repeat, size: 16),
                label: const Text('Read now'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _submitting
                  ? null
                  : () {
                      _stopScale();
                      _startScale();
                      setState(() => _scaleStatus = 'Reconnecting…');
                    },
              child: const Text('Reconnect'),
            ),
          ]),
        ]),
      ),

      const SizedBox(height: 12),

      // Capture buttons
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.error.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.error.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.science_outlined, color: AppTheme.error, size: 16),
            const SizedBox(width: 8),
            Text('Final Weights After Denaturation',
                style: TextStyle(
                    color: AppTheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting || _lastScaleValue <= 0
                    ? null
                    : () => setState(() {
                          _capturedBrut = _lastScaleValue;
                          _brutCaptured = true;
                          _scaleStatus = 'Brut set: ${fmt(_capturedBrut)} kg';
                        }),
                child: Text(
                    _brutCaptured
                        ? 'Brut ✓  ${fmt(_capturedBrut)} kg'
                        : 'Set brut',
                    style: const TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting || _lastScaleValue <= 0
                    ? null
                    : () => setState(() {
                          _capturedNet = _lastScaleValue;
                          _netCaptured = true;
                          _scaleStatus = 'Net set: ${fmt(_capturedNet)} kg';
                        }),
                child: Text(
                    _netCaptured ? 'Net ✓  ${fmt(_capturedNet)} kg' : 'Set net',
                    style: const TextStyle(fontSize: 13)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(
              labelText: 'Note (optional)',
              prefixIcon: const Icon(Icons.notes_outlined, size: 18),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ]),
      ),

      const SizedBox(height: 24),

      Row(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('CONFIRM DENATURATION'),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.error,
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: _resetToWaiting,
          child: const Text('Cancel'),
        ),
      ]),

      if (_error.isNotEmpty) ...[
        const SizedBox(height: 16),
        _ErrorBanner(error: _error),
      ],
    ]);
  }

  // ============================================================
  // PHASE 3 — DONE
  // ============================================================
  Widget _buildDone() {
    return Column(children: [
      const SizedBox(height: 60),
      Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppTheme.success.withOpacity(0.1),
          shape: BoxShape.circle,
          border:
              Border.all(color: AppTheme.success.withOpacity(0.3), width: 2),
        ),
        child: const Icon(Icons.science_rounded,
            color: AppTheme.success, size: 36),
      ),
      const SizedBox(height: 24),
      Text('Denaturation Recorded',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(color: AppTheme.success)),
      const SizedBox(height: 10),
      Text('Returning to scan mode…',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 24),
      SizedBox(
        width: 200,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: 0.0),
          duration: const Duration(seconds: 4),
          builder: (_, v, __) => LinearProgressIndicator(
            value: v,
            color: AppTheme.success,
            backgroundColor: AppTheme.success.withOpacity(0.1),
          ),
        ),
      ),
    ]);
  }

  // ============================================================
  // LEFT — PENDING QUEUE
  // ============================================================
  Widget _buildPendingQueue(bool isDark) {
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final hintColor = isDark ? AppTheme.darkTextHint : AppTheme.lightTextHint;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
        child: Row(children: [
          const Icon(Icons.science_outlined, color: AppTheme.error, size: 18),
          const SizedBox(width: 8),
          Text('Pending Queue', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (_pendingQueue.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.error,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${_pendingQueue.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
      Divider(color: borderColor, height: 1),
      Expanded(
        child: _pendingQueue.isEmpty
            ? Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    Icon(Icons.done_all_rounded, size: 36, color: hintColor),
                    const SizedBox(height: 10),
                    Text('Queue is clear',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: hintColor)),
                  ]))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: _pendingQueue.length,
                separatorBuilder: (_, __) => Divider(
                    color: borderColor, height: 1, indent: 16, endIndent: 16),
                itemBuilder: (_, i) {
                  final item = _pendingQueue[i];
                  return InkWell(
                    onTap: () => _openPendingWithScan(item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: AppTheme.error, shape: BoxShape.circle)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                  item.material.isNotEmpty
                                      ? item.material
                                      : item.qrCode,
                                  style:
                                      Theme.of(context).textTheme.labelMedium,
                                  overflow: TextOverflow.ellipsis),
                              Text('${item.weight.toStringAsFixed(2)} kg',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: hintColor),
                                  overflow: TextOverflow.ellipsis),
                            ])),
                        const Icon(Icons.play_arrow_rounded,
                            color: AppTheme.error, size: 16),
                      ]),
                    ),
                  );
                },
              ),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: PendingService.instance.refreshDenatQueue,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Refresh'),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10)),
          ),
        ),
      ),
    ]);
  }

  // ============================================================
  // RIGHT — HISTORY
  // ============================================================
  Widget _buildHistory(bool isDark) {
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final hintColor = isDark ? AppTheme.darkTextHint : AppTheme.lightTextHint;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
        child: Row(children: [
          Text('My History', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            onPressed: _loadHistory,
            tooltip: 'Refresh history',
          ),
        ]),
      ),
      Divider(color: borderColor, height: 1),
      Expanded(
        child: _histLoading
            ? const Center(child: CircularProgressIndicator())
            : _history.isEmpty
                ? Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        Icon(Icons.history_rounded, size: 36, color: hintColor),
                        const SizedBox(height: 10),
                        Text('No records yet',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: hintColor)),
                      ]))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => Divider(
                        color: borderColor,
                        height: 1,
                        indent: 16,
                        endIndent: 16),
                    itemBuilder: (_, i) => _DenatHistoryTile(
                      denat: _history[i],
                      isDark: isDark,
                      onCorrected: _loadHistory,
                    ),
                  ),
      ),
    ]);
  }
}

// ============================================================================
// HISTORY TILE
// ============================================================================
class _DenatHistoryTile extends StatelessWidget {
  final Denaturation denat;
  final bool isDark;
  final VoidCallback? onCorrected;

  const _DenatHistoryTile(
      {required this.denat, required this.isDark, this.onCorrected});

  @override
  Widget build(BuildContext context) {
    final color = denat.isCompleted ? AppTheme.success : AppTheme.warning;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.science_rounded, color: color, size: 16),
      ),
      title: Text(
        denat.weightNetAfter != null
            ? '${denat.weightNetAfter!.toStringAsFixed(3)} kg'
            : '${denat.weightBefore.toStringAsFixed(3)} kg',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      subtitle: Text(
        denat.material.isNotEmpty ? denat.material : denat.qrCode,
        style: Theme.of(context).textTheme.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: StatusBadge(status: denat.status),
      onTap: () async {
        final corrected = await showDialog<bool>(
          context: context,
          builder: (_) => _DenatDetailDialog(denat: denat),
        );
        if (corrected == true) onCorrected?.call();
      },
    );
  }
}

// ============================================================================
// DETAIL + CORRECTION DIALOG
// ============================================================================
class _DenatDetailDialog extends StatefulWidget {
  final Denaturation denat;
  const _DenatDetailDialog({required this.denat});

  @override
  State<_DenatDetailDialog> createState() => _DenatDetailDialogState();
}

class _DenatDetailDialogState extends State<_DenatDetailDialog> {
  // ── scale ─────────────────────────────────────────────────────────────
  late final ScaleService _scale;
  StreamSubscription? _scaleSub;
  double _lastScaleValue = 0.0;
  bool _isStable = false;
  DateTime? _lastScaleUpdate;
  String _scaleStatus = 'Waiting for scale…';

  // ── captured weights ───────────────────────────────────────────────────
  double _capturedNet = 0.0;
  double _capturedBrut = 0.0;
  bool _netCaptured = false;
  bool _brutCaptured = false;

  final _reasonCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scale = ScaleService(
        portName: AppConfig.scalePort, baudRate: AppConfig.scaleBaud);
    _startScale();
  }

  @override
  void dispose() {
    _scaleSub?.cancel();
    _reasonCtrl.dispose();
    super.dispose();
  }

  void _startScale() {
    _scaleSub = _scale.continuousStream.listen(
      (event) {
        final now = DateTime.now();
        if (_lastScaleUpdate != null &&
            now.difference(_lastScaleUpdate!).inMilliseconds < 150) return;
        _lastScaleUpdate = now;
        final kg = _scaleRawToKg(event.weight);
        final newVal = double.parse(kg.toStringAsFixed(3));
        final stable = event.isStable;
        if (newVal == _lastScaleValue && stable == _isStable) return;
        setState(() {
          _lastScaleValue = newVal;
          _isStable = stable;
        });
      },
      onError: (_) => setState(() => _isStable = false),
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

  Future<void> _submitCorrection() async {
    if (!_brutCaptured) {
      _snack('Please capture brut from the scale', isError: true);
      return;
    }
    if (!_netCaptured) {
      _snack('Please capture net from the scale', isError: true);
      return;
    }
    if (_capturedBrut <= 0 || _capturedNet <= 0) {
      _snack('Both weights must be positive', isError: true);
      return;
    }

    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      _snack('Reason is required', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final code = await DenaturationService.instance.correct(
        denatId: widget.denat.id,
        newNet: double.parse(_capturedNet.toStringAsFixed(3)),
        newBrut: double.parse(_capturedBrut.toStringAsFixed(3)),
        reason: reason,
      );
      if (!mounted) return;
      if (code == 0) {
        _snack('Correction submitted', isError: false);
        Navigator.of(context).pop(true);
      } else {
        _snack('Correction failed (code $code)', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg, {required bool isError}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: isError ? AppTheme.error : AppTheme.success));

  String _fmt(double v) => v.toStringAsFixed(3);

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 130,
              child: Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey))),
          Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(fontSize: 13))),
        ]),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(title,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey,
                letterSpacing: 0.8)),
      );

  @override
  Widget build(BuildContext context) {
    final d = widget.denat;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 16, 16),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('#${d.id}',
              style: const TextStyle(
                  color: AppTheme.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ),
        const SizedBox(width: 10),
        const Expanded(
            child: Text('Denaturation detail', style: TextStyle(fontSize: 16))),
        _StatusChip(
          status: d.status,
          color: d.isCompleted ? AppTheme.success : AppTheme.warning,
        ),
      ]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _section('OPERATION INFO'),
                Card(
                  elevation: 0,
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceVariant
                      .withOpacity(0.35),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      _row('Denat ID', d.id.toString()),
                      _row('Material', d.material),
                      _row('QR Code', d.qrCode),
                      _row('Status', d.status),
                      _row('Created', d.createdAt),
                      _row('Completed', d.completedAt ?? 'Not yet'),
                      _row('Note', d.note ?? '—'),
                    ]),
                  ),
                ),

                _section('MASS BALANCE'),
                Card(
                  elevation: 0,
                  color: AppTheme.error.withOpacity(0.04),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: AppTheme.error.withOpacity(0.2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Expanded(
                          child: _WeightMini(
                              label: 'Before',
                              value: d.weightBefore,
                              color: AppTheme.warning)),
                      const SizedBox(width: 16),
                      Expanded(
                          child: _WeightMini(
                              label: 'Net After',
                              value: d.weightNetAfter ?? 0.0,
                              color: AppTheme.success)),
                      const SizedBox(width: 16),
                      Expanded(
                          child: _WeightMini(
                              label: 'Brut After',
                              value: d.weightBrutAfter ?? 0.0,
                              color: AppTheme.primaryBlue)),
                    ]),
                  ),
                ),

                // ── CORRECTION ──────────────────────────────────────────────────
                _section('CORRECTION'),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: AppTheme.warning.withOpacity(0.25)),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.edit_note_rounded,
                              color: AppTheme.warning, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                            'Correction is logged in the audit trail.',
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.warning),
                          )),
                        ]),
                        const SizedBox(height: 12),

                        // Live scale display
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isStable
                                ? AppTheme.success.withOpacity(0.08)
                                : Colors.grey.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('SCALE',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.8)),
                                const SizedBox(height: 4),
                                Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                          child: Text(
                                              '${_fmt(_lastScaleValue)} kg',
                                              style: TextStyle(
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w700,
                                                  color: _isStable
                                                      ? AppTheme.success
                                                      : AppTheme.primaryBlue))),
                                      Text(_isStable ? 'Stable' : '',
                                          style: TextStyle(
                                              color: _isStable
                                                  ? AppTheme.success
                                                  : AppTheme.warning,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12)),
                                    ]),
                                const SizedBox(height: 4),
                                Text('Status: $_scaleStatus',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                                const SizedBox(height: 8),
                                Row(children: [
                                  Expanded(
                                      child: ElevatedButton.icon(
                                          onPressed: _busy ? null : _readScale,
                                          icon: const Icon(Icons.repeat,
                                              size: 14),
                                          label: const Text('Read now',
                                              style: TextStyle(fontSize: 12)),
                                          style: ElevatedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 8)))),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () {
                                            _scaleSub?.cancel();
                                            _startScale();
                                            setState(() =>
                                                _scaleStatus = 'Reconnecting…');
                                          },
                                    style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8, horizontal: 12)),
                                    child: const Text('Reconnect',
                                        style: TextStyle(fontSize: 12)),
                                  ),
                                ]),
                              ]),
                        ),

                        const SizedBox(height: 10),

                        // Capture buttons
                        Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy || _lastScaleValue <= 0
                                  ? null
                                  : () => setState(() {
                                        _capturedBrut = _lastScaleValue;
                                        _brutCaptured = true;
                                        _scaleStatus =
                                            'Brut set: ${_fmt(_capturedBrut)} kg';
                                      }),
                              child: Text(
                                  _brutCaptured
                                      ? 'Brut ✓  ${_fmt(_capturedBrut)} kg'
                                      : 'Set brut',
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy || _lastScaleValue <= 0
                                  ? null
                                  : () => setState(() {
                                        _capturedNet = _lastScaleValue;
                                        _netCaptured = true;
                                        _scaleStatus =
                                            'Net set: ${_fmt(_capturedNet)} kg';
                                      }),
                              child: Text(
                                  _netCaptured
                                      ? 'Net ✓  ${_fmt(_capturedNet)} kg'
                                      : 'Set net',
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                        ]),

                        const SizedBox(height: 10),
                        TextField(
                          controller: _reasonCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                              labelText: 'Reason (mandatory)', isDense: true),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _submitCorrection,
                            icon: _busy
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.save_rounded, size: 16),
                            label: const Text('SUBMIT CORRECTION'),
                            style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.warning),
                          ),
                        ),
                      ]),
                ),
                const SizedBox(height: 4),
              ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ============================================================================
// DENAT PENDING VERIFY DIALOG — In-dialog scan verification
// ============================================================================

class _DenatPendingVerifyDialog extends StatefulWidget {
  final PendingItem item;
  final VoidCallback onConfirmed;

  const _DenatPendingVerifyDialog(
      {required this.item, required this.onConfirmed});

  @override
  State<_DenatPendingVerifyDialog> createState() =>
      _DenatPendingVerifyDialogState();
}

class _DenatPendingVerifyDialogState extends State<_DenatPendingVerifyDialog> {
  StreamSubscription<String>? _scanSub;
  bool _verified = false;
  String _scanError = '';
  final _manualCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scanSub = WasteEngine.instance.scanner.denatScans.listen(_onScan);
  }

  void _onScan(String scanned) {
    final expected = widget.item.qrCode;
    if (scanned.trim() == expected.trim()) {
      setState(() {
        _verified = true;
        _scanError = '';
      });
    } else {
      setState(() {
        _verified = false;
        _scanError = 'Wrong bag\nScanned:  $scanned\nExpected: $expected';
      });
    }
  }

  void _verifyManual() {
    final input = _manualCtrl.text.trim();
    final expected = widget.item.qrCode;
    if (input == expected) {
      setState(() {
        _verified = true;
        _scanError = '';
      });
    } else {
      setState(() {
        _verified = false;
        _scanError = 'Wrong bag\nEntered:  $input\nExpected: $expected';
      });
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _manualCtrl.dispose();
    super.dispose();
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey))),
          Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(fontSize: 13))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 16, 16),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('#${item.id}',
              style: const TextStyle(
                  color: AppTheme.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ),
        const SizedBox(width: 10),
        const Expanded(
            child:
                Text('Pending Denaturation', style: TextStyle(fontSize: 16))),
      ]),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _row(
                    'Material', item.material.isNotEmpty ? item.material : '—'),
                _row('Product', item.product.isNotEmpty ? item.product : '—'),
                _row('Lot', item.lot.isNotEmpty ? item.lot : 'N/A'),
                _row('Zone', item.zone ?? 'N/A'),
                _row('Initial net', '${item.weight.toStringAsFixed(3)} kg'),
                if (item.originalGross > 0)
                  _row('Reco variance',
                      '${item.originalGross.toStringAsFixed(3)} kg'),
                const Divider(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _verified
                        ? AppTheme.success.withOpacity(0.08)
                        : AppTheme.error.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _verified
                          ? AppTheme.success.withOpacity(0.3)
                          : AppTheme.error.withOpacity(0.15),
                    ),
                  ),
                  child: _verified
                      ? const Row(children: [
                          Icon(Icons.check_circle,
                              color: AppTheme.success, size: 18),
                          SizedBox(width: 10),
                          Text('Bag confirmed — ready to denature',
                              style: TextStyle(color: AppTheme.success)),
                        ])
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.qr_code_scanner,
                                  color: AppTheme.error, size: 18),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Scan the physical bag to confirm it matches this denaturation record.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(
                                child: TextField(
                                  controller: _manualCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Or enter UUID manually',
                                    hintText: 'e.g. a1b2c3d4-...',
                                    isDense: true,
                                    prefixIcon: const Icon(
                                        Icons.keyboard_outlined,
                                        size: 16),
                                  ),
                                  onSubmitted: (_) => _verifyManual(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () {
                                  _verifyManual();
                                  _manualCtrl.clear();
                                },
                                child: const Text('Verify'),
                              ),
                            ]),
                          ],
                        ),
                ),
                if (_scanError.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: AppTheme.error.withOpacity(0.3)),
                    ),
                    child: Text(_scanError,
                        style: const TextStyle(
                            color: AppTheme.error, fontSize: 12)),
                  ),
                ],
              ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        if (!_verified)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.qr_code_scanner,
                  size: 16, color: AppTheme.error),
              const SizedBox(width: 6),
              Text('Scan to unlock',
                  style: TextStyle(color: AppTheme.error, fontSize: 12)),
            ]),
          ),
        if (_scanError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: const Text('⚠ Wrong bag',
                style: TextStyle(color: AppTheme.error, fontSize: 12)),
          ),
        FilledButton.icon(
          onPressed: _verified
              ? () {
                  Navigator.of(context).pop(true);
                  widget.onConfirmed();
                }
              : null,
          icon: Icon(_verified ? Icons.science_rounded : Icons.lock_outline,
              size: 18),
          label: Text(_verified ? 'Start Denaturation' : 'Scan to unlock'),
          style: FilledButton.styleFrom(
            backgroundColor: _verified ? AppTheme.error : Colors.grey,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// SHARED SMALL WIDGETS
// ============================================================================

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey))),
          Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(fontSize: 13))),
        ]),
      );
}

class _WeightMini extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _WeightMini(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(value.toStringAsFixed(3),
            style: TextStyle(
                color: color, fontSize: 22, fontWeight: FontWeight.w700)),
        Text('kg',
            style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
      ]);
}

class _StatusChip extends StatelessWidget {
  final String status;
  final Color color;
  const _StatusChip({required this.status, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(status.toUpperCase(),
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
        ]),
      );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final bool isDark;
  final Color color;
  const _InfoCard(
      {required this.icon,
      required this.title,
      required this.message,
      required this.isDark,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Row(children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodySmall),
              ])),
        ]),
      );
}

class _SuccessBanner extends StatelessWidget {
  final String message;
  const _SuccessBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.success.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.success.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle_outline,
              color: AppTheme.success, size: 18),
          const SizedBox(width: 10),
          Text(message,
              style: const TextStyle(color: AppTheme.success, fontSize: 13)),
        ]),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String error;
  const _ErrorBanner({required this.error});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.error.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: AppTheme.error, size: 16),
          const SizedBox(width: 10),
          Expanded(
              child: Text(error,
                  style: const TextStyle(color: AppTheme.error, fontSize: 13))),
        ]),
      );
}

class _WaitingIndicator extends StatefulWidget {
  final bool isDark;
  const _WaitingIndicator({required this.isDark});

  @override
  State<_WaitingIndicator> createState() => _WaitingIndicatorState();
}

class _WaitingIndicatorState extends State<_WaitingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 1.0)
            .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: AppTheme.error, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Text('Waiting for incoming scan…',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.error)),
        ]),
      );
}
