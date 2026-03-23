import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/romm/romm_service.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';

// Provider for loading RomMConfig (e.g., from SharedPreferences)
final rommConfigProvider = FutureProvider<RomMConfig>((ref) async {
  // Placeholder for actual configuration loading.
  // In a real app, you'd load this from SharedPreferences, a config file, or API.
  // For demonstration, using placeholder values.
  final prefs = await SharedPreferences.getInstance();
  final baseUrl = prefs.getString('rommBaseUrl') ?? 'https://api.romm.example.com';
  final username = prefs.getString('rommUsername') ?? 'guest';
  final password = prefs.getString('rommPassword') ?? '';

  return RomMConfig(baseUrl: baseUrl, username: username, password: password);
});


// Simplified DirectoryService provider
final directoryServiceProvider = FutureProvider<DirectoryService?>((ref) async {
  try {
    final service = DirectoryService();
    await service.initialize();
    return service;
  } catch (e) {
    return null; // Return null on error
  }
});

// Provider for StrategyRegistry
final strategyRegistryProvider = Provider<StrategyRegistry?>((ref) {
  final directoryService = ref.watch(directoryServiceProvider).value; // Get the value from AsyncValue

  // Only create StrategyRegistry if DirectoryService is available
  if (directoryService != null) {
    try {
      return StrategyRegistry(directoryService);
    } catch (e) {
      return null; // Return null on error
    }
  }
  return null; // Return null if DirectoryService is not ready
});


// Simplified RommService provider
final rommServiceProvider = Provider<RommService?>((ref) {
  final rommConfigAsync = ref.watch(rommConfigProvider);
  final directoryServiceAsync = ref.watch(directoryServiceProvider);

  // Get actual values, handle null/error states from AsyncValue
  final config = rommConfigAsync.asData?.value;
  final directoryService = directoryServiceAsync.asData?.value;

  // Only create RommService if config and directoryService are available
  if (config != null && directoryService != null) {
    try {
      // RommService constructor is RommService(this.config) and creates its own Dio instance.
      return RommService(config);
    } catch (e) {
      return null; // Return null on error during instantiation
    }
  }
  return null; // Return null if dependencies are not ready
});

// Removed RommService class definition as it's imported.
// Removed RommServiceExtension as it's no longer needed with the simplified provider.
