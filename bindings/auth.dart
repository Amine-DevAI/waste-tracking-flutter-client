import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'types.dart';

typedef NativeAuthNotify = Void Function(Pointer<Utf8> signalName);
typedef NativeScanCallback = Void Function(Pointer<Utf8> qrData);

typedef _NativeSetScanCb = Void Function(UserHandle user, Pointer<NativeFunction<NativeScanCallback>> cb);
typedef _DartSetScanCb   = void Function(UserHandle user, Pointer<NativeFunction<NativeScanCallback>> cb);

typedef _NativeLogin     = UserHandle Function(WasteTrackingHandle h, Pointer<Utf8> u, Pointer<Utf8> p);
typedef _DartLogin       = UserHandle Function(WasteTrackingHandle h, Pointer<Utf8> u, Pointer<Utf8> p);

typedef _NativeLogout    = Void Function(UserHandle user);
typedef _DartLogout      = void Function(UserHandle user);

typedef _NativeSetNotify = Void Function(UserHandle user, Pointer<NativeFunction<NativeAuthNotify>> cb);
typedef _DartSetNotify   = void Function(UserHandle user, Pointer<NativeFunction<NativeAuthNotify>> cb);

typedef _NativeSockConn  = Int32 Function(UserHandle user);
typedef _DartSockConn    = int   Function(UserHandle user);

typedef _NativeSockDisc  = Void Function(UserHandle user);
typedef _DartSockDisc    = void Function(UserHandle user);

typedef _NativeSockReady = Int32 Function(UserHandle user);
typedef _DartSockReady   = int   Function(UserHandle user);

typedef _NativeCheckPerm = Pointer<Utf8> Function(UserHandle user, Pointer<Utf8> perm);
typedef _DartCheckPerm   = Pointer<Utf8> Function(UserHandle user, Pointer<Utf8> perm);

typedef _NativeHasCapability = Int32 Function(UserHandle user, Pointer<Utf8> capability);
typedef _DartHasCapability   = int   Function(UserHandle user, Pointer<Utf8> capability);

typedef _NativeGetCapabilities = Pointer<Utf8> Function(UserHandle user);
typedef _DartGetCapabilities   = Pointer<Utf8> Function(UserHandle user);

typedef _NativeGetI32    = Int32 Function(UserHandle user);
typedef _DartGetI32      = int   Function(UserHandle user);

typedef _NativeGetStr    = Pointer<Utf8> Function(UserHandle user);
typedef _DartGetStr      = Pointer<Utf8> Function(UserHandle user);

typedef _NativeUserList   = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);
typedef _DartUserList     = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);

typedef _NativeUserCreate = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u,
    Pointer<Utf8> username, Pointer<Utf8> password,
    Pointer<Utf8> fullName, Pointer<Utf8> role,
    Pointer<Utf8> capabilities, Int32 zoneId);
typedef _DartUserCreate = Pointer<Utf8> Function(
    WasteTrackingHandle h, UserHandle u,
    Pointer<Utf8> username, Pointer<Utf8> password,
    Pointer<Utf8> fullName, Pointer<Utf8> role,
    Pointer<Utf8> capabilities, int zoneId);

typedef _NativeUserUpdate = Int32 Function(
    WasteTrackingHandle h, UserHandle u, Int32 targetId, Pointer<Utf8> fieldsJson);
typedef _DartUserUpdate = int Function(
    WasteTrackingHandle h, UserHandle u, int targetId, Pointer<Utf8> fieldsJson);

typedef _NativeUserDelete = Int32 Function(WasteTrackingHandle h, UserHandle u, Int32 targetId);
typedef _DartUserDelete   = int   Function(WasteTrackingHandle h, UserHandle u, int  targetId);

typedef _NativeUserResetPw = Int32 Function(
    WasteTrackingHandle h, UserHandle u, Int32 targetId, Pointer<Utf8> newPw);
typedef _DartUserResetPw = int Function(
    WasteTrackingHandle h, UserHandle u, int targetId, Pointer<Utf8> newPw);

typedef _NativeSessionList  = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);
typedef _DartSessionList    = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);

typedef _NativeSessionDeact = Int32 Function(WasteTrackingHandle h, UserHandle u, Int32 targetId);
typedef _DartSessionDeact   = int   Function(WasteTrackingHandle h, UserHandle u, int  targetId);

typedef _NativeLogsList     = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);
typedef _DartLogsList       = Pointer<Utf8> Function(WasteTrackingHandle h, UserHandle u);

typedef _NativeFreeStr = Void Function(Pointer<Utf8> ptr);
typedef _DartFreeStr   = void Function(Pointer<Utf8> ptr);

class AuthBindings {
  final DynamicLibrary _lib;

  late final _DartLogin        _login;
  late final _DartLogout       _logout;
  late final _DartSetNotify    _setNotify;
  late final _DartSockConn     _sockConnect;
  late final _DartSockDisc     _sockDisconnect;
  late final _DartSockReady    _sockReady;
  late final _DartCheckPerm    _checkPermission;
  late final _DartHasCapability _hasCapability;
  late final _DartGetCapabilities _getCapabilities;
  late final _DartGetI32       _getUserId;
  late final _DartGetI32       _getZoneId;
  late final _DartGetI32       _getRole;
  late final _DartGetStr       _getUsername;
  late final _DartGetStr       _getFullName;
  late final _DartGetStr       _getStationId;
  late final _DartGetStr       _getCreatedAt;
  late final _DartGetStr       _getLastLogin;
  late final _DartUserList     _userList;
  late final _DartUserCreate   _userCreate;
  late final _DartUserUpdate   _userUpdate;
  late final _DartUserDelete   _userDelete;
  late final _DartUserResetPw  _userResetPw;
  late final _DartSessionList  _sessionList;
  late final _DartSessionDeact _sessionDeactivate;
  late final _DartLogsList     _logsList;
  late final _DartFreeStr      _freeStr;
  late final _DartSetScanCb    _onRecoScan;
  late final _DartSetScanCb    _onShipScan;
  late final _DartSetScanCb    _onDenatScan;

  NativeCallable<NativeAuthNotify>?   _notifyCb;
  NativeCallable<NativeScanCallback>? _recoScanCb;
  NativeCallable<NativeScanCallback>? _shipScanCb;
  NativeCallable<NativeScanCallback>? _denatScanCb;

  AuthBindings(this._lib) {
    _login             = _lib.lookupFunction<_NativeLogin,        _DartLogin>       ('auth_login');
    _logout            = _lib.lookupFunction<_NativeLogout,       _DartLogout>      ('auth_logout');
    _setNotify         = _lib.lookupFunction<_NativeSetNotify,    _DartSetNotify>   ('auth_set_notify_callback');
    _sockConnect       = _lib.lookupFunction<_NativeSockConn,     _DartSockConn>    ('auth_sockets_connect');
    _sockDisconnect    = _lib.lookupFunction<_NativeSockDisc,     _DartSockDisc>    ('auth_sockets_disconnect');
    _sockReady         = _lib.lookupFunction<_NativeSockReady,    _DartSockReady>   ('auth_sockets_ready');
    _checkPermission   = _lib.lookupFunction<_NativeCheckPerm,      _DartCheckPerm>       ('auth_check_permission');
    _hasCapability     = _lib.lookupFunction<_NativeHasCapability,   _DartHasCapability>    ('auth_has_capability');
    _getCapabilities   = _lib.lookupFunction<_NativeGetCapabilities,_DartGetCapabilities>('auth_get_capabilities');
    _getUserId         = _lib.lookupFunction<_NativeGetI32,         _DartGetI32>           ('auth_get_user_id');
    _getZoneId         = _lib.lookupFunction<_NativeGetI32,         _DartGetI32>           ('auth_get_zone_id');
    _getRole           = _lib.lookupFunction<_NativeGetI32,         _DartGetI32>           ('auth_get_role');
    _getUsername       = _lib.lookupFunction<_NativeGetStr,         _DartGetStr>           ('auth_get_username');
    _getFullName       = _lib.lookupFunction<_NativeGetStr,         _DartGetStr>           ('auth_get_full_name');
    _getStationId      = _lib.lookupFunction<_NativeGetStr,         _DartGetStr>           ('auth_get_station_id');
    _getCreatedAt      = _lib.lookupFunction<_NativeGetStr,         _DartGetStr>           ('auth_get_created_at');
    _getLastLogin      = _lib.lookupFunction<_NativeGetStr,         _DartGetStr>           ('auth_get_last_login');
    _userList          = _lib.lookupFunction<_NativeUserList,     _DartUserList>    ('user_list');
    _userCreate        = _lib.lookupFunction<_NativeUserCreate,   _DartUserCreate>  ('user_create');
    _userUpdate        = _lib.lookupFunction<_NativeUserUpdate,   _DartUserUpdate>  ('user_update');
    _userDelete        = _lib.lookupFunction<_NativeUserDelete,   _DartUserDelete>  ('user_delete');
    _userResetPw       = _lib.lookupFunction<_NativeUserResetPw,  _DartUserResetPw> ('user_reset_password');
    _sessionList       = _lib.lookupFunction<_NativeSessionList,  _DartSessionList> ('session_list');
    _sessionDeactivate = _lib.lookupFunction<_NativeSessionDeact, _DartSessionDeact>('session_deactivate');
    _logsList          = _lib.lookupFunction<_NativeLogsList,     _DartLogsList>    ('logs_list');
    _freeStr           = _lib.lookupFunction<_NativeFreeStr,      _DartFreeStr>     ('auth_free_string');
    _onRecoScan        = _lib.lookupFunction<_NativeSetScanCb,    _DartSetScanCb>   ('auth_set_reco_scan_callback');
    _onShipScan        = _lib.lookupFunction<_NativeSetScanCb,    _DartSetScanCb>   ('auth_set_ship_scan_callback');
    _onDenatScan       = _lib.lookupFunction<_NativeSetScanCb,    _DartSetScanCb>   ('auth_set_denat_scan_callback');
  }

  String _rf(Pointer<Utf8> ptr) {
    if (ptr.address == 0) return '';
    try { return ptr.toDartString(); } finally { _freeStr(ptr); }
  }

  void setNotifyCallback(UserHandle user, void Function(String signal) cb) {
    _notifyCb?.close();
    _notifyCb = NativeCallable<NativeAuthNotify>.listener(
      (Pointer<Utf8> sig) => cb(sig.toDartString()),
    );
    _setNotify(user, _notifyCb!.nativeFunction);
  }

  void closeCallback() {
    _notifyCb?.close();   _notifyCb   = null;
    _recoScanCb?.close(); _recoScanCb = null;
    _shipScanCb?.close(); _shipScanCb = null;
    _denatScanCb?.close(); _denatScanCb = null;
  }

  void onRecoScan(UserHandle user, void Function(String qr) cb) {
    _recoScanCb?.close();
    _recoScanCb = NativeCallable<NativeScanCallback>.listener(
      (Pointer<Utf8> qr) => cb(qr.toDartString()),
    );
    _onRecoScan(user, _recoScanCb!.nativeFunction);
  }

  void onShipScan(UserHandle user, void Function(String qr) cb) {
    _shipScanCb?.close();
    _shipScanCb = NativeCallable<NativeScanCallback>.listener(
      (Pointer<Utf8> qr) => cb(qr.toDartString()),
    );
    _onShipScan(user, _shipScanCb!.nativeFunction);
  }

  void onDenatScan(UserHandle user, void Function(String qr) cb) {
    _denatScanCb?.close();
    _denatScanCb = NativeCallable<NativeScanCallback>.listener(
      (Pointer<Utf8> qr) => cb(qr.toDartString()),
    );
    _onDenatScan(user, _denatScanCb!.nativeFunction);
  }

  UserHandle login(WasteTrackingHandle h, String username, String password) {
    final u = username.toNativeUtf8();
    final p = password.toNativeUtf8();
    try { return _login(h, u, p); }
    finally { malloc.free(u); malloc.free(p); }
  }

  void logout(UserHandle user) => _logout(user);

  int  socketsConnect(UserHandle user)    => _sockConnect(user);
  void socketsDisconnect(UserHandle user) => _sockDisconnect(user);
  bool socketsReady(UserHandle user)      => _sockReady(user) != 0;

  String checkPermission(UserHandle user, String permission) {
    final p = permission.toNativeUtf8();
    try {
      final r = _checkPermission(user, p);
      return r.address == 0 ? 'NO_SESSION' : r.toDartString();
    } finally { malloc.free(p); }
  }

  bool hasPermission(UserHandle user, String permission) =>
      checkPermission(user, permission) == 'OK';

  bool hasCapability(UserHandle user, String capability) {
    final c = capability.toNativeUtf8();
    try {
      return _hasCapability(user, c) != 0;
    } finally { malloc.free(c); }
  }

  String getCapabilities(UserHandle user) => _rf(_getCapabilities(user));

  int  getUserId(UserHandle user) => _getUserId(user);
  int  getZoneId(UserHandle user) => _getZoneId(user);
  int  getRole(UserHandle user)   => _getRole(user);

  String getUsername(UserHandle user)  => _rf(_getUsername(user));
  String getFullName(UserHandle user)  => _rf(_getFullName(user));
  String getStationId(UserHandle user) => _rf(_getStationId(user));
  String getCreatedAt(UserHandle user) => _rf(_getCreatedAt(user));
  String getLastLogin(UserHandle user) => _rf(_getLastLogin(user));

  String userList(WasteTrackingHandle h, UserHandle u) =>
      _rf(_userList(h, u));

  String userCreate(WasteTrackingHandle h, UserHandle u,
      String username, String password, String fullName,
      String role, String capabilities, int zoneId) {
    final un = username.toNativeUtf8();
    final pw = password.toNativeUtf8();
    final fn = fullName.toNativeUtf8();
    final ro = role.toNativeUtf8();
    final cs = capabilities.toNativeUtf8();
    try { return _rf(_userCreate(h, u, un, pw, fn, ro, cs, zoneId)); }
    finally { malloc.free(un); malloc.free(pw); malloc.free(fn); malloc.free(ro); malloc.free(cs); }
  }

  int userUpdate(WasteTrackingHandle h, UserHandle u,
      int targetId, String fieldsJson) {
    final f = fieldsJson.toNativeUtf8();
    try { return _userUpdate(h, u, targetId, f); }
    finally { malloc.free(f); }
  }

  int userDelete(WasteTrackingHandle h, UserHandle u, int targetId) =>
      _userDelete(h, u, targetId);

  int userResetPassword(WasteTrackingHandle h, UserHandle u,
      int targetId, String newPassword) {
    final p = newPassword.toNativeUtf8();
    try { return _userResetPw(h, u, targetId, p); }
    finally { malloc.free(p); }
  }

  String sessionList(WasteTrackingHandle h, UserHandle u) =>
      _rf(_sessionList(h, u));

  int sessionDeactivate(WasteTrackingHandle h, UserHandle u, int targetId) =>
      _sessionDeactivate(h, u, targetId);

  String logsList(WasteTrackingHandle h, UserHandle u) =>
      _rf(_logsList(h, u));
}