import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';

// Services
import 'package:waste_tracking/ffi/services/reconciliation_service.dart';
import 'package:waste_tracking/ffi/services/scanner_service.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';
import 'package:waste_tracking/ffi/services/scale_service.dart';
import 'package:waste_tracking/ffi/services/pending_service.dart';

// Models & Engine
import 'package:waste_tracking/ffi/models/reconciliation.dart';
import 'package:waste_tracking/ffi/models/pending_reco.dart';
import 'package:waste_tracking/ffi/engine.dart';

// UI
import 'package:waste_tracking/ffi/widgets/scan_indicator.dart';

// Config & Theme
import 'package:waste_tracking/config/app_config.dart';
import 'package:waste_tracking/theme/app_theme.dart';

// ============================================================================
// RECO SCREEN — 3-column layout
//
//  ┌─────────────────┬────────────────────────┬────────────────┐
//  │  Pending Queue  │   Workflow (phases)     │  My History    │
//  │  (left, 260px)  │   (middle, flex)        │  (right, 280px)│
//  └─────────────────┴────────────────────────┴────────────────┘
//
//  QR arrives via socket (ScannerService.recoScans) automatically.
//  Validator can also type a UUID manually in the waiting phase.
//  No station QR code displayed here — that belongs on the mobile bridge.
// ============================================================================

enum RecoPhase {
  waiting, // Waiting for QR — manual entry available
  reviewing, // Weighing found — showing original weight
  weighingTare, // Capturing tare
  weighingGross, // Capturing gross
  confirming, // Showing diff — accept / reject
  done, // Result shown — auto resets after 4s
}

class RecoScreen extends StatefulWidget {
  const RecoScreen({super.key});

  @override
  State<RecoScreen> createState() => _RecoScreenState();
}

class _RecoScreenState extends State<RecoScreen> {
  // ── Phase ──────────────────────────────────────────────────────────────
  RecoPhase _phase = RecoPhase.waiting;

  // ── Scanner ────────────────────────────────────────────────────────────
  StreamSubscription? _scanSub;

  // ── Scan result ────────────────────────────────────────────────────────
  double _originalWeight = 0.0;

  // ── Scale ──────────────────────────────────────────────────────────────
  ScaleService? _scale;
  StreamSubscription? _liveSub;
  StreamSubscription? _stableSub;
  double _liveWeight = 0.0;
  double _capturedTare = 0.0;
  double _capturedGross = 0.0;
  bool _isStable = false;

  // ── Result ─────────────────────────────────────────────────────────────
  RecoResult? _recoResult;
  bool _submitting = false;
  String _error = '';
  bool _lastAccepted = false;

  // ── Pending queue (left panel) ──────────────────────────────────────────
  List<PendingItem> _pendingQueue = [];
  StreamSubscription? _pendingSub;

  // ── History (right panel) ──────────────────────────────────────────────
  List<Reconciliation> _history = [];
  bool _histLoading = false;
  String _histFilter = 'all';

  // ── Controllers ────────────────────────────────────────────────────────
  final _rejectCtrl = TextEditingController();
  final _manualQrCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    // FIX: Always clear any stale reconciliation state when screen loads
    ReconciliationService.instance.cancel();

    _startScanListener();
    _startPendingListener();
    _initScale();
    // Delay history load slightly to ensure session is fully propagated
    Future.delayed(const Duration(milliseconds: 100), _loadHistory);
  }

  // ── Scan listener ──────────────────────────────────────────────────────
  void _startScanListener() {
    _scanSub =
        ScannerService.instance.recoScans.listen((qr) => _onScanReceived(qr));
  }

  // ── Pending queue listener ─────────────────────────────────────────────
  void _startPendingListener() {
    _pendingSub = PendingService.instance.recoQueue.listen((items) {
      if (mounted) setState(() => _pendingQueue = items);
    });
    // Trigger initial load
    PendingService.instance.refreshRecoQueue();
  }

  // ── On QR received (socket OR manual) ─────────────────────────────────
  Future<void> _onScanReceived(String raw, {PendingItem? item}) async {
    if (_phase != RecoPhase.waiting) return;

    // Extract QR string — may arrive as raw UUID or JSON envelope
    String qr = raw.trim();
    try {
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) {
        qr = data['qr_code_data'] as String? ?? data['uuid'] as String? ?? qr;
      }
    } catch (_) {
      // Not JSON — treat as raw QR string
    }

    if (qr.isEmpty) return;

    setState(() {
      _phase = RecoPhase.reviewing;
      _error = '';
    });

    try {
      if (item != null) {
        ReconciliationService.instance.setCurrentFromPending(item);
      } else {
        final started = await ReconciliationService.instance.start(qr);
        if (!started) {
          _setError('QR not found or already processed');
          _resetToWaiting();
          return;
        }
      }
    } catch (e) {
      _setError('Error resolving QR: $e');
      _resetToWaiting();
      return;
    }

    final current = ReconciliationService.instance.current;
    if (mounted) {
      setState(() {
        _originalWeight = current?.originalWeight ?? 0.0;
        _phase = RecoPhase.reviewing;
      });
    }
  }

  // ── Scale ──────────────────────────────────────────────────────────────
  void _initScale() {
    _scale = ScaleService(
      portName: AppConfig.scalePort,
      baudRate: AppConfig.scaleBaud,
      stableRepeats: 5,
    );
  }

  void _startWeighing() {
    setState(() {
      _phase = RecoPhase.weighingTare;
      _liveWeight = 0.0;
      _capturedTare = 0.0;
      _capturedGross = 0.0;
      _isStable = false;
      _error = '';
    });

    _liveSub = _scale!.liveStream.listen((w) {
      if (mounted) setState(() => _liveWeight = w);
    });

    _stableSub = _scale!.stableStream.listen((w) {
      if (mounted && !_submitting) {
        setState(() {
          _isStable = true;
          _liveWeight = w;
        });
      }
    });
  }

  void _stopScale() {
    _liveSub?.cancel();
    _stableSub?.cancel();
    _scale?.stop();
  }

  // ── Capture steps ──────────────────────────────────────────────────────
  void _captureTare() {
    if (!_isStable) {
      _setError('Wait for stable reading');
      return;
    }
    setState(() {
      _capturedTare = _liveWeight;
      _phase = RecoPhase.weighingGross;
      _isStable = false;
      _error = '';
    });
  }

  void _captureGross() {
    if (!_isStable) {
      _setError('Wait for stable reading');
      return;
    }
    setState(() => _capturedGross = _liveWeight);
    _completeWeighing();
  }

  // ── Complete weighing → submit ─────────────────────────────────────────
  Future<void> _completeWeighing() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    _stopScale();

    try {
      // Problem 1 fix: send actual captured gross and tare
      final result = await ReconciliationService.instance.complete(
        gross: _capturedGross,
        tare: _capturedTare,
      );
      if (result == null) {
        _setError('Failed to submit reconciliation');
        _resetToWaiting();
        return;
      }
      if (mounted)
        setState(() {
          _recoResult = result;
          _phase = RecoPhase.confirming;
        });
    } catch (e) {
      _setError('Error: $e');
      _resetToWaiting();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Accept ─────────────────────────────────────────────────────────────
  Future<void> _accept() async {
    final recoId = _recoResult?.reconciliationId ?? -1;
    if (recoId < 0) {
      _setError('Invalid reconciliation ID');
      return;
    }

    setState(() => _submitting = true);
    try {
      final code = await ReconciliationService.instance.accept(recoId);
      if (code == 0) {
        ReconciliationService.instance
            .cancel(); // FIX: clear immediately, don't wait 4s
        setState(() {
          _lastAccepted = true;
          _phase = RecoPhase.done;
        });
        _loadHistory();
        PendingService.instance.refreshRecoQueue();
        _scheduleReset();
      } else {
        _setError('Accept failed — code $code');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Reject ─────────────────────────────────────────────────────────────
  Future<void> _showRejectDialog() async {
    _rejectCtrl.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Reconciliation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Provide a reason for rejection:'),
            const SizedBox(height: 12),
            TextField(
              controller: _rejectCtrl,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Enter reason...'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final reason = _rejectCtrl.text.trim();
    if (reason.isEmpty) {
      _setError('Rejection reason is required');
      return;
    }
    await _reject(reason);
  }

  Future<void> _reject(String reason) async {
    final recoId = _recoResult?.reconciliationId ?? -1;
    if (recoId < 0) return;

    setState(() => _submitting = true);
    try {
      final code = await ReconciliationService.instance.reject(recoId, reason);
      if (code == 0) {
        ReconciliationService.instance.cancel(); // FIX: clear immediately
        setState(() {
          _lastAccepted = false;
          _phase = RecoPhase.done;
        });
        _loadHistory();
        PendingService.instance.refreshRecoQueue();
        _scheduleReset();
      } else {
        _setError('Reject failed — code $code');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Reset ──────────────────────────────────────────────────────────────
  void _scheduleReset() => Future.delayed(const Duration(seconds: 4), () {
        if (mounted) _resetToWaiting();
      });

  void _resetToWaiting() {
    ReconciliationService.instance.cancel();
    _stopScale();
    if (mounted) {
      setState(() {
        _phase = RecoPhase.waiting;
        _originalWeight = 0.0;
        _liveWeight = 0.0;
        _capturedGross = 0.0;
        _capturedTare = 0.0;
        _isStable = false;
        _recoResult = null;
        _submitting = false;
        _error = '';
      });
    }
  }

  void _setError(String msg) => setState(() => _error = msg);

  // ── History ────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    setState(() => _histLoading = true);
    try {
      final all = await ReconciliationService.instance.list(
        status: _histFilter == 'all' ? null : _histFilter,
        limit: 50,
      );
      if (mounted) setState(() => _history = all);
    } finally {
      if (mounted) setState(() => _histLoading = false);
    }
  }

  // ── Open pending item detail popup ────────────────────────────────────
  Future<void> _openPendingDetail(PendingItem item) async {
    final startReco = await showDialog<bool>(
      context: context,
      builder: (_) => _PendingItemDetailDialog(item: item),
    );
    // "Start Reconciliation" button in dialog returns true
    if (startReco == true && mounted && _phase == RecoPhase.waiting) {
      _onScanReceived(item.qrCode, item: item);
    }
  }

  @override
  void dispose() {
    ReconciliationService.instance.cancel(); // FIX: add this
    _scanSub?.cancel();
    _pendingSub?.cancel();
    _stopScale();
    _rejectCtrl.dispose();
    _manualQrCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── LEFT: pending queue ─────────────────
          SizedBox(
            width: 260,
            child: _buildPendingQueue(isDark),
          ),

          Container(width: 1, color: dividerColor),

          // ── MIDDLE: workflow ────────────────────
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
                    child: SectionHeader(
                      title: 'Reconciliation',
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
              ],
            ),
          ),

          Container(width: 1, color: dividerColor),

          // ── RIGHT: history ──────────────────────
          SizedBox(
            width: 280,
            child: _buildHistory(isDark),
          ),
        ],
      ),
    );
  }

  String _phaseSubtitle() {
    switch (_phase) {
      case RecoPhase.waiting:
        return 'Scan the bag or select from the pending queue';
      case RecoPhase.reviewing:
        return 'Verify original weight and start weigh steps';
      case RecoPhase.weighingTare:
        return 'STEP 1: Capture empty container (Tare)';
      case RecoPhase.weighingGross:
        return 'STEP 2: Capture full container (Gross)';
      case RecoPhase.confirming:
        return 'Review difference then approve or reject';
      case RecoPhase.done:
        return 'Operation complete — resetting…';
    }
  }

  // ── Phase router ───────────────────────────────────────────────────────
  Widget _buildPhase(bool isDark) {
    switch (_phase) {
      case RecoPhase.waiting:
        return _buildWaiting(isDark);
      case RecoPhase.reviewing:
        return _buildReviewing(isDark);
      case RecoPhase.weighingTare:
      case RecoPhase.weighingGross:
        return _buildWeighingSteps(isDark);
      case RecoPhase.confirming:
        return _buildConfirming(isDark);
      case RecoPhase.done:
        return _buildDone(isDark);
    }
  }

  // ============================================================
  // PHASE 1 — WAITING
  // ============================================================
  Widget _buildWaiting(bool isDark) {
    return Column(
      children: [
        const SizedBox(height: 16),

        // Info card
        _InfoCard(
          icon: Icons.sensors_rounded,
          title: 'Ready for scan',
          message:
              'Scan the QR or barcode on the bag with the hardware scanner, '
              'or enter the UUID manually below.',
          isDark: isDark,
        ),

        const SizedBox(height: 28),

        // Manual entry
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _manualQrCtrl,
                decoration: InputDecoration(
                  labelText: 'Enter UUID manually',
                  hintText: 'e.g. a1b2c3d4-...',
                  prefixIcon: const Icon(Icons.keyboard_outlined, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    _onScanReceived(val.trim());
                    _manualQrCtrl.clear();
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () {
                final val = _manualQrCtrl.text.trim();
                if (val.isNotEmpty) {
                  _onScanReceived(val);
                  _manualQrCtrl.clear();
                }
              },
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Look up'),
            ),
          ],
        ),

        const SizedBox(height: 32),

        // Pulsing waiting indicator
        const ScanIndicator(message: 'Waiting for scan...'),

        if (_error.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ErrorBanner(error: _error),
        ],
      ],
    );
  }

  // ============================================================
  // PHASE 2 — REVIEWING
  // ============================================================
  Widget _buildReviewing(bool isDark) {
    final current = ReconciliationService.instance.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),

        _SuccessBanner(message: 'QR resolved — weighing record found'),

        const SizedBox(height: 20),

        // Item info
        if (current != null) _ItemInfoCard(reco: current, isDark: isDark),

        const SizedBox(height: 20),

        // Original weight
        _WeightCard(
          label: 'Original Net Weight',
          weight: _originalWeight,
          color: AppTheme.primaryBluee,
          isDark: isDark,
        ),

        const SizedBox(height: 28),

        _InfoCard(
          icon: Icons.scale_outlined,
          title: 'Place item on scale',
          message: 'Put the container on the scale, then press Start Weighing.',
          isDark: isDark,
        ),

        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _startWeighing,
                icon: const Icon(Icons.scale, size: 18),
                label: const Text('START WEIGHING'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryBluee,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () {
                ReconciliationService.instance.cancel(); // FIX: add this
                _resetToWaiting();
              },
              child: const Text('Cancel'),
            ),
          ],
        ),

        if (_error.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ErrorBanner(error: _error),
        ],
      ],
    );
  }

  // ============================================================
  // PHASE 3 — WEIGHING STEPS
  // ============================================================
  Widget _buildWeighingSteps(bool isDark) {
    final isTare = _phase == RecoPhase.weighingTare;

    return Column(
      children: [
        const SizedBox(height: 16),
        _InfoCard(
          icon: isTare ? Icons.shopping_basket_outlined : Icons.scale_outlined,
          title: isTare ? 'Step 1: Capture Tare' : 'Step 2: Capture Gross',
          message: isTare
              ? 'Place the EMPTY container on the scale, wait for stable, then capture.'
              : 'Place the FULL container on the scale, wait for stable, then capture.',
          isDark: isDark,
        ),
        const SizedBox(height: 24),
        if (isTare && _capturedTare == 0.0)
          const SizedBox.shrink()
        else if (!isTare)
          _WeightCard(
            label: 'Captured Tare',
            weight: _capturedTare,
            color: AppTheme.primaryBluee,
            isDark: isDark,
            compact: true,
          ),
        const SizedBox(height: 16),
        _ScaleDisplay(
          liveWeight: _liveWeight,
          isStable: _isStable,
          submitting: _submitting,
          isDark: isDark,
        ),
        const SizedBox(height: 32),
        if (!_submitting) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  _isStable ? (isTare ? _captureTare : _captureGross) : null,
              icon: Icon(isTare
                  ? Icons.subdirectory_arrow_right
                  : Icons.check_circle_outline),
              label: Text(isTare ? 'CAPTURE TARE' : 'CAPTURE GROSS & SUBMIT'),
              style: FilledButton.styleFrom(
                backgroundColor:
                    _isStable ? AppTheme.primaryBluee : Colors.grey.shade400,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () {
              _stopScale();
              if (isTare) {
                setState(() => _phase = RecoPhase.reviewing);
              } else {
                setState(() {
                  _capturedTare = 0.0;
                  _phase = RecoPhase.weighingTare;
                });
                _startWeighing();
              }
            },
            icon: const Icon(Icons.arrow_back),
            label: Text(isTare ? 'Back to Review' : 'Re-capture Tare'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
          ),
        ],
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ErrorBanner(error: _error),
        ],
      ],
    );
  }

  // ============================================================
  // PHASE 4 — CONFIRMING
  // ============================================================
  Widget _buildConfirming(bool isDark) {
    if (_recoResult == null) return const SizedBox.shrink();

    final result = _recoResult!;
    final orig = result.originalWeight;
    final newW = result.newWeight;
    final diff = result.difference;
    final diffAbs = diff.abs();
    final diffPct = orig > 0 ? (diffAbs / orig * 100) : 0.0;
    final diffColor = diffAbs < 0.01
        ? AppTheme.success
        : diffPct > 5.0
            ? AppTheme.error
            : AppTheme.warning;

    return Column(
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _WeightCard(
                label: 'Original',
                weight: orig,
                color: AppTheme.primaryBluee,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _WeightCard(
                label: 'New Weight',
                weight: newW,
                color: AppTheme.success,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _DiffCard(
          diff: diff,
          diffAbs: diffAbs,
          diffPct: diffPct,
          diffColor: diffColor,
          isDark: isDark,
        ),
        const SizedBox(height: 28),
        _submitting
            ? const CircularProgressIndicator()
            : Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showRejectDialog,
                      icon: const Icon(Icons.close,
                          size: 18, color: AppTheme.error),
                      label: const Text('REJECT',
                          style: TextStyle(color: AppTheme.error)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _accept,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('APPROVE'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ErrorBanner(error: _error),
        ],
      ],
    );
  }

  // ============================================================
  // PHASE 5 — DONE
  // ============================================================
  Widget _buildDone(bool isDark) {
    final color = _lastAccepted ? AppTheme.success : AppTheme.error;
    final icon = _lastAccepted ? Icons.check_circle : Icons.cancel;
    final label =
        _lastAccepted ? 'Reconciliation Approved' : 'Reconciliation Rejected';

    return Column(
      children: [
        const SizedBox(height: 60),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.3), width: 2),
          ),
          child: Icon(icon, color: color, size: 36),
        ),
        const SizedBox(height: 24),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: color)),
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
              color: color,
              backgroundColor: color.withOpacity(0.1),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // LEFT — PENDING QUEUE
  // ============================================================
  Widget _buildPendingQueue(bool isDark) {
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final hintColor = isDark ? AppTheme.darkTextHint : AppTheme.lightTextHint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
          child: Row(
            children: [
              const Icon(Icons.inbox_rounded,
                  color: AppTheme.primaryBluee, size: 18),
              const SizedBox(width: 8),
              Text('Pending Queue',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              // Count badge
              if (_pendingQueue.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBluee,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_pendingQueue.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
        Divider(color: borderColor, height: 1),

        // List
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
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: _pendingQueue.length,
                  separatorBuilder: (_, __) => Divider(
                      color: borderColor, height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (_, i) => _PendingQueueTile(
                    item: _pendingQueue[i],
                    isDark: isDark,
                    isActive: _phase != RecoPhase.waiting
                        ? ReconciliationService.instance.current?.id ==
                            _pendingQueue[i].id
                        : false,
                    // Always opens the detail card.
                    // The card's "Start" button fires _onScanReceived.
                    onTap: () => _openPendingDetail(_pendingQueue[i]),
                  ),
                ),
        ),

        // Refresh button
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: PendingService.instance.refreshRecoQueue,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10)),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // RIGHT — HISTORY
  // ============================================================
  Widget _buildHistory(bool isDark) {
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final hintColor = isDark ? AppTheme.darkTextHint : AppTheme.lightTextHint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
          child: Row(
            children: [
              Text('My History',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              DropdownButton<String>(
                value: _histFilter,
                underline: const SizedBox(),
                isDense: true,
                style: Theme.of(context).textTheme.bodySmall,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'approved', child: Text('Approved')),
                  DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _histFilter = v);
                    _loadHistory();
                  }
                },
              ),
            ],
          ),
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
                          Icon(Icons.history_rounded,
                              size: 36, color: hintColor),
                          const SizedBox(height: 10),
                          Text('No records yet',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: hintColor)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: _history.length,
                      separatorBuilder: (_, __) => Divider(
                          color: borderColor,
                          height: 1,
                          indent: 16,
                          endIndent: 16),
                      itemBuilder: (_, i) => _RecoHistoryTile(
                        reco: _history[i],
                        isDark: isDark,
                        onCorrected: _loadHistory,
                      ),
                    ),
        ),
      ],
    );
  }
}

// ============================================================================
// PENDING QUEUE TILE
// ============================================================================

class _PendingQueueTile extends StatelessWidget {
  final PendingItem item;
  final bool isDark;
  final bool isActive;
  final VoidCallback? onTap;

  const _PendingQueueTile({
    required this.item,
    required this.isDark,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg =
        isActive ? AppTheme.primaryBluee.withOpacity(0.08) : Colors.transparent;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryBluee,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.material.isNotEmpty ? item.material : 'Unknown',
                    style: Theme.of(context).textTheme.labelMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.weight.toStringAsFixed(2)} kg'
                    '${item.lot.isNotEmpty ? ' · ${item.lot}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Tap hint
            if (onTap != null)
              const Icon(Icons.play_arrow_rounded,
                  color: AppTheme.primaryBluee, size: 16),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ITEM INFO CARD  (shown in reviewing phase)
// ============================================================================

class _ItemInfoCard extends StatelessWidget {
  final Reconciliation reco;
  final bool isDark;

  const _ItemInfoCard({required this.reco, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _InfoRow(label: 'Material', value: reco.material),
          ),
          Expanded(
            child: _InfoRow(label: 'Product', value: reco.product),
          ),
          Expanded(
            child: _InfoRow(label: 'Lot', value: reco.lot),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value.isNotEmpty ? value : '—',
          style: Theme.of(context).textTheme.bodyMedium,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ============================================================================
// WEIGHT CARD
// ============================================================================

class _WeightCard extends StatelessWidget {
  final String label;
  final double weight;
  final Color color;
  final bool isDark;
  final bool compact;

  const _WeightCard({
    required this.label,
    required this.weight,
    required this.color,
    required this.isDark,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color)),
          SizedBox(height: compact ? 4 : 8),
          Text(
            '${weight.toStringAsFixed(3)} kg',
            style: TextStyle(
              color: color,
              fontSize: compact ? 20 : 30,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DIFF CARD
// ============================================================================

class _DiffCard extends StatelessWidget {
  final double diff;
  final double diffAbs;
  final double diffPct;
  final Color diffColor;
  final bool isDark;

  const _DiffCard({
    required this.diff,
    required this.diffAbs,
    required this.diffPct,
    required this.diffColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final sign = diff >= 0 ? '+' : '−';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: diffColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: diffColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(
            diffAbs < 0.01 ? Icons.check_circle_outline : Icons.info_outline,
            color: diffColor,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Weight Difference',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  diffAbs < 0.01
                      ? 'No significant difference'
                      : 'Difference detected',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign${diffAbs.toStringAsFixed(3)} kg',
                style: TextStyle(
                    color: diffColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
              Text(
                '${diffPct.toStringAsFixed(1)}%',
                style: TextStyle(color: diffColor, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SCALE DISPLAY
// ============================================================================

class _ScaleDisplay extends StatelessWidget {
  final double liveWeight;
  final bool isStable;
  final bool submitting;
  final bool isDark;

  const _ScaleDisplay({
    required this.liveWeight,
    required this.isStable,
    required this.submitting,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final color = isStable ? AppTheme.success : AppTheme.primaryBluee;
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.3), width: 2),
          ),
          child: Icon(Icons.scale, color: color, size: 32),
        ),
        const SizedBox(height: 20),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
              color: color, fontSize: 48, fontWeight: FontWeight.w700),
          child: Text('${liveWeight.toStringAsFixed(3)} kg'),
        ),
        const SizedBox(height: 8),
        if (submitting)
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Submitting…'),
          ])
        else if (isStable)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.check_circle, color: AppTheme.success, size: 14),
            const SizedBox(width: 6),
            Text('Stable — recording',
                style: TextStyle(color: AppTheme.success)),
          ])
        else
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: AppTheme.primaryBluee)),
            const SizedBox(width: 8),
            const Text('Waiting for stable reading…'),
          ]),
      ],
    );
  }
}

// ============================================================================
// INFO CARD
// ============================================================================

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final bool isDark;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryBluee.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryBluee.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryBluee.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppTheme.primaryBluee, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// WAITING INDICATOR
// ============================================================================

class _WaitingIndicator extends StatefulWidget {
  final bool isDark;
  const _WaitingIndicator({required this.isDark});

  @override
  State<_WaitingIndicator> createState() => _WaitingIndicatorState();
}

class _WaitingIndicatorState extends State<_WaitingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: AppTheme.primaryBluee, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            'Waiting for incoming scan…',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppTheme.primaryBluee),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SUCCESS BANNER
// ============================================================================

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
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: AppTheme.success, size: 18),
            const SizedBox(width: 10),
            Text(message,
                style: const TextStyle(color: AppTheme.success, fontSize: 13)),
          ],
        ),
      );
}

// ============================================================================
// ERROR BANNER
// ============================================================================

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
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(error,
                  style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
          ],
        ),
      );
}

// ============================================================================
// RECO HISTORY TILE
// ============================================================================

class _RecoHistoryTile extends StatelessWidget {
  final Reconciliation reco;
  final bool isDark;
  final VoidCallback? onCorrected;

  const _RecoHistoryTile(
      {required this.reco, required this.isDark, this.onCorrected});

  @override
  Widget build(BuildContext context) {
    final diff = reco.weightDifference;
    final diffColor = diff.abs() < 0.01 ? AppTheme.success : AppTheme.warning;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.primaryBluee.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.scale_rounded,
            color: AppTheme.primaryBluee, size: 16),
      ),
      title: Text(
        '${(reco.newWeight ?? reco.originalWeight).toStringAsFixed(3)} kg',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      subtitle: Text(
        'Δ ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(3)} kg',
        style:
            Theme.of(context).textTheme.bodySmall?.copyWith(color: diffColor),
      ),
      trailing: StatusBadge(status: reco.status),
      onTap: () async {
        final corrected = await showDialog<bool>(
          context: context,
          builder: (_) => _RecoDetailDialog(reco: reco),
        );
        if (corrected == true) onCorrected?.call();
      },
    );
  }
}

class _RecoDetailDialog extends StatefulWidget {
  final Reconciliation reco;
  const _RecoDetailDialog({required this.reco});

  @override
  State<_RecoDetailDialog> createState() => _RecoDetailDialogState();
}

class _RecoDetailDialogState extends State<_RecoDetailDialog> {
  // ── scale ─────────────────────────────────────────────────────────────
  late final ScaleService _scale;
  StreamSubscription? _scaleSub;
  double _lastScaleValue = 0.0;
  bool _isStable = false;
  DateTime? _lastScaleUpdate;
  String _scaleStatus = 'Waiting for scale…';

  // ── captured weights ───────────────────────────────────────────────────
  double _tare = 0.0;
  double _capturedGross = 0.0;
  bool _tareCaptured = false;
  bool _grossCaptured = false;

  // ── other correction fields ───────────────────────────────────────────
  final TextEditingController _reasonCtrl = TextEditingController();
  String? _selectedStatus;
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

  // ── scale stream ─────────────────────────────────────────────────────
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
      _snack('Net must be positive (gross must exceed tare)', isError: true);
      return;
    }

    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      _snack('Reason is required', isError: true);
      return;
    }

    final session = AuthService.instance.session;
    if (session == null) return;

    final grossR = double.parse(_capturedGross.toStringAsFixed(3));
    final tareR = double.parse(_tare.toStringAsFixed(3));
    final netR = double.parse(net.toStringAsFixed(3));

    final changes = <String, dynamic>{
      'id': widget.reco.id,
      'user_id': session.userId,
      'reason': reason,
      'new_weight': netR,
      'new_gross': grossR,
      'new_tare': tareR,
      if (_selectedStatus != null) 'status': _selectedStatus,
    };

    setState(() => _busy = true);
    try {
      final code = await ReconciliationService.instance
          .correct(widget.reco.id, reason, changes);
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

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ),
            Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey,
              letterSpacing: 0.8,
            )),
      );

  @override
  Widget build(BuildContext context) {
    final reco = widget.reco;
    final diff = reco.weightDifference;
    final diffAbs = diff.abs();
    final diffPct =
        reco.originalWeight > 0 ? (diffAbs / reco.originalWeight * 100) : 0.0;
    final diffColor = diffAbs < 0.01
        ? AppTheme.success
        : diffPct > 5.0
            ? AppTheme.error
            : AppTheme.warning;

    final statusColor = switch (reco.status.toLowerCase()) {
      'approved' => AppTheme.success,
      'rejected' => AppTheme.error,
      _ => AppTheme.primaryBluee,
    };

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryBluee.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('#${reco.id}',
                style: const TextStyle(
                    color: AppTheme.primaryBluee,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('Reconciliation detail',
                  style: TextStyle(fontSize: 16))),
          _StatusChip(status: reco.status, color: statusColor),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _section('IDENTIFICATION'),
              Card(
                elevation: 0,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(0.35),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    _row(context, 'Reconciliation ID', reco.id.toString()),
                    _row(context, 'Weighing ID', reco.weighingId.toString()),
                    _row(context, 'Material', reco.material),
                    _row(context, 'Product', reco.product),
                    _row(context, 'Lot', reco.lot),
                    if (reco.validatorName != null)
                      _row(context, 'Validator', reco.validatorName!),
                  ]),
                ),
              ),
              _section('WEIGHTS'),
              Card(
                elevation: 0,
                color: AppTheme.primaryBluee.withOpacity(0.04),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: AppTheme.primaryBluee.withOpacity(0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    Row(children: [
                      const SizedBox(width: 80),
                      Expanded(
                          child: Text('ORIGINAL',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.primaryBluee,
                                  fontWeight: FontWeight.w700))),
                      Expanded(
                          child: Text('VERIFIED',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.w700))),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      SizedBox(
                          width: 80,
                          child: Text('Net',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey))),
                      Expanded(
                          child: Text(
                              '${reco.originalWeight.toStringAsFixed(3)} kg',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                      Expanded(
                          child: Text(
                              '${(reco.newWeight ?? 0.0).toStringAsFixed(3)} kg',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.success))),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      SizedBox(
                          width: 80,
                          child: Text('Gross',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey))),
                      Expanded(
                          child: Text(
                              '${reco.originalGross.toStringAsFixed(3)} kg')),
                      Expanded(child: const Text('—')),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      SizedBox(
                          width: 80,
                          child: Text('Tare',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey))),
                      Expanded(
                          child: Text(
                              '${reco.originalTare.toStringAsFixed(3)} kg')),
                      Expanded(child: const Text('—')),
                    ]),
                  ]),
                ),
              ),
              _section('DIFFERENCE'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: diffColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: diffColor.withOpacity(0.25)),
                ),
                child: Row(children: [
                  Icon(
                      diffAbs < 0.01
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      color: diffColor,
                      size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(
                    diffAbs < 0.01
                        ? 'No significant difference'
                        : 'Difference detected',
                    style: TextStyle(color: diffColor, fontSize: 13),
                  )),
                  Text(
                    '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(3)} kg  '
                    '(${diffPct.toStringAsFixed(1)}%)',
                    style: TextStyle(
                        color: diffColor, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
              if (reco.status == 'rejected') ...[
                _section('REJECTION REASON'),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.error.withOpacity(0.2)),
                  ),
                  child: Text(
                    reco.rejectionReason?.isNotEmpty == true
                        ? reco.rejectionReason!
                        : 'No reason provided',
                    style: TextStyle(color: AppTheme.error, fontSize: 13),
                  ),
                ),
              ],
              _buildCorrectionSection(),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildCorrectionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('CORRECTION'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.warning.withOpacity(0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.warning.withOpacity(0.25)),
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
                  'Capture tare then gross from the scale. '
                  'All corrections are logged for audit.',
                  style: TextStyle(fontSize: 11, color: AppTheme.warning),
                )),
              ]),

              const SizedBox(height: 14),

              // ── live scale display ─────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
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
                          child: Text('${_fmt(_lastScaleValue)} kg',
                              style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  color: _isStable
                                      ? AppTheme.success
                                      : AppTheme.primaryBluee)),
                        ),
                        Text(_isStable ? 'Stable' : '',
                            style: TextStyle(
                                color: _isStable
                                    ? AppTheme.success
                                    : AppTheme.warning,
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Status: $_scaleStatus',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : _readScale,
                          icon: const Icon(Icons.repeat, size: 14),
                          label: const Text('Read now',
                              style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () {
                                _scaleSub?.cancel();
                                _startScale();
                                setState(() => _scaleStatus = 'Reconnecting…');
                              },
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12)),
                        child: const Text('Reconnect',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ]),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ── capture buttons ─────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy || _lastScaleValue <= 0
                        ? null
                        : () => setState(() {
                              _tare = _lastScaleValue;
                              _tareCaptured = true;
                              _scaleStatus = 'Tare set: ${_fmt(_tare)} kg';
                            }),
                    child: Text(
                        _tareCaptured
                            ? 'Tare ✓  ${_fmt(_tare)} kg'
                            : 'Set tare',
                        style: const TextStyle(fontSize: 12)),
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
                                  'Gross set: ${_fmt(_capturedGross)} kg';
                            }),
                    child: Text(
                        _grossCaptured
                            ? 'Gross ✓  ${_fmt(_capturedGross)} kg'
                            : 'Set gross',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ]),

              // ── net preview ───────────────────────────────────────────────
              if (_tareCaptured && _grossCaptured) ...[
                const SizedBox(height: 8),
                Text('Net: ${_fmt(_capturedGross - _tare)} kg',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
              ],

              const SizedBox(height: 12),

              // ── status override ─────────────────────────────────────
              DropdownButtonFormField<String>(
                value: _selectedStatus,
                decoration: const InputDecoration(
                    labelText: 'Override status (optional)', isDense: true),
                items: const [
                  DropdownMenuItem(
                      value: null, child: Text('— keep current —')),
                  DropdownMenuItem(value: 'pending', child: Text('pending')),
                  DropdownMenuItem(value: 'approved', child: Text('approved')),
                  DropdownMenuItem(value: 'rejected', child: Text('rejected')),
                ],
                onChanged: (v) => setState(() => _selectedStatus = v),
              ),

              const SizedBox(height: 10),

              // ── reason ────────────────────────────────────────────────
              TextField(
                controller: _reasonCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Reason for correction (mandatory)',
                    isDense: true),
              ),

              const SizedBox(height: 14),

              // ── submit ───────────────────────────────────────────────
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
                  style:
                      FilledButton.styleFrom(backgroundColor: AppTheme.warning),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// PENDING ITEM DETAIL DIALOG
//
// Opens when the validator taps any card in the pending queue.
// Shows every field returned by GET /api/reco/pending:
//   reco_id, status, original{net/gross/tare}, captured_at,
//   type(material), product, lot, qr, is_flagged, weighing_id
//
// "Start Reconciliation" pops with true → parent calls _onScanReceived.
// Button is disabled (with warning) if workflow is already running.
// ============================================================================

class _PendingItemDetailDialog extends StatefulWidget {
  final PendingItem item;

  const _PendingItemDetailDialog({required this.item});

  @override
  State<_PendingItemDetailDialog> createState() =>
      _PendingItemDetailDialogState();
}

class _PendingItemDetailDialogState extends State<_PendingItemDetailDialog> {
  StreamSubscription<String>? _scanSub;
  bool _verified = false;
  String _scanError = '';
  final _manualCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scanSub = WasteEngine.instance.scanner.recoScans.listen(_onScan);
  }

  void _onScan(String scanned) {
    final expected = widget.item.qrCode.trim();
    final input = scanned.trim();
    if (input == expected) {
      setState(() {
        _verified = true;
        _scanError = '';
      });
    } else {
      setState(() {
        _verified = false;
        _scanError = 'Wrong bag — scanned: $input\nExpected: $expected';
      });
    }
  }

  void _verifyManual() {
    final input = _manualCtrl.text.trim();
    final expected = widget.item.qrCode.trim();
    if (input == expected) {
      setState(() {
        _verified = true;
        _scanError = '';
      });
    } else {
      setState(() {
        _verified = false;
        _scanError = 'Wrong bag — entered: $input\nExpected: $expected';
      });
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _manualCtrl.dispose();
    super.dispose();
  }

  // ── Two-column label/value row (same style as WeighScreen) ─────────────
  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 128,
              child: Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? '—' : value,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );

  // ── Section label ───────────────────────────────────────────────────────
  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(title,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey,
                letterSpacing: 0.8)),
      );

  @override
  Widget build(BuildContext context) {
    // ── Status colour ────────────────────────────────────────────────────
    final statusColor = switch (widget.item.status.toLowerCase()) {
      'scanned' => AppTheme.warning,
      'approved' => AppTheme.success,
      'rejected' => AppTheme.error,
      'pending' => AppTheme.primaryBluee,
      _ => AppTheme.primaryBluee,
    };

    // Workflow busy = a reco is already loaded in the service
    final bool workflowBusy = ReconciliationService.instance.current != null;

    final net = widget.item.weight;
    final gross = widget.item.originalGross;
    final tare = widget.item.originalTare;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 16, 16),
      title: Row(
        children: [
          // Reco ID badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryBluee.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '#${widget.item.id}',
              style: const TextStyle(
                  color: AppTheme.primaryBluee,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('Pending item', style: TextStyle(fontSize: 16))),
          // Status chip
          _StatusChip(status: widget.item.status, color: statusColor),
          if (widget.item.isFlagged) ...[
            const SizedBox(width: 8),
            const Tooltip(
              message: 'Flagged for review',
              child:
                  Icon(Icons.flag_rounded, color: AppTheme.warning, size: 18),
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── IDENTIFICATION ──────────────────────────────────────────
              _section('IDENTIFICATION'),
              Card(
                elevation: 0,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(0.35),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _row('Reconciliation ID', widget.item.id.toString()),
                      if (widget.item.weighingId != null)
                        _row('Weighing ID', widget.item.weighingId.toString()),
                      _row('QR / UUID', widget.item.qrCode),
                    ],
                  ),
                ),
              ),

              // ── MATERIAL ────────────────────────────────────────────────
              _section('MATERIAL'),
              Card(
                elevation: 0,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(0.35),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _row(
                          'Type / Material',
                          widget.item.material.isNotEmpty
                              ? widget.item.material
                              : '—'),
                      _row(
                          'Product',
                          widget.item.product.isNotEmpty
                              ? widget.item.product
                              : '—'),
                      _row('Lot',
                          widget.item.lot.isNotEmpty ? widget.item.lot : '—'),
                    ],
                  ),
                ),
              ),

              // ── ORIGINAL WEIGHTS ────────────────────────────────────────
              _section('ORIGINAL WEIGHTS'),
              Card(
                elevation: 0,
                color: AppTheme.primaryBluee.withOpacity(0.04),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: AppTheme.primaryBluee.withOpacity(0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      // Weight row with visual emphasis
                      Row(
                        children: [
                          Expanded(
                            child: _WeightMini(
                                label: 'Gross',
                                value: gross,
                                color: AppTheme.primaryBluee),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _WeightMini(
                                label: 'Tare', value: tare, color: Colors.grey),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _WeightMini(
                                label: 'Net',
                                value: net,
                                color: AppTheme.success),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── METADATA ────────────────────────────────────────────────
              _section('METADATA'),
              Card(
                elevation: 0,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(0.35),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _row('Status', widget.item.status),
                      _row('Captured at', widget.item.createdAt),
                      if ((widget.item.assignedTo ?? '').isNotEmpty)
                        _row('Assigned to', widget.item.assignedTo!),
                      if ((widget.item.zone ?? '').isNotEmpty)
                        _row('Zone', widget.item.zone!),
                    ],
                  ),
                ),
              ),

              // ── BAG VERIFICATION ─────────────────────────────────────────
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _verified
                      ? AppTheme.success.withOpacity(0.08)
                      : AppTheme.primaryBluee.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _verified
                        ? AppTheme.success.withOpacity(0.3)
                        : AppTheme.primaryBluee.withOpacity(0.15),
                  ),
                ),
                child: _verified
                    ? const Row(children: [
                        Icon(Icons.check_circle,
                            color: AppTheme.success, size: 18),
                        SizedBox(width: 10),
                        Text('Bag confirmed — ready to start',
                            style: TextStyle(color: AppTheme.success)),
                      ])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.qr_code_scanner,
                                color: AppTheme.primaryBluee, size: 18),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Point the hardware scanner at the physical bag to confirm it matches this record.',
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
                    border: Border.all(color: AppTheme.error.withOpacity(0.3)),
                  ),
                  child: Text(_scanError,
                      style:
                          const TextStyle(color: AppTheme.error, fontSize: 12)),
                ),
              ],

              // ── Busy warning ─────────────────────────────────────────────
              if (workflowBusy) ...[
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppTheme.warning.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: AppTheme.warning, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'A reconciliation is already in progress. '
                          'Complete or cancel it before starting another.',
                          style:
                              TextStyle(color: AppTheme.warning, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
        if (!_verified && !workflowBusy)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.qr_code_scanner,
                  size: 16, color: AppTheme.primaryBluee),
              const SizedBox(width: 6),
              Text('Scan to unlock',
                  style: TextStyle(color: AppTheme.primaryBluee, fontSize: 12)),
            ]),
          ),
        if (_scanError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('⚠ Wrong bag',
                style: TextStyle(color: AppTheme.error, fontSize: 12)),
          ),
        FilledButton.icon(
          onPressed: (_verified && !workflowBusy)
              ? () => Navigator.of(context).pop(true)
              : null,
          icon: Icon(_verified ? Icons.check_circle : Icons.lock_outline,
              size: 18),
          label: Text(_verified ? 'Start Reconciliation' : 'Scan to unlock'),
          style: FilledButton.styleFrom(
            backgroundColor: _verified ? AppTheme.primaryBluee : Colors.grey,
          ),
        ),
      ],
    );
  }
}

// ── Small status chip ──────────────────────────────────────────────────────
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(
              status.toUpperCase(),
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5),
            ),
          ],
        ),
      );
}

// ── Small weight display used inside the detail dialog ─────────────────────
class _WeightMini extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _WeightMini(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(
            '${value.toStringAsFixed(3)}',
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Text('kg',
              style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
        ],
      );
}
