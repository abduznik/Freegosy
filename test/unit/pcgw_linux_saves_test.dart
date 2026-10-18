import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/save_sync_report.dart';
import 'package:freegosy/core/save/strategies/windows_save_strategy.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:freegosy/core/windows/pcgamingwiki_service.dart';
import 'package:freegosy/core/windows/windows_known_folders.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// The save rows PCGamingWiki lists for Psychonauts (from the wiki's API).
const _psychonauts = '''
{{Game data|
{{Game data/config|Windows|{{P|game}}}}
{{Game data/config|Linux|{{P|xdgdatahome}}/Psychonauts}}
}}
{{Game data|
{{Game data/saves|Windows|{{p|game}}\\Profiles}}
{{Game data/saves|Microsoft Store|{{P|localappdata}}\\Psychonauts\\Profiles}}
{{Game data/saves|OS X|{{p|osxhome}}/Library/Application Support/Psychonauts/Profiles}}
{{Game data/saves|Linux|{{P|xdgdatahome}}/Psychonauts/Profiles}}
}}
''';

const _linux = PlatformInfo('linux', environment: {});

void main() {
  late Directory tmp;
  late String prefix;
  late WindowsKnownFolders folders;
  final wiki = PcGamingWikiService(Dio(), platform: _linux);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pcgw_linux');
    prefix = p.join(tmp.path, 'prefix');
    Directory(p.join(prefix, 'drive_c', 'users', 'steamuser')).createSync(recursive: true);
    folders = WindowsKnownFolders.forPlatform(_linux, prefixDir: prefix);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('PCGamingWiki paths on Linux', () {
    test('Psychonauts: the Windows row {{p|game}}\\Profiles becomes <game folder>/Profiles', () {
      final found = wiki.parseSaveLocations(_psychonauts, 'Psychonauts', '/home/yan/ROMs/windows/Psychonauts', folders: folders);
      expect(found.map((f) => f['path']), ['/home/yan/ROMs/windows/Psychonauts/Profiles']);
    });

    test('AppData and Documents templates land inside the Wine prefix', () {
      const text = '''
{{Game data/saves|Windows|{{p|appdata}}\\Some Game\\Saves|{{p|userprofile\\documents}}\\My Games\\Some Game|{{p|localappdata}}\\Some Game\\save.dat}}
''';
      final paths = wiki.parseSaveLocations(text, 'Some Game', '/g', folders: folders).map((f) => f['path']).toList();
      final profile = p.join(prefix, 'drive_c', 'users', 'steamuser');
      expect(paths, [
        p.join(profile, 'AppData', 'Roaming', 'Some Game', 'Saves'),
        p.join(profile, 'Documents', 'My Games', 'Some Game'),
        p.join(profile, 'AppData', 'Local', 'Some Game'), // a file row names its folder
      ]);
    });

    test('with no prefix yet, only game-folder paths resolve and nothing is made up for the rest', () {
      const text = '{{Game data/saves|Windows|{{p|appdata}}\\Some Game|{{p|game}}\\Save}}';
      final none = WindowsKnownFolders.forPlatform(_linux);
      final paths = wiki.parseSaveLocations(text, 'Some Game', '/g/Some Game', folders: none).map((f) => f['path']).toList();
      expect(paths, ['/g/Some Game/Save']);
    });

    test('Windows keeps backslash paths from the environment, as before', () {
      final win = PcGamingWikiService(Dio(), platform: const PlatformInfo('windows', environment: {'APPDATA': r'C:\Users\Yan\AppData\Roaming'}));
      final paths = win.parseSaveLocations(_psychonauts, 'Psychonauts', r'C:\Games\Psychonauts').map((f) => f['path']).toList();
      expect(paths, [r'C:\Games\Psychonauts\Profiles']);
      const appdata = r'{{Game data/saves|Windows|{{p|appdata}}\Some Game}}';
      expect(win.parseSaveLocations(appdata, 'x', r'C:\g').map((f) => f['path']), [r'C:\Users\Yan\AppData\Roaming\Some Game']);
    });
  });

  group('portable save paths', () {
    test('Linux prefix paths become tokens, the most specific folder winning, and come back', () {
      final local = p.join(prefix, 'drive_c', 'users', 'steamuser', 'AppData', 'Local', 'Game');
      final roaming = p.join(prefix, 'drive_c', 'users', 'steamuser', 'AppData', 'Roaming', 'Game', 'Saves');
      expect(folders.toPortable(local), r"['LOCALAPPDATA']\Game");
      expect(folders.toPortable(roaming), r"['APPDATA']\Game\Saves");
      expect(folders.fromPortable(r"['APPDATA']\Game\Saves", posix: true), roaming);
      expect(folders.toPortable('/home/yan/ROMs/g/Profiles', gameDir: '/home/yan/ROMs/g'), r'[GAMEDIR]\Profiles');
      expect(folders.toPortable('/somewhere/else'), '/somewhere/else'); // under no known folder
    });

    test('a save pushed from Windows restores into the Linux prefix, and the other way round', () {
      const win = PlatformInfo('windows', environment: {'APPDATA': r'C:\Users\Yan\AppData\Roaming', 'LOCALAPPDATA': r'C:\Users\Yan\AppData\Local', 'USERPROFILE': r'C:\Users\Yan'});
      final onWindows = WindowsKnownFolders.forPlatform(win);
      final stored = onWindows.toPortable(r'C:\Users\Yan\AppData\Roaming\Game\Saves');
      expect(stored, r"['APPDATA']\Game\Saves");
      expect(folders.fromPortable(stored, posix: true), p.join(prefix, 'drive_c', 'users', 'steamuser', 'AppData', 'Roaming', 'Game', 'Saves'));

      final fromLinux = folders.toPortable(p.join(prefix, 'drive_c', 'users', 'steamuser', 'AppData', 'Roaming', 'Game', 'Saves'));
      expect(fromLinux, stored);
      expect(onWindows.fromPortable(fromLinux, posix: false), r'C:\Users\Yan\AppData\Roaming\Game\Saves');
    });

    test('plain Wine names the profile after the user instead of steamuser', () {
      final wine = Directory(p.join(tmp.path, 'wine', 'drive_c', 'users', 'yan'))..createSync(recursive: true);
      Directory(p.join(tmp.path, 'wine', 'drive_c', 'users', 'Public')).createSync();
      final f = WindowsKnownFolders.forPlatform(_linux, prefixDir: p.join(tmp.path, 'wine'));
      expect(f.byToken[WindowsKnownFolders.userProfile], wine.path);
    });
  });

  group('WindowsSaveStrategy on Linux', () {
    test('finds Psychonauts saves through PCGamingWiki in the game folder, without creating stray folders', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      final game = Directory(p.join(tmp.path, 'Psychonauts'))..createSync();
      File(p.join(game.path, 'Psychonauts.exe')).writeAsStringSync('exe');
      Directory(p.join(game.path, 'Profiles', 'Raz')).createSync(recursive: true);
      File(p.join(game.path, 'Profiles', 'Raz', 'save.dat')).writeAsStringSync('slot');
      final strategy = WindowsSaveStrategy(prefs,
          platform: _linux, prefixDirFor: (_) async => prefix, wikiService: _FakeWiki(_psychonauts, folders));
      final g = Game(id: '122', name: 'Psychonauts', fileSize: 0, platformSlug: 'windows');

      final dir = await strategy.getSaveDir(g, game.path);
      expect(dir, p.join(game.path, 'Profiles'));
      final files = await strategy.getSaveFiles(g, game.path);
      expect(files, isNotEmpty);
      // The bug this replaces made a folder literally named '\\home\\...\\Profiles' in the working directory.
      expect(Directory.current.listSync().any((e) => p.basename(e.path).contains(r'\')), isFalse);
    });
  });

  test('a game that has not saved yet gets a hint naming the place PCGamingWiki expects', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final game = Directory(p.join(tmp.path, 'Psychonauts'))..createSync();
    final strategy = WindowsSaveStrategy(prefs, platform: _linux, prefixDirFor: (_) async => prefix, wikiService: _FakeWiki(_psychonauts, folders));
    final g = Game(id: '123', name: 'Psychonauts', fileSize: 0, platformSlug: 'windows');

    expect(await strategy.getSaveDir(g, game.path), isNull);
    final hint = strategy.saveLocationHint(g)!;
    expect(hint, contains(p.join(game.path, 'Profiles')));

    final report = SaveSyncReport.analyze(
        gameName: 'Psychonauts', emulator: 'windows', noStrategy: false, saveDir: null, localSaves: const [], cloud: null, locationHint: hint);
    expect(report.toText(), contains('PCGamingWiki lists this game'));
  });

  group('a game extracted one folder down (Psychonauts/psychonauts/Psychonauts.exe)', () {
    late Directory outer;
    late Directory inner;
    late WindowsSaveStrategy strategy;
    final g = Game(id: '122', name: 'Psychonauts', fileSize: 0, platformSlug: 'windows');

    setUp(() async {
      outer = Directory(p.join(tmp.path, 'Psychonauts'))..createSync();
      inner = Directory(p.join(outer.path, 'psychonauts'))..createSync();
      File(p.join(inner.path, 'Psychonauts.exe')).writeAsStringSync('exe');
      Directory(p.join(inner.path, 'redist')).createSync();
      File(p.join(inner.path, 'redist', 'vcredist_x86.exe')).writeAsStringSync('installer');
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      strategy = WindowsSaveStrategy(prefs, platform: _linux, prefixDirFor: (_) async => prefix, wikiService: _FakeWiki(_psychonauts, folders));
    });

    test('the game folder is the one holding the executable, not the installer folders', () async {
      expect(await WindowsSaveStrategy.gameRoots(outer.path), [inner.path, outer.path]);
    });

    test('the save is found in the inner folder where the game wrote it, and nothing is created', () async {
      final profile = Directory(p.join(inner.path, 'Profiles', 'Profile 1'))..createSync(recursive: true);
      File(p.join(profile.path, 'SavedGame0')).writeAsStringSync('slot');
      expect(await strategy.getSaveDir(g, outer.path), p.join(inner.path, 'Profiles'));
      expect(Directory(p.join(outer.path, 'Profiles')).existsSync(), isFalse);
    });

    test('a differently-cased folder on disk still matches the wiki path', () async {
      final profile = Directory(p.join(inner.path, 'profiles', 'Profile 1'))..createSync(recursive: true); // wiki says "Profiles"
      File(p.join(profile.path, 'SavedGame0')).writeAsStringSync('slot');
      expect(await strategy.getSaveDir(g, outer.path), p.join(inner.path, 'profiles'));
      expect(await WindowsSaveStrategy.resolveCaseInsensitive(p.join(inner.path, 'PROFILES', 'profile 1')), p.join(inner.path, 'profiles', 'Profile 1'));
      expect(await WindowsSaveStrategy.resolveCaseInsensitive(p.join(inner.path, 'nope')), isNull);
    });

    test('before any save: nothing is created, and the hint points at the executable folder', () async {
      expect(await strategy.getSaveDir(g, outer.path), isNull);
      expect(Directory(p.join(outer.path, 'Profiles')).existsSync(), isFalse);
      expect(Directory(p.join(inner.path, 'Profiles')).existsSync(), isFalse);
      expect(strategy.saveLocationHint(g), contains(p.join(inner.path, 'Profiles')));
    });
  });
}

class _FakeWiki extends PcGamingWikiService {
  final String wikitext;
  final WindowsKnownFolders expected;
  _FakeWiki(this.wikitext, this.expected) : super(Dio(), platform: _linux);

  @override
  Future<List<Map<String, String>>> getSaveLocations(String gameTitle,
      {String gameDir = '', List<String>? gameRoots, WindowsKnownFolders? folders}) async {
    expect(folders?.byToken, expected.byToken); // the strategy hands over the prefix's folders
    return [
      for (final root in (gameRoots == null || gameRoots.isEmpty) ? [gameDir] : gameRoots) ...parseSaveLocations(wikitext, gameTitle, root, folders: folders),
    ];
  }
}
