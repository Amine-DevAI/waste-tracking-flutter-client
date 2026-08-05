import 'package:flutter/material.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';

import 'package:waste_tracking/ffi/services/admin_service.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';
import 'package:waste_tracking/ffi/engine.dart';

import 'package:waste_tracking/ffi/models/flag.dart';
import 'package:waste_tracking/ffi/models/weighing.dart';
import 'package:waste_tracking/ffi/models/reconciliation.dart';
import 'package:waste_tracking/ffi/models/shipment.dart';
import 'package:waste_tracking/ffi/models/denaturation.dart';

import 'package:waste_tracking/theme/app_theme.dart' hide SectionHeader;
import 'package:waste_tracking/ffi/screens/shared/section_header.dart';

class OversightScreen extends StatefulWidget {
  const OversightScreen({super.key});

  @override
  State<OversightScreen> createState() => _OversightScreenState();
}

class _OversightScreenState extends State<OversightScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  List<Weighing> _weighings = [];
  List<Reconciliation> _recos = [];
  List<Shipment> _shipments = [];
  List<Denaturation> _denats = [];
  List<Flag> _flags = [];

  bool _loading = true;

  // Filters
  String _weighStatus = '';
  String _recoStatus = '';
  String _shipFilter = 'all';
  String _denatStatus = 'all';
  String _flagTable = 'all';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) _loadCurrentTab();
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadWeighings(),
      _loadRecos(),
      _loadShipments(),
      _loadDenats(),
      _loadFlags(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadCurrentTab() async {
    setState(() => _loading = true);
    switch (_tab.index) {
      case 0:
        await _loadWeighings();
        break;
      case 1:
        await _loadRecos();
        break;
      case 2:
        await _loadShipments();
        break;
      case 3:
        await _loadDenats();
        break;
      case 4:
        await _loadFlags();
        break;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadWeighings() async {
    final f = _weighStatus.isEmpty ? '{}' : '{"status":"$_weighStatus"}';
    final list = await AdminService.instance.listWeighings(filters: f);
    if (mounted) setState(() => _weighings = list);
  }

  Future<void> _loadRecos() async {
    final list = await AdminService.instance
        .listReconciliationsFiltered(statusFilter: _recoStatus);
    if (mounted) setState(() => _recos = list);
  }

  Future<void> _loadShipments() async {
    final list = await AdminService.instance
        .listShipmentsFiltered(statusFilter: _shipFilter);
    if (mounted) setState(() => _shipments = list);
  }

  Future<void> _loadDenats() async {
    final list = await AdminService.instance
        .listDenaturationsFiltered(statusFilter: _denatStatus);
    if (mounted) setState(() => _denats = list);
  }

  Future<void> _loadFlags() async {
    final list = await AdminService.instance.listFlags(
      tableName: _flagTable == 'all' ? '' : _flagTable,
    );
    if (mounted) setState(() => _flags = list);
  }

  Future<void> _approveFlag(Flag flag) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve Flag'),
        content: Text('Mark flag #${flag.id} on ${flag.tableName} '
            '#${flag.recordId} as resolved?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final code = await AdminService.instance.approveFlag(flag.id);
    if (!mounted) return;
    _loadFlags();
    _snack(
      code == 0 ? 'Flag approved' : 'Failed — code $code',
      code == 0 ? AppTheme.success : AppTheme.error,
    );
  }

  Future<void> _rejectFlag(Flag flag) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resolve Flag'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Mark flag #${flag.id} on '
                '${flag.tableName} #${flag.recordId} as resolved?'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Reason for resolution...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    if (ok != true) {
      ctrl.dispose();
      return;
    }
    final reason = ctrl.text.trim();
    ctrl.dispose();
    final code = await AdminService.instance.rejectFlag(flag.id, reason);
    if (!mounted) return;
    _loadFlags();
    _snack(
      code == 0
          ? reason.isNotEmpty
              ? 'Flag resolved: $reason'
              : 'Flag resolved'
          : 'Failed — code $code',
      code == 0 ? AppTheme.error : AppTheme.error,
    );
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
            child: SectionHeader(
              title: 'Oversight',
              subtitle: 'total-view across all workflow tables',
              trailing: OutlinedButton.icon(
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh all'),
              ),
            ),
          ),

          // Tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              tabs: [
                _TabLabel(icon: Icons.scale_outlined, label: 'Weighings'),
                _TabLabel(
                    icon: Icons.qr_code_scanner_outlined,
                    label: 'Reconciliations'),
                _TabLabel(
                    icon: Icons.local_shipping_outlined, label: 'Shipments'),
                _TabLabel(icon: Icons.science_outlined, label: 'Denaturation'),
                _TabLabel(icon: Icons.flag_outlined, label: 'Flags'),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tab,
                    children: [
                      // ── Weighings ──────────────────────────────────
                      _ListTab(
                        filterRow: _StatusRow(
                          options: [
                            '',
                            'pending_reconciliation',
                            'approved',
                            'shipped'
                          ],
                          labels: ['All', 'Pending', 'Approved', 'Shipped'],
                          selected: _weighStatus,
                          onSelect: (s) {
                            setState(() => _weighStatus = s);
                            _loadWeighings();
                          },
                        ),
                        empty: 'No weighings',
                        isDark: isDark,
                        items: _weighings
                            .map((w) => _RowData(
                                  id: w.id,
                                  title:
                                      w.material.isNotEmpty ? w.material : '—',
                                  subtitle:
                                      '${w.weightNet.toStringAsFixed(2)} kg'
                                      '${w.operatorName.isNotEmpty ? ' · ${w.operatorName}' : ''}'
                                      '${w.product.isNotEmpty ? ' · ${w.product}' : ''}',
                                  status: w.status,
                                  date: w.createdAtFormatted,
                                  flagged: w.isFlagged,
                                ))
                            .toList(),
                      ),

                      // ── Reconciliations ────────────────────────────
                      _ListTab(
                        filterRow: _StatusRow(
                          options: ['', 'pending', 'approved', 'rejected'],
                          labels: ['All', 'Pending', 'Approved', 'Rejected'],
                          selected: _recoStatus,
                          onSelect: (s) {
                            setState(() => _recoStatus = s);
                            _loadRecos();
                          },
                        ),
                        empty: 'No reconciliations',
                        isDark: isDark,
                        items: _recos
                            .map((r) => _RowData(
                                  id: r.id,
                                  title:
                                      r.material.isNotEmpty ? r.material : '—',
                                  subtitle:
                                      'Net: ${r.originalWeight.toStringAsFixed(2)} kg'
                                      '${r.validatorName != null ? ' · ${r.validatorName}' : ''}',
                                  status: r.status,
                                  date: '',
                                  flagged: r.isFlagged,
                                ))
                            .toList(),
                      ),

                      // ── Shipments ──────────────────────────────────
                      _ListTab(
                        filterRow: _StatusRow(
                          options: ['', 'pending', 'shipped', 'cancelled'],
                          labels: ['All', 'Pending', 'Shipped', 'Cancelled'],
                          selected: _shipFilter,
                          onSelect: (s) {
                            setState(() => _shipFilter = s);
                            _loadShipments();
                          },
                        ),
                        empty: 'No shipments',
                        isDark: isDark,
                        items: _shipments
                            .map((s) => _RowData(
                                  id: s.id,
                                  title: s.product.isNotEmpty ? s.product : '—',
                                  subtitle: '${s.weight.toStringAsFixed(2)} kg'
                                      '${s.zone.isNotEmpty ? ' · ${s.zone}' : ''}'
                                      '${s.shipper.isNotEmpty ? ' · ${s.shipper}' : ''}',
                                  status: s.status,
                                  date: s.createdAt.length > 10
                                      ? s.createdAt.substring(0, 10)
                                      : s.createdAt,
                                  flagged: s.isFlagged,
                                ))
                            .toList(),
                      ),

                      // ── Denaturation ───────────────────────────────
                      _ListTab(
                        filterRow: _StatusRow(
                          options: ['all', 'pending', 'completed'],
                          labels: ['All', 'Pending', 'Completed'],
                          selected: _denatStatus,
                          onSelect: (s) {
                            setState(() => _denatStatus = s);
                            _loadDenats();
                          },
                        ),
                        empty: 'No denaturation operations',
                        isDark: isDark,
                        items: _denats
                            .map((d) => _RowData(
                                  id: d.id,
                                  title:
                                      d.material.isNotEmpty ? d.material : '—',
                                  subtitle:
                                      'Before: ${d.weightBefore.toStringAsFixed(2)} kg'
                                      '${d.weightNetAfter != null ? ' → After: ${d.weightNetAfter!.toStringAsFixed(2)} kg' : ''}'
                                      '${d.coordinatorName != null ? ' · ${d.coordinatorName}' : ''}',
                                  status: d.status,
                                  date: d.createdAt.length > 10
                                      ? d.createdAt.substring(0, 10)
                                      : d.createdAt,
                                  flagged: false,
                                ))
                            .toList(),
                      ),

                      // ── Flags ──────────────────────────────────────
                      _FlagsTab(
                        flags: _flags,
                        tableFilter: _flagTable,
                        onFilter: (t) {
                          setState(() => _flagTable = t);
                          _loadFlags();
                        },
                        onApprove: _approveFlag,
                        onReject: _rejectFlag,
                        isDark: isDark,
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
// ROW DATA — plain data class, no model dependency
// ============================================================================

class _RowData {
  final int id;
  final String title;
  final String subtitle;
  final String status;
  final String date;
  final bool flagged;

  const _RowData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.date,
    required this.flagged,
  });
}

// ============================================================================
// TAB LABEL
// ============================================================================

class _TabLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TabLabel({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      );
}

// ============================================================================
// GENERIC LIST TAB
// ============================================================================

class _ListTab extends StatelessWidget {
  final Widget filterRow;
  final List<_RowData> items;
  final String empty;
  final bool isDark;

  const _ListTab({
    required this.filterRow,
    required this.items,
    required this.empty,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          filterRow,
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      empty,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _Row(data: items[i], isDark: isDark),
                  ),
          ),
        ],
      );
}

// ============================================================================
// ROW WIDGET
// ============================================================================

class _Row extends StatelessWidget {
  final _RowData data;
  final bool isDark;

  const _Row({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: data.flagged
              ? AppTheme.warning.withOpacity(0.4)
              : isDark
                  ? AppTheme.darkBorder
                  : AppTheme.lightBorder,
        ),
      ),
      child: Row(
        children: [
          // ID
          SizedBox(
            width: 44,
            child: Text(
              '#${data.id}',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 10),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        data.title,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (data.flagged) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.flag,
                        size: 11,
                        color: AppTheme.warning,
                      ),
                    ],
                  ],
                ),
                if (data.subtitle.isNotEmpty)
                  Text(
                    data.subtitle,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Date
          if (data.date.isNotEmpty) ...[
            Text(
              data.date.length > 10 ? data.date.substring(0, 10) : data.date,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(width: 12),
          ],
          // Status badge
          _StatusBadge(status: data.status),
        ],
      ),
    );
  }
}

// ============================================================================
// FLAGS TAB — has approve/reject actions
// ============================================================================

class _FlagsTab extends StatelessWidget {
  final List<Flag> flags;
  final String tableFilter;
  final void Function(String) onFilter;
  final void Function(Flag) onApprove;
  final void Function(Flag) onReject;
  final bool isDark;

  const _FlagsTab({
    required this.flags,
    required this.tableFilter,
    required this.onFilter,
    required this.onApprove,
    required this.onReject,
    required this.isDark,
  });

  Color _tableColor(String t) {
    switch (t) {
      case 'weighings':
        return AppTheme.primaryBluee;
      case 'reconciliations':
        return AppTheme.accentCyan;
      case 'shipments':
        return AppTheme.warning;
      case 'denaturation_operations':
        return AppTheme.error;
      default:
        return AppTheme.darkTextHint;
    }
  }

  IconData _tableIcon(String t) {
    switch (t) {
      case 'weighings':
        return Icons.scale_outlined;
      case 'reconciliations':
        return Icons.qr_code_scanner_outlined;
      case 'shipments':
        return Icons.local_shipping_outlined;
      case 'denaturation_operations':
        return Icons.science_outlined;
      default:
        return Icons.flag_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Table filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 12, 32, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                'all',
                'weighings',
                'reconciliations',
                'shipments',
                'denaturation_operations',
              ].map((t) {
                final sel = tableFilter == t;
                final color = t == 'all' ? AppTheme.primaryBluee : _tableColor(t);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(
                      t == 'all'
                          ? 'All'
                          : t == 'denaturation_operations'
                              ? 'Denaturation'
                              : t[0].toUpperCase() + t.substring(1),
                      style: TextStyle(
                        fontSize: 11,
                        color: sel ? Colors.white : null,
                      ),
                    ),
                    selected: sel,
                    onSelected: (_) => onFilter(t),
                    selectedColor: color,
                    checkmarkColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Flag list
        Expanded(
          child: flags.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        size: 40,
                        color: isDark
                            ? AppTheme.darkTextHint
                            : AppTheme.lightTextHint,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No active flags',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
                  itemCount: flags.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final f = flags[i];
                    final color = _tableColor(f.tableName);
                    return Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark
                              ? AppTheme.darkBorder
                              : AppTheme.lightBorder,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.05),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10),
                              ),
                              border: Border(
                                bottom: BorderSide(
                                  color: isDark
                                      ? AppTheme.darkBorder
                                      : AppTheme.lightBorder,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Icon(
                                    _tableIcon(f.tableName),
                                    color: color,
                                    size: 13,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  f.tableName
                                      .toUpperCase()
                                      .replaceAll('_', ' '),
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '#${f.recordId}',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const Spacer(),
                                _StatusBadge(status: f.status),
                                const SizedBox(width: 8),
                                Text(
                                  _ago(f.createdAt),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          // Body
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        f.reason,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                      if (f.flaggedBy.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'By ${f.flaggedBy}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // Actions — only on pending flags
                                if (f.isPending) ...[
                                  const SizedBox(width: 12),
                                  OutlinedButton(
                                    onPressed: () => onReject(f),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                          color: AppTheme.error),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                    ),
                                    child: const Text(
                                      'Resolve',
                                      style: TextStyle(
                                        color: AppTheme.error,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton(
                                    onPressed: () => onApprove(f),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.success,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                    ),
                                    child: const Text(
                                      'Approve',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _ago(String ts) {
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
// STATUS ROW — filter chips
// ============================================================================

class _StatusRow extends StatelessWidget {
  final List<String> options;
  final List<String> labels;
  final String selected;
  final void Function(String) onSelect;

  const _StatusRow({
    required this.options,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 12, 32, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(
                options.length,
                (i) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 11,
                            color: selected == options[i] ? Colors.white : null,
                          ),
                        ),
                        selected: selected == options[i],
                        onSelected: (_) => onSelect(options[i]),
                        selectedColor: AppTheme.primaryBluee,
                        checkmarkColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                    )),
          ),
        ),
      );
}

// ============================================================================
// STATUS BADGE — inline, no external dependency
// ============================================================================

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color _color() {
    switch (status.toLowerCase()) {
      case 'pending':
      case 'pending_reconciliation':
        return AppTheme.warning;
      case 'scanned':
        return AppTheme.accentCyan;
      case 'approved':
      case 'completed':
      case 'shipped':
        return AppTheme.success;
      case 'rejected':
      case 'cancelled':
        return AppTheme.error;
      default:
        return AppTheme.darkTextHint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.toUpperCase().replaceAll('_', ' '),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
