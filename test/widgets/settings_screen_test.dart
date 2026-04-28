import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/providers/romm_provider.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:freegosy/ui/screens/settings_screen.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_screen_test.mocks.dart';

@GenerateMocks([DirectoryService, RommService, StrategyRegistry])
void main() {
  late MockDirectoryService mockDirectoryService;
  late MockRommService mockRommService;
  late MockStrategyRegistry mockStrategyRegistry;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'rommBaseUrl': 'https://old.com',
      'rommUsername': 'olduser',
    });
    prefs = await SharedPreferences.getInstance();
    mockDirectoryService = MockDirectoryService();
    mockRommService = MockRommService();
    mockStrategyRegistry = MockStrategyRegistry();
    
    when(mockDirectoryService.romsRootPath).thenReturn('/roms');
    when(mockDirectoryService.emulatorsRootPath).thenReturn('/emulators');
    when(mockDirectoryService.status).thenReturn(const StorageStatus());
    when(mockDirectoryService.isEmulatorInstalled(any, any)).thenAnswer((_) async => true);
    when(mockDirectoryService.getEmulatorPathOverride(any)).thenReturn(null);
    when(mockDirectoryService.linuxSyncPreset).thenReturn('default');
    when(mockRommService.getPlatforms()).thenAnswer((_) async => []);
    when(mockStrategyRegistry.detectConflicts()).thenReturn(<String, List<EmulatorStrategy>>{});
  });

  Widget createSettingsScreen() {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        rommServiceProvider.overrideWithValue(mockRommService),
        directoryServiceProvider.overrideWith((ref) => Future.value(mockDirectoryService)),
        strategyRegistryProvider.overrideWith((ref) => Future.value(mockStrategyRegistry)),
        rommConfigProvider.overrideWith((ref) => Future.value(RomMConfig(
          baseUrl: 'https://old.com',
          username: 'olduser',
          password: 'oldpassword',
        ))),
      ],
      child: const MaterialApp(
        home: SettingsScreen(),
      ),
    );
  }

  group('SettingsScreen', () {
    testWidgets('renders server configuration fields', (WidgetTester tester) async {
      await tester.pumpWidget(createSettingsScreen());
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsWidgets);
      expect(find.text('Server URL'), findsWidgets);
    });

    testWidgets('renders storage section', (WidgetTester tester) async {
      // Set large surface size to avoid ListView lazy loading issues
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createSettingsScreen());
      await tester.pumpAndSettle();

      expect(find.textContaining('roms'), findsWidgets);
      expect(find.textContaining('emulators'), findsWidgets);
    });

    testWidgets('renders emulator section', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createSettingsScreen());
      await tester.pumpAndSettle();

      expect(find.text('Emulators'), findsWidgets);
    });
  });
}
