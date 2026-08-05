import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'types.dart';

// WeighingNotifyCallback: void (*)(const char* signal_name)
// Signal: "WEIGHING_CORRECTED"
typedef NativeWeighingNotify = Void Function(Pointer<Utf8> signalName);

// weighing_create: returns UUID heap string on success, nullptr on failure
typedef _NativeCreate = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u,
    Int32 typeId, Int32 productId,
    Double grossWeight, Double tareWeight,
    Pointer<Utf8> lotNumber);
typedef _DartCreate = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u,
    int typeId, int productId,
    double grossWeight, double tareWeight,
    Pointer<Utf8> lotNumber);

// weighing_get_by_uuid
typedef _NativeGetByUUID = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> uuid);
typedef _DartGetByUUID = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> uuid);

// weighing_my_list
typedef _NativeMyList = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);
typedef _DartMyList   = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);

// weighing_correct
// changes_json: partial JSON e.g. '{"gross_weight":12.5,"tare_weight":0.8}'
typedef _NativeCorrect = Int32 Function(
    WasteTrackingHandle h, UserHandle u, Int32 weighingId,
    Pointer<Utf8> reason, Pointer<Utf8> changesJson);
typedef _DartCorrect = int Function(
    WasteTrackingHandle h, UserHandle u, int weighingId,
    Pointer<Utf8> reason, Pointer<Utf8> changesJson);

typedef _NativeSetNotify = Void Function(UserHandle u, Pointer<NativeFunction<NativeWeighingNotify>> cb);
typedef _DartSetNotify   = void Function(UserHandle u, Pointer<NativeFunction<NativeWeighingNotify>> cb);

typedef _NativeFreeStr = Void Function(Pointer<Utf8> ptr);
typedef _DartFreeStr   = void Function(Pointer<Utf8> ptr);

class WeighingBindings {
  final DynamicLibrary _lib;

  late final _DartCreate     _create;
  late final _DartGetByUUID  _getByUUID;
  late final _DartMyList     _myList;
  late final _DartCorrect    _correct;
  late final _DartSetNotify  _setNotify;
  late final _DartFreeStr    _freeStr;

  NativeCallable<NativeWeighingNotify>? _notifyCb;

  WeighingBindings(this._lib) {
    _create    = _lib.lookupFunction<_NativeCreate,    _DartCreate>   ('weighing_create');
    _getByUUID = _lib.lookupFunction<_NativeGetByUUID, _DartGetByUUID>('weighing_get_by_uuid');
    _myList    = _lib.lookupFunction<_NativeMyList,    _DartMyList>   ('weighing_my_list');
    _correct   = _lib.lookupFunction<_NativeCorrect,   _DartCorrect>  ('weighing_correct');
    _setNotify = _lib.lookupFunction<_NativeSetNotify, _DartSetNotify>('weighing_set_notify_callback');
    _freeStr   = _lib.lookupFunction<_NativeFreeStr,   _DartFreeStr>  ('weighing_free_string');
  }

  String _rf(Pointer<Utf8> ptr) {
    if (ptr.address == 0) return '';
    try { return ptr.toDartString(); } finally { _freeStr(ptr); }
  }

  void setNotifyCallback(UserHandle user, void Function(String signal) cb) {
    _notifyCb?.close();
    _notifyCb = NativeCallable<NativeWeighingNotify>.listener(
      (Pointer<Utf8> sig) => cb(sig.toDartString()),
    );
    _setNotify(user, _notifyCb!.nativeFunction);
  }

  void closeCallback() { _notifyCb?.close(); _notifyCb = null; }

  // Returns UUID string on success, '' on failure
  // productId: pass 0 if type doesn't require_product
  // lotNumber: pass '' if type doesn't require_lot
  String create(WasteTrackingHandle h, UserHandle u, {
    required int    typeId,
    int             productId   = 0,
    required double grossWeight,
    double          tareWeight  = 0.0,
    String          lotNumber   = '',
  }) {
    final lot = lotNumber.toNativeUtf8();
    try { return _rf(_create(h, u, typeId, productId, grossWeight, tareWeight, lot)); }
    finally { malloc.free(lot); }
  }

  // Returns JSON object, '' if not found
  String getByUUID(WasteTrackingHandle h, UserHandle u, String uuid) {
    final q = uuid.toNativeUtf8();
    try { return _rf(_getByUUID(h, u, q)); }
    finally { malloc.free(q); }
  }

  // Returns JSON array of calling operator's last 50 weighings
  String myList(WasteTrackingHandle h, UserHandle u) =>
      _rf(_myList(h, u));

  // changesJson: partial JSON with fields to correct
  // reason: mandatory for audit trail
  int correct(WasteTrackingHandle h, UserHandle u,
      int weighingId, String reason, String changesJson) {
    final r = reason.toNativeUtf8();
    final c = changesJson.toNativeUtf8();
    try { return _correct(h, u, weighingId, r, c); }
    finally { malloc.free(r); malloc.free(c); }
  }
}