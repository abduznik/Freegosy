import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/storage/secret_store.dart';
import 'package:freegosy/core/storage/secure_storage_service.dart';

import '../../helpers/fake_retroachievements.dart' show InMemoryAppPreferences;

class _MapStore implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
}

class _ThrowingStore implements SecretStore {
  @override
  Future<String?> read(String key) async => throw StateError('drive removed');
  @override
  Future<void> write(String key, String value) async => throw StateError('drive removed');
  @override
  Future<void> delete(String key) async => throw StateError('drive removed');
  @override
  Future<Map<String, String>> readAll() async => throw StateError('drive removed');
}

void main() {
  tearDown(() => SecureStorageService.useStore(null));

  test('with a store set, reads, writes and deletes go to it', () async {
    final store = _MapStore();
    final prefs = InMemoryAppPreferences();
    SecureStorageService.useStore(store);
    await SecureStorageService.write('rommPassword', 'pw', prefs);
    expect(store.values, {'rommPassword': 'pw'});
    expect(await SecureStorageService.read('rommPassword', prefs), 'pw');
    await SecureStorageService.delete('rommPassword', prefs);
    expect(store.values, isEmpty);
    expect(prefs.getKeys(), isEmpty, reason: 'nothing leaks into plain prefs');
  });

  test('a store that throws never makes the service throw', () async {
    final prefs = InMemoryAppPreferences();
    SecureStorageService.useStore(_ThrowingStore());
    expect(await SecureStorageService.read('k', prefs), isNull);
    await SecureStorageService.write('k', 'v', prefs);
    await SecureStorageService.delete('k', prefs);
  });
}
