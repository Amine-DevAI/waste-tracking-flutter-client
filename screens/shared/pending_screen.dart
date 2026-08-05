import 'dart:async';
import 'package:flutter/material.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';

import 'package:waste_tracking/ffi/services/pending_service.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';
import 'package:waste_tracking/ffi/engine.dart';
import 'package:waste_tracking/ffi/models/pending_reco.dart';
import 'package:waste_tracking/ffi/models/shipment.dart';
import 'package:waste_tracking/theme/app_theme.dart' hide SectionHeader;
import 'package:waste_tracking/ffi/screens/shared/section_header.dart';

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  // Which queues this user can see — computed once at init
  bool _canReco = false;
  bool _canShip = false;
  bool _canDenat = false;

  List<PendingItem> _recoItems = [];
  List<Shipment> _shipItems = [];
  List<PendingItem> _denatItems = [];

  bool _loading = true;

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _resolvePermissions();
    _subscribeToPendingStreams();
    _refresh();
  }

  void _resolvePermissions() {
    final session = AuthService.instance.session;
    if (session == null) return;
    final engine = WasteEngine.instance;
    setState(() {
      _canReco = engine.auth.hasPermission(session.handle, 'accept_reco');
      _canShip = engine.auth.hasPermission(session.handle, 'dispatch_shipment');
      _canDenat = engine.auth.hasPermission(session.handle, 'denaturation');
    });
  }

  void _subscribeToPendingStreams() {
    _subs.add(PendingService.instance.recoQueue.listen((items) {
      if (mounted) setState(() => _recoItems = items);
    }));
    _subs.add(PendingService.instance.shipQueue.listen((items) {
      if (mounted) setState(() => _shipItems = items);
    }));
    _subs.add(PendingService.instance.denatQueue.listen((items) {
      if (mounted) setState(() => _denatItems = items);
    }));
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await PendingService.instance.refreshAll();
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    super.dispose();
  }

  int get _totalCount =>
      (_canReco ? _recoItems.length : 0) +
      (_canShip ? _shipItems.length : 0) +
      (_canDenat ? _denatItems.length : 0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          // ── Header ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
              child: SectionHeader(
                title: 'Pending Work',
                subtitle: '$_totalCount items waiting',
                trailing: OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                ),
              ),
            ),
          ),

          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            // ── Reco queue ────────────────────────────────────────
            if (_canReco) ...[
              _SectionHeader(
                icon: Icons.qr_code_scanner_outlined,
                label: 'Reconciliation Queue',
                count: _recoItems.length,
                color: AppTheme.accentCyan,
                isDark: isDark,
              ),
              _recoItems.isEmpty
                  ? _SliverEmptyRow(
                      message: 'No pending reconciliations',
                      isDark: isDark,
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 0),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PendingCard(
                              item: _recoItems[i],
                              type: _QueueType.reco,
                              isDark: isDark,
                            ),
                          ),
                          childCount: _recoItems.length,
                        ),
                      ),
                    ),
            ],

            // ── Ship queue ────────────────────────────────────────
            if (_canShip) ...[
              _SectionHeader(
                icon: Icons.local_shipping_outlined,
                label: 'Shipment Queue',
                count: _shipItems.length,
                color: AppTheme.warning,
                isDark: isDark,
              ),
              _shipItems.isEmpty
                  ? _SliverEmptyRow(
                      message: 'No pending shipments',
                      isDark: isDark,
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 0),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PendingCard(
                              item: _shipItems[i],
                              type: _QueueType.ship,
                              isDark: isDark,
                            ),
                          ),
                          childCount: _shipItems.length,
                        ),
                      ),
                    ),
            ],

            // ── Denat queue ───────────────────────────────────────
            if (_canDenat) ...[
              _SectionHeader(
                icon: Icons.science_outlined,
                label: 'Denaturation Queue',
                count: _denatItems.length,
                color: AppTheme.error,
                isDark: isDark,
              ),
              _denatItems.isEmpty
                  ? _SliverEmptyRow(
                      message: 'No pending denaturation operations',
                      isDark: isDark,
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PendingCard(
                              item: _denatItems[i],
                              type: _QueueType.denat,
                              isDark: isDark,
                            ),
                          ),
                          childCount: _denatItems.length,
                        ),
                      ),
                    ),
            ],

            // ── Nothing to show ───────────────────────────────────
            if (!_canReco && !_canShip && !_canDenat)
              SliverFillRemaining(
                child: _FullEmptyState(isDark: isDark),
              ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// QUEUE TYPE
// ============================================================================

enum _QueueType { reco, ship, denat }

// ============================================================================
// SECTION HEADER SLIVER
// ============================================================================

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final bool isDark;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              // Count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

// ============================================================================
// PENDING CARD
// ============================================================================

class _PendingCard extends StatelessWidget {
  final dynamic item;
  final _QueueType type;
  final bool isDark;

  const _PendingCard({
    required this.item,
    required this.type,
    required this.isDark,
  });

  Color get _color {
    switch (type) {
      case _QueueType.reco:
        return AppTheme.accentCyan;
      case _QueueType.ship:
        return AppTheme.warning;
      case _QueueType.denat:
        return AppTheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: item.isFlagged
              ? AppTheme.warning.withOpacity(0.4)
              : isDark
                  ? AppTheme.darkBorder
                  : AppTheme.lightBorder,
        ),
      ),
      child: Row(
        children: [
          // ── Status dot ──────────────────────────────────────────
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),

          // ── Main info ───────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Material + product
                Row(
                  children: [
                    Text(
                      item.material,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (item.product.isNotEmpty && item.product != 'N/A') ...[
                      const SizedBox(width: 6),
                      Text(
                        '· ${item.product}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (item.isFlagged) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.flag,
                        size: 12,
                        color: AppTheme.warning,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                // Meta row
                Wrap(
                  spacing: 12,
                  children: [
                    if (item.lot.isNotEmpty && item.lot != 'N/A')
                      _Chip(
                        icon: Icons.tag,
                        label: item.lot,
                      ),
                    _Chip(
                      icon: Icons.monitor_weight_outlined,
                      label: '${item.weight.toStringAsFixed(2)} kg',
                    ),
                    if (item.zone != null && item.zone!.isNotEmpty)
                      _Chip(
                        icon: Icons.warehouse_outlined,
                        label: item.zone!,
                      ),
                    _Chip(
                      icon: Icons.access_time,
                      label: _timeAgo(item.createdAt),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // ── Status badge ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _color.withOpacity(0.3)),
            ),
            child: Text(
              item.status.toUpperCase(),
              style: TextStyle(
                color: _color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(String ts) {
    if (ts.isEmpty) return '';
    try {
      final diff = DateTime.now().difference(DateTime.parse(ts));
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return ts.length > 10 ? ts.substring(0, 10) : ts;
    }
  }
}

// ============================================================================
// CHIP
// ============================================================================

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 11,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
          const SizedBox(width: 3),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

// ============================================================================
// EMPTY ROW (inline, not full screen)
// ============================================================================

class _SliverEmptyRow extends StatelessWidget {
  final String message;
  final bool isDark;

  const _SliverEmptyRow({
    required this.message,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 14,
                  color: AppTheme.success,
                ),
                const SizedBox(width: 8),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.success,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ============================================================================
// FULL EMPTY STATE (no queues at all)
// ============================================================================

class _FullEmptyState extends StatelessWidget {
  final bool isDark;
  const _FullEmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: isDark ? AppTheme.darkTextHint : AppTheme.lightTextHint,
            ),
            const SizedBox(height: 12),
            Text(
              'No pending work',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Your queues are empty',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}
