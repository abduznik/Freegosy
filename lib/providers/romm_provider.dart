import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/save/save_sync_service.dart';
import 'package:freegosy/core/emulator/strategies/windows_strategy.dart';
import 'package:freegosy/core/emulator/emulator_registry_data.dart';

import 'package:freegosy/core/storage/download_cache_service.dart';
import 'package:freegosy/core/storage/metadata_cache_service.dart';
import 'package:freegosy/core/storage/rom_mapping_service.dart';
import 'package:freegosy/core/romm/rom_scanner_service.dart';
import 'package:freegosy/providers/custom_emulators_provider.dart';

import 'package:freegosy/core/emulator/firmware_service.dart';

import 'package:freegosy/core/storage/secure_storage_service.dart';

final emulatorStatusProvider = FutureProvider<Map<String, bool>>((ref) async {
  final directoryService = ref.watch(directoryServiceProvider).asData?.value;
  if (directoryService == null) return {};

  final states = <String, bool>{};
  for (final def in kEmulatorDefinitions) {
    final id = def['id'] as String;
    final String exe;
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      exe = (def['macos_executable'] as String?) ?? (def['windows_executable'] as String? ?? '');
    } else if (defaultTargetPlatform == TargetPlatform.linux) {
      exe = (def['linux_executable'] as String?) ?? '';
    } else {
      exe = (def['windows_executable'] as String?) ?? '';
    }
    if (exe.isEmpty) {
      states[id] = true;
      continue;
    }
    states[id] = await directoryService.isEmulatorInstalled(id, exe);
  }
  return states;
});

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
  
  String baseUrl = prefs.getString('rommBaseUrl') ?? '';
  if (baseUrl.isEmpty) baseUrl = 'https://api.romm.example.com';
  
  final username = prefs.getString('rommUsername') ?? '';
  final password = await SecureStorageService.read('rommPassword') ?? '';
  final token = await SecureStorageService.read('rommAuthToken');
  final apiKey = await SecureStorageService.read('rommApiKey') ?? '';

  debugPrint('[RomM-Init] Loading config:');
  debugPrint('  - Base URL: $baseUrl');
  debugPrint('  - Username: ${username.isEmpty ? "EMPTY" : username}');
  debugPrint('  - Password: ${password.isEmpty ? "EMPTY" : "LOADED"}');
  debugPrint('  - API Key: ${apiKey.isEmpty ? "EMPTY" : "LOADED"}');

  return RomMConfig(
    baseUrl: baseUrl, 
    username: username, 
    password: password, 
    token: token, 
    apiKey: apiKey
  );
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
    // Return service even on error so UI can access service.status
    final service = DirectoryService();
    service.status = StorageStatus(error: StorageError.unknown, message: e.toString());
    return service;
  }
});

// Provider for StrategyRegistry
final strategyRegistryProvider = FutureProvider<StrategyRegistry?>((ref) async {
  final directoryService = ref.watch(directoryServiceProvider).value;
  final customEmulators = ref.watch(customEmulatorsProvider);
  
  if (directoryService != null) {
    try {
      final registry = StrategyRegistry(directoryService, customEmulators: customEmulators);
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
      debugPrint('[RomM-Init] Initializing RommService with config for ${config.baseUrl}');
      final service = RommService(config);
      // Refresh token on startup to ensure latest scopes
      if (config.username.isNotEmpty && config.password.isNotEmpty) {
        debugPrint('[RomM-Init] Triggering background token refresh...');
        service.refreshToken();
      }
      return service;
    } catch (e) {
      debugPrint('[RomM-Init] FAILED to initialize RommService: $e');
      return null;
    }
  }
  return null;
});

final metadataCacheServiceProvider = FutureProvider<MetadataCacheService>((ref) async {
  final service = MetadataCacheService();
  await service.load();
  return service;
});

final romMappingServiceProvider = FutureProvider<RomMappingService>((ref) async {
  final service = RomMappingService();
  await service.init();
  return service;
});

final romScannerServiceProvider = Provider<RomScannerService?>((ref) {
  final rommService = ref.watch(rommServiceProvider);
  final mappingServiceAsync = ref.watch(romMappingServiceProvider);
  
  if (rommService != null && mappingServiceAsync.hasValue) {
    return RomScannerService(rommService, mappingServiceAsync.value!);
  }
  return null;
});
