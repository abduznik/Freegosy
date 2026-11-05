// Drives the real app against tool/fake_romm/fake_romm.py (see docs/live-testing.md):
// Select Files / Files / Delete / Download All, the long file picker, a DOS game and
// pause / resume. Everything it downloads goes to a temporary ROM folder.
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/app.dart';
import 'package:freegosy/core/platform/window_service.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/backup_entry.dart';
import 'package:freegosy/providers/romm_provider.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _env = io.Platform.environment;
final _server = _env['FAKE_ROMM_URL'] ?? 'http://127.0.0.1:18080';

Future<void> _pumpFor(WidgetTester t, int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Saves a screenshot of the window when LIVE_OUT names a folder.
Future<void> _shot(String name) async {
  final out = _env['LIVE_OUT'];
  if (out == null) return;
  await io.Process.run('spectacle', ['-b', '-n', '-a', '-o', '$out/$name.png']);
}

Future<void> _tapText(WidgetTester t, String text, {int wait = 800}) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) {
    final texts = t.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().toList();
    throw TestFailure('No "$text" on screen. Visible texts: $texts');
  }
  await t.tap(finder.first, warnIfMissed: false);
  await _pumpFor(t, wait);
}

Future<void> _confirmDelete(WidgetTester t) async {
  await _tapText(t, 'Delete');
  await t.tap(find.text('Delete').last, warnIfMissed: false);
  await _pumpFor(t, 2500);
}

Future<void> _back(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.arrow_back).first, warnIfMissed: false);
  await _pumpFor(t, 1200);
}

List<String> _tree(io.Directory root) => (root.listSync(recursive: true)..sort((a, b) => a.path.compareTo(b.path)))
    .map((e) => e.path.substring(root.path.length + 1))
    .toList();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('download, add files, delete, pick from a long list, DOS, pause and resume', (t) async {
    final root = io.Directory(_env['LIVE_ROMS'] ?? (await io.Directory.systemTemp.createTemp('freegosy_live')).path)
      ..createSync(recursive: true);
    List<String> files(String extension) => _tree(root).where((e) => e.endsWith(extension)).toList();

    Hive.registerAdapter(BackupEntryAdapter());
    await Hive.initFlutter((await getApplicationSupportDirectory()).path);
    await Hive.openBox<List>('freegosy_backups');
    await WindowService.init(fullscreen: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rommBaseUrl', _server);
    await prefs.setString('romsRootPath', root.path);

    await t.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        rommConfigProvider.overrideWith((ref) async => RomMConfig(baseUrl: _server, username: 'u', password: 'p')),
      ],
      child: const FreegosyApp(),
    ));
    await _pumpFor(t, 4000);
    if (find.text("Don't check").evaluate().isNotEmpty) await _tapText(t, "Don't check");
    expect(find.text('Zelda Bundle'), findsWidgets);
    await _shot('01-library');

    // Select Files: only the picked files, in one folder named after the game.
    await _tapText(t, 'Zelda Bundle', wait: 1500);
    await _tapText(t, 'Download Game');
    await _tapText(t, 'Select Files');
    await _tapText(t, 'base.nsp');
    await _tapText(t, 'update.nsp');
    await _shot('02-picker');
    await _tapText(t, 'Download 2 Files', wait: 4000);
    expect(files('.nsp'), ['switch/Zelda Bundle/base.nsp', 'switch/Zelda Bundle/update.nsp']);
    expect(find.text('Play Game'), findsOneWidget, reason: 'a partly downloaded game can be played');
    await _shot('03-after-select');

    // The Files button adds the missing file.
    await _tapText(t, 'Files', wait: 1000);
    await _tapText(t, 'Select Files');
    await _tapText(t, 'alt.nsp');
    await _tapText(t, 'Download 1 File', wait: 3500);
    expect(files('.nsp').length, 3);

    // Delete leaves nothing behind.
    await _confirmDelete(t);
    expect(_tree(root).where((e) => e != 'switch'), isEmpty, reason: 'delete left files behind');
    expect(find.text('Download Game'), findsOneWidget);

    // Download All: one folder, no empty folder named after RomM's file name.
    await _tapText(t, 'Download Game');
    await _tapText(t, 'Download All', wait: 3500);
    expect(files('.nsp').length, 3);
    expect(_tree(root), isNot(contains('switch/zelda_bundle_v1')));
    await _confirmDelete(t);
    expect(_tree(root).where((e) => e != 'switch'), isEmpty);

    // 60 files: the picker scrolls, a file from a subfolder keeps its subfolder.
    await _back(t);
    await _tapText(t, 'All', wait: 1200);
    await _tapText(t, 'Manual Collection', wait: 1500);
    await _tapText(t, 'Download Game');
    await _tapText(t, 'Select Files');
    expect(find.text('manual_page_59.pdf'), findsNothing);
    await t.drag(find.byType(Scrollable).last, const Offset(0, -6000));
    await _pumpFor(t, 500);
    await _shot('04-picker-scrolled');
    expect(find.text('manual_page_59.pdf'), findsOneWidget, reason: 'the picker did not scroll');
    await _tapText(t, 'manual_page_59.pdf');
    await _tapText(t, 'Download 1 File', wait: 3000);
    expect(files('.pdf'), ['switch/Manual Collection/media/manual_page_59.pdf']);
    await _confirmDelete(t);
    expect(_tree(root).where((e) => e != 'switch'), isEmpty);

    // DOS: Download All, then the folder is the game.
    await _back(t);
    await _tapText(t, 'DOS', wait: 1200);
    await _tapText(t, 'Darkside Story', wait: 1500);
    await _tapText(t, 'Download Game');
    await _tapText(t, 'Download All', wait: 3500);
    expect(_tree(root), contains('dos/Darkside Story/PLAY.BAT'));
    expect(find.text('Play Game'), findsOneWidget);
    await _confirmDelete(t);
    expect(_tree(root).where((e) => e != 'switch' && e != 'dos'), isEmpty);

    // Pause and resume: progress carries on and the button offers Pause again.
    await _back(t);
    await _tapText(t, 'GBA', wait: 1200);
    await _tapText(t, 'Big Game', wait: 1500);
    await _tapText(t, 'Download Game', wait: 2500);
    await _tapText(t, 'Pause', wait: 1200);
    expect(find.text('Resume'), findsOneWidget);
    await _shot('05-paused');
    await _tapText(t, 'Resume', wait: 1500);
    expect(find.text('Pause'), findsOneWidget, reason: 'after Resume the button must offer Pause again');
    expect(find.text('Resume'), findsNothing);
    for (var i = 0; i < 40 && find.text('Play Game').evaluate().isEmpty; i++) {
      await _pumpFor(t, 500);
    }
    expect(find.text('Play Game'), findsOneWidget);
    expect(io.File('${root.path}/gba/big.gba').lengthSync(), 6 * 1024 * 1024);
    await _confirmDelete(t);
    expect(io.File('${root.path}/gba/big.gba').existsSync(), isFalse);
  });
}
