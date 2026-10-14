import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/stats/play_time_store.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PlayTimeStore store;
  final t0 = DateTime.utc(2026, 10, 14, 12);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = PlayTimeStore(SharedPreferencesAppPreferences(await SharedPreferences.getInstance()));
  });

  test('no record yet', () => expect(store.statsFor('1'), isNull));

  test('sessions add up per game', () async {
    await store.record('1', t0, t0.add(const Duration(minutes: 30)));
    await store.record('1', t0.add(const Duration(days: 1)), t0.add(const Duration(days: 1, hours: 1, minutes: 15)));
    await store.record('2', t0, t0.add(const Duration(minutes: 5)));
    final s = store.statsFor('1')!;
    expect(s.total, const Duration(hours: 1, minutes: 45));
    expect(s.sessions, 2);
    expect(s.lastPlayed, t0.add(const Duration(days: 1, hours: 1, minutes: 15)));
    expect(store.statsFor('2')!.total, const Duration(minutes: 5));
  });

  test('a launch that closes within seconds is not counted', () async {
    await store.record('1', t0, t0.add(const Duration(seconds: 4)));
    expect(store.statsFor('1'), isNull);
  });

  test('a corrupt value reads as no record', () async {
    SharedPreferences.setMockInitialValues({'playtime_9': 'not json'});
    final s = PlayTimeStore(SharedPreferencesAppPreferences(await SharedPreferences.getInstance()));
    expect(s.statsFor('9'), isNull);
  });

  test('format', () {
    expect(PlayTimeStore.format(const Duration(seconds: 30)), 'under a minute');
    expect(PlayTimeStore.format(const Duration(minutes: 45)), '45m');
    expect(PlayTimeStore.format(const Duration(hours: 2)), '2h');
    expect(PlayTimeStore.format(const Duration(hours: 2, minutes: 15)), '2h 15m');
    expect(PlayTimeStore.format(const Duration(hours: 12, minutes: 40)), '12h');
  });

  test('ago', () {
    final now = DateTime(2026, 10, 14, 12);
    expect(PlayTimeStore.ago(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
    expect(PlayTimeStore.ago(now.subtract(const Duration(minutes: 1)), now: now), '1 minute ago');
    expect(PlayTimeStore.ago(now.subtract(const Duration(hours: 3)), now: now), '3 hours ago');
    expect(PlayTimeStore.ago(now.subtract(const Duration(days: 1, hours: 2)), now: now), 'yesterday');
    expect(PlayTimeStore.ago(now.subtract(const Duration(days: 9)), now: now), '9 days ago');
    expect(PlayTimeStore.ago(now.subtract(const Duration(days: 65)), now: now), '2 months ago');
  });
}
