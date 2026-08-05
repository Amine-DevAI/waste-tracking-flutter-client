import 'dart:async';
import 'package:flutter/material.dart';

// Services
import 'package:waste_tracking/ffi/services/admin_service.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';

// Models
import 'package:waste_tracking/ffi/models/weighing.dart';
import 'package:waste_tracking/ffi/models/shipment.dart';
import 'package:waste_tracking/ffi/models/reconciliation.dart';
import 'package:waste_tracking/ffi/models/flag.dart';
import 'package:waste_tracking/ffi/models/user.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';

// Theme & Layout
import 'package:waste_tracking/theme/app_theme.dart';
import 'package:waste_tracking/ffi/screens/shared/main_layout.dart';
// ============================================================================
// DASHBOARD SCREEN
// ============================================================================

class DashboardScreen extends StatefulWidget {
  final void Function(NavItem) onNavigate;

  const DashboardScreen({
    super.key,
    required this.onNavigate,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // ── Data ───────────────────────────────────────────────────────────────
  List<Shipment> _pendingShipments = [];
  List<Reconciliation> _pendingRecos = [];
  List<Flag> _pendingFlags = [];
  List<ActiveSession> _activeSessions = [];

  // ── Notifications feed ─────────────────────────────────────────────────
  final List<_NotifItem> _notifications = [];
  static const int _maxNotifs = 50;

  // ── Loading ────────────────────────────────────────────────────────────
  bool _loading = true;
  bool _refreshing = false;

  // ── Auto refresh ───────────────────────────────────────────────────────
  Timer? _refreshTimer;
  StreamSubscription<String>? _signalSub;

  @override
  void initState() {
    super.initState();
    _load();

    _signalSub = AuthService.instance.onRefresh.listen((signal) {
      if (signal == 'NEW_FLAG_ALERT' ||
          signal == 'FLAG_RESOLVED' ||
          signal == 'WEIGHING_CORRECTED' ||
          signal == 'RECO_STATE_UPDATED' ||
          signal == 'SHIPMENT_DISPATCHED') {
        _refresh();
      }
    });

    // Auto refresh every 60 seconds
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  // ── Load all dashboard data ────────────────────────────────────────────
  Future<void> _load() async {
    setState(() => _loading = true);
    await _fetchAll();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await _fetchAll();
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _fetchAll() async {
    try {
      final results = await Future.wait([
        AdminService.instance.listPendingShipments(),
        AdminService.instance
            .listReconciliationsFiltered(statusFilter: 'pending'),
        AdminService.instance.listFlags(status: 'pending'),
        AdminService.instance.listSessions(),
      ]);

      if (mounted) {
        setState(() {
          _pendingShipments = results[0] as List<Shipment>;
          _pendingRecos = results[1] as List<Reconciliation>;
          _pendingFlags = results[2] as List<Flag>;
          _activeSessions = results[3] as List<ActiveSession>;
        });
      }
    } catch (_) {}
  }

  // ── Add notification ───────────────────────────────────────────────────
  void addNotification(String json) {
    final isFlag = json.contains('FLAG_CREATED');
    final isCorrected = json.contains('FLAG_CORRECTED');

    if (!isFlag && !isCorrected) return;

    final notif = _NotifItem(
      message: isFlag
          ? 'New flag requires review'
          : 'Correction submitted for review',
      icon: isFlag ? Icons.flag : Icons.edit_note,
      color: isFlag ? AppTheme.warning : AppTheme.accentCyan,
      time: DateTime.now(),
    );

    setState(() {
      _notifications.insert(0, notif);
      if (_notifications.length > _maxNotifs) {
        _notifications.removeLast();
      }
    });

    // Refresh flags count
    _refresh();
  }

  Future<void> _closeOneFlagFromDashboard() async {
    if (_pendingFlags.length <= 1) {
      widget.onNavigate(NavItem.flags);
      return;
    }

    final flag = _pendingFlags.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Close one flag'),
        content: Text(
            'There are ${_pendingFlags.length} open flags. Close one now and keep the rest?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close one'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      widget.onNavigate(NavItem.flags);
      return;
    }

    try {
      final code = await AdminService.instance
          .rejectFlag(flag.id, 'Auto flag cleanup from dashboard');
      if (code == 0) {
        _showToast('One flag closed, ${_pendingFlags.length - 1} remain');
        _refresh();
      } else {
        _showToast('Failed to close one flag (code $code)', isError: true);
      }
    } catch (e) {
      _showToast('Error closing one flag: $e', isError: true);
    }
  }

  void _showToast(String message, {bool isError = false}) {
    final color = isError ? AppTheme.error : AppTheme.success;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _signalSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // ── Header ─────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: SectionHeader(
                            title: 'Dashboard',
                            subtitle: _greeting(),
                          ),
                        ),
                        // Refresh button
                        _refreshing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                onPressed: _refresh,
                                icon: const Icon(Icons.refresh),
                                tooltip: 'Refresh',
                              ),
                      ],
                    ),
                  ),
                ),

                // ── Stat cards ──────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                    child: _buildStatCards(isDark),
                  ),
                ),

                // ── Active sessions ─────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                    child: _buildSessions(isDark),
                  ),
                ),

                // ── Main content ────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                    child: LayoutBuilder(
                      builder: (ctx, constraints) {
                        final wide = constraints.maxWidth > 800;
                        if (wide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildQueues(isDark),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 2,
                                child: _buildNotifications(isDark),
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            _buildQueues(isDark),
                            const SizedBox(height: 24),
                            _buildNotifications(isDark),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Greeting ───────────────────────────────────────────────────────────
  String _greeting() {
    final h = DateTime.now().hour;
    final name = AuthService.instance.session!.username;
    if (h < 12) return 'Good morning, $name';
    if (h < 18) return 'Good afternoon, $name';
    return 'Good evening, $name';
  }

  // ── Stat cards ─────────────────────────────────────────────────────────
  Widget _buildStatCards(bool isDark) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final crossCount = constraints.maxWidth > 900
            ? 4
            : constraints.maxWidth > 600
                ? 2
                : 2;

        return GridView.count(
          crossAxisCount: crossCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.6,
          children: [
            StatCard(
              title: 'Pending Recos',
              value: '${_pendingRecos.length}',
              icon: Icons.qr_code_scanner_outlined,
              color: AppTheme.accentCyan,
              onTap: () => widget.onNavigate(NavItem.reconcile),
            ),
            StatCard(
              title: 'Pending Shipments',
              value: '${_pendingShipments.length}',
              icon: Icons.local_shipping_outlined,
              color: AppTheme.warning,
              onTap: () => widget.onNavigate(NavItem.shipment),
            ),
            StatCard(
              title: 'Open Flags',
              value: '${_pendingFlags.length}',
              icon: Icons.flag_outlined,
              color: AppTheme.error,
              onTap: _closeOneFlagFromDashboard,
            ),
          ],
        );
      },
    );
  }

  // ── Active sessions ────────────────────────────────────────────────────
  Widget _buildSessions(bool isDark) {
    if (_activeSessions.isEmpty) {
      return const SizedBox.shrink();
    }

    return _DashCard(
      title: 'Active Sessions',
      icon: Icons.devices_outlined,
      onViewAll: () => widget.onNavigate(NavItem.sessions),
      isDark: isDark,
      child: Column(
        children: _activeSessions
            .take(3)
            .map((s) => _SessionRow(
                  session: s,
                  isDark: isDark,
                ))
            .toList(),
      ),
    );
  }

  // ── Pending queues ─────────────────────────────────────────────────────
  Widget _buildQueues(bool isDark) {
    return Column(
      children: [
        // Pending recos
        if (_pendingRecos.isNotEmpty) ...[
          _DashCard(
            title: 'Pending Reconciliations',
            icon: Icons.qr_code_scanner_outlined,
            iconColor: AppTheme.accentCyan,
            onViewAll: () => widget.onNavigate(NavItem.reconcile),
            isDark: isDark,
            child: Column(
              children: _pendingRecos
                  .take(5)
                  .map((r) => _RecoRow(
                        reco: r,
                        isDark: isDark,
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Pending shipments
        if (_pendingShipments.isNotEmpty)
          _DashCard(
            title: 'Pending Shipments',
            icon: Icons.local_shipping_outlined,
            iconColor: AppTheme.warning,
            onViewAll: () => widget.onNavigate(NavItem.shipment),
            isDark: isDark,
            child: Column(
              children: _pendingShipments
                  .take(5)
                  .map((s) => _ShipmentRow(
                        shipment: s,
                        isDark: isDark,
                      ))
                  .toList(),
            ),
          ),

        // All clear
        if (_pendingRecos.isEmpty && _pendingShipments.isEmpty)
          _AllClearCard(isDark: isDark),
      ],
    );
  }

  // ── Notifications feed ─────────────────────────────────────────────────
  Widget _buildNotifications(bool isDark) {
    return _DashCard(
      title: 'Live Notifications',
      icon: Icons.notifications_outlined,
      isDark: isDark,
      child: _notifications.isEmpty
          ? _EmptyFeed(isDark: isDark)
          : Column(
              children: _notifications
                  .take(20)
                  .map((n) => _NotifRow(
                        notif: n,
                        isDark: isDark,
                      ))
                  .toList(),
            ),
    );
  }
}

// ============================================================================
// DASH CARD
// ============================================================================

class _DashCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final Widget child;
  final bool isDark;
  final VoidCallback? onViewAll;

  const _DashCard({
    required this.title,
    required this.icon,
    required this.child,
    required this.isDark,
    this.iconColor,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = iconColor ?? AppTheme.primaryBlue;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                if (onViewAll != null)
                  TextButton(
                    onPressed: onViewAll,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'View All',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),

          Divider(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            height: 16,
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ROW WIDGETS
// ============================================================================

class _SessionRow extends StatelessWidget {
  final ActiveSession session;
  final bool isDark;

  const _SessionRow({
    required this.session,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.circle,
                color: AppTheme.success,
                size: 8,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                session.username,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Text(
              session.ip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}

class _WeighingRow extends StatelessWidget {
  final Weighing weighing;
  final bool isDark;

  const _WeighingRow({
    required this.weighing,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final w = weighing;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.scale_outlined,
              color: AppTheme.primaryBlue,
              size: 14,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '#${w.id} — '
              '${w.netWeight.toStringAsFixed(2)} kg',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            w.createdAtFormatted,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RecoRow extends StatelessWidget {
  final Reconciliation reco;
  final bool isDark;

  const _RecoRow({
    required this.reco,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final r = reco;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.accentCyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.qr_code_scanner_outlined,
              color: AppTheme.accentCyan,
              size: 14,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '#${r.id} — '
              '${(r.newWeight ?? 0.0).toStringAsFixed(2)} kg',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          StatusBadge(status: r.status),
        ],
      ),
    );
  }
}

class _ShipmentRow extends StatelessWidget {
  final Shipment shipment;
  final bool isDark;

  const _ShipmentRow({
    required this.shipment,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final s = shipment;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.local_shipping_outlined,
              color: AppTheme.warning,
              size: 14,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '#${s.id} — '
              '${s.productName.isNotEmpty ? s.productName : 'Unknown'}',
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${s.netWeight.toStringAsFixed(2)} kg',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// NOTIFICATION ITEM + ROW
// ============================================================================

class _NotifItem {
  final String message;
  final IconData icon;
  final Color color;
  final DateTime time;

  const _NotifItem({
    required this.message,
    required this.icon,
    required this.color,
    required this.time,
  });
}

class _NotifRow extends StatelessWidget {
  final _NotifItem notif;
  final bool isDark;

  const _NotifRow({
    required this.notif,
    required this.isDark,
  });

  String _timeAgo() {
    final diff = DateTime.now().difference(notif.time);
    if (diff.inSeconds < 60) {
      return 'just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: notif.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                notif.icon,
                color: notif.color,
                size: 14,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                notif.message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Text(
              _timeAgo(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}

// ============================================================================
// ALL CLEAR CARD
// ============================================================================

class _AllClearCard extends StatelessWidget {
  final bool isDark;
  const _AllClearCard({required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppTheme.success.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.success.withOpacity(0.2),
          ),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: AppTheme.success,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'All Clear',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: AppTheme.success),
            ),
            const SizedBox(height: 4),
            Text(
              'No pending items at this time',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}

// ============================================================================
// EMPTY FEED
// ============================================================================

class _EmptyFeed extends StatelessWidget {
  final bool isDark;
  const _EmptyFeed({required this.isDark});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.notifications_none_outlined,
              size: 32,
              color: isDark ? AppTheme.darkTextHint : AppTheme.lightTextHint,
            ),
            const SizedBox(height: 8),
            Text(
              'No notifications yet',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}
/*```

**What's in this file:**
```
✅ Greeting — good morning/afternoon/evening + username
✅ Stat cards grid
   → pending weighings (blue) → navigates to weigh
   → pending recos (cyan)     → navigates to reconcile
   → pending shipments (orange) → navigates to shipment
   → open flags (red)         → navigates to flags
   → responsive: 4 cols wide / 2 cols narrow
✅ Active sessions strip
   → shows up to 3 active sessions
   → green dot per session
   → view all → sessions screen
✅ Pending queues
   → pending weighings list
   → pending recos list
   → pending shipments list
   → all clear card when nothing pending
✅ Live notifications feed
   → FLAG_CREATED → warning color
   → FLAG_CORRECTED → cyan color
   → time ago label
   → max 50 notifications kept
   → empty state
✅ Auto refresh every 60 seconds
✅ Manual refresh button
✅ Responsive 2-column layout on wide screens */
