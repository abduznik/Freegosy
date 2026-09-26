import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/platform/window_service.dart';
import 'package:freegosy/providers/library_provider.dart';
import 'package:freegosy/providers/platform_info_provider.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:freegosy/ui/screens/settings_display_section.dart';
import 'package:freegosy/ui/widgets/gamepad_slider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings → Display: the "Start in fullscreen" switch and the
/// games-per-row range.
void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  Future<void> pumpDisplaySection(WidgetTester tester, PlatformInfo platform) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformInfoProvider.overrideWithValue(platform),
      ]),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Consumer(builder: (context, ref, _) {
              return buildDisplaySection(
                context,
                ref.watch(cardAspectRatioProvider),
                ref.watch(columnCountProvider),
                ref.watch(cardSpacingProvider),
                ref.watch(showTitleProvider),
                ref.watch(activePresetProvider),
                ref,
              );
            }),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() => container.dispose());

  for (final os in ['windows', 'linux', 'macos']) {
    testWidgets('"Start in fullscreen" is offered on $os', (tester) async {
      await pumpDisplaySection(tester, PlatformInfo(os));
      expect(find.text('Start in fullscreen'), findsOneWidget);
    });
  }

  testWidgets('"Start in fullscreen" is hidden in the browser', (tester) async {
    await pumpDisplaySection(tester, PlatformInfo.web);
    expect(find.text('Start in fullscreen'), findsNothing);
    expect(find.text('Show game title'), findsOneWidget);
  });

  testWidgets('tapping "Start in fullscreen" saves the setting main() reads at startup', (tester) async {
    await pumpDisplaySection(tester, const PlatformInfo('linux'));
    expect(prefs.getBool(WindowService.launchFullscreenPrefKey), isNull);

    await tester.ensureVisible(find.text('Start in fullscreen'));
    await tester.tap(find.text('Start in fullscreen'));
    await tester.pumpAndSettle();

    expect(container.read(launchFullscreenProvider), isTrue);
    expect(prefs.getBool(WindowService.launchFullscreenPrefKey), isTrue);
    expect(WindowService.shouldStartFullscreen(const [], prefs.getBool(WindowService.launchFullscreenPrefKey)), isTrue);

    await tester.tap(find.text('Start in fullscreen'));
    await tester.pumpAndSettle();
    expect(prefs.getBool(WindowService.launchFullscreenPrefKey), isFalse);
  });

  testWidgets('games-per-row slider spans kMinColumnCount..kMaxColumnCount', (tester) async {
    await pumpDisplaySection(tester, const PlatformInfo('linux'));
    final slider = tester.widget<GamepadSlider>(find.byType(GamepadSlider));
    expect(slider.min, kMinColumnCount.toDouble());
    expect(slider.max, kMaxColumnCount.toDouble());
    expect(slider.divisions, kMaxColumnCount - kMinColumnCount);
    expect(kMaxColumnCount, 12);
  });

  testWidgets('a stored column count above the range is clamped instead of breaking the slider', (tester) async {
    SharedPreferences.setMockInitialValues({'column_count': 30});
    prefs = await SharedPreferences.getInstance();
    await pumpDisplaySection(tester, const PlatformInfo('linux'));
    final slider = tester.widget<GamepadSlider>(find.byType(GamepadSlider));
    expect(slider.value, kMaxColumnCount.toDouble());
  });
}
