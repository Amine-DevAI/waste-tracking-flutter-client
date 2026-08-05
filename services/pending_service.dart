import 'dart:async';
import 'dart:convert';
import 'package:waste_tracking/ffi/bindings/types.dart';
import 'package:waste_tracking/ffi/engine.dart';
import 'package:waste_tracking/ffi/models/pending_reco.dart'; // For Reco/Denat
import 'package:waste_tracking/ffi/models/shipment.dart';     // For the new Shipment model
import 'package:waste_tracking/ffi/services/auth_service.dart';

class PendingService {
  static final PendingService instance = PendingService._();
  PendingService._();

  // ── Streams ──────────────────────────────────────────────────────────────
  final _recoQueueCtrl  = StreamController<List<PendingItem>>.broadcast();
  final _shipQueueCtrl  = StreamController<List<Shipment>>.broadcast(); // Switched to Shipment model
  final _denatQueueCtrl = StreamController<List<PendingItem>>.broadcast();

  Stream<List<PendingItem>> get recoQueue  => _recoQueueCtrl.stream;
  Stream<List<Shipment>>    get shipQueue  => _shipQueueCtrl.stream;
  Stream<List<PendingItem>> get denatQueue => _denatQueueCtrl.stream;

  bool _isRefreshingReco  = false;
  bool _isRefreshingShip  = false;
  bool _isRefreshingDenat = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  void init(UserSession session) {
    final engine = WasteEngine.instance;
    
    engine.pending.setNotifyCallback(session.handle, (String signal) {
      print('[PendingService] ⚡ Signal Received: $signal');
      
      switch (signal) {
        case 'RECO_STEP_COMPLETED':
          if (session.can('accept_reco')) refreshRecoQueue();
          break;
        case 'SHIPMENT_READY':
        case 'SHIPMENT_DISPATCHED':
          if (session.can('dispatch_shipment')) refreshShipQueue();
          break;
        case 'DENATURATION_PENDING':
          if (session.can('denaturation')) refreshDenatQueue();
          break;
      }
    });

    refreshAll();
  }

  Future<void> refreshAll() async {
    final session = AuthService.instance.session;
    if (session == null) return;

    if (session.can('accept_reco'))      unawaited(refreshRecoQueue());
    if (session.can('dispatch_shipment')) unawaited(refreshShipQueue());
    if (session.can('denaturation'))      unawaited(refreshDenatQueue());
  }

  // ── Logic: Reconciliation Queue ───────────────────────────────────────────
  Future<void> refreshRecoQueue() async {
    if (_isRefreshingReco) return;
    _isRefreshingReco = true;
    try {
      final session = AuthService.instance.session;
      if (session == null) return;

      final raw = WasteEngine.instance.pending.recoList(
        WasteEngine.instance.handle, session.handle);
      
      // Unwrap: C++ returns {"success": true, "data": [...]}
      final decoded = jsonDecode(raw);
      if (decoded['success'] == true) {
        final List<dynamic> data = decoded['data'] ?? [];
        final items = data.map((e) => PendingItem.fromJson(e)).toList();
        _recoQueueCtrl.add(items);
        print('[PendingService] ✅ Reco Queue: ${items.length} items.');
      }
    } catch (e) {
      print('[PendingService] ❌ Reco Refresh Failed: $e');
      _recoQueueCtrl.addError(e);
    } finally {
      _isRefreshingReco = false;
    }
  }

  // ── Logic: Shipment Queue (THE FIX) ───────────────────────────────────────
  Future<void> refreshShipQueue() async {
    if (_isRefreshingShip) return;
    _isRefreshingShip = true;
    try {
      final session = AuthService.instance.session;
      if (session == null) return;

      final raw = WasteEngine.instance.pending.shipList(
        WasteEngine.instance.handle, session.handle);
      
      // DECODE THE WRAPPER (Prevents the "String is not a Map" error)
      final decoded = jsonDecode(raw);
      
      if (decoded['success'] == true) {
        final List<dynamic> data = decoded['data'] ?? [];
        
        // Map to the robust Shipment model we just reviewed
        final items = data.map((e) => Shipment.fromJson(e)).toList();
        
        _shipQueueCtrl.add(items);
        print('[PendingService] ✅ Ship Queue: ${items.length} items.');
      } else {
        print('[PendingService] ⚠️ Server reported failure: ${decoded['error']}');
      }
    } catch (e) {
      print('[PendingService] ❌ Ship Refresh Failed: $e');
      _shipQueueCtrl.addError(e);
    } finally {
      _isRefreshingShip = false;
    }
  }

  // ── Logic: Denaturation Queue ─────────────────────────────────────────────
  Future<void> refreshDenatQueue() async {
    if (_isRefreshingDenat) return;
    _isRefreshingDenat = true;
    try {
      final session = AuthService.instance.session;
      if (session == null) return;

      final raw = WasteEngine.instance.pending.denatList(
        WasteEngine.instance.handle, session.handle);
      
      final decoded = jsonDecode(raw);
      if (decoded['success'] == true) {
        final List<dynamic> data = decoded['data'] ?? [];
        final items = data.map((e) => PendingItem.fromJson(e)).toList();
        _denatQueueCtrl.add(items);
        print('[PendingService] ✅ Denat Queue: ${items.length} items.');
      }
    } catch (e) {
      print('[PendingService] ❌ Denat Refresh Failed: $e');
      _denatQueueCtrl.addError(e);
    } finally {
      _isRefreshingDenat = false;
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────
  void reset() {
    WasteEngine.instance.pending.closeCallback();
    _recoQueueCtrl.add([]);
    _shipQueueCtrl.add([]);
    _denatQueueCtrl.add([]);
    print('[PendingService] 🛡️ FFI callbacks closed and stream queues cleared.');
  }

  void dispose() {
    reset();
    _recoQueueCtrl.close();
    _shipQueueCtrl.close();
    _denatQueueCtrl.close();
  }
}