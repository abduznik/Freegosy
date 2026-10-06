import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/formats/save_format_registry.dart';
import 'package:freegosy/core/save/strategies/retroarch_save_strategy.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;

import '../helpers/ps1_card_builder.dart';
import 'save_sync_regression_test.mocks.dart';

/// A PS1 `.mcd` card on RomM (DuckStation's, or another client's serial
/// card) must land where a RetroArch PS1 core opens card 1: the game's
/// `<content>.srm`. See docs/save-interop.md.
void main() {
  late Directory tempDir;
  late String saveDir;
  late RetroArchSaveStrategy strategy;

  const romName = 'Colin McRae Rally 2.0 (Europe) (En,Fr,De,Es,It)';
  final card = buildPs1Card([(name: 'BESLES-02605-SETTING', blocks: [1], fill: 0x11)]);

  Game game({String slug = 'psx'}) =>
      Game(id: '1', name: 'Colin McRae Rally 2.0', fsName: '$romName.cue', platformSlug: slug, fileSize: 0);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ra_ps1_card_');
    final configDir = p.join(tempDir.path, '.config', 'retroarch');
    await Directory(configDir).create(recursive: true);
    saveDir = p.join(tempDir.path, 'saves');
    await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
      'savefile_directory = "$saveDir"',
      'sort_savefiles_enable = "false"',
    ].join('\n'));
    await Directory(saveDir).create(recursive: true);

    final dirService = MockDirectoryService();
    when(dirService.findEmulatorExecutable(argThat(isA<String>()), argThat(isA<String>())))
        .thenAnswer((_) async => null);
    when(dirService.linuxSyncPreset).thenReturn('default');
    when(dirService.getEmulatorAppSupportDirectory('retroarch', platformSlug: anyNamed('platformSlug')))
        .thenAnswer((_) async => configDir);
    strategy = RetroArchSaveStrategy(dirService, platform: PlatformInfo('linux', environment: {'HOME': tempDir.path}));
  });

  tearDown(() => tempDir.delete(recursive: true));

  String romPath() => p.join(tempDir.path, 'roms', '$romName.cue');
  List<String> savesOnDisk() =>
      Directory(saveDir).listSync().whereType<File>().map((f) => p.basename(f.path)).toList()..sort();

  /// What SaveSyncService restores for a downloaded [name]: the converted
  /// files, else the file as it came.
  Future<void> pull(String name, Uint8List bytes, {Game? g}) async {
    final gm = g ?? game();
    final conversion = convertSave(
      platformSlug: gm.platformSlug!,
      files: [SaveBlob(name, bytes)],
      targetTag: strategy.coreIdFor(gm)!,
      stem: strategy.getRomStem(gm),
    );
    final files = conversion is SaveConverted ? conversion.files : [SaveBlob(name, bytes)];
    for (final f in files) {
      expect(await strategy.restoreSave(gm, romPath(), f.bytes, f.name), isTrue);
    }
  }

  test('a DuckStation port-1 card is restored as the game\'s .srm', () async {
    await pull('${romName}_1.mcd', card);
    expect(savesOnDisk(), ['$romName.srm']);
    expect(File(p.join(saveDir, '$romName.srm')).readAsBytesSync(), card);
  });

  test('a card for another port keeps its name', () async {
    await pull('${romName}_2.mcd', card);
    expect(savesOnDisk(), ['${romName}_2.mcd']);
  });

  test('a .mcd that is not a raw PS1 card keeps its name', () async {
    await pull('${romName}_1.mcd', Uint8List(1000));
    expect(savesOnDisk(), ['${romName}_1.mcd']);
  });

  test('in a zip, the port-1 card becomes the .srm and port 2 keeps its name', () async {
    final zip = Archive()
      ..addFile(ArchiveFile('${romName}_1.mcd', card.length, card))
      ..addFile(ArchiveFile('${romName}_2.mcd', card.length, card));
    final bytes = Uint8List.fromList(ZipEncoder().encode(zip));
    expect(await strategy.restoreSave(game(), romPath(), bytes, 'save.zip'), isTrue);
    expect(savesOnDisk(), ['$romName.srm', '${romName}_2.mcd']);
  });

  test('in a zip, a non-PS1 game\'s .mcd keeps its name', () async {
    final zip = Archive()..addFile(ArchiveFile('x_1.mcd', card.length, card));
    final bytes = Uint8List.fromList(ZipEncoder().encode(zip));
    expect(await strategy.restoreSave(game(slug: 'saturn'), romPath(), bytes, 'save.zip'), isTrue);
    expect(savesOnDisk(), ['x_1.mcd']);
  });

  test('the restored .srm is what the RetroArch push then uploads', () async {
    await pull('SLES-02605_1.mcd', card);
    final files = await strategy.getSaveFiles(game(), romPath(), syncMode: 'saves');
    expect(files.map((f) => p.basename(f.path)), ['$romName.srm']);
  });
}
