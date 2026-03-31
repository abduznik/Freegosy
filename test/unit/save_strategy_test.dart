import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/save_strategy.dart';
import 'package:path/path.dart' as p;

class TestSaveStrategy extends SaveStrategy {
  @override
  String get strategyId => 'test';

  @override
  Future<String?> getSaveDir(Game game, String romPath) async => null;

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async => [];

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async => true;
}

void main() {
  late TestSaveStrategy strategy;

  setUp(() {
    strategy = TestSaveStrategy();
  });

  group('SaveStrategy Helpers', () {
    test('getRomStem() correctly strips file extensions', () {
      final g1 = Game(id: '1', name: 'God of War (USA).iso', fileSize: 0);
      expect(strategy.getRomStem(g1), 'God of War (USA)');

      final g2 = Game(id: '2', name: 'Crash Bandicoot.bin', fileSize: 0);
      expect(strategy.getRomStem(g2), 'Crash Bandicoot');

      final g3 = Game(id: '3', name: 'game.rom.zip', fileSize: 0);
      expect(strategy.getRomStem(g3), 'game.rom');
    });

    test('backupSave() rotation logic works', () async {
      final tempDir = await Directory.systemTemp.createTemp('save_backup_test');
      final saveFile = File(p.join(tempDir.path, 'game.sav'));
      
      try {
        // Initial file
        await saveFile.writeAsString('initial');
        await strategy.backupSave(saveFile.path);
        expect(File('${saveFile.path}.bak').existsSync(), isTrue);
        expect(await File('${saveFile.path}.bak').readAsString(), 'initial');

        // Second version
        await saveFile.writeAsString('v2');
        await strategy.backupSave(saveFile.path);
        expect(File('${saveFile.path}.bak').existsSync(), isTrue);
        expect(File('${saveFile.path}.bak1').existsSync(), isTrue);
        expect(await File('${saveFile.path}.bak').readAsString(), 'v2');
        expect(await File('${saveFile.path}.bak1').readAsString(), 'initial');

        // Third version
        await saveFile.writeAsString('v3');
        await strategy.backupSave(saveFile.path);
        expect(File('${saveFile.path}.bak').existsSync(), isTrue);
        expect(File('${saveFile.path}.bak1').existsSync(), isTrue);
        expect(File('${saveFile.path}.bak2').existsSync(), isTrue);
        expect(await File('${saveFile.path}.bak').readAsString(), 'v3');
        expect(await File('${saveFile.path}.bak1').readAsString(), 'v2');
        expect(await File('${saveFile.path}.bak2').readAsString(), 'initial');

        // Fourth version - rotation
        await saveFile.writeAsString('v4');
        await strategy.backupSave(saveFile.path);
        expect(File('${saveFile.path}.bak').existsSync(), isTrue);
        expect(File('${saveFile.path}.bak1').existsSync(), isTrue);
        expect(File('${saveFile.path}.bak2').existsSync(), isTrue);
        expect(await File('${saveFile.path}.bak').readAsString(), 'v4');
        expect(await File('${saveFile.path}.bak1').readAsString(), 'v3');
        expect(await File('${saveFile.path}.bak2').readAsString(), 'v2');
        // .bak3 should not exist
        expect(File('${saveFile.path}.bak3').existsSync(), isFalse);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
