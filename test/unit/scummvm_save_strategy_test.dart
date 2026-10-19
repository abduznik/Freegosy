import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/strategies/scummvm_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/strategies/scummvm_save_strategy.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _Dirs extends DirectoryService {
  final String base;
  _Dirs(super.prefs, this.base);

  @override
  Future<String> getEmulatorAppSupportDirectory(String emulatorName, {String? platformSlug}) async => base;
}

Game _game(String id) => Game(id: id, name: 'Monkey Island', fileSize: 0, platformSlug: 'scummvm');

void main() {
  late Directory tmp;
  late ScummVMSaveStrategy strategy;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('scummvm_save_');
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    strategy = ScummVMSaveStrategy(_Dirs(prefs, tmp.path));
  });
  tearDown(() => tmp.delete(recursive: true));

  test('each game gets its own save folder, and ScummVM is told to use it', () async {
    final a = await strategy.getSaveDir(_game('1'), '/roms/a');
    final b = await strategy.getSaveDir(_game('2'), '/roms/b');
    expect(a, p.join(tmp.path, 'freegosy_saves', '1'));
    expect(b, isNot(a));
    expect(ScummVMStrategy.gameArgs('/games/x', savePath: a),
        ['--auto-detect', '--path=/games/x', '--savepath=$a']);
    expect(ScummVMStrategy.gameArgs('/games/x'), ['--auto-detect', '--path=/games/x']);
  });

  test('no saves yet means nothing to sync; saves make the folder the save', () async {
    expect(await strategy.getSaveFiles(_game('1'), '/roms/a'), isEmpty);
    final dir = Directory(p.join(tmp.path, 'freegosy_saves', '1'))..createSync(recursive: true);
    expect(await strategy.getSaveFiles(_game('1'), '/roms/a'), isEmpty); // empty folder
    File(p.join(dir.path, 'monkey.s01')).writeAsStringSync('save');
    final files = await strategy.getSaveFiles(_game('1'), '/roms/a');
    expect(files.map((f) => f.path), [dir.path]);
  });

  test('restoring a zip writes the files, keeps a backup and refuses paths outside the folder', () async {
    final dir = p.join(tmp.path, 'freegosy_saves', '1');
    Uint8List zip(Map<String, String> files) {
      final archive = Archive();
      files.forEach((name, text) => archive.addFile(ArchiveFile(name, text.length, text.codeUnits)));
      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    expect(await strategy.restoreSave(_game('1'), '/roms/a', zip({'monkey.s01': 'one', '../evil.txt': 'x'}), 'save.zip'), isTrue);
    expect(File(p.join(dir, 'monkey.s01')).readAsStringSync(), 'one');
    expect(File(p.join(tmp.path, 'freegosy_saves', 'evil.txt')).existsSync(), isFalse);

    expect(await strategy.restoreSave(_game('1'), '/roms/a', zip({'monkey.s01': 'two'}), 'save.zip'), isTrue);
    expect(File(p.join(dir, 'monkey.s01')).readAsStringSync(), 'two');
    expect(File(p.join(dir, 'monkey.s01.bak')).readAsStringSync(), 'one');
  });
}
