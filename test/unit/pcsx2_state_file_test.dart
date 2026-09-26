import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/save_state_info.dart';
import 'package:freegosy/core/save/strategies/pcsx2_state_file.dart';
import 'package:path/path.dart' as p;

import '../helpers/p2s_builder.dart';
import '../helpers/pcsx2_test_env.dart';

/// The first 0x5C bytes of a real PCSX2 v2.8.2 state
/// (`SLUS-20803 (E9720D3E).resume.p2s`), captured with xxd.
final _realHeader = Uint8List.fromList([
  0x50, 0x4b, 0x03, 0x04, 0x0a, 0x00, 0x00, 0x08, 0x00, 0x00, 0x54, 0xa9, 0x35, 0x5d, 0xb4, 0x1b,
  0xd2, 0xe2, 0x24, 0x00, 0x00, 0x00, 0x24, 0x00, 0x00, 0x00, 0x1a, 0x00, 0x00, 0x00, 0x50, 0x43,
  0x53, 0x58, 0x32, 0x20, 0x53, 0x61, 0x76, 0x65, 0x73, 0x74, 0x61, 0x74, 0x65, 0x20, 0x56, 0x65,
  0x72, 0x73, 0x69, 0x6f, 0x6e, 0x2e, 0x69, 0x64, 0x00, 0x00, 0x59, 0x9a, 0x76, 0x32, 0x2e, 0x38,
  0x2e, 0x32, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
]);

void main() {
  group('parseVersionHeader', () {
    test('reads a real PCSX2 v2.8.2 header', () {
      final v = Pcsx2StateFile.parseVersionHeader(_realHeader);
      expect(v?.version, 'v2.8.2');
      expect(v?.formatId, '0x9A590000');
    });
    test('reads a generated state', () {
      expect(Pcsx2StateFile.parseVersionHeader(buildP2s(version: 'v2.6.0'))?.version, 'v2.6.0');
    });
    test('null for garbage, a truncated header, a compressed version entry, or no version entry', () {
      expect(Pcsx2StateFile.parseVersionHeader(Uint8List.fromList(List.filled(64, 9))), isNull);
      expect(Pcsx2StateFile.parseVersionHeader(_realHeader.sublist(0, 40)), isNull);
      expect(Pcsx2StateFile.parseVersionHeader(buildP2s(storedVersionEntry: false)), isNull);
      expect(Pcsx2StateFile.parseVersionHeader(buildP2s(version: null)), isNull);
    });
  });

  group('Pcsx2SaveStrategy', () {
    late Directory base;
    late Pcsx2TestEnv env;
    setUp(() async {
      base = await Directory.systemTemp.createTemp('p2s_reader');
      env = await Pcsx2TestEnv.create(base);
    });
    tearDown(() => base.delete(recursive: true));

    File write(String name, List<int> bytes) =>
        File(p.join(env.statesDir, name))..createSync(recursive: true)..writeAsBytesSync(bytes);

    test('slotOf', () {
      expect(env.strategy.slotOf('SCUS-97113 (A1B2C3D4).resume.p2s'), const AutoStateSlot());
      expect(env.strategy.slotOf('SCUS-97113 (A1B2C3D4).03.p2s'), const NumberedStateSlot(3));
      expect(env.strategy.slotOf('SCUS-97113 (A1B2C3D4).10.p2s'), const NumberedStateSlot(10));
      expect(env.strategy.slotOf('weird.p2s'), const UnknownStateSlot('weird.p2s'));
    });

    test('describeState reads version and format, savedAt is the modified time', () async {
      final file = write('SCUS-97113 (A1B2C3D4).01.p2s', buildP2s(version: 'v2.8.2'));
      final when = DateTime(2026, 9, 21, 21, 10);
      file.setLastModifiedSync(when);
      final info = await env.strategy.describeState(file);
      expect(info.emulatorVersion, 'v2.8.2');
      expect(info.formatId, '0x9A590000');
      expect(info.savedAt, when);
    });

    test('describeState on a corrupt file: no version, no throw', () async {
      final file = write('SCUS-97113 (A1B2C3D4).01.p2s', List.filled(300, 1));
      final info = await env.strategy.describeState(file);
      expect(info.emulatorVersion, isNull);
    });

    test('describeState on a tiny file: no version, no throw', () async {
      final file = write('SCUS-97113 (A1B2C3D4).01.p2s', [0x50, 0x4b]);
      expect((await env.strategy.describeState(file)).emulatorVersion, isNull);
    });

    test('stateScreenshot returns the embedded PNG bytes', () async {
      final png = [0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4];
      final file = write('SCUS-97113 (A1B2C3D4).01.p2s', buildP2s(screenshot: png));
      expect(await env.strategy.stateScreenshot(file), png);
    });

    test('stateScreenshot is null without a screenshot or for a corrupt file', () async {
      final none = write('SCUS-97113 (A1B2C3D4).01.p2s', buildP2s());
      final bad = write('SCUS-97113 (A1B2C3D4).02.p2s', List.filled(300, 1));
      expect(await env.strategy.stateScreenshot(none), isNull);
      expect(await env.strategy.stateScreenshot(bad), isNull);
    });
  });
}
