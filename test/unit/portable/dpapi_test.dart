import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/portable/dpapi.dart';
import 'package:freegosy/core/portable/dpapi_stub.dart' as stub;
import 'package:path/path.dart' as p;

void main() {
  final skip = io.Platform.isWindows ? false : 'DPAPI is Windows-only';

  test('DPAPI protects and unprotects for the current user', () {
    final protector = DpapiDataProtector();
    final data = Uint8List.fromList('secret'.codeUnits);
    final protected = protector.protect(data);
    expect(protected, isNot(data));
    expect(protector.unprotect(protected), data);
    expect(protector.unprotect(Uint8List.fromList([1, 2, 3])), isNull);
  }, skip: skip);

  test('MachineGuid is read from the registry', () {
    expect(readMachineGuid(), matches(RegExp(r'^[0-9a-fA-F-]{36}$')));
  }, skip: skip);

  test('the stub used without dart:ffi (web) refuses DPAPI and has no machine id', () {
    expect(() => stub.DpapiDataProtector().protect(Uint8List(1)), throwsUnsupportedError);
    expect(() => stub.DpapiDataProtector().unprotect(Uint8List(1)), throwsUnsupportedError);
    expect(stub.readMachineGuid(), isNull);
  });

  test('only dpapi_ffi.dart uses FFI, so the web build compiles', () {
    final offenders = <String>[];
    for (final entity in io.Directory('lib').listSync(recursive: true)) {
      if (entity is! io.File || !entity.path.endsWith('.dart')) continue;
      if (p.basename(entity.path) == 'dpapi_ffi.dart') continue;
      final text = entity.readAsStringSync();
      if (RegExp(r'''import\s+['"](dart:ffi|package:ffi/|package:win32/)''').hasMatch(text)) offenders.add(entity.path);
    }
    expect(offenders, isEmpty);
  });
}
