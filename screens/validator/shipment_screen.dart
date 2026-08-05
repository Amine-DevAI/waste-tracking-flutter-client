import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';

import 'package:waste_tracking/ffi/engine.dart';
import 'package:waste_tracking/ffi/services/shipment_service.dart';
import 'package:waste_tracking/ffi/services/scanner_service.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';
import 'package:waste_tracking/ffi/services/pending_service.dart';
import 'package:waste_tracking/ffi/models/shipment.dart';
import 'package:waste_tracking/ffi/models/pending_reco.dart';
import 'package:waste_tracking/ffi/widgets/scan_indicator.dart';
import 'package:waste_tracking/theme/app_theme.dart';

// ============================================================================
// SHIPMENT SCREEN — 3-column layout
//
//  ┌─────────────────┬────────────────────────┬────────────────┐
//  │  Pending Queue  │   Workflow (phases)     │  My History    │
//  │  (left, 260px)  │   (middle, flex)        │  (right, 280px)│
//  └─────────────────┴────────────────────────┴────────────────┘
// ============================================================================

enum ShipPhase { waiting, reviewing, done }

class ShipmentScreen extends StatefulWidget {
  const ShipmentScreen({super.key});

  @override
  State<ShipmentScreen> createState() => _ShipmentScreenState();
}

class _ShipmentScreenState extends State<ShipmentScreen> {
  ShipPhase _phase = ShipPhase.waiting;

  Shipment? _active;
  bool _dispatching = false;
  bool _lastDispatched = false;
  String _error = '';

  // ── Scanner ──────────────────────────────────────────────────────────────
  StreamSubscription? _scanSub;

  // ── Pending queue ────────────────────────────────────────────────────────
  List<Shipment> _pendingQueue = [];
  StreamSubscription? _pendingSub;

  // ── History ──────────────────────────────────────────────────────────────
  List<Shipment> _history = [];
  bool _histLoading = false;
  String _histFilter = 'all';

  // ── Manual entry ─────────────────────────────────────────────────────────
  final _manualCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scanSub = ScannerService.instance.shipmentScans.listen(_onScan);
    _pendingSub =
        PendingService.instance.shipQueue.listen((List<Shipment> items) {
      if (mounted) setState(() => _pendingQueue = items);
    });
    PendingService.instance.refreshShipQueue();
    Future.delayed(const Duration(milliseconds: 100), _loadHistory);
  }

  // ── QR received from hardware scanner ────────────────────────────────────
  Future<void> _onScan(String qr) async {
    if (_phase != ShipPhase.waiting) return;
    await _lookupQR(qr.trim());
  }

  Future<void> _lookupQR(String qr) async {
    if (qr.isEmpty) return;
    setState(() => _error = '');

    final ship = await ShipmentService.instance.getByQR(qr);
    if (!mounted) return;

    if (ship == null) {
      setState(() => _error = 'No pending shipment found for this QR');
      return;
    }

    setState(() {
      _active = ship;
      _phase = ShipPhase.reviewing;
    });
  }

  // ── Dispatch ─────────────────────────────────────────────────────────────
  Future<void> _dispatch() async {
    if (_active == null) return;
    setState(() => _dispatching = true);

    try {
      final result = await ShipmentService.instance.dispatch(_active!.id);
      if (!mounted) return;

      if (result) {
        setState(() {
          _lastDispatched = true;
          _phase = ShipPhase.done;
        });
        _loadHistory();
        PendingService.instance.refreshShipQueue();
        _scheduleReset();
      } else {
        setState(() => _error = 'Dispatch failed — check denaturation status');
      }
    } finally {
      if (mounted) setState(() => _dispatching = false);
    }
  }

  // ── Reset ─────────────────────────────────────────────────────────────────
  void _scheduleReset() => Future.delayed(const Duration(seconds: 4), () {
        if (mounted) _resetToWaiting();
      });

  void _resetToWaiting() {
    if (mounted)
      setState(() {
        _phase = ShipPhase.waiting;
        _active = null;
        _dispatching = false;
        _error = '';
      });
  }

  // ── History ───────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    setState(() => _histLoading = true);
    try {
      final list = await ShipmentService.instance.myList(
        status: _histFilter == 'all' ? 'all' : _histFilter,
      );
      if (mounted) setState(() => _history = list);
    } finally {
      if (mounted) setState(() => _histLoading = false);
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _pendingSub?.cancel();
    _manualCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
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
                    title: 'Shipment Dispatch',
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
      case ShipPhase.waiting:
        return 'Scan QR or barcode on the bag, or enter UUID manually';
      case ShipPhase.reviewing:
        return 'Verify batch details then confirm dispatch';
      case ShipPhase.done:
        return 'Dispatched — resetting…';
    }
  }

  Widget _buildPhase(bool isDark) {
    switch (_phase) {
      case ShipPhase.waiting:
        return _buildWaiting(isDark);
      case ShipPhase.reviewing:
        return _buildReviewing(isDark);
      case ShipPhase.done:
        return _buildDone(isDark);
    }
  }

  // ============================================================
  // PHASE 1 — WAITING
  // ============================================================
  Widget _buildWaiting(bool isDark) {
    return Column(children: [
      const SizedBox(height: 16),
      _InfoCard(
        icon: Icons.local_shipping_outlined,
        title: 'Ready for scan',
        message: 'Scan the QR or barcode on the bag with the hardware scanner, '
            'or enter the UUID manually below.',
        isDark: isDark,
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
    final s = _active!;
    final isBlocked = s.wasDenatured && s.denatStatus != 'completed';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      _SuccessBanner(message: 'Shipment found — verify before dispatching'),
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
          _DetailRow('Shipment ID', '#${s.id}'),
          _DetailRow('Material', s.material.isNotEmpty ? s.material : '—'),
          _DetailRow('Product', s.product.isNotEmpty ? s.product : 'N/A'),
          if (s.lot.isNotEmpty) _DetailRow('Lot', s.lot),
          if (s.zone.isNotEmpty) _DetailRow('Zone', s.zone),
          _DetailRow('Status', s.status),
          const Divider(height: 20),
          Row(children: [
            Expanded(
                child: _WeightMini(
                    label: 'Net', value: s.weight, color: AppTheme.success)),
          ]),
          if (s.wasDenatured) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.science_outlined,
                  color: s.denatStatus == 'completed'
                      ? AppTheme.success
                      : AppTheme.error,
                  size: 16),
              const SizedBox(width: 8),
              Text(
                'Denaturation: ${s.denatStatus}',
                style: TextStyle(
                  color: s.denatStatus == 'completed'
                      ? AppTheme.success
                      : AppTheme.error,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ]),
          ],
        ]),
      ),

      const SizedBox(height: 24),

      // Denaturation block banner
      if (isBlocked) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.error.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.error.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.block_rounded, color: AppTheme.error),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'DISPATCH BLOCKED — Batch requires chemical denaturation '
                'that is not yet completed.',
                style: TextStyle(
                    color: AppTheme.error, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
      ],

      Row(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: (isBlocked || _dispatching) ? null : _dispatch,
            icon: _dispatching
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.local_shipping_rounded, size: 18),
            label: const Text('CONFIRM DISPATCH'),
            style: FilledButton.styleFrom(
              backgroundColor: isBlocked ? Colors.grey : AppTheme.success,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
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
  Widget _buildDone(bool isDark) {
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
        child: const Icon(Icons.local_shipping_rounded,
            color: AppTheme.success, size: 36),
      ),
      const SizedBox(height: 24),
      Text('Dispatched Successfully',
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
          const Icon(Icons.inbox_rounded, color: AppTheme.primaryBlue, size: 18),
          const SizedBox(width: 8),
          Text('Pending Queue', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (_pendingQueue.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue,
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
                    // ── SURGICAL CHANGE: open dialog instead of direct lookup ──
                    onTap: () {
                      if (_phase != ShipPhase.waiting) return;
                      showDialog<bool>(
                        context: context,
                        builder: (_) => _ShipPendingDialog(
                          item: item,
                          onConfirmed: () => _lookupQR(item.qrCode),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: AppTheme.primaryBlue,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                  item.material.isNotEmpty
                                      ? item.material
                                      : 'Unknown',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(color: hintColor),
                                  overflow: TextOverflow.ellipsis),
                              Text('${item.weight.toStringAsFixed(2)} kg',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: hintColor),
                                  overflow: TextOverflow.ellipsis),
                            ])),
                        const Icon(Icons.play_arrow_rounded,
                            color: AppTheme.primaryBlue, size: 16),
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
            onPressed: PendingService.instance.refreshShipQueue,
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
          DropdownButton<String>(
            value: _histFilter,
            underline: const SizedBox(),
            isDense: true,
            style: Theme.of(context).textTheme.bodySmall,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All')),
              DropdownMenuItem(value: 'shipped', child: Text('Shipped')),
              DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => _histFilter = v);
                _loadHistory();
              }
            },
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
                    itemBuilder: (_, i) => _ShipHistoryTile(
                      ship: _history[i],
                      isDark: isDark,
                      onCorrected: _loadHistory,
                    ),
                  ),
      ),
    ]);
  }
}

// ============================================================================
// SHIP PENDING DIALOG — In-dialog scan verification (2-step)
// ============================================================================

class _ShipPendingDialog extends StatefulWidget {
  final Shipment item;
  final VoidCallback onConfirmed;

  const _ShipPendingDialog({required this.item, required this.onConfirmed});

  @override
  State<_ShipPendingDialog> createState() => _ShipPendingDialogState();
}

class _ShipPendingDialogState extends State<_ShipPendingDialog> {
  StreamSubscription<String>? _scanSub;
  bool _verified = false;
  String _scanError = '';
  final _manualCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scanSub = WasteEngine.instance.scanner.shipmentScans.listen(_onScan);
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
    final s = widget.item;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 16, 16),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('#${s.id}',
              style: const TextStyle(
                  color: AppTheme.primaryBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ),
        const SizedBox(width: 10),
        const Expanded(
            child: Text('Pending Shipment', style: TextStyle(fontSize: 16))),
      ]),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Info ────────────────────────────────────────────────────
                _row('Material', s.material.isNotEmpty ? s.material : '—'),
                _row('Product', s.product.isNotEmpty ? s.product : '—'),
                _row('Lot', s.lot.isNotEmpty ? s.lot : 'N/A'),
                _row('Zone', s.zone.isNotEmpty ? s.zone : 'N/A'),
                _row('Net weight', '${s.weight.toStringAsFixed(3)} kg'),
                if (s.wasDenatured) _row('Denaturation', s.denatStatus),

                const Divider(height: 24),

// ── Scan verification ────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _verified
                        ? AppTheme.success.withOpacity(0.08)
                        : AppTheme.primaryBlue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _verified
                          ? AppTheme.success.withOpacity(0.3)
                          : AppTheme.primaryBlue.withOpacity(0.15),
                    ),
                  ),
                  child: _verified
                      ? const Row(children: [
                          Icon(Icons.check_circle,
                              color: AppTheme.success, size: 18),
                          SizedBox(width: 10),
                          Text('Bag confirmed — ready to dispatch',
                              style: TextStyle(color: AppTheme.success)),
                        ])
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.qr_code_scanner,
                                  color: AppTheme.primaryBlue, size: 18),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Scan the physical bag to confirm it matches this shipment record.',
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _verified
              ? () {
                  Navigator.of(context).pop();
                  widget.onConfirmed();
                }
              : null,
          icon: Icon(
              _verified ? Icons.local_shipping_rounded : Icons.lock_outline,
              size: 18),
          label: Text(_verified ? 'Proceed to dispatch' : 'Scan to unlock'),
          style: FilledButton.styleFrom(
            backgroundColor: _verified ? AppTheme.success : Colors.grey,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// HISTORY TILE
// ============================================================================
class _ShipHistoryTile extends StatelessWidget {
  final Shipment ship;
  final bool isDark;
  final VoidCallback? onCorrected;

  const _ShipHistoryTile(
      {required this.ship, required this.isDark, this.onCorrected});

  @override
  Widget build(BuildContext context) {
    final color = ship.isShipped ? AppTheme.success : AppTheme.error;

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
        child: Icon(Icons.local_shipping_rounded, color: color, size: 16),
      ),
      title: Text('${ship.weight.toStringAsFixed(3)} kg',
          style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(ship.product.isNotEmpty ? ship.product : ship.note,
          style: Theme.of(context).textTheme.bodySmall,
          overflow: TextOverflow.ellipsis),
      trailing: StatusBadge(status: ship.status),
      onTap: () async {
        final corrected = await showDialog<bool>(
          context: context,
          builder: (_) => _ShipDetailDialog(ship: ship),
        );
        if (corrected == true) onCorrected?.call();
      },
    );
  }
}

// ============================================================================
// DETAIL + CORRECTION DIALOG
// ============================================================================
class _ShipDetailDialog extends StatefulWidget {
  final Shipment ship;
  const _ShipDetailDialog({required this.ship});

  @override
  State<_ShipDetailDialog> createState() => _ShipDetailDialogState();
}

class _ShipDetailDialogState extends State<_ShipDetailDialog> {
  final _reasonCtrl = TextEditingController();
  String? _selectedStatus;
  bool _busy = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 120,
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

  Future<void> _submitCorrection() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Reason is required'),
          backgroundColor: AppTheme.error));
      return;
    }
    if (_selectedStatus == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Select a new status'),
          backgroundColor: AppTheme.error));
      return;
    }

    setState(() => _busy = true);
    try {
      final code = await ShipmentService.instance
          .correctStatus(widget.ship.id, _selectedStatus!, reason);
      if (!mounted) return;
      if (code == 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Correction submitted'),
            backgroundColor: AppTheme.success));
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed (code $code)'),
            backgroundColor: AppTheme.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.ship;
    final statusColor = s.isShipped ? AppTheme.success : AppTheme.error;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 16, 16),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('#${s.id}',
              style: const TextStyle(
                  color: AppTheme.primaryBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ),
        const SizedBox(width: 10),
        const Expanded(
            child: Text('Shipment detail', style: TextStyle(fontSize: 16))),
        _StatusChip(status: s.status, color: statusColor),
        if (s.isFlagged) ...[
          const SizedBox(width: 8),
          const Icon(Icons.flag_rounded, color: AppTheme.warning, size: 18),
        ],
      ]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _section('SHIPMENT INFO'),
                Card(
                  elevation: 0,
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceVariant
                      .withOpacity(0.35),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      _row('Shipment ID', s.id.toString()),
                      _row(
                          'Material', s.material.isNotEmpty ? s.material : '—'),
                      _row('Product', s.product.isNotEmpty ? s.product : '—'),
                      if (s.lot.isNotEmpty) _row('Lot', s.lot),
                      if (s.zone.isNotEmpty) _row('Zone', s.zone),
                      if (s.shipper.isNotEmpty) _row('Shipper', s.shipper),
                      _row('Status', s.status),
                      _row('Shipped at',
                          s.shippedAt.isNotEmpty ? s.shippedAt : 'Not yet'),
                      if (s.note.isNotEmpty) _row('Note', s.note),
                    ]),
                  ),
                ),
                _section('WEIGHT'),
                Card(
                  elevation: 0,
                  color: AppTheme.primaryBlue.withOpacity(0.04),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side:
                        BorderSide(color: AppTheme.primaryBlue.withOpacity(0.2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Expanded(
                          child: _WeightMini(
                              label: 'Net',
                              value: s.weight,
                              color: AppTheme.success)),
                    ]),
                  ),
                ),
                if (s.wasDenatured) ...[
                  _section('DENATURATION'),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (s.denatStatus == 'completed'
                              ? AppTheme.success
                              : AppTheme.error)
                          .withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: (s.denatStatus == 'completed'
                                  ? AppTheme.success
                                  : AppTheme.error)
                              .withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      Icon(Icons.science_outlined,
                          color: s.denatStatus == 'completed'
                              ? AppTheme.success
                              : AppTheme.error,
                          size: 18),
                      const SizedBox(width: 10),
                      Text('Status: ${s.denatStatus}',
                          style: TextStyle(
                              color: s.denatStatus == 'completed'
                                  ? AppTheme.success
                                  : AppTheme.error)),
                    ]),
                  ),
                ],
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
                        DropdownButtonFormField<String>(
                          value: _selectedStatus,
                          decoration: const InputDecoration(
                              labelText: 'New status', isDense: true),
                          items: const [
                            DropdownMenuItem(
                                value: 'pending', child: Text('pending')),
                            DropdownMenuItem(
                                value: 'shipped', child: Text('shipped')),
                            DropdownMenuItem(
                                value: 'cancelled', child: Text('cancelled')),
                          ],
                          onChanged: (v) => setState(() => _selectedStatus = v),
                        ),
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
  const _InfoCard(
      {required this.icon,
      required this.title,
      required this.message,
      required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.15)),
        ),
        child: Row(children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: AppTheme.primaryBlue, size: 20)),
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
                  color: AppTheme.primaryBlue, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Text('Waiting for incoming scan…',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.primaryBlue)),
        ]),
      );
}
