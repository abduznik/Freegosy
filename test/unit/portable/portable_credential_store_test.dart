import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/portable/dpapi.dart';
import 'package:freegosy/core/portable/portable_credential_store.dart';
import 'package:path/path.dart' as p;

/// XOR with a per-"user" byte; unprotect fails for another user's data.
class _FakeProtector implements DataProtector {
  _FakeProtector(this.key);
  final int key;
  @override
  Uint8List protect(Uint8List data) => Uint8List.fromList([key, ...data.map((b) => b ^ key)]);
  @override
  Uint8List? unprotect(Uint8List data) =>
      data.isEmpty || data.first != key ? null : Uint8List.fromList(data.skip(1).map((b) => b ^ key).toList());
}

void main() {
  late io.Directory dir;
  setUp(() async => dir = await io.Directory.systemTemp.createTemp('creds'));
  tearDown(() => dir.delete(recursive: true));

  PortableCredentialStore storeFor(String pc, String user, String guid, int key) => PortableCredentialStore(
      dir: dir.path, protector: _FakeProtector(key), machineName: pc, userName: user, machineId: guid);

  test('the file name names the PC and user and carries a short machine id', () {
    final s = storeFor('DESKTOP-ABC', 'henri', 'guid-1', 1);
    expect(s.fileName, matches(RegExp(r'^DESKTOP-ABC-henri-[0-9a-f]{8}\.dat$')));
  });

  test('two PCs with the same names get different files', () {
    expect(storeFor('LAPTOP', 'henri', 'guid-1', 1).fileName, isNot(storeFor('LAPTOP', 'henri', 'guid-2', 1).fileName));
  });

  test('characters Windows forbids in file names are replaced', () {
    expect(storeFor('PC:1', r'a\b', 'g', 1).fileName, startsWith('PC_1-a_b-'));
  });

  test('values round-trip and are encrypted on disk', () async {
    final s = storeFor('PC', 'u', 'g', 7);
    await s.write('rommPassword', 'hunter2');
    await s.write('rommApiKey', 'k');
    final bytes = await io.File(p.join(dir.path, s.fileName)).readAsBytes();
    expect(utf8.decode(bytes, allowMalformed: true), isNot(contains('hunter2')));

    final again = storeFor('PC', 'u', 'g', 7);
    expect(await again.read('rommPassword'), 'hunter2');
    expect(await again.readAll(), {'rommPassword': 'hunter2', 'rommApiKey': 'k'});
    await again.delete('rommApiKey');
    expect(await storeFor('PC', 'u', 'g', 7).readAll(), {'rommPassword': 'hunter2'});
  });

  test('a PC without a file reads nothing', () async {
    expect(await storeFor('NEW', 'u', 'g', 1).read('rommPassword'), isNull);
  });

  test('a file this PC cannot decrypt reads as empty and is replaced on write', () async {
    final original = storeFor('PC', 'u', 'g', 1);
    await original.write('rommPassword', 'a');
    final otherUserSameName = storeFor('PC', 'u', 'g', 2);
    expect(await otherUserSameName.read('rommPassword'), isNull);
    await otherUserSameName.write('rommPassword', 'b');
    expect(await storeFor('PC', 'u', 'g', 2).read('rommPassword'), 'b');
  });

  test('writes leave no .tmp behind and writeAll replaces everything', () async {
    final s = storeFor('PC', 'u', 'g', 3);
    await s.write('a', '1');
    await s.writeAll({'b': '2'});
    expect(await storeFor('PC', 'u', 'g', 3).readAll(), {'b': '2'});
    expect(dir.listSync().map((e) => p.basename(e.path)).where((n) => n.endsWith('.tmp')), isEmpty);
  });

  for (final bad in {'not json': 'not json', 'json list': '[1,2]'}.entries) {
    test('decrypted but unparseable (${bad.key}) reads as empty, logs, and a write succeeds', () async {
      final s = storeFor('PC', 'u', 'g', 5);
      final bytes = _FakeProtector(5).protect(Uint8List.fromList(utf8.encode(bad.value)));
      await io.File(p.join(dir.path, s.fileName)).writeAsBytes(bytes);
      final logs = <String>[];
      final old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      try {
        expect(await s.read('rommPassword'), isNull);
      } finally {
        debugPrint = old;
      }
      expect(logs.single, contains(s.fileName));
      expect(logs.single, isNot(contains(bad.value)));
      await s.write('rommPassword', 'x');
      expect(await storeFor('PC', 'u', 'g', 5).read('rommPassword'), 'x');
    });
  }
}
