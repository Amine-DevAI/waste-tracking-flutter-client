import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:waste_tracking/ffi/bindings/types.dart';
import 'package:waste_tracking/ffi/engine.dart';
import 'package:waste_tracking/ffi/models/reconciliation.dart';
import 'package:waste_tracking/ffi/models/model_helpers.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';
import 'package:waste_tracking/ffi/models/pending_reco.dart';
import 'package:waste_tracking/ffi/services/pending_service.dart';

class ReconciliationService {
  static final ReconciliationService instance = ReconciliationService._();
  ReconciliationService._();

  Reconciliation? _current;
  Reconciliation? get current => _current;

  void init(UserSession session) {
    WasteEngine.instance.reconciliation.setNotifyCallback(session.handle, (String signal) {
      if (signal == 'RECO_STEP_COMPLETED' || signal == 'RECO_STATE_UPDATED' || signal == 'RECO_REJECTED') {
        PendingService.instance.refreshRecoQueue();
      }
    });
  }

  /// Starts a reconciliation by scanning a QR. Fetches original record from C++.
  Future<bool> start(String qr) async {
    final session = AuthService.instance.session;
    if (session == null) return false;
    final json = WasteEngine.instance.reconciliation.getByQR(
      WasteEngine.instance.handle,
      session.handle,
      qr,
    );
    final data = unwrapJsonObject(json);
    if (data != null) {
      _current = Reconciliation.fromJson(data);
      return true;
    }
    return false;
  }

  /// Bypasses the start() call if we already have the item details from the pending queue.
  /// Used to avoid 409 errors when an item is in 'scanned' status.
  void setCurrentFromPending(PendingItem item) {
    _current = Reconciliation(
      id:             item.id,
      weighingId:     item.weighingId ?? 0,
      originalWeight: item.weight,
      originalGross:  item.originalGross,
      originalTare:   item.originalTare,
      uuid:           item.qrCode,
      status:         item.status,
      material:       item.material,
      product:        item.product,
      lot:            item.lot,
      isFlagged:      item.isFlagged,
    );
  }

  /// Submits the new weights measured by the validator.
  Future<RecoResult?> complete({required double gross, required double tare}) async {
    if (_current == null) return null;
    final session = AuthService.instance.session!;

    // FIX: round to avoid floating point garbage like 10.000000000000007
    final net = double.parse((gross - tare).toStringAsFixed(6));

    final json = WasteEngine.instance.reconciliation.submit(
      WasteEngine.instance.handle,
      session.handle,
      _current!.weighingId,
      net,
      gross,
      tare,
    );

    final map = jsonDecode(json) as Map<String, dynamic>;
    if (map['success'] == true) {
      return RecoResult.fromJson(map['data'], _current!.originalWeight);
    }
    return null;
  }

  Future<int> accept(int recoId) async {
    final session = AuthService.instance.session!;
    return WasteEngine.instance.reconciliation.accept(
      WasteEngine.instance.handle,
      session.handle,
      recoId,
    );
  }

  Future<int> reject(int recoId, String reason) async {
    final session = AuthService.instance.session!;
    return WasteEngine.instance.reconciliation.reject(
      WasteEngine.instance.handle,
      session.handle,
      recoId,
      reason,
    );
  }

  Future<List<Reconciliation>> list({String? status, int limit = 50}) async {
    final session = AuthService.instance.session;
    if (session == null || session.userId <= 0) return [];

    // Temporary debug
    print('[RecoService] list() — session user_id check: ${session.userId}');

    final json = WasteEngine.instance.reconciliation.myList(
      WasteEngine.instance.handle,
      session.handle,
      status: status ?? 'all',
    );
    return Reconciliation.fromJsonArray(json);
  }

  Future<int> correct(int recoId, String reason, Map<String, dynamic> changes) async {
    final session = AuthService.instance.session;
    if (session == null) return -1;
    return WasteEngine.instance.reconciliation.correct(
      WasteEngine.instance.handle,
      session.handle,
      recoId,
      reason,
      jsonEncode(changes),
    );
  }

  void cancel() => _current = null;
}