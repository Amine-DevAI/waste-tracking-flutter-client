import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';

import 'package:waste_tracking/ffi/bindings/scale.dart';
import 'package:waste_tracking/ffi/bindings/types.dart' hide WeightReading;
import 'package:waste_tracking/ffi/engine.dart';

// ============================================================================
// MODELS
// ============================================================================

class WeightReading {
  final String weight; // raw string e.g. "00353"
  final int errorCode;
  final String? errorMessage;

  bool get isSuccess => ScaleError.isSuccess(errorCode);

  const WeightReading({
    required this.weight,
    required this.errorCode,
    this.errorMessage,
  });

  factory WeightReading.fromNative(WeightReadingNative n) => WeightReading(
        weight: n.weightString,
        errorCode: n.error,
        errorMessage: n.errorString.isEmpty ? null : n.errorString,
      );

  @override
  String toString() => isSuccess
      ? 'WeightReading($weight)'
      : 'WeightReading(error: ${ScaleError.message(errorCode)} — $errorMessage)';
}

class WeightEvent {
  final String weight; // raw string e.g. "00353"
  final bool isStable;
  const WeightEvent(this.weight, {required this.isStable});

  @override
  String toString() => 'WeightEvent($weight stable:$isStable)';
}

// ============================================================================
// ISOLATE INTERNALS
// ============================================================================

class _WeightStreamError {
  final int errorCode;
  const _WeightStreamError(this.errorCode);
}

class _IsolateParams {
  final SendPort sendPort;
  final String libPath;
  final String portName;
  final int baudRate;
  final int stableRepeats;

  const _IsolateParams({
    required this.sendPort,
    required this.libPath,
    required this.portName,
    required this.baudRate,
    required this.stableRepeats,
  });
}

void _isolateEntry(_IsolateParams p) {
  final lib = DynamicLibrary.open(p.libPath);
  final b = ScaleBindings(lib);

  final handle = b.create(p.portName, p.baudRate);
  if (!b.isValid(handle)) {
    p.sendPort.send(_WeightStreamError(ScaleError.openFailed));
    p.sendPort.send('done');
    return;
  }

  final openErr = b.open(handle);
  if (!ScaleError.isSuccess(openErr)) {
    b.destroy(handle);
    p.sendPort.send(_WeightStreamError(openErr));
    p.sendPort.send('done');
    return;
  }

  final shouldStop = malloc<Int32>()..value = 0;
  final controlPort = ReceivePort();
  p.sendPort.send(controlPort.sendPort);

  controlPort.listen((msg) {
    if (msg == 'stop') shouldStop.value = 1;
  });

  final liveCallable = NativeCallable<NativeWeightCallback>.isolateLocal(
    (Pointer<Utf8> w, Pointer<Void> _) =>
        p.sendPort.send(WeightEvent(w.toDartString(), isStable: false)),
  );

  final stableCallable = NativeCallable<NativeWeightCallback>.isolateLocal(
    (Pointer<Utf8> w, Pointer<Void> _) =>
        p.sendPort.send(WeightEvent(w.toDartString(), isStable: true)),
  );

  try {
    final err = b.readContinuous(
      handle,
      liveCallable.nativeFunction,
      stableCallable.nativeFunction,
      nullptr,
      p.stableRepeats,
      shouldStop,
    );
    if (!ScaleError.isSuccess(err)) {
      p.sendPort.send(_WeightStreamError(err));
    }
  } finally {
    liveCallable.close();
    stableCallable.close();
    b.destroy(handle);
    malloc.free(shouldStop);
    controlPort.close();
    p.sendPort.send('done');
  }
}

// ============================================================================
// SCALE SERVICE
// ============================================================================

class ScaleService {
  final String portName;
  final int baudRate;
  final int stableRepeats;

  ScaleService({
    required this.portName,
    this.baudRate = 9600,
    this.stableRepeats = 5,
  });

  Stream<WeightEvent>? _stream;
  ReceivePort? _receivePort;
  SendPort? _controlPort;

  Stream<WeightEvent> get continuousStream {
    _stream ??= _buildStream();
    return _stream!;
  }

  Stream<WeightEvent> _buildStream() {
    final controller = StreamController<WeightEvent>.broadcast(
      onCancel: stop,
    );
    _receivePort = ReceivePort();

    _receivePort!.listen((msg) {
      if (msg is WeightEvent) {
        controller.add(msg);
      } else if (msg is SendPort) {
        _controlPort = msg;
      } else if (msg is _WeightStreamError) {
        controller.addError(ScaleError.message(msg.errorCode));
        controller.close();
      } else if (msg == 'done') {
        controller.close();
        _receivePort?.close();
        _receivePort = null;
        _stream = null;
      }
    });

    Isolate.spawn(
      _isolateEntry,
      _IsolateParams(
        sendPort: _receivePort!.sendPort,
        libPath: WasteEngine.libPath,
        portName: portName,
        baudRate: baudRate,
        stableRepeats: stableRepeats,
      ),
    );

    return controller.stream;
  }

  void stop() {
    _controlPort?.send('stop');
    _controlPort = null;
  }

  Future<WeightReading> readOnce({int timeoutMs = 8000}) {
    final libPath = WasteEngine.libPath;
    final port = portName;
    final baud = baudRate;
    final repeats = stableRepeats;

    return Isolate.run(() {
      final lib = DynamicLibrary.open(libPath);
      final b = ScaleBindings(lib);
      final handle = b.create(port, baud);

      if (!b.isValid(handle)) {
        return const WeightReading(
          weight: '',
          errorCode: ScaleError.openFailed,
          errorMessage: 'Could not create handle',
        );
      }

      final openErr = b.open(handle);
      if (!ScaleError.isSuccess(openErr)) {
        b.destroy(handle);
        return WeightReading(
          weight: '',
          errorCode: openErr,
          errorMessage: 'Failed to open $port @ ${baud}baud',
        );
      }

      try {
        return WeightReading.fromNative(
            b.readWeight(handle, timeoutMs: timeoutMs, stableRepeats: repeats));
      } finally {
        b.destroy(handle);
      }
    });
  }

  double _parseRawWeight(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[^0-9.+\-]'), '');
    if (cleaned.isEmpty) return 0.0;
    final parsed = double.tryParse(cleaned);
    return parsed ?? 0.0;
  }

  double _scaleRawToKg(String raw) {
    final value = _parseRawWeight(raw);
    if (value > 100.0) {
      return value / 1000.0;
    }
    return value;
  }

  Stream<double> get stableStream => continuousStream
      .where((e) => e.isStable)
      .map((e) => _scaleRawToKg(e.weight));

  Stream<double> get liveStream => continuousStream
      .where((e) => !e.isStable)
      .map((e) => _scaleRawToKg(e.weight));
}
