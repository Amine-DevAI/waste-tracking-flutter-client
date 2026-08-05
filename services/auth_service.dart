import 'dart:async';
import 'dart:convert';
import 'package:waste_tracking/ffi/bindings/types.dart';
import 'package:waste_tracking/ffi/engine.dart';
import 'package:waste_tracking/ffi/models/model_helpers.dart';
import 'package:waste_tracking/ffi/models/user.dart';
import 'package:waste_tracking/ffi/services/pending_service.dart';
import 'package:waste_tracking/ffi/services/scanner_service.dart';
import 'package:waste_tracking/ffi/services/reconciliation_service.dart';
import 'package:waste_tracking/ffi/services/shipment_service.dart';
import 'package:waste_tracking/ffi/services/denaturation_service.dart';

extension SessionPermissions on UserSession {
  bool can(String permission) {
    final auth = WasteEngine.instance.auth;
    return auth.hasCapability(handle, permission) ||
        auth.hasPermission(handle, permission);
  }

  bool hasCapability(String capability) =>
      WasteEngine.instance.auth.hasCapability(handle, capability);

  String get roleName => UserRole.name(role);
}

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  UserSession? _session;
  UserSession? get session => _session;
  bool get isLoggedIn => _session != null;

  StreamController<String>? _forceLogoutController;
  Stream<String> get onForceLogout =>
      (_forceLogoutController ??= StreamController<String>.broadcast()).stream;

  StreamController<String>? _refreshController;
  Stream<String> get onRefresh =>
      (_refreshController ??= StreamController<String>.broadcast()).stream;

  Future<UserSession> login(String username, String password) async {
    if (isLoggedIn) await logout();

    final engine = WasteEngine.instance;

    // ✅ All synchronous FFI calls run off the UI thread via Future()
    // so the spinner stays alive and the UI never freezes.
    // WasteEngineException is thrown here with the engine's own error message,
    // which login_screen.dart catches and displays directly.
    final sessionData = await Future(() {
      final handle = engine.auth.login(engine.handle, username, password);

      if (handle.address == 0) {
        throw WasteEngineException(engine.lastError.isNotEmpty
            ? engine.lastError
            : 'Invalid credentials');
      }

      return (
        handle: handle,
        role:   engine.auth.getRole(handle),
        zoneId: engine.auth.getZoneId(handle),
        userId: engine.auth.getUserId(handle),
        uname:  engine.auth.getUsername(handle),
        fname:  engine.auth.getFullName(handle),
        caps:   engine.auth.getCapabilities(handle),
        sid:    engine.auth.getStationId(handle),
      );
    });

    _session = UserSession(
      handle:       sessionData.handle,
      userId:       sessionData.userId,
      zoneId:       sessionData.zoneId,
      username:     sessionData.uname,
      fullName:     sessionData.fname,
      capabilities: sessionData.caps,
      role:         sessionData.role,
      sessionToken: '', // token lives in C++ session only
      stationId:    sessionData.sid,
    );

    // Wire auth signals before we connect sockets for a zero-window miss.
    engine.auth.setNotifyCallback(_session!.handle, (String signal) {
      if (signal == 'FORCE_LOGOUT') {
        _session = null;
        if (!(_forceLogoutController?.isClosed ?? true))
          _forceLogoutController?.add(signal);
      } else {
        if (!(_refreshController?.isClosed ?? true))
          _refreshController?.add(signal);
      }
    });

    final socketOk = engine.auth.socketsConnect(_session!.handle);
    if (socketOk == 0) {
      throw WasteEngineException(
          'Socket connection failed for user ${sessionData.userId}');
    }

    // Maintain all service callbacks and queue refresh streams.
    ScannerService.instance.startAll(_session!);
    PendingService.instance.init(_session!);
    ReconciliationService.instance.init(_session!);
    ShipmentService.instance.init(_session!);
    DenaturationService.instance.init(_session!);

    return _session!;
  }

  Future<void> logout() async {
    if (!isLoggedIn) return;

    ScannerService.instance.stopAll();

    WasteEngine.instance.logout(_session!.handle);
    WasteEngine.instance.auth.closeCallback();
    WasteEngine.instance.pending.closeCallback();
    WasteEngine.instance.reconciliation.closeCallback();
    WasteEngine.instance.shipment.closeCallback();
    WasteEngine.instance.denat.closeCallback();
    WasteEngine.instance.admin.closeCallback();

    _refreshController?.close();
    _forceLogoutController?.close();

    _session = null;

    _refreshController      = StreamController<String>.broadcast();
    _forceLogoutController  = StreamController<String>.broadcast();
  }

  Future<List<User>> listUsers() async {
    _requireLogin();
    final json = WasteEngine.instance.auth
        .userList(WasteEngine.instance.handle, _session!.handle);
    return User.fromJsonArray(json);
  }

  Future<int> createUser({
    required String username,
    required String password,
    required String fullName,
    required String role, // "admin" | "operator" | "validator" | "Coordinateur"
    required String capabilities,
    int zoneId = -1,
  }) async {
    _requireLogin();
    final resultJson = WasteEngine.instance.auth.userCreate(
      WasteEngine.instance.handle,
      _session!.handle,
      username,
      password,
      fullName,
      role,
      capabilities,
      zoneId,
    );

    try {
      final parsed = jsonDecode(resultJson);
      if (parsed is Map<String, dynamic>) {
        if (parsed['success'] == true) {
          final data = parsed['data'];
          if (data is Map<String, dynamic>) {
            return parseInt(data['id']);
          }
          return 0;
        }
        final error = parsed['error']?.toString() ?? 'Create user failed';
        throw WasteEngineException(error);
      }
      throw WasteEngineException('Unexpected createUser response');
    } catch (e) {
      throw WasteEngineException('Create user error: $e');
    }
  }

  Future<int> deleteUser(int userId) async {
    _requireLogin();
    return WasteEngine.instance.auth
        .userDelete(WasteEngine.instance.handle, _session!.handle, userId);
  }

  Future<int> resetPassword(int userId, String newPassword) async {
    _requireLogin();
    return WasteEngine.instance.auth.userResetPassword(
        WasteEngine.instance.handle, _session!.handle, userId, newPassword);
  }

  Future<int> updateUser(int userId, Map<String, dynamic> fields) async {
    _requireLogin();
    final fieldsJson = jsonEncode(fields);
    return WasteEngine.instance.auth.userUpdate(
        WasteEngine.instance.handle, _session!.handle, userId, fieldsJson);
  }

  void _requireLogin() {
    if (!isLoggedIn) throw WasteEngineException('Not logged in');
  }
}