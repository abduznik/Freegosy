import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/emulator/strategies/retroarch_strategy.dart';
import 'package:freegosy/core/emulator/strategies/dolphin_strategy.dart';
import 'package:freegosy/core/emulator/strategies/eden_strategy.dart';
import 'package:freegosy/core/emulator/emulator_registry_data.dart';
import 'package:freegosy/core/storage/directory_service.dart';

class StrategyRegistry {
  final DirectoryService _directoryService;
  late final List<EmulatorStrategy> _strategies;

  StrategyRegistry(this._directoryService) {
    _strategies = [
      RetroArchStrategy(_directoryService),
      DolphinStrategy(_directoryService),
      EdenStrategy(_directoryService),
    ];
  }

  EmulatorStrategy? getStrategyForSlug(String platformSlug) {
    if (kIsWeb) {
      return null;
    }

    for (final strategy in _strategies) {
      if (strategy.supportedSlugs.contains(platformSlug)) {
        return strategy;
      }
    }
    return null;
  }

  Map<String, dynamic>? getDefinition(String emulatorId) {
    try {
      return kEmulatorDefinitions.firstWhere((def) => def['id'] == emulatorId);
    } catch (e) {
      return null;
    }
  }
}
