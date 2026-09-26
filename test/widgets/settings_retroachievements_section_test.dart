import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/retroachievements/retroachievements_emulator_login.dart';
import 'package:freegosy/core/retroachievements/retroachievements_models.dart';
import 'package:freegosy/providers/retroachievements_provider.dart';
import 'package:freegosy/providers/romm_provider.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:freegosy/ui/screens/settings_retroachievements_section.dart';

import '../helpers/fake_retroachievements.dart';

/// Drives the RetroAchievements Settings form against a fake RA service and
/// in-memory storage: username required, password/Web API key optional, and
/// a confirmation when saving without a password.
void main() {
  late InMemoryAppPreferences prefs;
  late FakeRetroAchievementsService service;

  setUp(() {
    useInMemorySecureStorage();
    prefs = InMemoryAppPreferences();
    service = FakeRetroAchievementsService(loginUsername: 'Player');
  });
  tearDown(resetSecureStorage);

  // No RomM connection unless a test provides one, so the RomM link UI stays hidden.
  Future<void> pumpSection(WidgetTester tester, {FakeRommRaService? romm}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithValue(prefs),
        retroAchievementsServiceProvider.overrideWithValue(service),
        rommServiceProvider.overrideWithValue(romm),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: SettingsRetroAchievementsSection())),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> tapConnect(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
  }

  group('connecting', () {
    testWidgets('shows the three fields, with password and key marked optional', (tester) async {
      await pumpSection(tester);
      expect(field('Username'), findsOneWidget);
      expect(field('Password (optional)'), findsOneWidget);
      expect(field('Web API Key (optional)'), findsOneWidget);
      expect(find.text('Signs RetroArch in to RetroAchievements. Used once, never stored.'), findsOneWidget);
    });

    testWidgets('requires a username', (tester) async {
      await pumpSection(tester);
      await tapConnect(tester);
      expect(find.text('Username is required.'), findsOneWidget);
      expect(service.calls, isEmpty);
    });

    testWidgets('requires a password or a Web API key', (tester) async {
      await pumpSection(tester);
      await tester.enterText(field('Username'), 'Player');
      await tapConnect(tester);
      expect(find.text('Enter your password, your Web API key, or both.'), findsOneWidget);
      expect(service.calls, isEmpty);
    });

    testWidgets('warns before saving without a password; Go back saves nothing', (tester) async {
      await pumpSection(tester);
      await tester.enterText(field('Username'), 'Player');
      await tester.enterText(field('Web API Key (optional)'), 'webkey');
      await tapConnect(tester);

      expect(find.text('Emulators won\'t be set up'), findsOneWidget);
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();

      expect(find.text('Emulators won\'t be set up'), findsNothing);
      expect(service.calls, isEmpty);
      expect(prefs.values, isEmpty);
    });

    testWidgets('Save anyway connects with the key only', (tester) async {
      await pumpSection(tester);
      await tester.enterText(field('Username'), 'Player');
      await tester.enterText(field('Web API Key (optional)'), 'webkey');
      await tapConnect(tester);
      await tester.tap(find.text('Save anyway'));
      await tester.pumpAndSettle();

      expect(service.calls, contains('profile:Player'));
      expect(service.calls.where((c) => c.startsWith('login:')), isEmpty);
      expect(find.text('Connected to RetroAchievements!'), findsOneWidget);
      expect(find.text('Emulators are not signed in — add your password to set them up.'), findsOneWidget);
      expect(find.text('Live progress from RetroAchievements.'), findsOneWidget);
      expect(find.text('Hardcore mode'), findsNothing);
    });

    testWidgets('with a password: no warning, RetroArch signed in, token stored', (tester) async {
      await pumpSection(tester);
      await tester.enterText(field('Username'), 'Player');
      await tester.enterText(field('Password (optional)'), 'hunter2');
      await tapConnect(tester);

      expect(find.text('Emulators won\'t be set up'), findsNothing);
      expect(prefs.getString(secureKey(kRaConnectTokenSecureKey)), 'tok123');
      expect(prefs.values.values, isNot(contains('hunter2')));
      expect(find.text('RetroArch is signed in at launch.'), findsOneWidget);
      expect(
        find.text('Progress comes from RomM only (if your server has RetroAchievements enabled).'),
        findsOneWidget,
      );
      expect(find.text('Hardcore mode'), findsOneWidget);
    });

    testWidgets('shows RA\'s error for a wrong password and stays in the form', (tester) async {
      service.loginError = const RetroAchievementsAuthException('Invalid User/Password combination.');
      await pumpSection(tester);
      await tester.enterText(field('Username'), 'Player');
      await tester.enterText(field('Password (optional)'), 'wrong');
      await tapConnect(tester);

      expect(find.text('Invalid User/Password combination.'), findsOneWidget);
      expect(field('Username'), findsOneWidget);
      expect(prefs.values, isEmpty);
    });
  });

  group('connected', () {
    setUp(() {
      prefs.values.addAll({
        kRaUsernameKey: 'Player',
        secureKey(kRaWebApiKeySecureKey): 'webkey',
        secureKey(kRaConnectTokenSecureKey): 'tok',
      });
    });

    testWidgets('shows the profile and both statuses', (tester) async {
      await pumpSection(tester);
      expect(find.text('Player'), findsOneWidget);
      expect(find.text('Rank #1 — 100 points (200 hardcore)'), findsOneWidget);
      expect(find.text('RetroArch is signed in at launch.'), findsOneWidget);
      expect(find.text('Live progress from RetroAchievements.'), findsOneWidget);
    });

    testWidgets('hardcore switch persists', (tester) async {
      await pumpSection(tester);
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(prefs.getBool(kRaHardcoreKey), isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('editing without a password keeps the emulator login (no warning)', (tester) async {
      await pumpSection(tester);
      await tester.tap(find.byIcon(Icons.lock));
      await tester.pumpAndSettle();

      expect(find.text('Emulators are signed in. Leave empty to keep that, or re-enter to refresh.'), findsOneWidget);
      await tapConnect(tester);

      expect(find.text('Emulators won\'t be set up'), findsNothing);
      expect(prefs.getString(secureKey(kRaConnectTokenSecureKey)), 'tok');
      // The saved key was pre-filled, so re-saving doesn't wipe it.
      expect(prefs.getString(secureKey(kRaWebApiKeySecureKey)), 'webkey');
    });

    testWidgets('disconnect clears everything and returns to the form', (tester) async {
      await pumpSection(tester);
      await tester.tap(find.byIcon(Icons.lock));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Disconnect'));
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(prefs.values, isEmpty);
      expect(field('Username'), findsOneWidget);
      expect(find.text('Disconnected from RetroAchievements.'), findsOneWidget);
    });
  });

  testWidgets('connected without a Web API key shows the username without a profile call', (tester) async {
    prefs.values.addAll({kRaUsernameKey: 'Player', secureKey(kRaConnectTokenSecureKey): 'tok'});
    await pumpSection(tester);

    expect(find.text('Player'), findsOneWidget);
    expect(service.calls, isEmpty);
    expect(find.text('Progress comes from RomM only (if your server has RetroAchievements enabled).'), findsOneWidget);
  });

  group('RomM link', () {
    final dialogLink = find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(TextButton, 'Link'));

    Future<void> connectWithPassword(WidgetTester tester) async {
      await tester.enterText(field('Username'), 'Player');
      await tester.enterText(field('Password (optional)'), 'pw');
      await tapConnect(tester);
    }

    testWidgets('warns when the RomM server has RetroAchievements disabled', (tester) async {
      await pumpSection(tester, romm: FakeRommRaService(raEnabled: false));
      expect(find.textContaining('RomM server doesn\'t have RetroAchievements enabled'), findsOneWidget);
      expect(find.textContaining('RETROACHIEVEMENTS_API_KEY'), findsOneWidget);
    });

    testWidgets('no warning when RomM\'s RA status is unknown', (tester) async {
      await pumpSection(tester, romm: FakeRommRaService(raEnabled: null));
      expect(find.textContaining('RetroAchievements enabled'), findsNothing);
    });

    testWidgets('after connecting, asks permission and links the RomM profile', (tester) async {
      final romm = FakeRommRaService(linkedUsername: 'OldName');
      await pumpSection(tester, romm: romm);
      await connectWithPassword(tester);

      expect(find.text('Link RomM profile?'), findsOneWidget);
      expect(find.textContaining('(currently "OldName")'), findsOneWidget);
      await tester.tap(dialogLink);
      await tester.pumpAndSettle();

      expect(romm.calls, containsAllInOrder(['set:5:Player', 'refresh:5']));
      expect(find.text('Linked to RomM and synced your RetroAchievements progress.'), findsOneWidget);
      expect(find.text('Linked to your RomM profile.'), findsOneWidget);
    });

    testWidgets('Not now leaves RomM untouched and offers a Link button', (tester) async {
      final romm = FakeRommRaService();
      await pumpSection(tester, romm: romm);
      await connectWithPassword(tester);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(romm.calls.where((c) => c.startsWith('set:')), isEmpty);
      expect(find.text('Not linked to your RomM profile.'), findsOneWidget);

      await tester.ensureVisible(find.widgetWithText(TextButton, 'Link'));
      await tester.tap(find.widgetWithText(TextButton, 'Link'));
      await tester.pumpAndSettle();
      expect(find.text('Link RomM profile?'), findsOneWidget);
    });

    testWidgets('no prompt when the RomM profile is already linked', (tester) async {
      final romm = FakeRommRaService(linkedUsername: 'player');
      await pumpSection(tester, romm: romm);
      await connectWithPassword(tester);

      expect(find.text('Link RomM profile?'), findsNothing);
      expect(find.text('Linked to your RomM profile.'), findsOneWidget);
    });

    testWidgets('no prompt when the RomM server has RA disabled', (tester) async {
      await pumpSection(tester, romm: FakeRommRaService(raEnabled: false));
      await connectWithPassword(tester);
      expect(find.text('Link RomM profile?'), findsNothing);
    });

    testWidgets('a sync failure still reports the link', (tester) async {
      final romm = FakeRommRaService(refreshSucceeds: false);
      await pumpSection(tester, romm: romm);
      await connectWithPassword(tester);
      await tester.tap(dialogLink);
      await tester.pumpAndSettle();

      expect(find.text('Linked to RomM. It will sync your progress on its next scheduled run.'), findsOneWidget);
    });

    testWidgets('a failed link is reported', (tester) async {
      final romm = FakeRommRaService()..setError = Exception('403');
      await pumpSection(tester, romm: romm);
      await connectWithPassword(tester);
      await tester.tap(dialogLink);
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not link your RomM profile'), findsOneWidget);
      expect(find.text('Not linked to your RomM profile.'), findsOneWidget);
    });
  });
}
