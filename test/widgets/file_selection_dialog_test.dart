import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/ui/widgets/file_selection_dialog.dart';

void main() {
  Game gameWith(int n) => Game(
        id: '1', name: 'Big', fileSize: 1, hasMultipleFiles: true,
        files: [for (var i = 0; i < n; i++) {'id': i, 'file_name': 'file $i', 'file_size_bytes': 1048576}],
      );

  testWidgets('a long file list scrolls and picks files near the end (#198)', (t) async {
    t.view.physicalSize = const Size(900, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    List<int>? result;
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) => TextButton(
        onPressed: () async => result = await FileSelectionDialog.show(ctx, gameWith(60)),
        child: const Text('open'))),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull, reason: 'the list must not overflow the dialog');

    expect(find.text('file 59'), findsNothing);
    await t.scrollUntilVisible(find.text('file 59'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('file 59'), findsOneWidget);

    await t.ensureVisible(find.text('file 59'));
    await t.pumpAndSettle();
    await t.tap(find.text('file 59'));
    await t.pump();
    await t.tap(find.text('Download 1 File'));
    await t.pumpAndSettle();
    expect(result, [59]);
  });

  testWidgets('download stays disabled until a file is picked', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: FileSelectionDialog(game: gameWith(3)))));
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });
}
