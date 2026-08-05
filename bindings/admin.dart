import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'types.dart';

// AdminNotifyCallback: void (*)(const char* signal_name)
// Signals: "NEW_FLAG_ALERT","FLAG_RESOLVED","WEIGHING_CORRECTED",
//          "RECO_STATE_UPDATED","SHIPMENT_DISPATCHED",
//          "USER_CREATED","USER_UPDATED","USER_DEACTIVATED"
typedef NativeAdminNotify = Void Function(Pointer<Utf8> signalName);

// All list functions accept filters_json — pass nullptr/"" for no filter
typedef _NativeListWithFilter = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> filtersJson);
typedef _DartListWithFilter = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u, Pointer<Utf8> filtersJson);

typedef _NativeListNoFilter = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);
typedef _DartListNoFilter   = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);

typedef _NativeFlagMarkRead = Int32 Function(
    WasteTrackingHandle h, UserHandle u, Int32 flagId);
typedef _DartFlagMarkRead = int Function(
    WasteTrackingHandle h, UserHandle u, int flagId);

typedef _NativeSessionDeact = Int32 Function(
    WasteTrackingHandle h, UserHandle u, Int32 targetUserId);
typedef _DartSessionDeact = int Function(
    WasteTrackingHandle h, UserHandle u, int targetUserId);

typedef _NativeSetNotify = Void Function(UserHandle u, Pointer<NativeFunction<NativeAdminNotify>> cb);
typedef _DartSetNotify   = void Function(UserHandle u, Pointer<NativeFunction<NativeAdminNotify>> cb);

typedef _NativeFreeStr = Void Function(Pointer<Utf8> ptr);
typedef _DartFreeStr   = void Function(Pointer<Utf8> ptr);

class AdminBindings {
  final DynamicLibrary _lib;

  late final _DartListWithFilter _weighList;
  late final _DartListWithFilter _recoList;
  late final _DartListWithFilter _shipList;
  late final _DartListNoFilter   _flagsList;
  late final _DartFlagMarkRead   _flagMarkRead;
  late final _DartListWithFilter _correctionsList;
  late final _DartListNoFilter   _exportAll;
  late final _DartListNoFilter   _sessionsList;
  late final _DartSessionDeact   _sessionDeactivate;
  late final _DartListNoFilter   _logsList;
  late final _DartListWithFilter _denatList;
  late final _DartSetNotify      _setNotify;
  late final _DartFreeStr        _freeStr;

  NativeCallable<NativeAdminNotify>? _notifyCb;

  AdminBindings(this._lib) {
    _weighList         = _lib.lookupFunction<_NativeListWithFilter, _DartListWithFilter>('admin_weigh_list');
    _recoList          = _lib.lookupFunction<_NativeListWithFilter, _DartListWithFilter>('admin_reco_list');
    _shipList          = _lib.lookupFunction<_NativeListWithFilter, _DartListWithFilter>('admin_ship_list');
    _flagsList         = _lib.lookupFunction<_NativeListNoFilter,   _DartListNoFilter>  ('admin_flags_list');
    _flagMarkRead      = _lib.lookupFunction<_NativeFlagMarkRead,   _DartFlagMarkRead>  ('admin_flag_mark_read');
    _correctionsList   = _lib.lookupFunction<_NativeListWithFilter, _DartListWithFilter>('admin_corrections_list');
    _exportAll         = _lib.lookupFunction<_NativeListNoFilter,   _DartListNoFilter>  ('admin_export_all');
    _sessionsList      = _lib.lookupFunction<_NativeListNoFilter,   _DartListNoFilter>  ('admin_sessions_list');
    _sessionDeactivate = _lib.lookupFunction<_NativeSessionDeact,   _DartSessionDeact>  ('admin_session_deactivate');
    _logsList          = _lib.lookupFunction<_NativeListNoFilter,   _DartListNoFilter>  ('admin_logs_list');
    _denatList         = _lib.lookupFunction<_NativeListWithFilter, _DartListWithFilter>('admin_denat_list');
    _setNotify         = _lib.lookupFunction<_NativeSetNotify,      _DartSetNotify>     ('admin_set_notify_callback');
    _freeStr           = _lib.lookupFunction<_NativeFreeStr,        _DartFreeStr>       ('admin_free_string');
  }

  String _rf(Pointer<Utf8> ptr) {
    if (ptr.address == 0) return '';
    try { return ptr.toDartString(); } finally { _freeStr(ptr); }
  }

  String _rfFilter(
      Pointer<Utf8> Function(WasteTrackingHandle, UserHandle, Pointer<Utf8>) fn,
      WasteTrackingHandle h, UserHandle u, String filtersJson) {
    final f = filtersJson.toNativeUtf8();
    try { return _rf(fn(h, u, f)); }
    finally { malloc.free(f); }
  }

  void setNotifyCallback(UserHandle user, void Function(String signal) cb) {
    _notifyCb?.close();
    _notifyCb = NativeCallable<NativeAdminNotify>.listener(
      (Pointer<Utf8> sig) => cb(sig.toDartString()),
    );
    _setNotify(user, _notifyCb!.nativeFunction);
  }

  void closeCallback() { _notifyCb?.close(); _notifyCb = null; }

  // filtersJson keys: status, type_id, search, limit, offset
  String weighList(WasteTrackingHandle h, UserHandle u, {String filters = '{}'}) =>
      _rfFilter(_weighList, h, u, filters);

  // filtersJson keys: status, search, limit, offset
  String recoList(WasteTrackingHandle h, UserHandle u, {String filters = '{}'}) =>
      _rfFilter(_recoList, h, u, filters);

  // filtersJson keys: filter("all"|"pending"|"shipped"|"flagged"), start, limit
  String shipList(WasteTrackingHandle h, UserHandle u, {String filters = '{}'}) =>
      _rfFilter(_shipList, h, u, filters);

  // All unresolved flags — no filter
  String flagsList(WasteTrackingHandle h, UserHandle u) =>
      _rf(_flagsList(h, u));

  // Returns WtError
  int flagMarkRead(WasteTrackingHandle h, UserHandle u, int flagId) =>
      _flagMarkRead(h, u, flagId);

  // filtersJson keys: table_name, record_id
  String correctionsList(WasteTrackingHandle h, UserHandle u, {String filters = '{}'}) =>
      _rfFilter(_correctionsList, h, u, filters);

  // Full traceability master view — call only on explicit export button
  String exportAll(WasteTrackingHandle h, UserHandle u) =>
      _rf(_exportAll(h, u));

  // Active sessions (last 5 minutes)
  String sessionsList(WasteTrackingHandle h, UserHandle u) =>
      _rf(_sessionsList(h, u));

  // Returns WtError — also fires FORCE_LOGOUT to target via heartbeat
  int sessionDeactivate(WasteTrackingHandle h, UserHandle u, int targetUserId) =>
      _sessionDeactivate(h, u, targetUserId);

  // Last 100 login attempts
  String logsList(WasteTrackingHandle h, UserHandle u) =>
      _rf(_logsList(h, u));

  // filtersJson keys: status("pending"|"completed"|"all"), limit
  String denatList(WasteTrackingHandle h, UserHandle u, {String filters = '{}'}) =>
      _rfFilter(_denatList, h, u, filters);
}