import 'dart:async';
import 'package:flutter/material.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';

// Your Project Imports
import 'package:waste_tracking/ffi/services/admin_service.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';
import 'package:waste_tracking/ffi/models/user.dart';
import 'package:waste_tracking/theme/app_theme.dart';
// ============================================================================
// SESSIONS SCREEN
// ============================================================================

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  // ── Data ───────────────────────────────────────────────────────────────
  List<ActiveSession> _sessions = [];
  bool _loading = true;
  bool _refreshing = false;

  // ── Auto refresh ───────────────────────────────────────────────────────
  Timer? _timer;
  StreamSubscription<String>? _refreshSub;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    _refreshSub = AuthService.instance.onRefresh.listen((signal) {
      if (mounted &&
          (signal == 'USER_DEACTIVATED' || signal == 'USER_UPDATED')) {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _refreshSub?.cancel();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────
  bool get _isAdmin => AuthService.instance.session?.isAdmin ?? false;

  // ── Load ───────────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() => _loading = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final sessions = await AdminService.instance.listSessions();
      if (mounted) {
        setState(() => _sessions = sessions);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Refresh ────────────────────────────────────────────────────────────
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final sessions = await AdminService.instance.listSessions();
      if (mounted) {
        setState(() => _sessions = sessions);
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  // ── Force logout ───────────────────────────────────────────────────────
  Future<void> _forceLogout(ActiveSession session) async {
    // Only admins can force logout others
    if (!AuthService.instance.session!.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only admins can force logout users'),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Cannot force logout yourself
    final selfId = AuthService.instance.session!.userId;
    if (session.userId == selfId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot force logout yourself'),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Force Logout'),
        content: Text(
          'This will immediately terminate all '
          'active sessions for '
          '${session.username}.\n\n'
          'They will be logged out instantly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Force Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final code =
          await AdminService.instance.deactivateSession(session.userId);

      if (code == 0) {
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${session.username} logged out'),
              backgroundColor: AppTheme.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Force logout failed'),
              backgroundColor: AppTheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selfId = AuthService.instance.session!.userId;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          // ── Header ─────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
              child: SectionHeader(
                title: 'Active Sessions',
                subtitle: '${_sessions.length} '
                    'sessions active in last 5 minutes',
                trailing: Row(
                  children: [
                    // Auto refresh indicator
                    if (_refreshing)
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    // Manual refresh
                    OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Info banner ────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
              child: _InfoBanner(
                message: 'Sessions are considered active '
                    'if they have sent a heartbeat '
                    'in the last 5 minutes. '
                    'Force logout terminates all '
                    'sessions for a user instantly.',
                isDark: isDark,
              ),
            ),
          ),

          // ── Sessions list ──────────────────────
          _loading
              ? const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              : _sessions.isEmpty
                  ? SliverFillRemaining(
                      child: _EmptyState(
                        isDark: isDark,
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(32, 20, 32, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            final s = _sessions[i];
                            final isSelf = s.userId == selfId;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _SessionCard(
                                session: s,
                                isSelf: isSelf,
                                isAdmin: _isAdmin,
                                isDark: isDark,
                                onForceLogout: () => _forceLogout(s),
                              ),
                            );
                          },
                          childCount: _sessions.length,
                        ),
                      ),
                    ),
        ],
      ),
    );
  }
}

// ============================================================================
// SESSION CARD
// ============================================================================

class _SessionCard extends StatelessWidget {
  final ActiveSession session;
  final bool isSelf;
  final bool isAdmin;
  final bool isDark;
  final VoidCallback onForceLogout;

  const _SessionCard({
    required this.session,
    required this.isSelf,
    required this.isAdmin,
    required this.isDark,
    required this.onForceLogout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelf
              ? AppTheme.primaryBluee.withOpacity(0.3)
              : isDark
                  ? AppTheme.darkBorder
                  : AppTheme.lightBorder,
        ),
      ),
      child: Row(
        children: [
          // ── Live indicator ────────────────────
          Column(
            children: [
              _PulsingDot(),
              const SizedBox(height: 4),
              Text(
                'LIVE',
                style: const TextStyle(
                  color: AppTheme.success,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),

          const SizedBox(width: 16),

          // ── Info ──────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        session.username,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBluee.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'YOU',
                          style: TextStyle(
                            color: AppTheme.primaryBluee,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // IP
                    _MetaChip(
                      icon: Icons.lan_outlined,
                      label: session.ip.isNotEmpty ? session.ip : 'Unknown IP',
                    ),
                    const SizedBox(width: 8),
                    // Version
                    if (session.version.isNotEmpty)
                      _MetaChip(
                        icon: Icons.info_outline,
                        label: session.version,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // Last active
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 12,
                      color: isDark
                          ? AppTheme.darkTextHint
                          : AppTheme.lightTextHint,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Last active: '
                      '${_formatTime(session.lastActive)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Force logout ──────────────────────
          if (!isSelf && isAdmin)
            ElevatedButton.icon(
              onPressed: onForceLogout,
              icon: const Icon(
                Icons.logout,
                size: 14,
              ),
              label: const Text(
                'Force Logout',
                style: TextStyle(fontSize: 12),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error.withOpacity(0.9),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            )
          else if (!isSelf && !isAdmin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.warning.withOpacity(0.3),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 14, color: AppTheme.warning),
                  SizedBox(width: 6),
                  Text(
                    'No Permission To Force Logout',
                    style: TextStyle(
                      color: AppTheme.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryBluee.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.primaryBluee.withOpacity(0.2),
                ),
              ),
              child: const Text(
                'Current Session',
                style: TextStyle(
                  color: AppTheme.primaryBluee,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(String timestamp) {
    if (timestamp.isEmpty) return 'Unknown';
    if (timestamp.length >= 19) {
      return timestamp.substring(11, 19);
    }
    return timestamp;
  }
}

// ============================================================================
// PULSING DOT
// ============================================================================

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.3, end: 1.0).animate(_anim),
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: AppTheme.success,
            shape: BoxShape.circle,
          ),
        ),
      );
}

// ============================================================================
// META CHIP
// ============================================================================

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
}

// ============================================================================
// INFO BANNER
// ============================================================================

class _InfoBanner extends StatelessWidget {
  final String message;
  final bool isDark;

  const _InfoBanner({
    required this.message,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.primaryBluee.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppTheme.primaryBluee.withOpacity(0.15),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline,
              color: AppTheme.primaryBluee,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
}

// ============================================================================
// EMPTY STATE
// ============================================================================

class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.devices_outlined,
              size: 48,
              color: isDark ? AppTheme.darkTextHint : AppTheme.lightTextHint,
            ),
            const SizedBox(height: 12),
            Text(
              'No active sessions',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'All users are currently logged out',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}
/*```

**What's in this file:**
```
✅ Session list — active in last 5 minutes
✅ Auto refresh every 30 seconds
✅ Manual refresh button
✅ Info banner explaining what active means
✅ Session card
   → pulsing green dot — live indicator
   → username + YOU badge on self
   → IP address chip
   → client version chip
   → last active time (HH:MM:SS)
   → force logout button (red)
   → current session label on self (no logout)
✅ Force logout flow
   → cannot logout yourself — warning snackbar
   → confirmation dialog with clear warning
   → success/error snackbar after action
   → auto refresh after success
✅ Empty state
   → no active sessions message
✅ Self highlighted with blue border */
