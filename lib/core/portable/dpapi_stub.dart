import 'dart:typed_data';

import 'dpapi.dart';

// Used where dart:ffi doesn't exist (the web). Portable mode is Windows-only,
// so nothing here is ever reached in practice.

/// DPAPI isn't available on this platform.
class DpapiDataProtector implements DataProtector {
  @override
  Uint8List protect(Uint8List data) => throw UnsupportedError('DPAPI is Windows-only');

  @override
  Uint8List? unprotect(Uint8List data) => throw UnsupportedError('DPAPI is Windows-only');
}

/// Windows' per-install machine id; never available here.
String? readMachineGuid() => null;
