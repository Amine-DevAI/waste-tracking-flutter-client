import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'types.dart';

// CatalogNotifyCallback: void (*)(const char* signal_name)
// Signals: "TYPE_CREATED","TYPE_UPDATED","TYPE_DELETED","REFRESH_PRODUCTS"
typedef NativeCatalogNotify = Void Function(Pointer<Utf8> signalName);

// ── type_create ────────────────────────────────────────────────────────────
typedef _NativeTypeCreate = Int32 Function(
    WasteTrackingHandle h, UserHandle u,
    Pointer<Utf8> code, Pointer<Utf8> name, Pointer<Utf8> nature,
    Pointer<Utf8> forme, Int32 tagCode,
    Bool requiresLot, Bool requiresName,
    Bool requiresProduct, Bool requiresDenaturation);
typedef _DartTypeCreate = int Function(
    WasteTrackingHandle h, UserHandle u,
    Pointer<Utf8> code, Pointer<Utf8> name, Pointer<Utf8> nature,
    Pointer<Utf8> forme, int tagCode,
    bool requiresLot, bool requiresName,
    bool requiresProduct, bool requiresDenaturation);

// ── type_update — fields_json partial JSON + "id" ─────────────────────────
typedef _NativeTypeUpdate = Int32 Function(
    WasteTrackingHandle h, UserHandle u, Int32 typeId, Pointer<Utf8> fieldsJson);
typedef _DartTypeUpdate = int Function(
    WasteTrackingHandle h, UserHandle u, int typeId, Pointer<Utf8> fieldsJson);

// ── type_delete ────────────────────────────────────────────────────────────
typedef _NativeTypeDelete = Int32 Function(WasteTrackingHandle h, UserHandle u, Int32 typeId);
typedef _DartTypeDelete   = int   Function(WasteTrackingHandle h, UserHandle u, int  typeId);

// ── type_list — open read, no user_handle ─────────────────────────────────
typedef _NativeTypeList = Pointer<Utf8> Function(WasteTrackingHandle h, Pointer<Utf8> search);
typedef _DartTypeList   = Pointer<Utf8> Function(WasteTrackingHandle h, Pointer<Utf8> search);

// ── type_get ──────────────────────────────────────────────────────────────
typedef _NativeTypeGet = Pointer<Utf8> Function(WasteTrackingHandle h, Int32 typeId);
typedef _DartTypeGet   = Pointer<Utf8> Function(WasteTrackingHandle h, int  typeId);

// ── product_create ────────────────────────────────────────────────────────
typedef _NativeProdCreate = Int32 Function(WasteTrackingHandle h, UserHandle u, Pointer<Utf8> name);
typedef _DartProdCreate   = int   Function(WasteTrackingHandle h, UserHandle u, Pointer<Utf8> name);

// ── product_update ────────────────────────────────────────────────────────
typedef _NativeProdUpdate = Int32 Function(WasteTrackingHandle h, UserHandle u, Int32 id, Pointer<Utf8> name);
typedef _DartProdUpdate   = int   Function(WasteTrackingHandle h, UserHandle u, int  id, Pointer<Utf8> name);

// ── product_delete ────────────────────────────────────────────────────────
typedef _NativeProdDelete = Int32 Function(WasteTrackingHandle h, UserHandle u, Int32 id);
typedef _DartProdDelete   = int   Function(WasteTrackingHandle h, UserHandle u, int  id);

// ── product_list — open read ──────────────────────────────────────────────
typedef _NativeProdList = Pointer<Utf8> Function(WasteTrackingHandle h);
typedef _DartProdList   = Pointer<Utf8> Function(WasteTrackingHandle h);

// ── notify callback setter ────────────────────────────────────────────────
typedef _NativeSetNotify = Void Function(UserHandle u, Pointer<NativeFunction<NativeCatalogNotify>> cb);
typedef _DartSetNotify   = void Function(UserHandle u, Pointer<NativeFunction<NativeCatalogNotify>> cb);

typedef _NativeFreeStr = Void Function(Pointer<Utf8> ptr);
typedef _DartFreeStr   = void Function(Pointer<Utf8> ptr);

class CatalogBindings {
  final DynamicLibrary _lib;

  late final _DartTypeCreate  _typeCreate;
  late final _DartTypeUpdate  _typeUpdate;
  late final _DartTypeDelete  _typeDelete;
  late final _DartTypeList    _typeList;
  late final _DartTypeGet     _typeGet;
  late final _DartProdCreate  _prodCreate;
  late final _DartProdUpdate  _prodUpdate;
  late final _DartProdDelete  _prodDelete;
  late final _DartProdList    _prodList;
  late final _DartSetNotify   _setNotify;
  late final _DartFreeStr     _freeStr;

  NativeCallable<NativeCatalogNotify>? _notifyCb;

  CatalogBindings(this._lib) {
    _typeCreate = _lib.lookupFunction<_NativeTypeCreate, _DartTypeCreate>('type_create');
    _typeUpdate = _lib.lookupFunction<_NativeTypeUpdate, _DartTypeUpdate>('type_update');
    _typeDelete = _lib.lookupFunction<_NativeTypeDelete, _DartTypeDelete>('type_delete');
    _typeList   = _lib.lookupFunction<_NativeTypeList,   _DartTypeList>  ('type_list');
    _typeGet    = _lib.lookupFunction<_NativeTypeGet,    _DartTypeGet>   ('type_get');
    _prodCreate = _lib.lookupFunction<_NativeProdCreate, _DartProdCreate>('product_create');
    _prodUpdate = _lib.lookupFunction<_NativeProdUpdate, _DartProdUpdate>('product_update');
    _prodDelete = _lib.lookupFunction<_NativeProdDelete, _DartProdDelete>('product_delete');
    _prodList   = _lib.lookupFunction<_NativeProdList,   _DartProdList>  ('product_list');
    _setNotify  = _lib.lookupFunction<_NativeSetNotify,  _DartSetNotify> ('catalog_set_notify_callback');
    _freeStr    = _lib.lookupFunction<_NativeFreeStr,    _DartFreeStr>   ('catalog_free_string');
  }

  String _rf(Pointer<Utf8> ptr) {
    if (ptr.address == 0) return '';
    try { return ptr.toDartString(); } finally { _freeStr(ptr); }
  }

  // Signals: TYPE_CREATED | TYPE_UPDATED | TYPE_DELETED | REFRESH_PRODUCTS
  void setNotifyCallback(UserHandle user, void Function(String signal) cb) {
    _notifyCb?.close();
    _notifyCb = NativeCallable<NativeCatalogNotify>.listener(
      (Pointer<Utf8> sig) => cb(sig.toDartString()),
    );
    _setNotify(user, _notifyCb!.nativeFunction);
  }

  void closeCallback() { _notifyCb?.close(); _notifyCb = null; }

  // Returns new id on success, -1 on failure
  int typeCreate(WasteTrackingHandle h, UserHandle u, {
    required String code,
    required String name,
    required String nature,
    String  forme              = '',
    int     tagCode            = 0,
    bool    requiresLot        = false,
    bool    requiresName       = false,
    bool    requiresProduct    = false,
    bool    requiresDenaturation = false,
  }) {
    final c  = code.toNativeUtf8();
    final n  = name.toNativeUtf8();
    final na = nature.toNativeUtf8();
    final fo = forme.toNativeUtf8();
    try {
      return _typeCreate(h, u, c, n, na, fo, tagCode,
          requiresLot, requiresName, requiresProduct, requiresDenaturation);
    } finally {
      malloc.free(c); malloc.free(n); malloc.free(na); malloc.free(fo);
    }
  }

  // fieldsJson: partial JSON with fields to change + "id"
  // Allowed keys: code,name,nature,forme,tag_code,requires_lot,
  //               requires_name,requires_product,requires_denaturation
  int typeUpdate(WasteTrackingHandle h, UserHandle u, int typeId, String fieldsJson) {
    final f = fieldsJson.toNativeUtf8();
    try { return _typeUpdate(h, u, typeId, f); }
    finally { malloc.free(f); }
  }

  int typeDelete(WasteTrackingHandle h, UserHandle u, int typeId) =>
      _typeDelete(h, u, typeId);

  // search: pass '' for full list
  String typeList(WasteTrackingHandle h, {String search = ''}) {
    final s = search.toNativeUtf8();
    try { return _rf(_typeList(h, s)); }
    finally { malloc.free(s); }
  }

  String typeGet(WasteTrackingHandle h, int typeId) =>
      _rf(_typeGet(h, typeId));

  // Returns new id on success, -1 on failure (duplicate name)
  int productCreate(WasteTrackingHandle h, UserHandle u, String name) {
    final n = name.toNativeUtf8();
    try { return _prodCreate(h, u, n); }
    finally { malloc.free(n); }
  }

  int productUpdate(WasteTrackingHandle h, UserHandle u, int id, String name) {
    final n = name.toNativeUtf8();
    try { return _prodUpdate(h, u, id, n); }
    finally { malloc.free(n); }
  }

  int productDelete(WasteTrackingHandle h, UserHandle u, int id) =>
      _prodDelete(h, u, id);

  String productList(WasteTrackingHandle h) => _rf(_prodList(h));
}