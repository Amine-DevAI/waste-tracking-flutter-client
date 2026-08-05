

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:waste_tracking/ffi/bindings/types.dart';
import 'package:waste_tracking/ffi/bindings/auth.dart';
import 'package:waste_tracking/ffi/bindings/context.dart';
import 'package:waste_tracking/ffi/bindings/reconciliation.dart';
import 'package:waste_tracking/ffi/bindings/weighing.dart';
import 'package:waste_tracking/ffi/bindings/shipment.dart';
import 'package:waste_tracking/ffi/bindings/admin.dart';
import 'package:waste_tracking/ffi/bindings/catalog.dart';
import 'package:waste_tracking/ffi/bindings/zone.dart';
import 'package:waste_tracking/ffi/bindings/pending.dart';
import 'package:waste_tracking/ffi/bindings/denat.dart';
import 'package:waste_tracking/ffi/bindings/scanner.dart';







class WasteEngineException implements Exception {
  final String message;
  WasteEngineException(this.message);
  @override
  String toString() => message;
}

class WasteEngine {
    // Returns the last error from the native context, if any
    String get lastError => context.getError(handle);

    // Logs out the given user handle using the native bindings
    void logout(UserHandle user) => auth.logout(user);
  static WasteEngine? _instance;
  static WasteEngine get instance => _instance ??= WasteEngine._();

  String _serverIp = '';
  String get currentServerIp => _serverIp;

  final DynamicLibrary _lib;
  late final WasteTrackingHandle handle;

  late final AuthBindings auth;
  late final ContextBindings context;
  // bindings/reconciliation.dart defines RecoBindings (not ReconciliationBindings)
  late final RecoBindings reconciliation;
  late final WeighingBindings weighing;
  // bindings/shipment.dart defines ShipBindings (not ShipmentBindings)
  late final ShipBindings shipment;
  late final AdminBindings admin;
  late final CatalogBindings catalog;
  late final ZoneBindings zone;
  late final PendingBindings pending;
  late final DenatBindings denat;
  late final ScannerBindings scanner;

  WasteEngine._() : _lib = DynamicLibrary.open(libPath) {
    auth = AuthBindings(_lib);
    context = ContextBindings(_lib);
    reconciliation = RecoBindings(_lib);
    weighing = WeighingBindings(_lib);
    shipment = ShipBindings(_lib);
    admin = AdminBindings(_lib);
    catalog = CatalogBindings(_lib);
    zone = ZoneBindings(_lib);
    pending = PendingBindings(_lib);
    denat = DenatBindings(_lib);
    scanner = ScannerBindings(_lib);

    // IP is set later via init() — pass empty for now
    handle = context.init('');
  }

  static String get libPath {
    if (Platform.isLinux || Platform.isAndroid) return 'libwaste_engine.so';
    if (Platform.isWindows) return 'waste_engine.dll';
    throw UnsupportedError('Platform not supported');
  }

  void init(String ip) {
    _serverIp = ip;
    context.setServer(handle, ip);
  }



  // Old sync method for legacy use
  // Synchronous (legacy, blocks UI!)
  bool switchServer(String ip) {
    _serverIp = ip;
    context.setServer(handle, ip);
    return true;
  }






}

