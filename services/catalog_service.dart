import 'dart:ffi';
import 'dart:convert';
import 'dart:isolate';
import 'package:waste_tracking/ffi/engine.dart';
import 'package:waste_tracking/ffi/models/material_type.dart';
import 'package:waste_tracking/ffi/models/product.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';

class CatalogService {
  static final CatalogService instance = CatalogService._();
  CatalogService._();

  WasteEngine get _e  => WasteEngine.instance;
  get _ctx            => _e.handle;
  get _usr            => AuthService.instance.session!.handle;

  // ── Types ──────────────────────────────────────────────────────────────────
  Future<List<MaterialType>> listTypes({String search = ''}) async {
    final json = _e.catalog.typeList(_ctx, search: search);
    return MaterialType.fromJsonArray(json);
  }

  Future<MaterialType?> getType(int typeId) async {
    final json = _e.catalog.typeGet(_ctx, typeId);
    if (json.isEmpty) return null;
    return MaterialType.fromJsonObject(json);
  }

  Future<int> createType({
    required String code,
    required String name,
    required String nature,
    String forme                = '',
    int    tagCode              = 0,
    bool   requiresLot         = false,
    bool   requiresName        = false,
    bool   requiresProduct     = false,
    bool   requiresDenaturation = false,
  }) async {
    return _e.catalog.typeCreate(_ctx, _usr,
      code: code, name: name, nature: nature, forme: forme,
      tagCode: tagCode, requiresLot: requiresLot,
      requiresName: requiresName, requiresProduct: requiresProduct,
      requiresDenaturation: requiresDenaturation,
    );
  }

  Future<int> updateType(int typeId, Map<String, dynamic> fields) async {
    final fieldsJson = jsonEncode({...fields, 'id': typeId});
    return _e.catalog.typeUpdate(_ctx, _usr, typeId, fieldsJson);
  }

      Future<int> deleteType(int typeId) async =>
        _e.catalog.typeDelete(_ctx, _usr, typeId);

  // ── Products ───────────────────────────────────────────────────────────────
  Future<List<Product>> listProducts() async {
    final json = _e.catalog.productList(_ctx);
    return Product.fromJsonArray(json);
  }

  Future<int> createProduct(String name) async =>
      _e.catalog.productCreate(_ctx, _usr, name);

  Future<int> updateProduct(int id, String name) async =>
      _e.catalog.productUpdate(_ctx, _usr, id, name);

  Future<int> deleteProduct(int id) async =>
      _e.catalog.productDelete(_ctx, _usr, id);
}