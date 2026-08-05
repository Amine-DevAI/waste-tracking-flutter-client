import 'dart:async';

import 'package:waste_tracking/ffi/bindings/types.dart';
import 'package:waste_tracking/ffi/engine.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';

// ============================================================================
// SCANNER SERVICE
//
// Scan data arrives via the WebSocket bridge sockets already set up in C++.
// The phone scans a QR on the mobile page → server relays it → C++ fires
// auth_on_reco_scan or auth_on_ship_scan callback → we receive it here.
//
// No phantom C++ symbols needed — the bridge is already wired in the
// SocketConnection layer. We just register the callbacks once after
// socketsConnect() and expose Dart streams.
//
// Callbacks fire from C++'s IXWebSocket thread — NativeCallable.listener
// is used inside AuthBindings which handles the cross-thread dispatch.
// We receive the string on the Dart side and add it to the stream.
// ============================================================================

enum ScanType { reco, shipment, denaturation }

class ScanEvent {
  final String   qrData;
  final ScanType type;
  const ScanEvent({required this.qrData, required this.type});

  @override
  String toString() => 'ScanEvent($type: $qrData)';
}

class ScannerService {
  static final ScannerService instance = ScannerService._();
  ScannerService._();

  final _controller = StreamController<ScanEvent>.broadcast();

  Stream<ScanEvent> get scanEvents     => _controller.stream;
  Stream<String>    get recoScans      =>
      scanEvents.where((e) => e.type == ScanType.reco).map((e) => e.qrData);
  Stream<String>    get shipmentScans  =>
      scanEvents.where((e) => e.type == ScanType.shipment).map((e) => e.qrData);
  Stream<String>    get denatScans     =>
      scanEvents.where((e) => e.type == ScanType.denaturation).map((e) => e.qrData);

  UserHandle? _activeHandle;

  // ── register ──────────────────────────────────────────────────────────────
  ///
  /// register() MUST be called from the main isolate.
  void register(UserSession session) {
    if (_activeHandle == session.handle) return;
    _activeHandle = session.handle;

    final auth = WasteEngine.instance.auth;

    auth.onRecoScan(session.handle, (String qr) {
      if (!_controller.isClosed)
        _controller.add(ScanEvent(qrData: qr, type: ScanType.reco));
    });

    auth.onShipScan(session.handle, (String qr) {
      if (!_controller.isClosed)
        _controller.add(ScanEvent(qrData: qr, type: ScanType.shipment));
    });

    auth.onDenatScan(session.handle, (String qr) {
      if (!_controller.isClosed)
        _controller.add(ScanEvent(qrData: qr, type: ScanType.denaturation));
    });
  }

  /// Inject a manually entered QR code as if it came from the scanner bridge.
  /// The UI calls this from a text field submit handler.
  void injectManualQR(ScanType type, String qrData) {
    final cleanData = qrData.trim();
    if (!_controller.isClosed && cleanData.isNotEmpty) {
      _controller.add(ScanEvent(qrData: cleanData, type: type));
    }
  }

  // ── unregister ────────────────────────────────────────────────────────────
  void unregister() {
    _activeHandle = null;
  }

  // ── dispose ───────────────────────────────────────────────────────────────
  void dispose() {
    unregister();
    _controller.close();
  }

  // ── convenience aliases ──────────────────────────────────────────────────
  void startAll(UserSession session) => register(session);
  void stopAll() => unregister();

  // ── QR Code Generation ────────────────────────────────────────────────────

  /// Generates the payload for the desktop "Link Mobile" QR code.
  /// The mobile app scans this to know which server to talk to and 
  /// which station ID to impersonate when sending scans.
  String buildStationPayload() {
    final session = AuthService.instance.session;
    final ip = WasteEngine.instance.currentServerIp;
    
    if (session == null || ip.isEmpty) return '';

    final String sid = session.stationId;
    return 'PT_LINK:$ip|$sid';
  }

  /// Generates a payload that includes the specific workflow mode.
  /// Format: PT_LINK:IP|STATION_ID|MODE
  String buildModePayload(String mode) {
    final base = buildStationPayload();
    return base.isEmpty ? '' : '$base|$mode';
  }

  // Updated convenience methods for the UI to use the new protocol
  String getRecoQrPayload()  => buildModePayload('reco');
  String getShipQrPayload()  => buildModePayload('ship');
  String getDenatQrPayload() => buildModePayload('denat');
}