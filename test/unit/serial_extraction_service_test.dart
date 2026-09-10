import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/disc/serial_extraction_service.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/storage/app_preferences.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal DirectoryService stub — SerialExtractionService only calls
/// findEmulatorExecutable while resolving chdman candidates.
class _StubDirectoryService extends DirectoryService {
  _StubDirectoryService._internal(super.prefs);

  factory _StubDirectoryService(AppPreferences prefs) = _StubDirectoryService._internal;

  @override
  Future<String?> findEmulatorExecutable(String emulatorId, String executableName) async => null;
}

final ps2BootPattern = RegExp(
    r'BOOT2\s*=\s*cdrom[^:]*:\\?([A-Z]{4}[_-]\d{3}[.]\d{2})',
    caseSensitive: false);
final ps1BootPattern = RegExp(
    r'BOOT\s*=\s*cdrom[^:]*:\\?([A-Z]{4}[_-]\d{3}[.]\d{2})',
    caseSensitive: false);

void main() {
  late SerialExtractionService service;
  late AppPreferences prefs;
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    service = SerialExtractionService(
      _StubDirectoryService(prefs),
      prefs,
      platform: const PlatformInfo('windows', environment: {}),
    );
    tempDir = await Directory.systemTemp.createTemp('serial_extraction_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('SerialExtractionService.normalizeSerial', () {
    test('converts underscore separator to dash', () {
      expect(service.normalizeSerial('SLUS_12345'), 'SLUS-12345');
    });

    test('removes the dot before the last two digits', () {
      expect(service.normalizeSerial('SLUS-123.45'), 'SLUS-12345');
    });
  });

  group('SerialExtractionService.extractSerial filename fast path', () {
    test('extracts a serial embedded in the ROM filename', () async {
      final romPath = p.join(tempDir.path, 'Ico (SCUS-97113).iso');
      final serial = await service.extractSerial(
        romPath: romPath,
        bootLinePattern: ps2BootPattern,
        chdmanCandidates: const [],
      );
      expect(serial, 'SCUS-97113');
    });

    test('normalizes an underscore/dot filename serial', () async {
      final romPath = p.join(tempDir.path, 'Game (SLUS_123.45).iso');
      final serial = await service.extractSerial(
        romPath: romPath,
        bootLinePattern: ps2BootPattern,
        chdmanCandidates: const [],
      );
      expect(serial, 'SLUS-12345');
    });
  });

  group('SerialExtractionService.extractSerial header scan', () {
    test('finds a serial via a caller-supplied boot-line pattern', () async {
      final romPath = p.join(tempDir.path, 'NoSerialInName.iso');
      await File(romPath).writeAsBytes(
        List<int>.filled(2048, 0) + 'BOOT2 = cdrom0:\\SLUS_200.01;1'.codeUnits,
      );
      final serial = await service.extractSerial(
        romPath: romPath,
        bootLinePattern: ps2BootPattern,
        chdmanCandidates: const [],
      );
      expect(serial, 'SLUS-20001');
    });

    test('finds a boot line located past the old 4MB header-scan limit', () async {
      // Real ISO9660 discs can place their root directory (and so
      // SYSTEM.CNF's actual data) anywhere on the disc — there's no
      // guarantee it's near the start just because the disc is small.
      // Regression test for a bug where the scan silently gave up after
      // 4MB even when handed a fully, unbounded-extracted image.
      final romPath = p.join(tempDir.path, 'BootLineFarIn.iso');
      final padding = List<int>.filled(6 * 1024 * 1024, 0);
      await File(romPath).writeAsBytes(padding + 'BOOT2 = cdrom0:\\SLUS_200.01;1'.codeUnits);
      final serial = await service.extractSerial(
        romPath: romPath,
        bootLinePattern: ps2BootPattern,
        chdmanCandidates: const [],
      );
      expect(serial, 'SLUS-20001');
    });

    test('a PS1-style boot line ("BOOT =") is not matched by a PS2 ("BOOT2 =") pattern', () async {
      final romPath = p.join(tempDir.path, 'Ps1Disc.iso');
      await File(romPath).writeAsBytes(
        List<int>.filled(2048, 0) + 'BOOT = cdrom:\\SCUS_944.51;1'.codeUnits,
      );
      final serial = await service.extractSerial(
        romPath: romPath,
        bootLinePattern: ps2BootPattern,
        chdmanCandidates: const [],
      );
      expect(serial, isNull);
    });

    test('the same PS1-style boot line is matched by a PS1 boot-line pattern', () async {
      final romPath = p.join(tempDir.path, 'Ps1Disc.iso');
      await File(romPath).writeAsBytes(
        List<int>.filled(2048, 0) + 'BOOT = cdrom:\\SCUS_944.51;1'.codeUnits,
      );
      final serial = await service.extractSerial(
        romPath: romPath,
        bootLinePattern: ps1BootPattern,
        chdmanCandidates: const [],
      );
      expect(serial, 'SCUS-94451');
    });
  });

  group('SerialExtractionService.extractSerial multi-track BIN/CUE handling', () {
    test('resolves to the .cue\'s first (data) track when romPath points at a later, larger track', () async {
      // Track 01 is the data track (contains the boot line) but is smaller
      // than Track 02, an audio track — reproduces a real multi-track PS1
      // disc where the "largest file" heuristic elsewhere in the app can
      // hand this service the wrong track.
      final track1 = p.join(tempDir.path, 'Game (Track 01).bin');
      final track2 = p.join(tempDir.path, 'Game (Track 02).bin');
      await File(track1).writeAsBytes(
        List<int>.filled(2048, 0) + 'BOOT = cdrom:\\SCUS_944.51;1'.codeUnits,
      );
      await File(track2).writeAsBytes(List<int>.filled(8192, 0));
      await File(p.join(tempDir.path, 'Game.cue')).writeAsString(
        'FILE "Game (Track 01).bin" BINARY\n'
        '  TRACK 01 MODE1/2352\n'
        '    INDEX 01 00:00:00\n'
        'FILE "Game (Track 02).bin" BINARY\n'
        '  TRACK 02 AUDIO\n'
        '    INDEX 00 00:00:00\n'
        '    INDEX 01 00:02:00\n',
      );

      final serial = await service.extractSerial(
        romPath: track2,
        bootLinePattern: ps1BootPattern,
        chdmanCandidates: const [],
      );
      expect(serial, 'SCUS-94451');
    });

    test('falls back to scanning romPath directly when no sibling .cue exists', () async {
      final romPath = p.join(tempDir.path, 'SingleTrack.bin');
      await File(romPath).writeAsBytes(
        List<int>.filled(2048, 0) + 'BOOT = cdrom:\\SCUS_944.51;1'.codeUnits,
      );

      final serial = await service.extractSerial(
        romPath: romPath,
        bootLinePattern: ps1BootPattern,
        chdmanCandidates: const [],
      );
      expect(serial, 'SCUS-94451');
    });

    test('falls back to scanning romPath directly when the .cue\'s track 01 file is missing on disk', () async {
      final romPath = p.join(tempDir.path, 'Orphaned (Track 02).bin');
      await File(romPath).writeAsBytes(
        List<int>.filled(2048, 0) + 'BOOT = cdrom:\\SCUS_944.51;1'.codeUnits,
      );
      // References a Track 01 file that was never written to disk.
      await File(p.join(tempDir.path, 'Orphaned.cue')).writeAsString(
        'FILE "Orphaned (Track 01).bin" BINARY\n'
        '  TRACK 01 MODE1/2352\n'
        '    INDEX 01 00:00:00\n'
        'FILE "Orphaned (Track 02).bin" BINARY\n'
        '  TRACK 02 AUDIO\n'
        '    INDEX 01 00:00:00\n',
      );

      final serial = await service.extractSerial(
        romPath: romPath,
        bootLinePattern: ps1BootPattern,
        chdmanCandidates: const [],
      );
      expect(serial, 'SCUS-94451');
    });
  });

  group('SerialExtractionService.extractSerial CHD handling', () {
    test('returns a serial cached in AppPreferences without needing chdman', () async {
      final romPath = p.join(tempDir.path, 'Game.chd');
      await File(romPath).writeAsBytes([0]);
      await prefs.setString('disc_serial_${p.absolute(romPath)}', 'SLUS-20152');

      final serial = await service.extractSerial(
        romPath: romPath,
        bootLinePattern: ps2BootPattern,
        chdmanCandidates: const [],
      );
      expect(serial, 'SLUS-20152');
    });

    test('returns null (not an error) when chdman cannot be found for an uncached CHD', () async {
      final romPath = p.join(tempDir.path, 'Uncached.chd');
      await File(romPath).writeAsBytes([0]);

      final serial = await service.extractSerial(
        romPath: romPath,
        bootLinePattern: ps2BootPattern,
        chdmanCandidates: const [],
      );
      expect(serial, isNull);
    });
  });
}
