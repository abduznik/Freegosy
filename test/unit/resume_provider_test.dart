import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/file_system_index.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:freegosy/providers/resume_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _Dir extends DirectoryService {
  _Dir(super.prefs, this.existing);
  final String? existing;
  @override
  Future<String?> findExistingRomPath(Game game, {FileSystemIndex? index}) async => existing;
}

void main() {
  late Directory tmp;
  late SharedPreferencesAppPreferences prefs;
  final game = Game(id: '1', name: 'G', platformSlug: 'ps2', fileSize: 0);
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('resume_rom');
    SharedPreferences.setMockInitialValues({});
    prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
  });
  tearDown(() => tmp.delete(recursive: true));

  test('ResumeKey equality: same id and ROM-resolution fields, other fields ignored', () {
    expect(ResumeKey(game), ResumeKey(Game(id: '1', name: 'other', platformSlug: 'ps2', fileSize: 0)));
    expect(ResumeKey(game).hashCode,
        ResumeKey(Game(id: '1', name: 'other', platformSlug: 'ps2', fileSize: 0)).hashCode);
    expect(ResumeKey(game) == ResumeKey(Game(id: '2', name: 'G', platformSlug: 'ps2', fileSize: 0)), isFalse);
  });

  test('ResumeKey: a fuller Game with the same id is a different key (its ROM may resolve differently)', () {
    final thin = Game(id: '1', name: 'G', platformSlug: 'ps2', fileSize: 0);
    final withFiles = Game(id: '1', name: 'G', platformSlug: 'ps2', fileSize: 0, hasMultipleFiles: true, files: [
      {'file_name': 'G (Disc 1).iso'},
      {'file_name': 'G (Disc 2).iso'},
    ]);
    final withFsName = Game(id: '1', name: 'G', platformSlug: 'ps2', fileSize: 0, fsName: 'G.iso');
    final withExt = Game(id: '1', name: 'G', platformSlug: 'ps2', fileSize: 0, fsExtension: 'iso');
    final otherPlatform = Game(id: '1', name: 'G', platformSlug: 'ps1', fileSize: 0);

    expect(ResumeKey(thin) == ResumeKey(withFiles), isFalse);
    expect(ResumeKey(thin) == ResumeKey(withFsName), isFalse);
    expect(ResumeKey(thin) == ResumeKey(withExt), isFalse);
    expect(ResumeKey(thin) == ResumeKey(otherPlatform), isFalse);
    expect(ResumeKey(withFsName), ResumeKey(Game(id: '1', name: 'G', platformSlug: 'ps2', fileSize: 0, fsName: 'G.iso')));
  });

  test('a ROM file is used as is', () async {
    final rom = File(p.join(tmp.path, 'G.iso'))..writeAsStringSync('x');
    expect(await resolveResumeRomPaths(game, _Dir(prefs, rom.path), null), [rom.path]);
  });

  test('not downloaded: empty', () async {
    expect(await resolveResumeRomPaths(game, _Dir(prefs, null), null), isEmpty);
  });

  test('a multi-disc folder: every disc, sorted, full paths, no playlist or readme', () async {
    final folder = Directory(p.join(tmp.path, 'G'))..createSync();
    final disc2 = File(p.join(folder.path, 'Disc 2.iso'))..writeAsStringSync('x');
    final disc1 = File(p.join(folder.path, 'Disc 1.iso'))..writeAsStringSync('x');
    File(p.join(folder.path, 'game.m3u')).writeAsStringSync('Disc 1.iso\nDisc 2.iso\n');
    File(p.join(folder.path, 'A-readme.txt')).writeAsStringSync('x');

    expect(await resolveResumeRomPaths(game, _Dir(prefs, folder.path), null), [disc1.path, disc2.path]);
  });

  test('a folder without disc images falls back to its first non-.txt file', () async {
    final folder = Directory(p.join(tmp.path, 'G'))..createSync();
    final rom = File(p.join(folder.path, 'G.elf'))..writeAsStringSync('x');
    File(p.join(folder.path, 'A-readme.txt')).writeAsStringSync('x'); // sorts before the rom
    expect(await resolveResumeRomPaths(game, _Dir(prefs, folder.path), null), [rom.path]);
  });

  test('an empty folder: empty, no throw', () async {
    final folder = Directory(p.join(tmp.path, 'E'))..createSync();
    expect(await resolveResumeRomPaths(game, _Dir(prefs, folder.path), null), isEmpty);
  });
}
