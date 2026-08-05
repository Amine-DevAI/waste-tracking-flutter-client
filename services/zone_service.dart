import 'dart:isolate';
import 'package:waste_tracking/ffi/engine.dart';
import 'package:waste_tracking/ffi/models/zone.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';

class ZoneService {
  static final ZoneService instance = ZoneService._();
  ZoneService._();

  WasteEngine get _e  => WasteEngine.instance;
  get _ctx            => _e.handle;
  get _usr            => AuthService.instance.session!.handle;

  Future<List<Zone>> list() async {
    final json = _e.zone.list(_ctx);
    return Zone.fromJsonArray(json);
  }

      Future<int> insert(String code, String name) async =>
        _e.zone.insert(_ctx, _usr, code, name);

  // active=false soft-deletes, active=true restores
      Future<int> update(int zoneId, String code, String name,
        {bool active = true}) async =>
        _e.zone.update(_ctx, _usr, zoneId, code, name, active: active);
}