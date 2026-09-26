import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/pe_version_reader.dart';
import 'package:freegosy/core/emulator/strategies/pcsx2_strategy.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// "MZ", padding, then a VS_FIXEDFILEINFO for [major].[minor].[build].[revision].
Uint8List fakePe(int major, int minor, int build, int revision, {int padding = 5000}) {
  final info = ByteData(16)
    ..setUint32(0, 0xFEEF04BD, Endian.little)
    ..setUint32(4, 0x00010000, Endian.little)
    ..setUint32(8, (major << 16) | minor, Endian.little)
    ..setUint32(12, (build << 16) | revision, Endian.little);
  return Uint8List.fromList([0x4D, 0x5A, ...List.filled(padding, 0), ...info.buffer.asUint8List(), 0, 0]);
}

class _ExeDirectoryService extends DirectoryService {
  _ExeDirectoryService(super.prefs, this.exe);
  final String? exe;
  @override
  Future<String?> findEmulatorExecutable(String emulatorId, String executableName) async => exe;
}

void main() {
  test('parse reads major.minor.build.revision', () {
    expect(PeVersionReader.parse(fakePe(2, 8, 2, 0)), '2.8.2.0');
    expect(PeVersionReader.parse(fakePe(1, 17, 300, 4, padding: 3)), '1.17.300.4');
  });

  test('parse is null for a non-PE file or a PE without version info', () {
    expect(PeVersionReader.parse(Uint8List.fromList([1, 2, 3, 4])), isNull);
    expect(PeVersionReader.parse(Uint8List.fromList([0x4D, 0x5A, ...List.filled(100, 0)])), isNull);
  });

  test('a stray signature with the wrong struct version is skipped; the real block after it still parses', () {
    final stray = ByteData(16)
      ..setUint32(0, 0xFEEF04BD, Endian.little)
      ..setUint32(4, 0x00020000, Endian.little) // wrong dwStrucVersion
      ..setUint32(8, (9 << 16) | 9, Endian.little)
      ..setUint32(12, (9 << 16) | 9, Endian.little);
    final real = ByteData(16)
      ..setUint32(0, 0xFEEF04BD, Endian.little)
      ..setUint32(4, 0x00010000, Endian.little)
      ..setUint32(8, (2 << 16) | 8, Endian.little)
      ..setUint32(12, (2 << 16) | 0, Endian.little);
    final bytes = Uint8List.fromList([
      0x4D, 0x5A, ...List.filled(50, 0),
      ...stray.buffer.asUint8List(),
      ...List.filled(50, 0),
      ...real.buffer.asUint8List(),
      0, 0,
    ]);
    expect(PeVersionReader.parse(bytes), '2.8.2.0');
  });

  group('Pcsx2Strategy.installedVersion', () {
    late Directory tmp;
    late SharedPreferencesAppPreferences prefs;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('pe_version');
      SharedPreferences.setMockInitialValues({});
      prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    });
    tearDown(() => tmp.delete(recursive: true));

    test('reads the exe on Windows', () async {
      final exe = File(p.join(tmp.path, 'pcsx2-qt.exe'))..writeAsBytesSync(fakePe(2, 8, 2, 0));
      final strategy = Pcsx2Strategy(_ExeDirectoryService(prefs, exe.path),
          platform: const PlatformInfo('windows', environment: {}));
      expect(await strategy.installedVersion(), '2.8.2.0');
    });

    test('re-reads after the exe changes (cache keyed on modified time)', () async {
      final exe = File(p.join(tmp.path, 'pcsx2-qt.exe'))..writeAsBytesSync(fakePe(2, 8, 2, 0));
      final strategy = Pcsx2Strategy(_ExeDirectoryService(prefs, exe.path),
          platform: const PlatformInfo('windows', environment: {}));
      expect(await strategy.installedVersion(), '2.8.2.0');
      exe.writeAsBytesSync(fakePe(2, 9, 0, 0));
      exe.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
      expect(await strategy.installedVersion(), '2.9.0.0');
    });

    test('null off Windows, without an exe, or for an unreadable exe', () async {
      final exe = File(p.join(tmp.path, 'pcsx2-qt'))..writeAsBytesSync(fakePe(2, 8, 2, 0));
      expect(await Pcsx2Strategy(_ExeDirectoryService(prefs, exe.path),
              platform: const PlatformInfo('linux', environment: {})).installedVersion(), isNull);
      expect(await Pcsx2Strategy(_ExeDirectoryService(prefs, null),
              platform: const PlatformInfo('windows', environment: {})).installedVersion(), isNull);
      expect(await Pcsx2Strategy(_ExeDirectoryService(prefs, p.join(tmp.path, 'missing.exe')),
              platform: const PlatformInfo('windows', environment: {})).installedVersion(), isNull);
    });
  });
}
