import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'types.dart';

// PendingNotifyCallback: void (*)(const char* signal_name)
// Signals: "RECO_STEP_COMPLETED","SHIPMENT_READY","DENATURATION_PENDING"
typedef NativePendingNotify = Void Function(Pointer<Utf8> signalName);

typedef _NativeRecoList  = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);
typedef _DartRecoList    = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);

typedef _NativeShipList  = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);
typedef _DartShipList    = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);

typedef _NativeDenatList = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);
typedef _DartDenatList   = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);

typedef _NativeSetNotify = Void Function(UserHandle u, Pointer<NativeFunction<NativePendingNotify>> cb);
typedef _DartSetNotify   = void Function(UserHandle u, Pointer<NativeFunction<NativePendingNotify>> cb);

typedef _NativeFreeStr   = Void Function(Pointer<Utf8> ptr);
typedef _DartFreeStr     = void Function(Pointer<Utf8> ptr);

class PendingBindings {
  final DynamicLibrary _lib;

  late final _DartRecoList  _recoList;
  late final _DartShipList  _shipList;
  late final _DartDenatList _denatList;
  late final _DartSetNotify _setNotify;
  late final _DartFreeStr   _freeStr;

  NativeCallable<NativePendingNotify>? _notifyCb;

  PendingBindings(this._lib) {
    _recoList  = _lib.lookupFunction<_NativeRecoList,  _DartRecoList> ('pending_reco_list');
    _shipList  = _lib.lookupFunction<_NativeShipList,  _DartShipList> ('pending_ship_list');
    _denatList = _lib.lookupFunction<_NativeDenatList, _DartDenatList>('pending_denat_list');
    _setNotify = _lib.lookupFunction<_NativeSetNotify, _DartSetNotify>('pending_set_notify_callback');
    _freeStr   = _lib.lookupFunction<_NativeFreeStr,   _DartFreeStr>  ('pending_free_string');
  }

  String _rf(Pointer<Utf8> ptr) {
    if (ptr.address == 0) return '';
    try { return ptr.toDartString(); } finally { _freeStr(ptr); }
  }

  // One callback covers all 3 queues — match signal to right list call:
  //   "RECO_STEP_COMPLETED"  → recoList()
  //   "SHIPMENT_READY"       → shipList()
  //   "DENATURATION_PENDING" → denatList()
  void setNotifyCallback(UserHandle user, void Function(String signal) cb) {
    _notifyCb?.close();
    _notifyCb = NativeCallable<NativePendingNotify>.listener(
      (Pointer<Utf8> sig) => cb(sig.toDartString()),
    );
    _setNotify(user, _notifyCb!.nativeFunction);
  }

  void closeCallback() { _notifyCb?.close(); _notifyCb = null; }

  // Validator queue: status pending or scanned, oldest first
  String recoList(WasteTrackingHandle h, UserHandle u) =>
      _rf(_recoList(h, u));

  // Shipper queue: status pending, grouped by zone
  String shipList(WasteTrackingHandle h, UserHandle u) =>
      _rf(_shipList(h, u));

  // Coordinateur queue: denaturation_operations status pending
  String denatList(WasteTrackingHandle h, UserHandle u) =>
      _rf(_denatList(h, u));
}