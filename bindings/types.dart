import 'dart:ffi';
import 'package:ffi/ffi.dart';

typedef WasteTrackingHandle = Pointer<Void>;
typedef UserHandle          = Pointer<Void>;
typedef ScaleReaderHandle   = Pointer<Void>;

abstract class WtError {
  static const int success        =  0;
  static const int invalidParam   = -1;
  static const int notFound       = -2;
  static const int database       = -3;
  static const int authentication = -4;
  static const int permission     = -5;
  static const int invalidState   = -6;
  static const int io             = -7;
  static bool isOk(int c)    => c == 0;
  static bool isError(int c) => c != 0;
}

abstract class UserRole {
  static const int admin        = 0;
  static const int operator_    = 1;
  static const int validator    = 2;
  static const int coordinateur = 3;
  static const int viewer       = 4;

  static String name(int role) {
    switch (role) {
      case admin:        return 'Administrator';
      case operator_:    return 'Operator';
      case validator:    return 'Validator';
      case coordinateur: return 'Coordinateur';
      default:           return 'Viewer';
    }
  }
}

abstract class ScaleErr {
  static const int success      =  0;
  static const int invalidPort  = -1;
  static const int openFailed   = -2;
  static const int readFailed   = -3;
  static const int noData       = -4;
  static const int invalidFrame = -5;

  static bool isSuccess(int c) => c == success;
  static String message(int code) {
    switch (code) {
      case invalidPort:  return 'Invalid port';
      case openFailed:   return 'Failed to open port';
      case readFailed:   return 'Read failed';
      case noData:       return 'No data received';
      case invalidFrame: return 'Invalid data frame';
      default:           return 'Unknown error ($code)';
    }
  }
}

// layout must mirror C exactly:
//   char    weight[16]         16 bytes  offset 0
//   int32_t error               4 bytes  offset 16
//   char    error_message[256]  256 bytes offset 20
//   total: 276 bytes
final class WeightReading extends Struct {
  @Array(16)  external Array<Uint8> weightRaw;
  @Int32()    external int          error;
  @Array(256) external Array<Uint8> errorMessage;

  String get weightString {
    final bytes = <int>[];
    for (int i = 0; i < 16; i++) {
      final b = weightRaw[i];
      if (b == 0) break;
      bytes.add(b);
    }
    return String.fromCharCodes(bytes);
  }

  String get errorString {
    final bytes = <int>[];
    for (int i = 0; i < 256; i++) {
      final b = errorMessage[i];
      if (b == 0) break;
      bytes.add(b);
    }
    return String.fromCharCodes(bytes);
  }
}

typedef ScaleError          = ScaleErr;
typedef WeightReadingNative = WeightReading;

class UserSession {
  final UserHandle handle;
  final int        userId;
  final int        zoneId;
  final int        role;
  final String     username;
  final String     fullName;
  final String     capabilities;
  final String     sessionToken;
  final String     stationId;

  const UserSession({
    required this.handle,
    required this.userId,
    required this.zoneId,
    required this.role,
    required this.username,
    required this.fullName,
    required this.capabilities,
    required this.sessionToken,
    required this.stationId,
  });

  bool get isAdmin        => role == UserRole.admin;
  bool get isOperator     => role == UserRole.operator_;
  bool get isValidator    => role == UserRole.validator;
  bool get isCoordinateur => role == UserRole.coordinateur;
}

abstract class ExportSource {
  static const int weighings       = 0;
  static const int reconciliations = 1;
  static const int shipments       = 2;
  static const int zones           = 3;
  static const int products        = 4;
  static const int types           = 5;
  static const int users           = 6;
  static const int flags           = 7;
  static const int corrections     = 8;

  static String name(int source) {
    switch (source) {
      case weighings:       return 'Weighings';
      case reconciliations: return 'Reconciliations';
      case shipments:       return 'Shipments';
      case zones:           return 'Zones';
      case products:        return 'Products';
      case types:           return 'Types';
      case users:           return 'Users';
      case flags:           return 'Flags';
      case corrections:     return 'Corrections';
      default:              return 'Data';
    }
  }
}

abstract class ExportFormat {
  static const int xlsx = 0;
  static const int csv  = 1;
  static const int txt  = 2;

  static String extension(int format) {
    switch (format) {
      case xlsx: return '.csv'; // xlsx is currently exported as CSV until proper XLSX support is added
      case csv:  return '.csv';
      case txt:  return '.txt';
      default:   return '.dat';
    }
  }
}