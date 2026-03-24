import 'package:flutter/foundation.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/emulator/strategies/retroarch_strategy.dart';
import 'package:freegosy/core/emulator/strategies/dolphin_strategy.dart';
import 'package:freegosy/core/emulator/strategies/eden_strategy.dart';
import 'package:freegosy/core/emulator/strategies/rpcs3_strategy.dart';
import 'package:freegosy/core/emulator/strategies/pcsx2_strategy.dart';
import 'package:freegosy/core/emulator/strategies/azahar_strategy.dart';
import 'package:freegosy/core/emulator/strategies/cemu_strategy.dart';
import 'package:freegosy/core/emulator/strategies/duckstation_strategy.dart';
import 'package:freegosy/core/emulator/strategies/xemu_strategy.dart';
import 'package:freegosy/core/emulator/strategies/xenia_strategy.dart';
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
      Rpcs3Strategy(_directoryService),
      Pcsx2Strategy(_directoryService),
      AzaharStrategy(_directoryService),
      CemuStrategy(_directoryService),
      DuckstationStrategy(_directoryService),
      XemuStrategy(_directoryService),
      XeniaStrategy(_directoryService),
    ];
  }

  EmulatorStrategy? getStrategyForSlug(String platformSlug) {
    if (kIsWeb) return null;
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