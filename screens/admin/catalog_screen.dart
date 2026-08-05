import 'dart:async';
import 'package:flutter/material.dart' hide MaterialType;
import 'package:waste_tracking/l10n/app_localizations.dart';
import 'package:waste_tracking/ffi/services/catalog_service.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';
import 'package:waste_tracking/ffi/services/zone_service.dart';
import 'package:waste_tracking/ffi/models/material_type.dart';
import 'package:waste_tracking/ffi/models/product.dart';
import 'package:waste_tracking/ffi/models/zone.dart';
import 'package:waste_tracking/theme/app_theme.dart' hide SectionHeader;
import 'package:waste_tracking/ffi/screens/shared/section_header.dart';

// ============================================================================
// CATALOG SCREEN — tabbed: Types / Products / Zones
// ============================================================================

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
            child: SectionHeader(
              title: 'Catalog & Zones',
              subtitle: 'Manage material types, products and storage zones',
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
              ),
              child: TabBar(
                controller: _tabCtrl,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppTheme.primaryBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                labelColor: Colors.white,
                unselectedLabelColor:
                    isDark ? AppTheme.darkTextSecond : AppTheme.lightTextSecond,
                labelStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.science_outlined, size: 16),
                    text: 'Material Types',
                    iconMargin: EdgeInsets.only(bottom: 2),
                  ),
                  Tab(
                    icon: Icon(Icons.medication_outlined, size: 16),
                    text: 'Products',
                    iconMargin: EdgeInsets.only(bottom: 2),
                  ),
                  Tab(
                    icon: Icon(Icons.warehouse_outlined, size: 16),
                    text: 'Storage Zones',
                    iconMargin: EdgeInsets.only(bottom: 2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: const [
                _TypesTab(),
                _ProductsTab(),
                _ZonesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TYPES TAB
// ============================================================================

class _TypesTab extends StatefulWidget {
  const _TypesTab();

  @override
  State<_TypesTab> createState() => _TypesTabState();
}

class _TypesTabState extends State<_TypesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<MaterialType> _types = [];
  List<MaterialType> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  StreamSubscription<String>? _refreshSub;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_filter);
    _refreshSub = AuthService.instance.onRefresh.listen((entity) {
      if (entity == 'TYPES' && mounted) _load();
    });
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final types = await CatalogService.instance.listTypes();
      if (mounted) {
        setState(() {
          _types = types;
          _filtered = types;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _types
          .where((t) =>
              q.isEmpty ||
              t.code.toLowerCase().contains(q) ||
              t.name.toLowerCase().contains(q) ||
              t.nature.toLowerCase().contains(q))
          .toList();
    });
  }

  Future<void> _showTypeDialog({MaterialType? type}) async {
    await showDialog(
      context: context,
      builder: (_) => _TypeDialog(type: type, onSaved: _load),
    );
  }

  Future<void> _deleteType(MaterialType type) async {
    final confirmed = await _confirmDelete(type.name);
    if (!confirmed) return;
    try {
      await CatalogService.instance.deleteType(type.id);
      _load();
      _showSnack('${type.name} deleted', AppTheme.success);
    } catch (e) {
      _showSnack('Error: $e', AppTheme.error);
    }
  }

  Future<bool> _confirmDelete(String name) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Delete $name?'),
            content: const Text('This will deactivate this item. '
                'Existing records will not be affected.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search types...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _showTypeDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Type'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? _EmptyState(
                      icon: Icons.science_outlined,
                      message: 'No material types found',
                      isDark: isDark,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _TypeCard(
                        type: _filtered[i],
                        isDark: isDark,
                        onEdit: () => _showTypeDialog(type: _filtered[i]),
                        onDelete: () => _deleteType(_filtered[i]),
                      ),
                    ),
        ),
      ],
    );
  }
}

// ============================================================================
// TYPE CARD
// ============================================================================

class _TypeCard extends StatelessWidget {
  final MaterialType type;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TypeCard({
    required this.type,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppTheme.tagColor(type.tagCode);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
          border: Border(
            left: BorderSide(color: color, width: 3),
            top: BorderSide(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            right: BorderSide(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            bottom: BorderSide(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Tag color dot
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Center(
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          type.code,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(color: color),
                        ),
                        const SizedBox(width: 8),
                        Text('—', style: theme.textTheme.bodySmall),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            type.name,
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _InfoChip(label: type.nature),
                        if (type.forme.isNotEmpty) _InfoChip(label: type.forme),
                        if (type.requiresLot)
                          _InfoChip(
                              label: 'Lot Required', color: AppTheme.warning),
                        if (type.requiresName)
                          _InfoChip(
                              label: 'Name Required',
                              color: AppTheme.primaryBlue),
                        if (type.requiresProduct)
                          _InfoChip(
                              label: 'Product Required',
                              color: AppTheme.success),
                        // ── NEW ──────────────────────────────────────────────
                        if (type.requiresDenaturation)
                          _InfoChip(
                              label: '⚗ Denaturation', color: AppTheme.error),
                        // ─────────────────────────────────────────────────────
                        TagBadge(
                          tagCode: type.tagCode,
                          showLabel: true,
                          size: 8,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Actions
              Row(
                children: [
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit',
                    color: AppTheme.primaryBlue,
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Delete',
                    color: AppTheme.error,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// TYPE DIALOG — create + edit
// ============================================================================

class _TypeDialog extends StatefulWidget {
  final MaterialType? type;
  final VoidCallback onSaved;

  const _TypeDialog({required this.onSaved, this.type});

  @override
  State<_TypeDialog> createState() => _TypeDialogState();
}

class _TypeDialogState extends State<_TypeDialog> {
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _natureCtrl = TextEditingController();
  final _formeCtrl = TextEditingController();

  int _tagCode = 3;
  bool _requiresLot = false;
  bool _requiresName = false;
  bool _requiresProduct = false;
  bool _requiresDenat = false;
  bool _loading = false;
  String _error = '';

  bool get _isEdit => widget.type != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final t = widget.type!;
      _codeCtrl.text = t.code;
      _nameCtrl.text = t.name;
      _natureCtrl.text = t.nature;
      _formeCtrl.text = t.forme;
      _tagCode = t.tagCode;
      _requiresLot = t.requiresLot;
      _requiresName = t.requiresName;
      _requiresProduct = t.requiresProduct;
      _requiresDenat = t.requiresDenaturation;
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _natureCtrl.dispose();
    _formeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final code = _codeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final nature = _natureCtrl.text.trim();

    if (code.isEmpty || name.isEmpty || nature.isEmpty) {
      setState(() => _error = 'Code, name and nature are required');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      if (_isEdit) {
        await CatalogService.instance.updateType(widget.type!.id, {
          'code': code,
          'name': name,
          'nature': nature,
          'forme': _formeCtrl.text.trim(),
          'tag_code': _tagCode,
          'requires_lot': _requiresLot,
          'requires_name': _requiresName,
          'requires_product': _requiresProduct,
          'requires_denaturation': _requiresDenat,
        });
      } else {
        await CatalogService.instance.createType(
          code: code,
          name: name,
          nature: nature,
          forme: _formeCtrl.text.trim(),
          tagCode: _tagCode,
          requiresLot: _requiresLot,
          requiresName: _requiresName,
          requiresProduct: _requiresProduct,
          requiresDenaturation: _requiresDenat,
        );
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Type' : 'New Material Type'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Code + Name
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Code *',
                        hintText: 'e.g. CYT-01',
                        prefixIcon: Icon(Icons.tag_outlined, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name *',
                        hintText: 'e.g. Cytotoxic Waste',
                        prefixIcon: Icon(Icons.label_outlined, size: 18),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Nature + Forme
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _natureCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nature *',
                        hintText: 'e.g. Pharmaceutical',
                        prefixIcon: Icon(Icons.category_outlined, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _formeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Form',
                        hintText: 'e.g. Solid / Liquid',
                        prefixIcon: Icon(Icons.science_outlined, size: 18),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Tag picker
              Text(
                'TAG COLOR',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _TagOption(
                      code: 0,
                      selected: _tagCode,
                      onTap: () => setState(() => _tagCode = 0)),
                  const SizedBox(width: 12),
                  _TagOption(
                      code: 2,
                      selected: _tagCode,
                      onTap: () => setState(() => _tagCode = 2)),
                  const SizedBox(width: 12),
                  _TagOption(
                      code: 3,
                      selected: _tagCode,
                      onTap: () => setState(() => _tagCode = 3)),
                ],
              ),

              const SizedBox(height: 20),

              // ── Requirements ───────────────────────────────────────────────
              Text(
                'REQUIREMENTS',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(letterSpacing: 1),
              ),
              const SizedBox(height: 8),

              _Toggle(
                label: 'Requires Lot Number',
                value: _requiresLot,
                onChanged: (v) => setState(() => _requiresLot = v),
              ),
              _Toggle(
                label: 'Requires Product Name',
                value: _requiresName,
                onChanged: (v) => setState(() => _requiresName = v),
              ),
              _Toggle(
                label: 'Requires Product',
                value: _requiresProduct,
                onChanged: (v) => setState(() => _requiresProduct = v),
              ),

              // Denaturation requirement (use existing _Toggle widget)

              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ErrorText(error: _error),
              ],
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
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

// ============================================================================
// PRODUCTS TAB
// ============================================================================

class _ProductsTab extends StatefulWidget {
  const _ProductsTab();

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Product> _products = [];
  List<Product> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  StreamSubscription<String>? _refreshSub;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_filter);
    _refreshSub = AuthService.instance.onRefresh.listen((entity) {
      if (entity == 'PRODUCTS' && mounted) _load();
    });
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final products = await CatalogService.instance.listProducts();
      if (mounted) {
        setState(() {
          _products = products;
          _filtered = products;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _products
          .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
          .toList();
    });
  }

  Future<void> _showProductDialog({Product? product}) async {
    await showDialog(
      context: context,
      builder: (_) => _ProductDialog(product: product, onSaved: _load),
    );
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await _confirmDelete(product.name);
    if (!confirmed) return;
    try {
      await CatalogService.instance.deleteProduct(product.id);
      _load();
      _showSnack('${product.name} deleted', AppTheme.success);
    } catch (e) {
      _showSnack('Error: $e', AppTheme.error);
    }
  }

  Future<bool> _confirmDelete(String name) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Delete $name?'),
          content: const Text('This will deactivate this product.'),
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
      ) ??
      false;

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search products...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _showProductDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Product'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? _EmptyState(
                      icon: Icons.medication_outlined,
                      message: 'No products found',
                      isDark: isDark,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _ProductCard(
                        product: _filtered[i],
                        isDark: isDark,
                        onEdit: () => _showProductDialog(product: _filtered[i]),
                        onDelete: () => _deleteProduct(_filtered[i]),
                      ),
                    ),
        ),
      ],
    );
  }
}

// ============================================================================
// PRODUCT CARD
// ============================================================================

class _ProductCard extends StatelessWidget {
  final Product product;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.product,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.medication_outlined,
                color: AppTheme.primaryBlue, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(product.name, style: theme.textTheme.titleSmall),
          ),
          Row(
            children: [
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit',
                color: AppTheme.primaryBlue,
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Delete',
                color: AppTheme.error,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PRODUCT DIALOG
// ============================================================================

class _ProductDialog extends StatefulWidget {
  final Product? product;
  final VoidCallback onSaved;

  const _ProductDialog({required this.onSaved, this.product});

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _nameCtrl = TextEditingController();
  bool _loading = false;
  String _error = '';

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _nameCtrl.text = widget.product!.name;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      if (_isEdit) {
        await CatalogService.instance.updateProduct(widget.product!.id, name);
      } else {
        await CatalogService.instance.createProduct(name);
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Product' : 'New Product'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Product Name *',
                hintText: 'e.g. Paclitaxel 150mg',
                prefixIcon: Icon(Icons.medication_outlined, size: 18),
              ),
              onSubmitted: (_) => _save(),
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
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

// ============================================================================
// ZONES TAB
// ============================================================================

class _ZonesTab extends StatefulWidget {
  const _ZonesTab();

  @override
  State<_ZonesTab> createState() => _ZonesTabState();
}

class _ZonesTabState extends State<_ZonesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Zone> _zones = [];
  List<Zone> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  StreamSubscription<String>? _refreshSub;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_filter);
    _refreshSub = AuthService.instance.onRefresh.listen((entity) {
      if (entity == 'ZONES' && mounted) _load();
    });
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final zones = await ZoneService.instance.list();
      if (mounted) {
        setState(() {
          _zones = zones;
          _filtered = zones;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _zones
          .where((z) =>
              q.isEmpty ||
              z.code.toLowerCase().contains(q) ||
              z.name.toLowerCase().contains(q))
          .toList();
    });
  }

  Future<void> _showZoneDialog({Zone? zone}) async {
    await showDialog(
      context: context,
      builder: (_) => _ZoneDialog(zone: zone, onSaved: _load),
    );
  }

  Future<void> _deleteZone(Zone zone) async {
    final confirmed = await _confirmDelete(zone.name);
    if (!confirmed) return;
    try {
      await ZoneService.instance
          .update(zone.id, zone.code, zone.name, active: false);
      _load();
      _showSnack('${zone.name} deleted', AppTheme.success);
    } catch (e) {
      _showSnack('Error: $e', AppTheme.error);
    }
  }

  Future<bool> _confirmDelete(String name) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Delete $name?'),
          content: const Text('This will deactivate this zone.'),
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
      ) ??
      false;

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search zones...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _showZoneDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Zone'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? _EmptyState(
                      icon: Icons.warehouse_outlined,
                      message: 'No zones found',
                      isDark: isDark,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _ZoneCard(
                        zone: _filtered[i],
                        isDark: isDark,
                        onEdit: () => _showZoneDialog(zone: _filtered[i]),
                        onDelete: () => _deleteZone(_filtered[i]),
                      ),
                    ),
        ),
      ],
    );
  }
}

// ============================================================================
// ZONE CARD
// ============================================================================

class _ZoneCard extends StatelessWidget {
  final Zone zone;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ZoneCard({
    required this.zone,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.warehouse_outlined,
                color: AppTheme.success, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Text(zone.code,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: AppTheme.success)),
                const SizedBox(width: 8),
                Text('—', style: theme.textTheme.bodySmall),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(zone.name,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit',
                color: AppTheme.primaryBlue,
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Delete',
                color: AppTheme.error,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ZONE DIALOG
// ============================================================================

class _ZoneDialog extends StatefulWidget {
  final Zone? zone;
  final VoidCallback onSaved;

  const _ZoneDialog({required this.onSaved, this.zone});

  @override
  State<_ZoneDialog> createState() => _ZoneDialogState();
}

class _ZoneDialogState extends State<_ZoneDialog> {
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _loading = false;
  String _error = '';

  bool get _isEdit => widget.zone != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _codeCtrl.text = widget.zone!.code;
      _nameCtrl.text = widget.zone!.name;
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final code = _codeCtrl.text.trim();
    final name = _nameCtrl.text.trim();

    if (code.isEmpty || name.isEmpty) {
      setState(() => _error = 'Code and name are required');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      if (_isEdit) {
        await ZoneService.instance.update(widget.zone!.id, code, name);
      } else {
        await ZoneService.instance.insert(code, name);
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Zone' : 'New Storage Zone'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _codeCtrl,
              autofocus: !_isEdit,
              decoration: const InputDecoration(
                labelText: 'Zone Code *',
                hintText: 'e.g. ZN-A1',
                prefixIcon: Icon(Icons.tag_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              autofocus: _isEdit,
              decoration: const InputDecoration(
                labelText: 'Zone Name *',
                hintText: 'e.g. Cold Storage A',
                prefixIcon: Icon(Icons.warehouse_outlined, size: 18),
              ),
              onSubmitted: (_) => _save(),
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
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

// ============================================================================
// SHARED WIDGETS
// ============================================================================

class _TagOption extends StatelessWidget {
  final int code;
  final int selected;
  final VoidCallback onTap;

  const _TagOption(
      {required this.code, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.tagColor(code);
    final label = AppTheme.tagLabel(code);
    final isSelected = code == selected;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? color.withOpacity(0.5)
                : Theme.of(context).colorScheme.outline,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            color: color.withOpacity(0.4),
                            blurRadius: 4,
                            spreadRadius: 1)
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 6),
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

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Toggle(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
              child:
                  Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Switch(
              value: value,
              onChanged: onChanged,
              activeColor: AppTheme.primaryBlue),
        ],
      );
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color? color;

  const _InfoChip({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ??
        (Theme.of(context).brightness == Brightness.dark
            ? AppTheme.darkTextSecond
            : AppTheme.lightTextSecond);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withOpacity(0.2)),
      ),
      child: Text(label, style: TextStyle(color: c, fontSize: 11)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool isDark;

  const _EmptyState(
      {required this.icon, required this.message, required this.isDark});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 48,
                color: isDark ? AppTheme.darkTextHint : AppTheme.lightTextHint),
            const SizedBox(height: 12),
            Text(message, style: Theme.of(context).textTheme.bodySmall),
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
          border: Border.all(color: AppTheme.error.withOpacity(0.3)),
        ),
        child: Text(error,
            style: const TextStyle(color: AppTheme.error, fontSize: 12)),
      );
}
