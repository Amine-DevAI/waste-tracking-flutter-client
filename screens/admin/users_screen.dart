import 'dart:async';
import 'package:flutter/material.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';

// Services
import 'package:waste_tracking/ffi/services/auth_service.dart';
import 'package:waste_tracking/ffi/services/zone_service.dart';

// FFI Bindings
import 'package:waste_tracking/ffi/bindings/types.dart';

// Models
import 'package:waste_tracking/ffi/models/user.dart';
import 'package:waste_tracking/ffi/models/zone.dart';

// Theme
import 'package:waste_tracking/theme/app_theme.dart' hide SectionHeader;
import 'package:waste_tracking/ffi/screens/shared/section_header.dart';
// ============================================================================
// USERS SCREEN
// ============================================================================

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  // ── Data ───────────────────────────────────────────────────────────────
  List<User> _users = [];
  List<User> _filtered = [];
  bool _loading = true;

  // ── Search ─────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _roleFilter = 'all';
  StreamSubscription<String>? _refreshSub;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.toLowerCase();
        _applyFilter();
      });
    });
    // Auto-reload when server says users changed
    _refreshSub = AuthService.instance.onRefresh.listen((signal) {
      if (mounted &&
          (signal == 'USER_CREATED' ||
              signal == 'USER_UPDATED' ||
              signal == 'USER_DEACTIVATED')) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Load ───────────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() => _loading = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final users = await AuthService.instance.listUsers();
      if (mounted) {
        setState(() {
          _users = users;
          _applyFilter();
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Filter ─────────────────────────────────────────────────────────────
  void _applyFilter() {
    _filtered = _users.where((u) {
      final matchSearch = _searchQuery.isEmpty ||
          u.username.toLowerCase().contains(_searchQuery) ||
          u.fullName.toLowerCase().contains(_searchQuery);
      final matchRole =
          _roleFilter == 'all' || u.role.toLowerCase() == _roleFilter;
      return matchSearch && matchRole;
    }).toList();
  }

  // ── Create user dialog ─────────────────────────────────────────────────
  Future<void> _showCreateDialog() async {
    await showDialog(
      context: context,
      builder: (_) => _CreateUserDialog(
        onCreated: _load,
      ),
    );
  }

  // ── Reset password dialog ──────────────────────────────────────────────
  Future<void> _showResetDialog(User user) async {
    await showDialog(
      context: context,
      builder: (_) => _ResetPasswordDialog(
        user: user,
        onReset: _load,
      ),
    );
  }

  // ── Edit user dialog ─────────────────────────────────────────────────────
  Future<void> _showEditDialog(User user) async {
    await showDialog(
      context: context,
      builder: (_) => _EditUserDialog(
        user: user,
        onUpdated: _load,
      ),
    );
  }

  // ── Delete user ────────────────────────────────────────────────────────
  Future<void> _deleteUser(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${user.username}?'),
        content: Text('This will deactivate the account '
            'and terminate all active sessions '
            'for ${user.fullName}.\n\n'
            'This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await AuthService.instance.deleteUser(user.id);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${user.username} deleted'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          // ── Header ─────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
              child: SectionHeader(
                title: 'User Management',
                subtitle: '${_filtered.length} users',
                trailing: ElevatedButton.icon(
                  onPressed: _showCreateDialog,
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: const Text('New User'),
                ),
              ),
            ),
          ),

          // ── Filters ────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
              child: Row(
                children: [
                  // Search
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Search by username or name...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Role filter
                  _RoleFilterChips(
                    selected: _roleFilter,
                    onSelected: (r) {
                      setState(() {
                        _roleFilter = r;
                        _applyFilter();
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── User list ──────────────────────────
          _loading
              ? const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              : _filtered.isEmpty
                  ? SliverFillRemaining(
                      child: _EmptyState(
                        icon: Icons.people_outline,
                        message: _searchQuery.isNotEmpty
                            ? 'No users match your search'
                            : 'No users found',
                        isDark: isDark,
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _UserCard(
                              user: _filtered[i],
                              isDark: isDark,
                              onEdit: () => _showEditDialog(_filtered[i]),
                              onReset: () => _showResetDialog(_filtered[i]),
                              onDelete: () => _deleteUser(_filtered[i]),
                            ),
                          ),
                          childCount: _filtered.length,
                        ),
                      ),
                    ),
        ],
      ),
    );
  }
}

// ============================================================================
// USER CARD
// ============================================================================

class _UserCard extends StatelessWidget {
  final User user;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onReset;
  final VoidCallback onDelete;

  const _UserCard({
    required this.user,
    required this.isDark,
    required this.onEdit,
    required this.onReset,
    required this.onDelete,
  });

  Color _roleColor() {
    switch (user.roleCode) {
      case UserRole.admin:
        return AppTheme.accentCyan;
      case UserRole.operator_:
        return AppTheme.primaryBlue;
      case UserRole.validator:
        return AppTheme.warning;
      case UserRole.coordinateur:
        return AppTheme.success;
      default:
        return AppTheme.darkTextHint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roleColor = _roleColor();
    final isSelf = user.id == AuthService.instance.session!.userId;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Row(
        children: [
          // ── Avatar ───────────────────────────
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: roleColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: roleColor.withOpacity(0.3),
              ),
            ),
            child: Center(
              child: Text(
                user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                style: TextStyle(
                  color: roleColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(width: 14),

          // ── Info ─────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.username,
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
                          color: AppTheme.primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'YOU',
                          style: TextStyle(
                            color: AppTheme.primaryBlue,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    // Status dot
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color:
                            user.isActive ? AppTheme.success : AppTheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      user.isActive ? 'Active' : 'Inactive',
                      style: TextStyle(
                        color:
                            user.isActive ? AppTheme.success : AppTheme.error,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  user.fullName,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // Role badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: roleColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: roleColor.withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        user.role.toUpperCase(),
                        style: TextStyle(
                          color: roleColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (user.lastLogin.isNotEmpty)
                      Text(
                        'Last login: ${user.lastLogin.length > 10 ? user.lastLogin.substring(0, 10) : user.lastLogin}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── Actions ──────────────────────────
          if (!isSelf)
            Row(
              children: [
                // Edit user
                Tooltip(
                  message: 'Edit User',
                  child: IconButton(
                    onPressed: onEdit,
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 18,
                    ),
                    color: AppTheme.primaryBlue,
                  ),
                ),
                // Reset password
                Tooltip(
                  message: 'Reset Password',
                  child: IconButton(
                    onPressed: onReset,
                    icon: const Icon(
                      Icons.lock_reset_outlined,
                      size: 18,
                    ),
                    color: AppTheme.primaryBlue,
                  ),
                ),
                // Delete
                Tooltip(
                  message: 'Delete User',
                  child: IconButton(
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.person_remove_outlined,
                      size: 18,
                    ),
                    color: AppTheme.error,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// ROLE FILTER CHIPS
// ============================================================================

class _RoleFilterChips extends StatelessWidget {
  final String selected;
  final void Function(String) onSelected;

  const _RoleFilterChips({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        'all',
        'admin',
        'operator',
        'validator',
        'coordinateur',
      ].map((r) {
        final isSelected = selected == r;
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: FilterChip(
            label: Text(
              r == 'all' ? 'All' : r[0].toUpperCase() + r.substring(1),
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.white : null,
              ),
            ),
            selected: isSelected,
            onSelected: (_) => onSelected(r),
            selectedColor: AppTheme.primaryBlue,
            checkmarkColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
        );
      }).toList(),
    );
  }
}

// ============================================================================
// CREATE USER DIALOG
// ============================================================================

class _CreateUserDialog extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateUserDialog({required this.onCreated});

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CapabilityOption {
  final String key;
  final String label;
  const _CapabilityOption({required this.key, required this.label});
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final Set<String> _selectedCapabilities = {};
  int _role = UserRole.operator_;
  bool _loading = false;
  String _error = '';
  bool _showPass = false;

  List<Zone> _zones = [];
  int? _selectedZoneId;

  static const List<_CapabilityOption> _capabilityOptions = [
    _CapabilityOption(key: 'weigh_1', label: 'Weighing'),
    _CapabilityOption(key: 'reconcile_2', label: 'Reconciliation'),
    _CapabilityOption(key: 'shipment_3', label: 'Shipment'),
    _CapabilityOption(key: 'denaturation_4', label: 'Denaturation'),
    _CapabilityOption(key: 'user_admin_5', label: 'User Admin'),
    _CapabilityOption(key: 'catalog_6', label: 'Catalog'),
    _CapabilityOption(key: 'sessions_7', label: 'Sessions'),
    _CapabilityOption(key: 'oversight_8', label: 'Oversight'),
    _CapabilityOption(key: 'corrections_9', label: 'Corrections'),
    _CapabilityOption(key: 'export_10', label: 'Export'),
    _CapabilityOption(key: 'dashboard_11', label: 'Dashboard'),
  ];

  String _buildCapabilitiesString() {
    return _capabilityOptions
        .where((option) => _selectedCapabilities.contains(option.key))
        .map((option) => option.key)
        .join(' | ');
  }

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  Future<void> _loadZones() async {
    try {
      _zones = await ZoneService.instance.list();
      if (_zones.isNotEmpty) _selectedZoneId = _zones.first.id;
      if (mounted) setState(() {});
    } catch (_) {
      // ignore failures, optional
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final name = _nameCtrl.text.trim();
    final capabilities = _buildCapabilitiesString();

    if (username.isEmpty || password.isEmpty || name.isEmpty) {
      setState(() => _error = 'All fields required');
      return;
    }
    if (_selectedCapabilities.isEmpty) {
      setState(() => _error = 'Select at least one permission');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password min 6 characters');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final id = await AuthService.instance.createUser(
        username: username,
        password: password,
        fullName: name,
        role: _roleName(_role),
        capabilities: capabilities,
        zoneId: _selectedZoneId ?? -1,
      );

      if (id > 0) {
        widget.onCreated();
        if (mounted) Navigator.pop(context);
      } else {
        setState(() => _error = 'Failed to create user');
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _roleName(int code) {
    switch (code) {
      case UserRole.admin:
        return 'admin';
      case UserRole.operator_:
        return 'operator';
      case UserRole.validator:
        return 'validator';
      case UserRole.coordinateur:
        return 'Coordinateur';
      default:
        return 'viewer';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New User'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Full name
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.badge_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 12),

              // Username
              TextField(
                controller: _usernameCtrl,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline, size: 18),
                ),
              ),
              const SizedBox(height: 12),

              // Password
              TextField(
                controller: _passwordCtrl,
                obscureText: !_showPass,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline, size: 18),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _showPass = !_showPass),
                    icon: Icon(
                      _showPass
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Capability tags
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Permissions',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(letterSpacing: 1)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _capabilityOptions.map((option) {
                  final selected = _selectedCapabilities.contains(option.key);
                  return ChoiceChip(
                    label: Text(option.label),
                    selected: selected,
                    selectedColor:
                        Theme.of(context).colorScheme.primary.withOpacity(0.15),
                    onSelected: (_) => setState(() {
                      if (selected) {
                        _selectedCapabilities.remove(option.key);
                      } else {
                        _selectedCapabilities.add(option.key);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Zone picker
              ...(_zones.isNotEmpty
                  ? [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('ZONE',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(letterSpacing: 1)),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        value: _selectedZoneId,
                        isExpanded: true,
                        items: _zones
                            .map((zone) => DropdownMenuItem<int>(
                                  value: zone.id,
                                  child: Text('${zone.code} - ${zone.name}'),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedZoneId = value),
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(), isDense: true),
                      ),
                      const SizedBox(height: 16),
                    ]
                  : []),

              // Role picker
              _RolePicker(
                selected: _role,
                onSelected: (r) => setState(() => _role = r),
              ),

              // Error
              ...(_error.isNotEmpty
                  ? [
                      const SizedBox(height: 12),
                      _ErrorText(error: _error),
                    ]
                  : []),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _create,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

// ============================================================================
// RESET PASSWORD DIALOG
// ============================================================================

class _ResetPasswordDialog extends StatefulWidget {
  final User user;
  final VoidCallback onReset;

  const _ResetPasswordDialog({
    required this.user,
    required this.onReset,
  });

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String _error = '';
  bool _showPass = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    final pass = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (pass.isEmpty) {
      setState(() => _error = 'Password required');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Password min 6 characters');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final code =
          await AuthService.instance.resetPassword(widget.user.id, pass);

      if (code == 0) {
        widget.onReset();
        if (mounted) Navigator.pop(context);
      } else {
        setState(() => _error = 'Reset failed — code $code');
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reset Password — ${widget.user.username}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _passCtrl,
              obscureText: !_showPass,
              decoration: InputDecoration(
                labelText: 'New Password',
                prefixIcon: const Icon(Icons.lock_outline, size: 18),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _showPass = !_showPass),
                  icon: Icon(
                    _showPass
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: !_showPass,
              decoration: const InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon: Icon(Icons.lock_outline, size: 18),
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ErrorText(error: _error),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _reset,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Reset Password'),
        ),
      ],
    );
  }
}

// ============================================================================
// EDIT USER DIALOG
// ============================================================================

class _EditUserDialog extends StatefulWidget {
  final User user;
  final VoidCallback onUpdated;

  const _EditUserDialog({
    required this.user,
    required this.onUpdated,
  });

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  final _usernameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final Set<String> _selectedCapabilities = {};
  int _role = UserRole.operator_;
  bool _loading = false;
  String _error = '';

  List<Zone> _zones = [];
  int? _selectedZoneId;

  static const List<_CapabilityOption> _capabilityOptions = [
    _CapabilityOption(key: 'weigh_1', label: 'Weighing'),
    _CapabilityOption(key: 'reconcile_2', label: 'Reconciliation'),
    _CapabilityOption(key: 'shipment_3', label: 'Shipment'),
    _CapabilityOption(key: 'denaturation_4', label: 'Denaturation'),
    _CapabilityOption(key: 'user_admin_5', label: 'User Admin'),
    _CapabilityOption(key: 'catalog_6', label: 'Catalog'),
    _CapabilityOption(key: 'sessions_7', label: 'Sessions'),
    _CapabilityOption(key: 'oversight_8', label: 'Oversight'),
    _CapabilityOption(key: 'corrections_9', label: 'Corrections'),
    _CapabilityOption(key: 'export_10', label: 'Export'),
    _CapabilityOption(key: 'dashboard_11', label: 'Dashboard'),
  ];

  String _buildCapabilitiesString() {
    return _capabilityOptions
        .where((option) => _selectedCapabilities.contains(option.key))
        .map((option) => option.key)
        .join(' | ');
  }

  @override
  void initState() {
    super.initState();
    _usernameCtrl.text = widget.user.username;
    _nameCtrl.text = widget.user.fullName;
    _role = widget.user.roleCode;
    _selectedZoneId = widget.user.zoneId;
    if (widget.user.zoneId != null) {
      _selectedZoneId = widget.user.zoneId;
    }
    _loadZones();
  }

  Future<void> _loadZones() async {
    try {
      _zones = await ZoneService.instance.list();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  String _roleName(int code) {
    switch (code) {
      case UserRole.admin:
        return 'admin';
      case UserRole.operator_:
        return 'operator';
      case UserRole.validator:
        return 'validator';
      case UserRole.coordinateur:
        return 'Coordinateur';
      default:
        return 'viewer';
    }
  }

  Future<void> _update() async {
    final username = _usernameCtrl.text.trim();
    final name = _nameCtrl.text.trim();

    if (username.isEmpty || name.isEmpty) {
      setState(() => _error = 'Username and full name required');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final fields = <String, dynamic>{
        'username': username,
        'full_name': name,
        'role': _roleName(_role),
      };

      if (_selectedCapabilities.isNotEmpty) {
        fields['capabilities'] = _buildCapabilitiesString();
      }

      if (_selectedZoneId != null) {
        fields['id_zone'] = _selectedZoneId;
      }

      final code =
          await AuthService.instance.updateUser(widget.user.id, fields);

      if (code == 0) {
        widget.onUpdated();
        if (mounted) Navigator.pop(context);
      } else {
        setState(() => _error = 'Update failed — code $code');
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit User — ${widget.user.username}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.badge_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _usernameCtrl,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline, size: 18),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Permissions',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(letterSpacing: 1)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _capabilityOptions.map((option) {
                  final selected = _selectedCapabilities.contains(option.key);
                  return ChoiceChip(
                    label: Text(option.label),
                    selected: selected,
                    selectedColor:
                        Theme.of(context).colorScheme.primary.withOpacity(0.15),
                    onSelected: (_) => setState(() {
                      if (selected) {
                        _selectedCapabilities.remove(option.key);
                      } else {
                        _selectedCapabilities.add(option.key);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              ...(_zones.isNotEmpty
                  ? [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('ZONE',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(letterSpacing: 1)),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        value: _selectedZoneId,
                        isExpanded: true,
                        items: _zones
                            .map((zone) => DropdownMenuItem<int>(
                                  value: zone.id,
                                  child: Text('${zone.code} - ${zone.name}'),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedZoneId = value),
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(), isDense: true),
                      ),
                      const SizedBox(height: 16),
                    ]
                  : []),
              _RolePicker(
                selected: _role,
                onSelected: (r) => setState(() => _role = r),
              ),
              ...(_error.isNotEmpty
                  ? [
                      const SizedBox(height: 12),
                      _ErrorText(error: _error),
                    ]
                  : []),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _update,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ============================================================================
// ROLE PICKER
// ============================================================================

class _RolePicker extends StatelessWidget {
  final int selected;
  final void Function(int) onSelected;

  const _RolePicker({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROLE',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _RoleOption(
              label: 'Operator',
              role: UserRole.operator_,
              selected: selected,
              color: AppTheme.primaryBlue,
              onTap: () => onSelected(UserRole.operator_),
            ),
            const SizedBox(width: 8),
            _RoleOption(
              label: 'Validator',
              role: UserRole.validator,
              selected: selected,
              color: AppTheme.warning,
              onTap: () => onSelected(UserRole.validator),
            ),
            const SizedBox(width: 8),
            _RoleOption(
              label: 'Coordinateur',
              role: UserRole.coordinateur,
              selected: selected,
              color: AppTheme.warning,
              onTap: () => onSelected(UserRole.coordinateur),
            ),
            const SizedBox(width: 8),
            _RoleOption(
              label: 'Admin',
              role: UserRole.admin,
              selected: selected,
              color: AppTheme.accentCyan,
              onTap: () => onSelected(UserRole.admin),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoleOption extends StatelessWidget {
  final String label;
  final int role;
  final int selected;
  final Color color;
  final VoidCallback onTap;

  const _RoleOption({
    required this.label,
    required this.role,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = role == selected;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? color.withOpacity(0.4)
                : Theme.of(context).colorScheme.outline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? color
                : Theme.of(context).textTheme.bodyMedium?.color,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SHARED WIDGETS
// ============================================================================

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool isDark;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 48,
              color: isDark ? AppTheme.darkTextHint : AppTheme.lightTextHint,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}

class _ErrorText extends StatelessWidget {
  final String error;
  const _ErrorText({required this.error});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppTheme.error.withOpacity(0.3),
          ),
        ),
        child: Text(
          error,
          style: const TextStyle(
            color: AppTheme.error,
            fontSize: 12,
          ),
        ),
      );
}
/*```

**What's in this file:**
```
✅ User list with search + role filter chips
✅ User card
   → avatar with role color
   → YOU badge on current user
   → active/inactive dot
   → role badge + last login
   → reset password + delete buttons
   → no actions on self (cannot delete yourself)
✅ Create user dialog
   → full name + username + password
   → show/hide password toggle
   → role picker (operator/validator/admin)
   → validation — all fields + min 6 chars
✅ Reset password dialog
   → new password + confirm
   → passwords must match
   → min 6 chars validation
✅ Delete user dialog
   → confirmation with warning message
   → success/error snackbar after action
✅ Role filter chips — all/admin/operator/validator
✅ Search — username + full name
✅ Empty state for no results */
