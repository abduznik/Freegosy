import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/ui/widgets/portable_mode_settings.dart';
import 'package:path/path.dart' as p;

void main() {
  Future<void> pump(WidgetTester tester, PortableRowState state) => tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PortableModeSettings(stateOverride: state, folderOverride: r'E:\Freegosy'))));

  testWidgets('a writable normal copy offers to become portable', (tester) async {
    await pump(tester, PortableRowState.normalWritable);
    expect(find.text('Make this copy portable…'), findsOneWidget);
  });

  testWidgets('an installed copy explains it needs the zip version', (tester) async {
    await pump(tester, PortableRowState.notWritable);
    expect(find.textContaining('needs the zip version'), findsOneWidget);
    expect(find.text('Make this copy portable…'), findsNothing);
  });

  group('stateFor', () {
    const folder = r'E:\Freegosy';
    test('a writable zip copy can become portable', () {
      expect(PortableModeSettings.stateFor(portable: false, folder: folder, exists: (_) => false, writable: (_) => true),
          PortableRowState.normalWritable);
    });

    test('an installer copy is not eligible even when its folder is writable', () {
      for (final uninstaller in ['unins000.exe', 'unins000.dat']) {
        expect(
            PortableModeSettings.stateFor(
                portable: false,
                folder: folder,
                exists: (f) => f == p.windows.join(r'E:\Freegosy', uninstaller),
                writable: (_) => true),
            PortableRowState.notWritable,
            reason: uninstaller);
      }
    });

    test('a read-only folder is not eligible; a portable copy is portable', () {
      expect(PortableModeSettings.stateFor(portable: false, folder: folder, exists: (_) => false, writable: (_) => false),
          PortableRowState.notWritable);
      expect(PortableModeSettings.stateFor(portable: true, folder: folder, exists: (_) => true, writable: (_) => false),
          PortableRowState.portable);
    });

    test('the folder is probed once, not on every build', () {
      var probes = 0;
      bool writable(String _) {
        probes++;
        return true;
      }

      PortableModeSettings.resetStateForTesting();
      PortableModeSettings.currentState(folder: folder, exists: (_) => false, writable: writable);
      PortableModeSettings.currentState(folder: folder, exists: (_) => false, writable: writable);
      expect(probes, 1);
      PortableModeSettings.resetStateForTesting();
    });
  });

  testWidgets('a portable copy shows where its data is and offers to stop', (tester) async {
    await pump(tester, PortableRowState.portable);
    expect(find.textContaining(r'E:\Freegosy\userdata'), findsOneWidget);
    expect(find.text('Stop being portable…'), findsOneWidget);
    expect(find.text('Open folder'), findsOneWidget);
  });

  testWidgets('the confirm dialog has a default-on copy checkbox that hides the folders one', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => PortableModeSettings.confirmDialog(context,
                        title: 'T',
                        body: 'B',
                        copyLabel: 'Copy my current settings, backups and sign-in',
                        foldersLabel: 'Also copy ROMs',
                        action: 'Go'),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Copy my current settings, backups and sign-in'), findsOneWidget);
    expect(find.text('Also copy ROMs'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile).first).value, isTrue);
    await tester.tap(find.text('Copy my current settings, backups and sign-in'));
    await tester.pump();
    expect(find.text('Also copy ROMs'), findsNothing);
  });

  group('confirm dialog notes follow the checkboxes', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => PortableModeSettings.confirmDialog(context,
                          title: 'T',
                          body: 'B',
                          copyNote: 'replaced note',
                          noCopyNote: 'reused note',
                          copyLabel: 'Copy',
                          foldersLabel: 'Folders',
                          foldersNote: 'kept note',
                          action: 'Go'),
                      child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('copying: the replace note, folders note only once folders are ticked', (tester) async {
      await open(tester);
      expect(find.text('replaced note'), findsOneWidget);
      expect(find.text('reused note'), findsNothing);
      expect(find.text('kept note'), findsNothing);
      await tester.tap(find.text('Folders'));
      await tester.pump();
      expect(find.text('kept note'), findsOneWidget);
    });

    testWidgets('not copying: nothing is replaced, so only the other note', (tester) async {
      await open(tester);
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(find.text('replaced note'), findsNothing);
      expect(find.text('reused note'), findsOneWidget);
      expect(find.text('kept note'), findsNothing);
    });
  });
}
