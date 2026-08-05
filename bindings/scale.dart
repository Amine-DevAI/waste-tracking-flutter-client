import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'types.dart';

// WeightCallback: void (*)(const char* weight, void* user_data)
typedef NativeWeightCallback = Void Function(Pointer<Utf8> weight, Pointer<Void> userData);

typedef _NativeCreate = ScaleReaderHandle Function(Pointer<Utf8> portName, Int32 baudRate);
typedef _DartCreate   = ScaleReaderHandle Function(Pointer<Utf8> portName, int baudRate);

typedef _NativeOpen = Int32 Function(ScaleReaderHandle handle);
typedef _DartOpen   = int   Function(ScaleReaderHandle handle);

typedef _NativeClose = Void Function(ScaleReaderHandle handle);
typedef _DartClose   = void Function(ScaleReaderHandle handle);

typedef _NativeIsOpen = Int32 Function(ScaleReaderHandle handle);
typedef _DartIsOpen   = int   Function(ScaleReaderHandle handle);

typedef _NativeDestroy = Void Function(ScaleReaderHandle handle);
typedef _DartDestroy   = void Function(ScaleReaderHandle handle);

typedef _NativeGetError = Pointer<Utf8> Function(ScaleReaderHandle handle);
typedef _DartGetError   = Pointer<Utf8> Function(ScaleReaderHandle handle);

typedef _NativeReadWeight = WeightReading Function(
    ScaleReaderHandle handle, Int32 timeoutMs, Int32 stableRepeats);
typedef _DartReadWeight = WeightReading Function(
    ScaleReaderHandle handle, int timeoutMs, int stableRepeats);

typedef _NativeReadContinuous = Int32 Function(
    ScaleReaderHandle handle,
    Pointer<NativeFunction<NativeWeightCallback>> liveCallback,
    Pointer<NativeFunction<NativeWeightCallback>> stableCallback,
    Pointer<Void> userData,
    Int32 stableRepeats,
    Pointer<Int32> shouldStop);
typedef _DartReadContinuous = int Function(
    ScaleReaderHandle handle,
    Pointer<NativeFunction<NativeWeightCallback>> liveCallback,
    Pointer<NativeFunction<NativeWeightCallback>> stableCallback,
    Pointer<Void> userData,
    int stableRepeats,
    Pointer<Int32> shouldStop);

class ScaleBindings {
  final DynamicLibrary _lib;

  late final _DartCreate         _create;
  late final _DartOpen           _open;
  late final _DartClose          _close;
  late final _DartIsOpen         _isOpen;
  late final _DartDestroy        _destroy;
  late final _DartGetError       _getError;
  late final _DartReadWeight     _readWeight;
  late final _DartReadContinuous _readContinuous;

  ScaleBindings(this._lib) {
    _create         = _lib.lookupFunction<_NativeCreate,         _DartCreate>        ('scale_reader_create');
    _open           = _lib.lookupFunction<_NativeOpen,           _DartOpen>          ('scale_reader_open');
    _close          = _lib.lookupFunction<_NativeClose,          _DartClose>         ('scale_reader_close');
    _isOpen         = _lib.lookupFunction<_NativeIsOpen,         _DartIsOpen>        ('scale_reader_is_open');
    _destroy        = _lib.lookupFunction<_NativeDestroy,        _DartDestroy>       ('scale_reader_destroy');
    _getError       = _lib.lookupFunction<_NativeGetError,       _DartGetError>      ('scale_reader_get_error');
    _readWeight     = _lib.lookupFunction<_NativeReadWeight,     _DartReadWeight>    ('scale_reader_read_weight');
    _readContinuous = _lib.lookupFunction<_NativeReadContinuous, _DartReadContinuous>('scale_reader_read_continuous');
  }

  ScaleReaderHandle create(String portName, int baudRate) {
    final p = portName.toNativeUtf8();
    try { return _create(p, baudRate); }
    finally { malloc.free(p); }
  }

  int open(ScaleReaderHandle handle) {
    if (handle.address == 0) return ScaleErr.invalidPort;
    return _open(handle);
  }

  void close(ScaleReaderHandle handle) {
    if (handle.address != 0) _close(handle);
  }

  bool isOpen(ScaleReaderHandle handle) {
    if (handle.address == 0) return false;
    return _isOpen(handle) != 0;
  }

  void destroy(ScaleReaderHandle handle) {
    if (handle.address != 0) _destroy(handle);
  }

  String getError(ScaleReaderHandle handle) {
    if (handle.address == 0) return 'Invalid handle';
    final ptr = _getError(handle);
    return ptr.address == 0 ? '' : ptr.toDartString();
  }

  bool isValid(ScaleReaderHandle handle) => handle.address != 0;

  WeightReading readWeight(ScaleReaderHandle handle,
      {int timeoutMs = 3000, int stableRepeats = 3}) {
    return _readWeight(handle, timeoutMs, stableRepeats);
  }

  int readContinuous(
    ScaleReaderHandle handle,
    Pointer<NativeFunction<NativeWeightCallback>> liveCallback,
    Pointer<NativeFunction<NativeWeightCallback>> stableCallback,
    Pointer<Void> userData,
    int stableRepeats,
    Pointer<Int32> shouldStop,
  ) {
    return _readContinuous(
        handle, liveCallback, stableCallback,
        userData, stableRepeats, shouldStop);
  }
}