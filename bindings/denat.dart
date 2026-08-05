import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'types.dart';

// DenatNotifyCallback: void (*)(const char* signal_name)
// Signals: "DENATURATION_PENDING","DENATURATION_SUCCESS"
typedef NativeDenatNotify = Void Function(Pointer<Utf8> signalName);

typedef _NativeScanByQR = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> qr);
typedef _DartScanByQR = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> qr);

typedef _NativeSubmit = Int32 Function(
    WasteTrackingHandle h, UserHandle u, Int32 denatId,
    Double brutAfter, Double netAfter,
    Pointer<Utf8> qrScanned, Pointer<Utf8> note);
typedef _DartSubmit = int Function(
    WasteTrackingHandle h, UserHandle u, int denatId,
    double brutAfter, double netAfter,
    Pointer<Utf8> qrScanned, Pointer<Utf8> note);

// limit=0 → server uses default (20)
typedef _NativeMyList = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Int32 limit);
typedef _DartMyList = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, int limit);

typedef _NativeCorrect = Int32 Function(
    WasteTrackingHandle h, UserHandle u, Int32 denatId,
    Double newNet, Double newBrut, Pointer<Utf8> reason);
typedef _DartCorrect = int Function(
    WasteTrackingHandle h, UserHandle u, int denatId,
    double newNet, double newBrut, Pointer<Utf8> reason);

typedef _NativeSetNotify = Void Function(UserHandle u, Pointer<NativeFunction<NativeDenatNotify>> cb);
typedef _DartSetNotify   = void Function(UserHandle u, Pointer<NativeFunction<NativeDenatNotify>> cb);

typedef _NativeFreeStr = Void Function(Pointer<Utf8> ptr);
typedef _DartFreeStr   = void Function(Pointer<Utf8> ptr);

class DenatBindings {
  final DynamicLibrary _lib;

  late final _DartScanByQR  _scanByQR;
  late final _DartSubmit    _submit;
  late final _DartMyList    _myList;
  late final _DartCorrect   _correct;
  late final _DartSetNotify _setNotify;
  late final _DartFreeStr   _freeStr;

  NativeCallable<NativeDenatNotify>? _notifyCb;

  DenatBindings(this._lib) {
    _scanByQR  = _lib.lookupFunction<_NativeScanByQR, _DartScanByQR>('denat_scan_by_qr');
    _submit    = _lib.lookupFunction<_NativeSubmit,   _DartSubmit>  ('denat_submit');
    _myList    = _lib.lookupFunction<_NativeMyList,   _DartMyList>  ('denat_my_list');
    _correct   = _lib.lookupFunction<_NativeCorrect,  _DartCorrect> ('denat_correct');
    _setNotify = _lib.lookupFunction<_NativeSetNotify,_DartSetNotify>('denat_set_notify_callback');
    _freeStr   = _lib.lookupFunction<_NativeFreeStr,  _DartFreeStr> ('denat_free_string');
  }

  String _rf(Pointer<Utf8> ptr) {
    if (ptr.address == 0) return '';
    try { return ptr.toDartString(); } finally { _freeStr(ptr); }
  }

  void setNotifyCallback(UserHandle user, void Function(String signal) cb) {
    _notifyCb?.close();
    _notifyCb = NativeCallable<NativeDenatNotify>.listener(
      (Pointer<Utf8> sig) => cb(sig.toDartString()),
    );
    _setNotify(user, _notifyCb!.nativeFunction);
  }

  void closeCallback() { _notifyCb?.close(); _notifyCb = null; }

  // Returns JSON with denat_id/material/weight_before, or error JSON
  String scanByQR(WasteTrackingHandle h, UserHandle u, String qr) {
    final q = qr.toNativeUtf8();
    try { return _rf(_scanByQR(h, u, q)); }
    finally { malloc.free(q); }
  }

  // qrScanned: mandatory second verification
  // note: pass '' for default
  int submit(WasteTrackingHandle h, UserHandle u, int denatId,
      double brutAfter, double netAfter,
      String qrScanned, {String note = ''}) {
    final q = qrScanned.toNativeUtf8();
    final n = note.toNativeUtf8();
    try { return _submit(h, u, denatId, brutAfter, netAfter, q, n); }
    finally { malloc.free(q); malloc.free(n); }
  }

  // Returns JSON array of completed operations for this coordinator
  String myList(WasteTrackingHandle h, UserHandle u, {int limit = 20}) =>
      _rf(_myList(h, u, limit));

  // reason: mandatory
  int correct(WasteTrackingHandle h, UserHandle u, int denatId,
      double newNet, double newBrut, String reason) {
    final r = reason.toNativeUtf8();
    try { return _correct(h, u, denatId, newNet, newBrut, r); }
    finally { malloc.free(r); }
  }
}