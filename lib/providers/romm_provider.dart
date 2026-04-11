import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/emulator/strategies/windows_strategy.dart';

import 'package:freegosy/core/storage/download_cache_service.dart';

import 'package:freegosy/core/emulator/firmware_service.dart';

import 'package:freegosy/core/storage/secure_storage_service.dart';

final firmwareServiceProvider = FutureProvider<FirmwareService?>((ref) async {
  final rommService = ref.watch(rommServiceProvider);
  final directoryService = ref.watch(directoryServiceProvider).asData?.value;
  final strategyRegistry = await ref.watch(strategyRegistryProvider.future);
  if (rommService == null || directoryService == null || strategyRegistry == null) return null;
  return FirmwareService(rommService, directoryService, strategyRegistry);
});

final downloadCacheServiceProvider = Provider<DownloadCacheService>((ref) {
  return DownloadCacheService();
});

// Provider for loading RomMConfig (including stored Bearer token)
final rommConfigProvider = FutureProvider<RomMConfig>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final baseUrl = prefs.getString('rommBaseUrl') ?? 'https://api.romm.example.com';
  final username = prefs.getString('rommUsername') ?? 'guest';
  final password = await SecureStorageService.read('rommPassword') ?? '';
  final token = await SecureStorageService.read('rommAuthToken');
  final apiKey = await SecureStorageService.read('rommApiKey') ?? '';

  return RomMConfig(baseUrl: baseUrl, username: username, password: password, token: token, apiKey: apiKey);
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
final strategyRegistryProvider = FutureProvider<StrategyRegistry?>((ref) async {
  final directoryService = ref.watch(directoryServiceProvider).value;
  if (directoryService != null) {
    try {
      final registry = StrategyRegistry(directoryService);
      await registry.loadPreferences(); // Await preferences loading
      // Load persisted Windows exe overrides
      final winStrategy = registry.getStrategyForSlug('windows');
      if (winStrategy is WindowsStrategy) {
        winStrategy.loadPersistedOverrides();
      }
      return registry;
    } catch (e) {
      return null;
    }
  }
  return null;
});

// SaveSyncService provider
final saveSyncServiceProvider = FutureProvider<SaveSyncService?>((ref) async {
  final rommService = ref.watch(rommServiceProvider);
  final directoryService = ref.watch(directoryServiceProvider).asData?.value;
  final strategyRegistry = await ref.watch(strategyRegistryProvider.future);
  if (rommService == null || directoryService == null || strategyRegistry == null) return null;
  final service = SaveSyncService(rommService, directoryService, strategyRegistry);
  service.windowsSaveStrategy.loadPersistedOverrides();
  return service;
});

// Simplified RommService provider
final rommServiceProvider = Provider<RommService?>((ref) {
  final rommConfigAsync = ref.watch(rommConfigProvider);
  final directoryServiceAsync = ref.watch(directoryServiceProvider);

  final config = rommConfigAsync.asData?.value;
  final directoryService = directoryServiceAsync.asData?.value;

  if (config != null && directoryService != null) {
    try {
      final service = RommService(config);
      // Refresh token on startup to ensure latest scopes
      if (config.username.isNotEmpty && config.password.isNotEmpty) {
        service.refreshToken();
      }
      return service;
    } catch (e) {
      return null;
    }
  }
  return null;
});
