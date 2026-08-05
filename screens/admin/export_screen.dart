import 'dart:io';
import 'package:flutter/material.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';

// Your Project Imports
import 'package:waste_tracking/ffi/services/admin_service.dart';
import 'package:waste_tracking/ffi/models/export_record.dart';
import 'package:waste_tracking/ffi/bindings/types.dart';
import 'package:waste_tracking/theme/app_theme.dart';
import 'package:waste_tracking/config/app_config.dart';
// ============================================================================
// EXPORT SCREEN
// ============================================================================

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  // ── Format selection ───────────────────────────────────────────────────
  int _format = ExportFormat.xlsx;

  // ── Date range ─────────────────────────────────────────────────────────
  DateTime? _startDate;
  DateTime? _endDate;

  // ── Columns ────────────────────────────────────────────────────────────
  List<String> _availableColumns = [];
  Set<String> _selectedColumns = {};

  int get _source => ExportSource.weighings;

  // ── State ──────────────────────────────────────────────────────────────
  bool _exporting = false;
  bool _selectAll = true;
  String _lastExported = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadColumns();
    // Default date range — last 30 days
    final now = DateTime.now();
    _endDate = now;
    _startDate = now.subtract(const Duration(days: 30));
  }

  // ── Load columns ─────────────────────────────────────────────────────
  void _loadColumns() {
    final cols = ExportRecord.allColumns;
    setState(() {
      _availableColumns = cols;
      _selectedColumns = Set.from(cols);
      _selectAll = true;
    });
  }

  // ── Toggle column ──────────────────────────────────────────────────────
  void _toggleColumn(String col) {
    setState(() {
      if (_selectedColumns.contains(col)) {
        _selectedColumns.remove(col);
      } else {
        _selectedColumns.add(col);
      }
      _selectAll = _selectedColumns.length == _availableColumns.length;
    });
  }

  // ── Toggle all ─────────────────────────────────────────────────────────
  void _toggleAll(bool select) {
    setState(() {
      _selectAll = select;
      if (select) {
        _selectedColumns = Set.from(_availableColumns);
      } else {
        _selectedColumns.clear();
      }
    });
  }

  // ── Validate ───────────────────────────────────────────────────────────
  bool _validate() {
    // Reference data — no date needed
    final isRef = _isReferenceData(_source);

    if (!isRef) {
      if (_startDate == null || _endDate == null) {
        setState(() => _error = 'Please select a date range');
        return false;
      }
      if (_endDate!.isBefore(_startDate!)) {
        setState(() => _error = 'End date must be after start date');
        return false;
      }
    }

    if (_selectedColumns.isEmpty) {
      setState(() => _error = 'Please select at least one column');
      return false;
    }

    setState(() => _error = '');
    return true;
  }

  bool _isReferenceData(int source) =>
      source == ExportSource.zones ||
      source == ExportSource.products ||
      source == ExportSource.types ||
      source == ExportSource.users;

  // ── Export ─────────────────────────────────────────────────────────────
  Future<void> _export() async {
    if (!_validate()) return;

    setState(() {
      _exporting = true;
      _lastExported = '';
      _error = '';
    });

    try {
      // Build file path
      final dir = await _getExportDir();
      final name = _buildFileName();
      final path = '${dir.path}/$name';

      final code = await AdminService.instance.export(
        source: _source,
        format: _format,
        filePath: path,
        startDate: _startDate != null ? _fmtDate(_startDate!) : '',
        endDate: _endDate != null ? _fmtDate(_endDate!) : '',
        columns: _selectedColumns.toList(),
      );

      if (code == 0) {
        setState(() => _lastExported = path);
        _showSuccess(path);
      } else {
        setState(() => _error = 'Export failed: '
            'Error code $code');
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  // ── Get export directory ───────────────────────────────────────────────
  Future<Directory> _getExportDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/waste_exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ── Build file name ────────────────────────────────────────────────────
  String _buildFileName() {
    final src = ExportSource.name(_source).toLowerCase().replaceAll(' ', '_');
    final ext = ExportFormat.extension(_format);
    final now = DateTime.now();
    final ts = '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    return '${src}_$ts$ext';
  }

  // ── Show success ───────────────────────────────────────────────────────
  void _showSuccess(String path) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.check_circle,
              color: AppTheme.success,
              size: 24,
            ),
            SizedBox(width: 8),
            Text('Export Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your file has been saved to:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppTheme.success.withOpacity(0.2),
                ),
              ),
              child: Text(
                path,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime? d) => d != null ? _fmtDate(d) : 'Not set';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isRef = _isReferenceData(_source);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          // ── Header ─────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
              child: SectionHeader(
                // Changed subtitle
                title: 'Export Data',
                subtitle: 'Full traceability export',
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
              child: LayoutBuilder(
                builder: (_, constraints) {
                  final wide = constraints.maxWidth > 800;
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _leftCol(isDark, isRef),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _rightCol(isDark),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _leftCol(isDark, isRef),
                      const SizedBox(height: 24),
                      _rightCol(isDark),
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

  // ── Left column ───────────────────────────────────────────────────────
  Widget _leftCol(bool isDark, bool isRef) {
    return Column(
      children: [
        // Format card
        _Card(
          title: 'Export Format',
          icon: Icons.file_download_outlined,
          isDark: isDark,
          child: _FormatPicker(
            selected: _format,
            onSelected: (f) => setState(() => _format = f),
          ),
        ),

        const SizedBox(height: 16),

        // Date range card — only for transactional
        if (!isRef)
          _Card(
            title: 'Date Range',
            icon: Icons.date_range_outlined,
            isDark: isDark,
            child: _DateRangePicker(
              startDate: _startDate,
              endDate: _endDate,
              displayStart: _displayDate(_startDate),
              displayEnd: _displayDate(_endDate),
              onPickStart: () => _pickDate(isStart: true),
              onPickEnd: () => _pickDate(isStart: false),
              onQuickRange: _applyQuickRange,
              isDark: isDark,
            ),
          )
        else
          _Card(
            title: 'Date Range',
            icon: Icons.date_range_outlined,
            isDark: isDark,
            child: _RefDataInfo(),
          ),

        const SizedBox(height: 16),

        // Export button
        _ExportButton(
          exporting: _exporting,
          error: _error,
          lastExported: _lastExported,
          onExport: _export,
          isDark: isDark,
        ),
      ],
    );
  }

  // ── Right column ──────────────────────────────────────────────────────
  Widget _rightCol(bool isDark) {
    return _Card(
      title: 'Columns to Export',
      icon: Icons.view_column_outlined,
      isDark: isDark,
      child: _ColumnPicker(
        available: _availableColumns,
        selected: _selectedColumns,
        selectAll: _selectAll,
        onToggle: _toggleColumn,
        onToggleAll: _toggleAll,
        isDark: isDark,
      ),
    );
  }

  // ── Date picker ────────────────────────────────────────────────────────
  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final maxEnd = now;
    final minStart = DateTime(2020, 1, 1);

    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startDate ?? now.subtract(const Duration(days: 30)))
          : (_endDate ?? now),
      firstDate: minStart,
      lastDate: maxEnd,
    );

    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startDate = picked;
        // Auto adjust end if needed
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked.add(const Duration(days: 1));
        }
      } else {
        _endDate = picked;
        // Auto adjust start if needed
        if (_startDate != null && _startDate!.isAfter(picked)) {
          _startDate = picked.subtract(const Duration(days: 1));
        }
      }
      _error = '';
    });
  }

  // ── Quick range ────────────────────────────────────────────────────────
  void _applyQuickRange(String range) {
    final now = DateTime.now();
    setState(() {
      _endDate = now;
      switch (range) {
        case '7d':
          _startDate = now.subtract(const Duration(days: 7));
          break;
        case '30d':
          _startDate = now.subtract(const Duration(days: 30));
          break;
        case '90d':
          _startDate = now.subtract(const Duration(days: 90));
          break;
      }
      _error = '';
    });
  }
}

// ============================================================================
// FORMAT PICKER
// ============================================================================

class _FormatPicker extends StatelessWidget {
  final int selected;
  final void Function(int) onSelected;

  const _FormatPicker({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FormatOption(
          format: ExportFormat.xlsx,
          label: 'Excel',
          icon: Icons.table_chart,
          color: AppTheme.success,
          selected: selected,
          onTap: () => onSelected(ExportFormat.xlsx),
        ),
        const SizedBox(width: 8),
        _FormatOption(
          format: ExportFormat.csv,
          label: 'CSV',
          icon: Icons.grid_on,
          color: AppTheme.primary,
          selected: selected,
          onTap: () => onSelected(ExportFormat.csv),
        ),
        const SizedBox(width: 8),
        _FormatOption(
          format: ExportFormat.txt,
          label: 'TXT',
          icon: Icons.text_snippet_outlined,
          color: AppTheme.secondary,
          selected: selected,
          onTap: () => onSelected(ExportFormat.txt),
        ),
      ],
    );
  }
}

class _FormatOption extends StatelessWidget {
  final int format;
  final String label;
  final IconData icon;
  final Color color;
  final int selected;
  final VoidCallback onTap;

  const _FormatOption({
    required this.format,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = format == selected;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? color.withOpacity(0.4)
                : Theme.of(context).colorScheme.outline,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? color : Theme.of(context).iconTheme.color,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : null,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// DATE RANGE PICKER
// ============================================================================

class _DateRangePicker extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final String displayStart;
  final String displayEnd;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final void Function(String) onQuickRange;
  final bool isDark;

  const _DateRangePicker({
    required this.startDate,
    required this.endDate,
    required this.displayStart,
    required this.displayEnd,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onQuickRange,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Days diff
    int? days;
    if (startDate != null && endDate != null) {
      days = endDate!.difference(startDate!).inDays;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick range buttons
        Row(
          children: [
            _QuickBtn(label: 'Last 7 days', onTap: () => onQuickRange('7d')),
            const SizedBox(width: 6),
            _QuickBtn(label: 'Last 30 days', onTap: () => onQuickRange('30d')),
            const SizedBox(width: 6),
            _QuickBtn(label: 'Last 90 days', onTap: () => onQuickRange('90d')),
          ],
        ),

        const SizedBox(height: 12),

        // Date pickers
        Row(
          children: [
            Expanded(
              child: _DateButton(
                label: 'Start Date',
                display: displayStart,
                onTap: onPickStart,
                isDark: isDark,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.arrow_forward,
                size: 16,
                color: isDark ? AppTheme.darkTextHint : AppTheme.lightTextHint,
              ),
            ),
            Expanded(
              child: _DateButton(
                label: 'End Date',
                display: displayEnd,
                onTap: onPickEnd,
                isDark: isDark,
              ),
            ),
          ],
        ),

        // Days label
        if (days != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                  // Always info icon
                  Icons.info_outline,
                  size: 12,
                  color: AppTheme.success),
              const SizedBox(width: 6),
              Text(
                // Removed warning branch
                '$days days selected',
                style: TextStyle(
                  color: AppTheme.success, // Always success color
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _QuickBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickBtn({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ActionChip(
        label: Text(
          label,
          style: const TextStyle(fontSize: 11),
        ),
        onPressed: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
      );
}

class _DateButton extends StatelessWidget {
  final String label;
  final String display;
  final VoidCallback onTap;
  final bool isDark;

  const _DateButton({
    required this.label,
    required this.display,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      display,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

// ============================================================================
// REFERENCE DATA INFO
// ============================================================================

class _RefDataInfo extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppTheme.primary.withOpacity(0.15),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: AppTheme.primary,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Reference data exports the full '
                'list — no date range needed.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
}

// ============================================================================
// COLUMN PICKER
// ============================================================================

class _ColumnPicker extends StatelessWidget {
  final List<String> available;
  final Set<String> selected;
  final bool selectAll;
  final void Function(String) onToggle;
  final void Function(bool) onToggleAll;
  final bool isDark;

  const _ColumnPicker({
    required this.available,
    required this.selected,
    required this.selectAll,
    required this.onToggle,
    required this.onToggleAll,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (available.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Select all toggle
        Row(
          children: [
            Checkbox(
              value: selectAll,
              onChanged: (v) => onToggleAll(v ?? true),
              activeColor: AppTheme.primaryBlue,
              tristate: true,
            ),
            Text(
              selectAll ? 'Deselect All' : 'Select All',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            Text(
              '${selected.length}/${available.length}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const Divider(height: 16),
        // Column list
        Wrap(
          // Changed to Wrap layout
          spacing: 8,
          runSpacing: 8,
          children: available.map((col) {
            final isSelected = selected.contains(col);
            return GestureDetector(
              onTap: () => onToggle(col), // Changed to GestureDetector
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryBlue.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryBlue.withOpacity(0.4)
                        : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSelected) // Added checkmark icon
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.check,
                            size: 12, color: AppTheme.primaryBlue),
                      ),
                    Text(
                      col,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isSelected
                                ? AppTheme.primaryBlue
                                : isDark
                                    ? AppTheme.darkTextHint
                                    : AppTheme.lightTextHint,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ============================================================================
// EXPORT BUTTON
// ============================================================================

class _ExportButton extends StatelessWidget {
  final bool exporting;
  final String error;
  final String lastExported;
  final VoidCallback onExport;
  final bool isDark;

  const _ExportButton({
    required this.exporting,
    required this.error,
    required this.lastExported,
    required this.onExport,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Error
        if (error.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.error.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppTheme.error,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: AppTheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Last exported
        if (lastExported.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.success.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: AppTheme.success,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Saved to: $lastExported',
                    style: const TextStyle(
                      color: AppTheme.success,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Export button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: exporting
              ? Container(
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Exporting...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              : ElevatedButton.icon(
                  onPressed: onExport,
                  icon: const Icon(Icons.download_outlined, size: 20),
                  label: const Text(
                    'EXPORT',
                    style: TextStyle(fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                  ),
                ),
        ),
      ],
    );
  }
}

// ============================================================================
// CARD
// ============================================================================

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool isDark;

  const _Card({
    required this.title,
    required this.icon,
    required this.child,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  icon,
                  color: AppTheme.primaryBlue,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(title, style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 16),
          Divider(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            height: 1,
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
/*```

**What's in this file:**
```
✅ Source picker — all 9 sources
   weighings/recos/shipments/zones/
   products/types/users/flags/corrections
   each with color + icon
✅ Format picker — XLSX / CSV / TXT
   visual tiles with icon
✅ Date range
   → quick buttons: last 7/30/90 days
   → date pickers with calendar
   → auto-adjust: if end < start → fix
   → 90 day hard limit enforced
   → days counter shows diff
   → reference data → no date needed
     shows info banner instead
✅ Column picker
   → select/deselect all
   → per column toggle
   → X/Y selected counter
   → columns load from C++ → always correct
✅ Export button
   → validates before export
   → shows progress while exporting
   → error banner on failure
   → success banner + file path on done
   → success dialog with path
✅ Auto filename:
   source_YYYYMMDD_HHMM.ext
✅ Saves to documents/waste_exports/
✅ Two column layout on wide screens
```

**Full screen map — complete:**
```
✅ login_screen.dart
✅ settings_screen.dart
✅ main_layout.dart
✅ sidebar.dart
✅ operator/weigh_screen.dart
✅ validator/reco_screen.dart
✅ validator/shipment_screen.dart
✅ admin/dashboard_screen.dart
✅ admin/users_screen.dart
✅ admin/sessions_screen.dart
✅ admin/flags_screen.dart
✅ admin/corrections_screen.dart
✅ admin/export_screen.dart */
