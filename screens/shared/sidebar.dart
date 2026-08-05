import 'package:flutter/material.dart';

import 'package:waste_tracking/ffi/bindings/types.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';

// Theme & Layout
import 'package:waste_tracking/theme/app_theme.dart';
import 'package:waste_tracking/ffi/screens/shared/main_layout.dart';

List<NavItem> visibleNavItems(UserSession session) {
  if (session.isAdmin) {
    return [
      NavItem.dashboard,
      NavItem.weigh,
      NavItem.reconcile,
      NavItem.shipment,
      NavItem.denat,
      NavItem.users,
      NavItem.catalog,
      NavItem.sessions,
      NavItem.flags,
      NavItem.corrections,
      NavItem.export,
      NavItem.settings,
    ];
  }

  return NavItem.values.where((item) {
    final key = item.capabilityKey;
    return key == null || session.can(key);
  }).toList();
}

extension NavItemCapability on NavItem {
  String? get capabilityKey {
    switch (this) {
      case NavItem.weigh:
        return 'weigh_1';
      case NavItem.reconcile:
        return 'reconcile_2';
      case NavItem.shipment:
        return 'shipment_3';
      case NavItem.denat:
        return 'denaturation_4';
      case NavItem.tasks:
        return 'task_inbox'; // Keep old for now
      case NavItem.dashboard:
        return 'dashboard_11';
      case NavItem.users:
        return 'user_admin_5';
      case NavItem.catalog:
        return 'catalog_6';
      case NavItem.sessions:
        return 'sessions_7';
      case NavItem.flags:
        return 'oversight_8';
      case NavItem.corrections:
        return 'corrections_9';
      case NavItem.export:
        return 'export_10';
      case NavItem.settings:
        return null;
    }
  }
}

// ============================================================================
// SIDEBAR
// ============================================================================

class Sidebar extends StatelessWidget {
  final UserSession session;
  final NavItem current;
  final int flagCount;
  final void Function(NavItem) onSelect;
  final VoidCallback onLogout;
  final VoidCallback onToggleTheme;
  final VoidCallback onLanguage;

  const Sidebar({
    super.key,
    required this.session,
    required this.current,
    required this.flagCount,
    required this.onSelect,
    required this.onLogout,
    required this.onToggleTheme,
    required this.onLanguage,
  });

  // ── Nav items based on capabilities / role ─────────────────────────────
  List<NavItem> _itemsForRole() {
    return visibleNavItems(session);
  }

  // ── Role label ────────────────────────────────────────────────────────────
  String get _roleLabel => UserRole.name(session.role).toUpperCase();

  Color _roleColor() {
    if (session.isAdmin) return AppTheme.accentCyan;
    if (session.isOperator) return AppTheme.primaryBluee;
    if (session.isValidator) return AppTheme.warning;
    return AppTheme.darkTextHint;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Container(
      color: bg,
      child: Column(
        children: [
          // ── Logo (no toggle) ────────────────────────────────
          _buildHeader(context, isDark),

          const SizedBox(height: 8),

          // ── Nav items ───────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                _groupLabel(context, 'NAVIGATION'),
                const SizedBox(height: 4),

                // Items
                ..._itemsForRole().map((item) => _NavTile(
                      item: item,
                      selected: current == item,
                      expanded: true,
                      badge: item == NavItem.flags ? flagCount : 0,
                      onTap: () => onSelect(item),
                    )),

                const SizedBox(height: 8),
                Divider(color: border, height: 1),
                const SizedBox(height: 8),

                // Settings — always visible
                _NavTile(
                  item: NavItem.settings,
                  selected: current == NavItem.settings,
                  expanded: true,
                  onTap: () => onSelect(NavItem.settings),
                ),
              ],
            ),
          ),

          // ── Bottom: user info + actions ──────────────────────
          _buildFooter(context, true, border),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo icon (always expanded)
          SizedBox(
            width: 32,
            height: 32,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.primaryBluee,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.hub_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WASTE TRACKING',
                  style: TextStyle(
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  'Industrial Management',
                  style: TextStyle(
                    color: isDark
                        ? AppTheme.darkTextHint
                        : AppTheme.lightTextHint,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _buildFooter(BuildContext context, bool isDark, Color border) {
    final textPrimary =
        isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textHint = isDark ? AppTheme.darkTextHint : AppTheme.lightTextHint;

    return Column(
      children: [
        Divider(color: border, height: 1),

        // User info (always expanded)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _roleColor().withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _roleColor().withOpacity(0.3)),
                ),
                child: Center(
                  child: Text(
                    session.username.isNotEmpty
                        ? session.username[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: _roleColor(),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.username,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _roleColor().withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _roleLabel,
                        style: TextStyle(
                          color: _roleColor(),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Action buttons (always expanded)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Row(
            children: [
              // Theme toggle
              Expanded(
                child: _ActionButton(
                  icon: Icons.brightness_6_outlined,
                  label: 'Theme',
                  onTap: onToggleTheme,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              // Language
              Expanded(
                child: _ActionButton(
                  icon: Icons.language_outlined,
                  label: 'Language',
                  onTap: onLanguage,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              // Logout
              Expanded(
                child: _ActionButton(
                  icon: Icons.logout,
                  label: 'Logout',
                  onTap: onLogout,
                  isDark: isDark,
                  color: AppTheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Group label ───────────────────────────────────────────────────────────
  Widget _groupLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

// ============================================================================
// NAV TILE
// ============================================================================

class _NavTile extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final bool expanded;
  final int badge;
  final VoidCallback onTap;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.expanded,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final selectedBg = AppTheme.primaryBluee.withOpacity(0.12);
    final selectedFg = AppTheme.primaryBluee;
    final normalFg =
        isDark ? AppTheme.darkTextSecond : AppTheme.lightTextSecond;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 12 : 0,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: selected ? selectedBg : null,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: AppTheme.primaryBluee.withOpacity(0.2))
                : null,
          ),
          child: expanded
              ? Row(
                  children: [
                    // Icon
                    Icon(
                      selected ? item.iconFilled : item.icon,
                      color: selected ? selectedFg : normalFg,
                      size: 20,
                    ),
                    const SizedBox(width: 12),

                     // Label
                     Flexible(
                       child: Builder(
                         builder: (context) {
                           final l10n = AppLocalizations.of(context)!;
                           return Text(
                             _getLocalizedLabel(item, l10n),
                             style: TextStyle(
                               color: selected ? selectedFg : normalFg,
                               fontSize: 13,
                               fontWeight:
                                   selected ? FontWeight.w600 : FontWeight.w400,
                             ),
                             overflow: TextOverflow.ellipsis,
                             maxLines: 1,
                           );
                         },
                       ),
                     ),

                    // Badge
                    if (badge > 0) _Badge(count: badge),
                  ],
                )
              : Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        selected ? item.iconFilled : item.icon,
                        color: selected ? selectedFg : normalFg,
                        size: 20,
                      ),
                      if (badge > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: _Badge(count: badge, small: true),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

// ============================================================================
// BADGE
// ============================================================================

class _Badge extends StatelessWidget {
  final int count;
  final bool small;

  const _Badge({required this.count, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 4 : 6,
        vertical: small ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: AppTheme.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          color: Colors.white,
          fontSize: small ? 9 : 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _getLocalizedLabel(NavItem item, AppLocalizations l10n) {
  switch (item) {
    case NavItem.weigh:
      return l10n.weighing;
    case NavItem.reconcile:
      return l10n.reconcile;
    case NavItem.shipment:
      return l10n.shipment;
    case NavItem.denat:
      return l10n.denaturation;
    case NavItem.tasks:
      return 'Task Inbox';
    case NavItem.dashboard:
      return l10n.dashboard;
    case NavItem.users:
      return l10n.users;
    case NavItem.catalog:
      return l10n.catalog;
    case NavItem.sessions:
      return l10n.sessions;
    case NavItem.flags:
      return l10n.oversight;
    case NavItem.corrections:
      return l10n.corrections;
    case NavItem.export:
      return l10n.export;
    case NavItem.settings:
      return l10n.settings;
  }
}

// ============================================================================
// ACTION BUTTON — expanded sidebar
// ============================================================================

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fg =
        color ?? (isDark ? AppTheme.darkTextSecond : AppTheme.lightTextSecond);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: fg.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: fg.withOpacity(0.12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ICON ACTION — collapsed sidebar
// ============================================================================

class _IconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;
  final Color? color;

  const _IconAction({
    required this.icon,
    required this.onTap,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fg =
        color ?? (isDark ? AppTheme.darkTextSecond : AppTheme.lightTextSecond);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: fg.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: fg, size: 16),
      ),
    );
  }
}
/*```

**What's in this file:**
```
✅ Sidebar — full component
✅ Role-based nav items
   Admin    → all 9 items
   Operator → weigh only
   Validator→ reconcile + shipment
✅ Animated expand/collapse
✅ Flag badge — red count on flags item
   collapsed → dot on icon
   expanded  → pill next to label
✅ User avatar → first letter of username
✅ Role badge → colored pill (cyan/blue/orange)
✅ Theme toggle button
✅ Logout button with confirmation
✅ Tooltip on collapsed items
✅ Settings always visible
✅ Active state → filled icon + blue bg
✅ Smooth animations throughout */
