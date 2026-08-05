import 'dart:async';
import 'package:flutter/material.dart';

// Services & Engine
import 'package:waste_tracking/ffi/services/auth_service.dart';
import 'package:waste_tracking/ffi/services/scanner_service.dart';
import 'package:waste_tracking/ffi/services/pending_service.dart';
import 'package:waste_tracking/ffi/services/reconciliation_service.dart';
import 'package:waste_tracking/ffi/services/shipment_service.dart';
import 'package:waste_tracking/ffi/services/denaturation_service.dart';
import 'package:waste_tracking/ffi/bindings/types.dart';
import 'package:waste_tracking/ffi/engine.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';

// Theme & Shared Layout Components
import 'package:waste_tracking/theme/app_theme.dart';
import 'package:waste_tracking/ffi/screens/shared/sidebar.dart';
import 'package:waste_tracking/ffi/screens/shared/settings_screen.dart';

// Operator Screens
import 'package:waste_tracking/ffi/screens/operator/weigh_screen.dart';

// Validator Screens
import 'package:waste_tracking/ffi/screens/validator/reco_screen.dart';
import 'package:waste_tracking/ffi/screens/validator/shipment_screen.dart';

// Coordinateur Screens
import 'package:waste_tracking/ffi/screens/coordinateur/denat_screen.dart';

// Admin Screens
import 'package:waste_tracking/ffi/screens/admin/catalog_screen.dart';
import 'package:waste_tracking/ffi/screens/admin/dashboard_screen.dart';
import 'package:waste_tracking/ffi/screens/admin/users_screen.dart';
import 'package:waste_tracking/ffi/screens/admin/sessions_screen.dart';
import 'package:waste_tracking/ffi/screens/admin/oversight_screen.dart';
import 'package:waste_tracking/ffi/screens/admin/corrections_screen.dart';
import 'package:waste_tracking/ffi/screens/admin/export_screen.dart';
import 'package:waste_tracking/ffi/screens/shared/pending_screen.dart';

// ============================================================================
// NAV ITEM
// ============================================================================

enum NavItem {
  weigh,
  reconcile,
  shipment,
  denat,
  tasks,
  dashboard,
  users,
  catalog,
  sessions,
  flags,
  corrections,
  export,
  settings,
}

extension NavItemX on NavItem {
  String get label {
    switch (this) {
      case NavItem.weigh:
        return 'Weighing';
      case NavItem.reconcile:
        return 'Reconcile';
      case NavItem.shipment:
        return 'Shipment';
      case NavItem.denat:
        return 'Denaturation';
      case NavItem.tasks:
        return 'Task Inbox';
      case NavItem.dashboard:
        return 'Dashboard';
      case NavItem.users:
        return 'Users';
      case NavItem.catalog:
        return 'Catalog & Zones';
      case NavItem.sessions:
        return 'Sessions';
      case NavItem.flags:
        return 'Oversight';
      case NavItem.corrections:
        return 'Corrections';
      case NavItem.export:
        return 'Export';
      case NavItem.settings:
        return 'Settings';
    }
  }

  IconData get icon {
    switch (this) {
      case NavItem.weigh:
        return Icons.scale_outlined;
      case NavItem.reconcile:
        return Icons.qr_code_scanner_outlined;
      case NavItem.shipment:
        return Icons.local_shipping_outlined;
      case NavItem.denat:
        return Icons.science_outlined;
      case NavItem.tasks:
        return Icons.assignment_outlined;
      case NavItem.dashboard:
        return Icons.dashboard_outlined;
      case NavItem.users:
        return Icons.people_outline;
      case NavItem.catalog:
        return Icons.category_outlined;
      case NavItem.sessions:
        return Icons.devices_outlined;
      case NavItem.flags:
        return Icons.flag_outlined;
      case NavItem.corrections:
        return Icons.history_outlined;
      case NavItem.export:
        return Icons.download_outlined;
      case NavItem.settings:
        return Icons.settings_outlined;
    }
  }

  IconData get iconFilled {
    switch (this) {
      case NavItem.weigh:
        return Icons.scale;
      case NavItem.reconcile:
        return Icons.qr_code_scanner;
      case NavItem.shipment:
        return Icons.local_shipping;
      case NavItem.denat:
        return Icons.science;
      case NavItem.tasks:
        return Icons.assignment;
      case NavItem.dashboard:
        return Icons.dashboard;
      case NavItem.users:
        return Icons.people;
      case NavItem.catalog:
        return Icons.category;
      case NavItem.sessions:
        return Icons.devices;
      case NavItem.flags:
        return Icons.flag;
      case NavItem.corrections:
        return Icons.history;
      case NavItem.export:
        return Icons.download;
      case NavItem.settings:
        return Icons.settings;
    }
  }
}

// ============================================================================
// ADMIN EVENT — used to route C++ callbacks safely to the main isolate
// ============================================================================

enum _AdminEvent { flagCreated, correction }

// ============================================================================
// MAIN LAYOUT
// ============================================================================

class MainLayout extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final void Function(String) onChangeLocale;
  const MainLayout(
      {super.key, required this.onToggleTheme, required this.onChangeLocale});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  NavItem _current = NavItem.dashboard;
  int _pendingFlags = 0;

  final List<_ToastData> _toasts = [];

  // StreamController bridges C++ callbacks → main isolate safely.
  // NativeCallable.listener fires from IXWebSocket thread — we CANNOT
  // call setState or any Flutter method from there directly.
  // We add an event to the controller (thread-safe) and the listener
  // below runs on the main isolate where setState is allowed.
  final _adminEventCtrl = StreamController<_AdminEvent>.broadcast();
  StreamSubscription<_AdminEvent>? _adminEventSub;
  StreamSubscription<String>? _forceLogoutSub;

  @override
  void initState() {
    super.initState();
    _initForRole();
  }

  @override
  void dispose() {
    _adminEventSub?.cancel();
    _forceLogoutSub?.cancel();
    _adminEventCtrl.close();
    ScannerService.instance.stopAll();
    super.dispose();
  }

  // ── Role init ─────────────────────────────────────────────────────────────

  void _initForRole() {
    final session = AuthService.instance.session!;
    final allowed = visibleNavItems(session);
    _current = allowed.isNotEmpty ? allowed.first : NavItem.settings;

    if (session.isAdmin) {
      _registerAdminListeners(session.handle);
    }

    // Always attach scan listeners for any active session.
    ScannerService.instance.startAll(session);

    // Start live pending updates for all service queues.
    PendingService.instance.init(session);
    ReconciliationService.instance.init(session);
    ShipmentService.instance.init(session);
    DenaturationService.instance.init(session);

    // Force logout — stream is already on main isolate, safe to call setState
    _forceLogoutSub = AuthService.instance.onForceLogout.listen((_) {
      if (mounted) _handleForceLogout();
    });
  }

  // ── Admin listeners ───────────────────────────────────────────────────────
  //
  // The NativeCallable.listener callbacks fire from C++'s IXWebSocket thread.
  // We MUST NOT call setState / Navigator / ScaffoldMessenger from there.
  // Solution: add a plain enum value to a StreamController (thread-safe),
  // then react on the main isolate inside the .listen() below.

  void _registerAdminListeners(UserHandle user) {
    final admin = WasteEngine.instance.admin;
    final ctrl = _adminEventCtrl; // capture only the controller, not 'this'

    // Admin signals come from admin chamber (C++ → admin_set_notify_callback)
    // Signals include: NEW_FLAG_ALERT, FLAG_RESOLVED, WEIGHING_CORRECTED, ...
    admin.setNotifyCallback(user, (String signal) {
      if (signal == 'NEW_FLAG_ALERT') {
        ctrl.add(_AdminEvent.flagCreated);
      } else if (signal == 'WEIGHING_CORRECTED' ||
          signal == 'RECO_STATE_UPDATED' ||
          signal == 'SHIPMENT_DISPATCHED' ||
          signal == 'FLAG_RESOLVED') {
        ctrl.add(_AdminEvent.correction);
      }
    });

    // This runs on the main isolate — setState is safe here
    _adminEventSub = ctrl.stream.listen((event) {
      if (!mounted) return;
      switch (event) {
        case _AdminEvent.flagCreated:
          setState(() => _pendingFlags++);
          _showToast(_ToastData(
            message: 'New flag requires review',
            icon: Icons.flag,
            color: AppTheme.warning,
            onTap: () => _navigateTo(NavItem.flags),
          ));
        case _AdminEvent.correction:
          _showToast(_ToastData(
            message: 'Correction submitted',
            icon: Icons.edit_note,
            color: AppTheme.accentCyan,
            onTap: () => _navigateTo(NavItem.corrections),
          ));
      }
    });
  }

  // ── Toast ─────────────────────────────────────────────────────────────────

  void _showToast(_ToastData toast) {
    setState(() => _toasts.add(toast));
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _toasts.remove(toast));
    });
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _navigateTo(NavItem item) {
    setState(() {
      _current = item;
      if (item == NavItem.flags) _pendingFlags = 0;
    });
  }

  // ── Force logout ──────────────────────────────────────────────────────────

  void _handleForceLogout() {
    ScannerService.instance.stopAll();
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Your session was terminated by an administrator.'),
      backgroundColor: AppTheme.error,
      duration: Duration(seconds: 5),
    ));
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> _logout() async {
    if (!await _confirmLogout()) return;
    ScannerService.instance.stopAll();
    await AuthService.instance.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  Future<bool> _confirmLogout() async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirm Logout'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                child: const Text('Logout'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── Screen builder ────────────────────────────────────────────────────────

  Widget _buildScreen() {
    switch (_current) {
      case NavItem.weigh:
        return const WeighScreen();
      case NavItem.reconcile:
        return const RecoScreen();
      case NavItem.shipment:
        return const ShipmentScreen();
      case NavItem.denat:
        return const DenatScreen();
      case NavItem.tasks:
        return const PendingScreen();
      case NavItem.dashboard:
        return DashboardScreen(onNavigate: _navigateTo);
      case NavItem.users:
        return const UsersScreen();
      case NavItem.catalog:
        return const CatalogScreen();
      case NavItem.sessions:
        return const SessionsScreen();
      case NavItem.flags:
        return const OversightScreen();
      case NavItem.corrections:
        return const CorrectionsScreen();
      case NavItem.export:
        return const ExportScreen();
      case NavItem.settings:
        return SettingsScreen(
            onToggleTheme: widget.onToggleTheme,
            onChangeLocale: widget.onChangeLocale);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final session = AuthService.instance.session!;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: Row(
        children: [
          // Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: AppTheme.sidebarExpanded,
            child: Sidebar(
              session: session,
              current: _current,
              flagCount: _pendingFlags,
              onSelect: _navigateTo,
              onLogout: _logout,
              onToggleTheme: widget.onToggleTheme,
              onLanguage: () => _navigateTo(NavItem.settings),
            ),
          ),

          // Divider
          Container(
              width: 1,
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),

          // Content
          Expanded(
            child: Stack(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(_current),
                    child: _buildScreen(),
                  ),
                ),

                // Toasts — top right
                Positioned(
                  top: 16,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: _toasts
                        .map((t) => _ToastWidget(
                              data: t,
                              onDismiss: () =>
                                  setState(() => _toasts.remove(t)),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TOAST
// ============================================================================

class _ToastData {
  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ToastData(
      {required this.message,
      required this.icon,
      required this.color,
      this.onTap});
}

class _ToastWidget extends StatefulWidget {
  final _ToastData data;
  final VoidCallback onDismiss;
  const _ToastWidget({required this.data, required this.onDismiss});

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FadeTransition(
      opacity: _anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(_anim),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () {
              widget.data.onTap?.call();
              widget.onDismiss();
            },
            child: Container(
              width: 320,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: widget.data.color.withOpacity(0.4)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: widget.data.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6)),
                  child: Icon(widget.data.icon,
                      color: widget.data.color, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(widget.data.message,
                        style: theme.textTheme.bodyMedium)),
                GestureDetector(
                  onTap: widget.onDismiss,
                  child: Icon(Icons.close,
                      size: 14,
                      color: isDark
                          ? AppTheme.darkTextHint
                          : AppTheme.lightTextHint),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
