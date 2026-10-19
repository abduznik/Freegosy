import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/save/save_sync_report.dart';
import 'package:freegosy/ui/screens/library_dialog_service.dart';

SaveSyncReport _analyze({
  bool noStrategy = false,
  String? blocked,
  String? saveDir = '/saves',
  List<LocalSaveInfo> local = const [],
  CloudSaveInfo? cloud,
  String? cloudError,
}) =>
    SaveSyncReport.analyze(
      gameName: 'Emerald', emulator: 'ares', noStrategy: noStrategy, blockedReason: blocked,
      saveDir: saveDir, localSaves: local, cloud: cloud, cloudError: cloudError,
    );

final _t0 = DateTime(2026, 1, 1, 12);
LocalSaveInfo _save(String name, {int size = 256, DateTime? at}) => LocalSaveInfo(name, size, at ?? _t0);

Iterable<String> _texts(SaveSyncReport r, FindingLevel l) => r.findings.where((f) => f.level == l).map((f) => f.text);

void main() {
  test('no strategy is a problem', () {
    final r = _analyze(noStrategy: true);
    expect(r.hasProblems, isTrue);
  });

  test('a blocked strategy reports its reason', () {
    final r = _analyze(blocked: 'Turn on portable mode');
    expect(_texts(r, FindingLevel.problem), ['Turn on portable mode']);
  });

  test('missing save folder warns and says what to do', () {
    final r = _analyze(saveDir: null);
    expect(_texts(r, FindingLevel.warning).first, contains('save folder was not found'));
  });

  test('a healthy game: local save, same age on RomM', () {
    final r = _analyze(local: [_save('Emerald.ram')], cloud: CloudSaveInfo('Emerald.ram', 256, _t0));
    expect(r.hasProblems, isFalse);
    expect(r.hasWarnings, isFalse);
    expect(r.findings.first.level, FindingLevel.ok);
  });

  test('a save under 100 bytes warns that it will not upload', () {
    final r = _analyze(local: [_save('Emerald.ram', size: 40)]);
    expect(_texts(r, FindingLevel.warning).single, contains('only 40 bytes'));
  });

  test('saves that differ only in case are flagged (the Ares restore bug of #172)', () {
    final r = _analyze(local: [_save('Emerald.ram'), _save('emerald.ram')]);
    expect(_texts(r, FindingLevel.warning).single, contains('differ only in letter case'));
  });

  test('newer local, newer cloud and no cloud save', () {
    final later = _t0.add(const Duration(minutes: 5));
    expect(_texts(_analyze(local: [_save('a.ram', at: later)], cloud: CloudSaveInfo('a.ram', 1, _t0)), FindingLevel.info).single,
        contains('local save is newer'));
    expect(_texts(_analyze(local: [_save('a.ram')], cloud: CloudSaveInfo('a.ram', 1, later)), FindingLevel.info).single,
        contains('RomM is newer'));
    expect(_texts(_analyze(local: [_save('a.ram')]), FindingLevel.info).single, contains('no save for this game yet'));
  });

  test('a RomM error is a warning, not a crash', () {
    final r = _analyze(local: [_save('a.ram')], cloudError: 'timeout');
    expect(_texts(r, FindingLevel.warning).single, contains('Could not reach RomM: timeout'));
  });

  test('toText lists folder, files and findings for a bug report', () {
    final text = _analyze(local: [_save('Emerald.ram')], cloud: CloudSaveInfo('Emerald.ram', 256, _t0)).toText();
    expect(text, contains('Emulator: ares'));
    expect(text, contains('Save folder: /saves'));
    expect(text, contains('- Emerald.ram (256 bytes'));
    expect(text, contains('[ok]'));
  });

  testWidgets('the dialog shows findings and the report', (tester) async {
    final report = _analyze(local: [_save('Emerald.ram', size: 10)]);
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) => TextButton(onPressed: () => LibraryDialogService.showSyncReportDialog(c, report), child: const Text('open'))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Save sync: Emerald'), findsOneWidget);
    expect(find.textContaining('only 10 bytes'), findsWidgets);
    expect(find.text('Copy report'), findsOneWidget);
  });
}
