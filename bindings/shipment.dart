import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'types.dart';

// ShipNotifyCallback: void (*)(const char* signal_name)
// Signals: "SHIPMENT_READY","SHIPMENT_DISPATCHED"
typedef NativeShipNotify = Void Function(Pointer<Utf8> signalName);

typedef _NativeGetByQR = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> qr);
typedef _DartGetByQR = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> qr);

// ship_dispatch returns heap JSON string
typedef _NativeDispatch = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Int32 shipmentId, Pointer<Utf8> note);
typedef _DartDispatch = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, int shipmentId, Pointer<Utf8> note);

typedef _NativeMyList = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> status);
typedef _DartMyList = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> status);

typedef _NativeCorrectStatus = Int32 Function(
    WasteTrackingHandle h, UserHandle u, Int32 shipmentId,
    Pointer<Utf8> newStatus, Pointer<Utf8> reason);
typedef _DartCorrectStatus = int Function(
    WasteTrackingHandle h, UserHandle u, int shipmentId,
    Pointer<Utf8> newStatus, Pointer<Utf8> reason);

typedef _NativeSetNotify = Void Function(UserHandle u, Pointer<NativeFunction<NativeShipNotify>> cb);
typedef _DartSetNotify   = void Function(UserHandle u, Pointer<NativeFunction<NativeShipNotify>> cb);

typedef _NativeFreeStr = Void Function(Pointer<Utf8> ptr);
typedef _DartFreeStr   = void Function(Pointer<Utf8> ptr);

class ShipBindings {
  final DynamicLibrary _lib;

  late final _DartGetByQR        _getByQR;
  late final _DartDispatch       _dispatch;
  late final _DartMyList         _myList;
  late final _DartCorrectStatus  _correctStatus;
  late final _DartSetNotify      _setNotify;
  late final _DartFreeStr        _freeStr;

  NativeCallable<NativeShipNotify>? _notifyCb;

  ShipBindings(this._lib) {
    _getByQR       = _lib.lookupFunction<_NativeGetByQR,       _DartGetByQR>      ('ship_get_by_qr');
    _dispatch      = _lib.lookupFunction<_NativeDispatch,      _DartDispatch>     ('ship_dispatch');
    _myList        = _lib.lookupFunction<_NativeMyList,        _DartMyList>       ('ship_my_list');
    _correctStatus = _lib.lookupFunction<_NativeCorrectStatus, _DartCorrectStatus>('ship_correct_status');
    _setNotify     = _lib.lookupFunction<_NativeSetNotify,     _DartSetNotify>    ('ship_set_notify_callback');
    _freeStr       = _lib.lookupFunction<_NativeFreeStr,       _DartFreeStr>      ('ship_free_string');
  }

  String _rf(Pointer<Utf8> ptr) {
    if (ptr.address == 0) return '';
    try { return ptr.toDartString(); } finally { _freeStr(ptr); }
  }

  void setNotifyCallback(UserHandle user, void Function(String signal) cb) {
    _notifyCb?.close();
    _notifyCb = NativeCallable<NativeShipNotify>.listener(
      (Pointer<Utf8> sig) => cb(sig.toDartString()),
    );
    _setNotify(user, _notifyCb!.nativeFunction);
  }

  void closeCallback() { _notifyCb?.close(); _notifyCb = null; }

  // Returns JSON with shipment detail, or error JSON
  String getByQR(WasteTrackingHandle h, UserHandle u, String qr) {
    final q = qr.toNativeUtf8();
    try { return _rf(_getByQR(h, u, q)); }
    finally { malloc.free(q); }
  }

  // note: optional. Returns JSON with dispatch result or error JSON.
  // Server blocks if denaturation not completed.
  String dispatch(WasteTrackingHandle h, UserHandle u,
      int shipmentId, {String note = ''}) {
    final n = note.toNativeUtf8();
    try { return _rf(_dispatch(h, u, shipmentId, n)); }
    finally { malloc.free(n); }
  }

  // status: "shipped" | "cancelled" | "all"
  String myList(WasteTrackingHandle h, UserHandle u, {String status = 'all'}) {
    final s = status.toNativeUtf8();
    try { return _rf(_myList(h, u, s)); }
    finally { malloc.free(s); }
  }

  // newStatus: "pending" | "shipped" | "cancelled"
  // reason: mandatory
  int correctStatus(WasteTrackingHandle h, UserHandle u,
      int shipmentId, String newStatus, String reason) {
    final s = newStatus.toNativeUtf8();
    final r = reason.toNativeUtf8();
    try { return _correctStatus(h, u, shipmentId, s, r); }
    finally { malloc.free(s); malloc.free(r); }
  }
}