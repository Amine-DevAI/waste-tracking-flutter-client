import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'types.dart';

// RecoNotifyCallback: void (*)(const char* signal_name)
// Signals: "RECO_STEP_COMPLETED","RECO_REJECTED","RECO_STATE_UPDATED"
typedef NativeRecoNotify = Void Function(Pointer<Utf8> signalName);

typedef _NativeGetByQR = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> qr);
typedef _DartGetByQR = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> qr);

typedef _NativeSubmit = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u,
    Int32 weighingId, Double newNet, Double newGross, Double newTare);
typedef _DartSubmit = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u,
    int weighingId, double newNet, double newGross, double newTare);

typedef _NativeAccept = Int32 Function(WasteTrackingHandle h, UserHandle u, Int32 recoId);
typedef _DartAccept   = int   Function(WasteTrackingHandle h, UserHandle u, int  recoId);

typedef _NativeReject = Int32 Function(
    WasteTrackingHandle h, UserHandle u, Int32 recoId, Pointer<Utf8> reason);
typedef _DartReject = int Function(
    WasteTrackingHandle h, UserHandle u, int  recoId, Pointer<Utf8> reason);

typedef _NativeMyList = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> status);
typedef _DartMyList = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> status);

typedef _NativeCorrect = Int32 Function(
    WasteTrackingHandle h, UserHandle u, Int32 recoId,
    Pointer<Utf8> reason, Pointer<Utf8> changesJson);
typedef _DartCorrect = int Function(
    WasteTrackingHandle h, UserHandle u, int recoId,
    Pointer<Utf8> reason, Pointer<Utf8> changesJson);

typedef _NativeSetNotify = Void Function(UserHandle u, Pointer<NativeFunction<NativeRecoNotify>> cb);
typedef _DartSetNotify   = void Function(UserHandle u, Pointer<NativeFunction<NativeRecoNotify>> cb);

typedef _NativeFreeStr = Void Function(Pointer<Utf8> ptr);
typedef _DartFreeStr   = void Function(Pointer<Utf8> ptr);

class RecoBindings {
  final DynamicLibrary _lib;

  late final _DartGetByQR   _getByQR;
  late final _DartSubmit    _submit;
  late final _DartAccept    _accept;
  late final _DartReject    _reject;
  late final _DartMyList    _myList;
  late final _DartCorrect   _correct;
  late final _DartSetNotify _setNotify;
  late final _DartFreeStr   _freeStr;

  NativeCallable<NativeRecoNotify>? _notifyCb;

  RecoBindings(this._lib) {
    _getByQR   = _lib.lookupFunction<_NativeGetByQR,   _DartGetByQR>  ('reco_get_by_qr');
    _submit    = _lib.lookupFunction<_NativeSubmit,    _DartSubmit>   ('reco_submit');
    _accept    = _lib.lookupFunction<_NativeAccept,    _DartAccept>   ('reco_accept');
    _reject    = _lib.lookupFunction<_NativeReject,    _DartReject>   ('reco_reject');
    _myList    = _lib.lookupFunction<_NativeMyList,    _DartMyList>   ('reco_my_list');
    _correct   = _lib.lookupFunction<_NativeCorrect,   _DartCorrect>  ('reco_correct');
    _setNotify = _lib.lookupFunction<_NativeSetNotify, _DartSetNotify>('reco_set_notify_callback');
    _freeStr   = _lib.lookupFunction<_NativeFreeStr,   _DartFreeStr>  ('reco_free_string');
  }

  String _rf(Pointer<Utf8> ptr) {
    if (ptr.address == 0) return '';
    try { return ptr.toDartString(); } finally { _freeStr(ptr); }
  }

  void setNotifyCallback(UserHandle user, void Function(String signal) cb) {
    _notifyCb?.close();
    _notifyCb = NativeCallable<NativeRecoNotify>.listener(
      (Pointer<Utf8> sig) => cb(sig.toDartString()),
    );
    _setNotify(user, _notifyCb!.nativeFunction);
  }

  void closeCallback() { _notifyCb?.close(); _notifyCb = null; }

  // Returns JSON with original weighing data, or error JSON
  String getByQR(WasteTrackingHandle h, UserHandle u, String qr) {
    final q = qr.toNativeUtf8();
    try { return _rf(_getByQR(h, u, q)); }
    finally { malloc.free(q); }
  }

  // Returns JSON with reco_id + diffs on success, error JSON on failure
  String submit(WasteTrackingHandle h, UserHandle u,
      int weighingId, double newNet, double newGross, double newTare) =>
      _rf(_submit(h, u, weighingId, newNet, newGross, newTare));

  // Returns WtError
  int accept(WasteTrackingHandle h, UserHandle u, int recoId) =>
      _accept(h, u, recoId);

  // reason is mandatory — returns WtError
  int reject(WasteTrackingHandle h, UserHandle u, int recoId, String reason) {
    final r = reason.toNativeUtf8();
    try { return _reject(h, u, recoId, r); }
    finally { malloc.free(r); }
  }

  // status: "approved" | "rejected" | "all"
  String myList(WasteTrackingHandle h, UserHandle u, {String status = 'all'}) {
    final s = status.toNativeUtf8();
    try { return _rf(_myList(h, u, s)); }
    finally { malloc.free(s); }
  }

  // changesJson: e.g. '{"new_weight":12.5,"new_gross":15.0,"new_tare":2.5}'
  int correct(WasteTrackingHandle h, UserHandle u, int recoId,
      String reason, String changesJson) {
    final r = reason.toNativeUtf8();
    final c = changesJson.toNativeUtf8();
    try { return _correct(h, u, recoId, r, c); }
    finally { malloc.free(r); malloc.free(c); }
  }
}