import 'dart:isolate';
import 'package:waste_tracking/ffi/bindings/types.dart';
import 'package:waste_tracking/ffi/engine.dart';
import 'package:waste_tracking/ffi/models/denaturation.dart';
import 'package:waste_tracking/ffi/models/model_helpers.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';
import 'package:waste_tracking/ffi/services/pending_service.dart';

class DenaturationService {
  static final DenaturationService instance = DenaturationService._();
  DenaturationService._();

  WasteEngine get _e  => WasteEngine.instance;
  get _ctx            => _e.handle;
  get _usr            => AuthService.instance.session!.handle;

  // ── init — wire signal callback ───────────────────────────────────────────
  void init(UserSession session) {
    _e.denat.setNotifyCallback(session.handle, (String signal) {
      if (signal == 'DENATURATION_PENDING' || signal == 'DENATURATION_SUCCESS') {
        PendingService.instance.refreshDenatQueue();
      }
    });
  }

  // ── scanByQR — coordinateur scans the bag ─────────────────────────────────
  Future<Denaturation?> scanByQR(String qrData) async {
    final json = _e.denat.scanByQR(_ctx, _usr, qrData);
    final data = unwrapJsonObject(json);
    return data != null ? Denaturation.fromJson(data) : null;
  }

  // ── submit — coordinateur enters final weights after denaturation ──────────
  Future<int> submit({
    required int    denatId,
    required double brutAfter,
    required double netAfter,
    required String qrScanned,
    String          note = '',
  }) async {
    return _e.denat.submit(
      _ctx, _usr,
      denatId, brutAfter, netAfter, qrScanned,
      note: note,
    );
  }

  // ── myList — coordinateur history ─────────────────────────────────────────
  Future<List<Denaturation>> myList({int limit = 20}) async {
    final json = _e.denat.myList(_ctx, _usr, limit: limit);
    return Denaturation.fromJsonArray(json);
  }

  // ── correct — fix wrong weights on a completed operation ──────────────────
  Future<int> correct({
    required int    denatId,
    required double newNet,
    required double newBrut,
    required String reason,
  }) async {
    return _e.denat.correct(_ctx, _usr, denatId, newNet, newBrut, reason);
  }
}