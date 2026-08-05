import 'dart:ffi';
import 'dart:async';
import 'package:ffi/ffi.dart';

typedef NativeScanCallback = Void Function(Pointer<Utf8> data);

typedef _NativeStart = Int32 Function(Pointer<Utf8> port, Int32 baud,
    Pointer<NativeFunction<NativeScanCallback>> cb);
typedef _DartStart = int Function(Pointer<Utf8> port, int baud,
    Pointer<NativeFunction<NativeScanCallback>> cb);

typedef _NativeStop = Void Function();
typedef _DartStop = void Function();
typedef _NativeRunning = Bool Function();
typedef _DartRunning = bool Function();

class ScannerBindings {
  final DynamicLibrary _lib;

  late final _DartStart _start;
  late final _DartStop _stop;
  late final _DartRunning _isRunning;

  NativeCallable<NativeScanCallback>? _callback;

  final _denat = StreamController<String>.broadcast();
  final _shipment = StreamController<String>.broadcast();
  final _reco = StreamController<String>.broadcast();

  Stream<String> get denatScans => _denat.stream;
  Stream<String> get shipmentScans => _shipment.stream;
  Stream<String> get recoScans => _reco.stream;

  _ActiveWorkflow _active = _ActiveWorkflow.none;

  void activateDenat() => _active = _ActiveWorkflow.denat;
  void activateShipment() => _active = _ActiveWorkflow.shipment;
  void activateReco() => _active = _ActiveWorkflow.reco;
  void deactivate() => _active = _ActiveWorkflow.none;

  ScannerBindings(this._lib) {
    _start = _lib.lookupFunction<_NativeStart, _DartStart>('scanner_start');
    _stop = _lib.lookupFunction<_NativeStop, _DartStop>('scanner_stop');
    _isRunning =
        _lib.lookupFunction<_NativeRunning, _DartRunning>('scanner_is_running');
  }

  bool start(String portName, {int baud = 9600}) {
    if (_isRunning()) return true;

    _callback?.close();
    _callback = NativeCallable<NativeScanCallback>.listener(
      (Pointer<Utf8> data) => _route(data.toDartString()),
    );

    final port = portName.toNativeUtf8();
    try {
      return _start(port, baud, _callback!.nativeFunction) == 0;
    } finally {
      malloc.free(port);
    }
  }

  void _route(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    switch (_active) {
      case _ActiveWorkflow.denat:
        _denat.add(v);
        break;
      case _ActiveWorkflow.shipment:
        _shipment.add(v);
        break;
      case _ActiveWorkflow.reco:
        _reco.add(v);
        break;
      case _ActiveWorkflow.none:
        break;
    }
  }

  void stop() {
    _stop();
    _callback?.close();
    _callback = null;
  }

  bool get isRunning => _isRunning();

  void dispose() {
    stop();
    _denat.close();
    _shipment.close();
    _reco.close();
  }
}

enum _ActiveWorkflow { none, denat, shipment, reco }
