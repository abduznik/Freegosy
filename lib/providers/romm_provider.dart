import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';

// Provider for loading RomMConfig (including stored Bearer token)
final rommConfigProvider = FutureProvider<RomMConfig>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final baseUrl = prefs.getString('rommBaseUrl') ?? 'https://api.romm.example.com';
  final username = prefs.getString('rommUsername') ?? 'guest';
  final password = prefs.getString('rommPassword') ?? '';
  final token = prefs.getString('rommAuthToken');

  return RomMConfig(baseUrl: baseUrl, username: username, password: password, token: token);
});

// Exposes a login function that fetches a Bearer token and refreshes the config/service providers.
final loginProvider = Provider<Future<void> Function(String baseUrl, String username, String password)>((ref) {
  return (baseUrl, username, password) async {
    await RommService.fetchToken(baseUrl, username, password);
    ref.invalidate(rommConfigProvider);
    ref.invalidate(rommServiceProvider);
  };
});

// Simplified DirectoryService provider
final directoryServiceProvider = FutureProvider<DirectoryService?>((ref) async {
  try {
    final service = DirectoryService();
    await service.initialize();
    return service;
  } catch (e) {
    return null;
  }
});

// Provider for StrategyRegistry
final strategyRegistryProvider = Provider<StrategyRegistry?>((ref) {
  final directoryService = ref.watch(directoryServiceProvider).value;
  if (directoryService != null) {
    try {
      return StrategyRegistry(directoryService);
    } catch (e) {
      return null;
    }
  }
  return null;
});

// Simplified RommService provider
final rommServiceProvider = Provider<RommService?>((ref) {
  final rommConfigAsync = ref.watch(rommConfigProvider);
  final directoryServiceAsync = ref.watch(directoryServiceProvider);

  final config = rommConfigAsync.asData?.value;
  final directoryService = directoryServiceAsync.asData?.value;

  if (config != null && directoryService != null) {
    try {
      return RommService(config);
    } catch (e) {
      return null;
    }
  }
  return null;
});
