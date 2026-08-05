import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'types.dart';

// ============================================================================
// CONTEXT BINDINGS
//
// C++ symbols (context.cpp):
// context_init        → WasteTrackingHandle
// context_cleanup     → void
// context_set_server  → int32 (WasteTrackingError)
// context_get_error   → const char* NON-OWNING — never free
// context_free_string → void — free every other heap char*

typedef _NativeInit      = WasteTrackingHandle Function(Pointer<Utf8> ip);
typedef _DartInit        = WasteTrackingHandle Function(Pointer<Utf8> ip);

typedef _NativeCleanup   = Void Function(WasteTrackingHandle h);
typedef _DartCleanup     = void Function(WasteTrackingHandle h);

typedef _NativeSetServer = Int32 Function(WasteTrackingHandle h, Pointer<Utf8> ip);
typedef _DartSetServer   = int   Function(WasteTrackingHandle h, Pointer<Utf8> ip);

typedef _NativeGetError  = Pointer<Utf8> Function(WasteTrackingHandle h);
typedef _DartGetError    = Pointer<Utf8> Function(WasteTrackingHandle h);

typedef _NativeFreeStr   = Void Function(Pointer<Utf8> ptr);
typedef _DartFreeStr     = void Function(Pointer<Utf8> ptr);

// ============================================================================
// CONTEXT BINDINGS CLASS
// ============================================================================

class ContextBindings {
  final DynamicLibrary _lib;

  late final _DartInit        _init;
  late final _DartCleanup     _cleanup;
  late final _DartSetServer   _setServer;
  late final _DartGetError    _getError;
  late final _DartFreeStr     _freeString;

  ContextBindings(this._lib) {
    _init       = _lib.lookupFunction<_NativeInit,      _DartInit>     ('context_init');
    _cleanup    = _lib.lookupFunction<_NativeCleanup,   _DartCleanup>  ('context_cleanup');
    _setServer  = _lib.lookupFunction<_NativeSetServer, _DartSetServer>('context_set_server');
    _getError   = _lib.lookupFunction<_NativeGetError,  _DartGetError> ('context_get_error');
    _freeString = _lib.lookupFunction<_NativeFreeStr,   _DartFreeStr>  ('context_free_string');
  }

  WasteTrackingHandle init(String ip) {
    final p = ip.toNativeUtf8();
    try { return _init(p); } finally { malloc.free(p); }
  }

  void cleanup(WasteTrackingHandle h) {
    if (h.address != 0) _cleanup(h);
  }

  // Returns WtError code: 0 = success
  int setServer(WasteTrackingHandle h, String ip) {
    final p = ip.toNativeUtf8();
    try { return _setServer(h, p); } finally { malloc.free(p); }
  }

  // NON-OWNING — copy immediately, NEVER free
  String getError(WasteTrackingHandle h) {
    if (h.address == 0) return 'Invalid handle';
    final ptr = _getError(h);
    return ptr.address == 0 ? '' : ptr.toDartString();
  }

  // Call this to free any heap char* from other chambers
  void freeString(Pointer<Utf8> ptr) {
    if (ptr.address != 0) _freeString(ptr);
  }

  bool isValid(WasteTrackingHandle h) => h.address != 0;
}