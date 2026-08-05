import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:waste_tracking/ffi/bindings/types.dart';
import 'package:waste_tracking/ffi/engine.dart';
import 'package:waste_tracking/ffi/models/weighing.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';

class WeighingService {
  static final WeighingService instance = WeighingService._();
  WeighingService._();

  /// Creates a new weighing record and returns the UUID for the QR label.
  Future<String?> create({
    required int typeId,
    int productId = 0,
    required double gross,
    required double tare,
    String? lot,
  }) async {
    final session = AuthService.instance.session;
    if (session == null) return null;
    final uuid = WasteEngine.instance.weighing.create(
      WasteEngine.instance.handle,
      session.handle,
      typeId: typeId,
      productId: productId,
      grossWeight: gross,
      tareWeight: tare,
      lotNumber: lot ?? '',
    );
    return uuid.isEmpty ? null : uuid;
  }

  Future<Weighing?> getByUuid(String uuid) async {
    final session = AuthService.instance.session;
    if (session == null) return null;
    final json = WasteEngine.instance.weighing.getByUUID(
      WasteEngine.instance.handle,
      session.handle,
      uuid,
    );
    return Weighing.fromJsonObject(json);
  }

  Future<List<Weighing>> myList() async {
    final session = AuthService.instance.session;
    if (session == null) return [];
    final json = WasteEngine.instance.weighing.myList(WasteEngine.instance.handle, session.handle);
    return Weighing.fromJsonArray(json);
  }

  /// Correct an existing weighing (server audits + flags).
  /// `changes` is a partial JSON object, e.g.:
  /// `{ "gross_weight": 12.5, "tare_weight": 0.8 }`
  Future<int> correct({
    required int weighingId,
    required String reason,
    required Map<String, dynamic> changes,
  }) async {
    final session = AuthService.instance.session;
    if (session == null) return WtError.authentication;
    final changesJson = jsonEncode(changes);
    return WasteEngine.instance.weighing.correct(
      WasteEngine.instance.handle,
      session.handle,
      weighingId,
      reason,
      changesJson,
    );
  }
}