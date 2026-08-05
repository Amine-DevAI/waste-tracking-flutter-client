import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'types.dart';

// ZoneNotifyCallback: void (*)(const char* signal_name)
// Signal: "REFRESH_ZONES"
typedef NativeZoneNotify = Void Function(Pointer<Utf8> signalName);

typedef _NativeZoneList   = Pointer<Utf8> Function(WasteTrackingHandle h);
typedef _DartZoneList     = Pointer<Utf8> Function(WasteTrackingHandle h);

// zone_insert: returns 1 on success, -1 on failure
typedef _NativeZoneInsert = Int32 Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> code, Pointer<Utf8> name);
typedef _DartZoneInsert   = int Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> code, Pointer<Utf8> name);

// zone_update: also handles soft-delete via active=false
typedef _NativeZoneUpdate = Int32 Function(
    WasteTrackingHandle h, UserHandle u, Int32 zoneId,
    Pointer<Utf8> code, Pointer<Utf8> name, Bool active);
typedef _DartZoneUpdate   = int Function(
    WasteTrackingHandle h, UserHandle u, int  zoneId,
    Pointer<Utf8> code, Pointer<Utf8> name, bool active);

typedef _NativeSetNotify  = Void Function(UserHandle u, Pointer<NativeFunction<NativeZoneNotify>> cb);
typedef _DartSetNotify    = void Function(UserHandle u, Pointer<NativeFunction<NativeZoneNotify>> cb);

typedef _NativeFreeStr = Void Function(Pointer<Utf8> ptr);
typedef _DartFreeStr   = void Function(Pointer<Utf8> ptr);

// ============================================================================
// ZONE BINDINGS CLASS
// ============================================================================

class ZoneBindings {
  final DynamicLibrary _lib;

  late final _DartZoneList   _list;
  late final _DartZoneInsert _insert;
  late final _DartZoneUpdate _update;
  late final _DartSetNotify  _setNotify;
  late final _DartFreeStr    _freeStr;

  NativeCallable<NativeZoneNotify>? _notifyCb;

  ZoneBindings(this._lib) {
    _list      = _lib.lookupFunction<_NativeZoneList,   _DartZoneList>  ('zone_list');
    _insert    = _lib.lookupFunction<_NativeZoneInsert, _DartZoneInsert>('zone_insert');
    _update    = _lib.lookupFunction<_NativeZoneUpdate, _DartZoneUpdate>('zone_update');
    _setNotify = _lib.lookupFunction<_NativeSetNotify,  _DartSetNotify> ('zone_set_notify_callback');
    _freeStr   = _lib.lookupFunction<_NativeFreeStr,    _DartFreeStr>   ('zone_free_string');
  }

  String _rf(Pointer<Utf8> ptr) {
    if (ptr.address == 0) return '';
    try { return ptr.toDartString(); } finally { _freeStr(ptr); }
  }

  void setNotifyCallback(UserHandle user, void Function(String signal) cb) {
    _notifyCb?.close();
    _notifyCb = NativeCallable<NativeZoneNotify>.listener(
      (Pointer<Utf8> sig) => cb(sig.toDartString()),
    );
    _setNotify(user, _notifyCb!.nativeFunction);
  }

  void closeCallback() { _notifyCb?.close(); _notifyCb = null; }

  // Only active zones returned (server filters WHERE active = TRUE)
  String list(WasteTrackingHandle h) => _rf(_list(h));

  // Returns 1 on success, -1 on failure
  int insert(WasteTrackingHandle h, UserHandle u, String code, String name) {
    final c = code.toNativeUtf8();
    final n = name.toNativeUtf8();
    try { return _insert(h, u, c, n); }
    finally { malloc.free(c); malloc.free(n); }
  }

  // active=false → soft delete. active=true → restore.
  int update(WasteTrackingHandle h, UserHandle u, int zoneId,
      String code, String name, {bool active = true}) {
    final c = code.toNativeUtf8();
    final n = name.toNativeUtf8();
    try { return _update(h, u, zoneId, c, n, active); }
    finally { malloc.free(c); malloc.free(n); }
  }
}