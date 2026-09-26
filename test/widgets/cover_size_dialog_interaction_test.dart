import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/providers/library_provider.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:freegosy/ui/widgets/cover_size_button.dart';
import 'package:freegosy/ui/widgets/gamepad_slider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Using the library's cover-size dialog end to end.
void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  Future<void> openDialog(WidgetTester tester, {int columns = 6, String preset = 'windows_best'}) async {
    SharedPreferences.setMockInitialValues({'column_count': columns, 'active_preset': preset});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: Center(child: CoverSizeButton()))),
    ));
    await tester.tap(find.byTooltip('Cover size'));
    await tester.pumpAndSettle();
  }

  tearDown(() => container.dispose());

  GamepadSlider slider(WidgetTester tester) => tester.widget<GamepadSlider>(find.byType(GamepadSlider));

  testWidgets('moving the slider right makes covers bigger (fewer per row) and saves it', (tester) async {
    await openDialog(tester, columns: 6);

    slider(tester).onChanged(CoverSizeButton.sizeStepFor(4).toDouble());
    await tester.pumpAndSettle();

    expect(container.read(columnCountProvider), 4);
    expect(prefs.getInt('column_count'), 4);
    expect(find.text('4 games per row'), findsOneWidget);
  });

  testWidgets('moving it all the way left gives the smallest covers', (tester) async {
    await openDialog(tester, columns: 6);

    slider(tester).onChanged(0);
    await tester.pumpAndSettle();

    expect(container.read(columnCountProvider), kMaxColumnCount);
  });

  testWidgets('a change switches the display preset to custom', (tester) async {
    await openDialog(tester, columns: 6, preset: 'cozy');

    slider(tester).onChanged(CoverSizeButton.sizeStepFor(8).toDouble());
    await tester.pumpAndSettle();

    expect(container.read(activePresetProvider), 'custom');
  });

  testWidgets('landing on the current size changes nothing, preset included', (tester) async {
    await openDialog(tester, columns: 6, preset: 'cozy');

    slider(tester).onChanged(CoverSizeButton.sizeStepFor(6).toDouble());
    await tester.pumpAndSettle();

    expect(container.read(columnCountProvider), 6);
    expect(container.read(activePresetProvider), 'cozy');
  });

  testWidgets('dragging the real slider thumb resizes covers', (tester) async {
    await openDialog(tester, columns: 6);

    await tester.drag(find.byType(Slider), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(container.read(columnCountProvider), kMaxColumnCount);
  });

  testWidgets('Done closes the dialog and keeps the new size', (tester) async {
    await openDialog(tester, columns: 6);
    slider(tester).onChanged(CoverSizeButton.sizeStepFor(3).toDouble());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Cover size'), findsNothing);
    expect(container.read(columnCountProvider), 3);
  });
}
