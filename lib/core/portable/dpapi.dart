import 'dart:typed_data';

// The implementation needs dart:ffi, which the web build doesn't have.
export 'dpapi_stub.dart' if (dart.library.ffi) 'dpapi_ffi.dart';

/// Encrypts data so only the same Windows user can read it back.
abstract class DataProtector {
  Uint8List protect(Uint8List data);

  /// Null when the data can't be decrypted (another user or PC, or damaged).
  Uint8List? unprotect(Uint8List data);
}
