import 'dart:async';
import 'package:flutter/material.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';

import 'package:waste_tracking/ffi/services/admin_service.dart';
import 'package:waste_tracking/ffi/models/correction.dart';
import 'package:waste_tracking/theme/app_theme.dart' hide SectionHeader;
import 'package:waste_tracking/ffi/screens/shared/section_header.dart';

class CorrectionsScreen extends StatefulWidget {
  const CorrectionsScreen({super.key});

  @override
  State<CorrectionsScreen> createState() => _CorrectionsScreenState();
}

class _CorrectionsScreenState extends State<CorrectionsScreen> {
  List<Correction> _all = [];
  List<Correction> _filtered = [];
  bool _loading = true;

  // Filters
  String _tableFilter = 'all';
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

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
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await AdminService.instance.listCorrections();
      if (mounted) {
        setState(() {
          _all = list;
          _applyFilter();
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    _filtered = _all.where((c) {
      final matchTable = _tableFilter == 'all' || c.tableName == _tableFilter;
      final matchSearch = _searchQuery.isEmpty ||
          c.userName.toLowerCase().contains(_searchQuery) ||
          c.reason.toLowerCase().contains(_searchQuery) ||
          c.recordId.toString().contains(_searchQuery);
      return matchTable && matchSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
              child: SectionHeader(
                title: 'Corrections',
                subtitle: '${_filtered.length} audit entries',
                trailing: OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                ),
              ),
            ),
          ),

          // ── Filters ─────────────────────────────────────────────────
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
                        hintText: 'Search by user, reason, record ID...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Table filter chips
                  _TableFilterChips(
                    selected: _tableFilter,
                    onSelected: (t) => setState(() {
                      _tableFilter = t;
                      _applyFilter();
                    }),
                  ),
                ],
              ),
            ),
          ),

          // ── List ────────────────────────────────────────────────────
          _loading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              : _filtered.isEmpty
                  ? SliverFillRemaining(
                      child: _EmptyState(isDark: isDark),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(32, 20, 32, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _CorrectionCard(
                              correction: _filtered[i],
                              isDark: isDark,
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
// CORRECTION CARD
// ============================================================================

class _CorrectionCard extends StatelessWidget {
  final Correction correction;
  final bool isDark;

  const _CorrectionCard({
    required this.correction,
    required this.isDark,
  });

  Color _tableColor() {
    switch (correction.tableName) {
      case 'weighings':
        return AppTheme.primaryBlue;
      case 'reconciliations':
        return AppTheme.accentCyan;
      case 'shipments':
        return AppTheme.warning;
      default:
        return AppTheme.darkTextHint;
    }
  }

  IconData _tableIcon() {
    switch (correction.tableName) {
      case 'weighings':
        return Icons.scale_outlined;
      case 'reconciliations':
        return Icons.qr_code_scanner_outlined;
      case 'shipments':
        return Icons.local_shipping_outlined;
      default:
        return Icons.edit_note_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tableColor = _tableColor();

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
          // ── Header bar ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: tableColor.withOpacity(0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
              ),
            ),
            child: Row(
              children: [
                // Table icon + label
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: tableColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(_tableIcon(), color: tableColor, size: 13),
                ),
                const SizedBox(width: 8),
                Text(
                  correction.tableName.toUpperCase().replaceAll('_', ' '),
                  style: TextStyle(
                    color: tableColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                // Record ID badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: tableColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: tableColor.withOpacity(0.25)),
                  ),
                  child: Text(
                    '#${correction.recordId}',
                    style: TextStyle(
                      color: tableColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                // Time
                Text(
                  _timeAgo(correction.createdAt),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),

          // ── Body ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User avatar
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppTheme.primaryBlue.withOpacity(0.2)),
                  ),
                  child: Center(
                    child: Text(
                      correction.userName.isNotEmpty
                          ? correction.userName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: AppTheme.primaryBlue,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // User name
                      Text(
                        correction.userName.isNotEmpty
                            ? correction.userName
                            : 'Unknown user',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      // Date
                      Text(
                        _formatDate(correction.createdAt),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      // Reason
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark
                                ? AppTheme.darkBorder
                                : AppTheme.lightBorder,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.format_quote,
                              size: 14,
                              color: isDark
                                  ? AppTheme.darkTextHint
                                  : AppTheme.lightTextHint,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                correction.reason,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

  String _formatDate(String ts) {
    if (ts.isEmpty) return '';
    try {
      final d = DateTime.parse(ts);
      return '${d.year}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}  '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return ts.length > 16 ? ts.substring(0, 16) : ts;
    }
  }
}

// ============================================================================
// TABLE FILTER CHIPS
// ============================================================================

class _TableFilterChips extends StatelessWidget {
  final String selected;
  final void Function(String) onSelected;

  const _TableFilterChips({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        'all',
        'weighings',
        'reconciliations',
        'shipments',
      ].map((t) {
        final isSelected = selected == t;
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: FilterChip(
            label: Text(
              t == 'all' ? 'All' : t[0].toUpperCase() + t.substring(1),
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.white : null,
              ),
            ),
            selected: isSelected,
            onSelected: (_) => onSelected(t),
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
              Icons.edit_note_outlined,
              size: 48,
              color: isDark ? AppTheme.darkTextHint : AppTheme.lightTextHint,
            ),
            const SizedBox(height: 12),
            Text(
              'No corrections found',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Corrections appear here when operators amend records',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}
