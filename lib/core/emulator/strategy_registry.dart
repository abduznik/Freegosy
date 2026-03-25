import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/emulator/strategies/retroarch_strategy.dart';
import 'package:freegosy/core/emulator/strategies/dolphin_strategy.dart';
import 'package:freegosy/core/emulator/strategies/eden_strategy.dart';
import 'package:freegosy/core/emulator/strategies/rpcs3_strategy.dart';
import 'package:freegosy/core/emulator/strategies/pcsx2_strategy.dart';
import 'package:freegosy/core/emulator/strategies/azahar_strategy.dart';
import 'package:freegosy/core/emulator/strategies/cemu_strategy.dart';
import 'package:freegosy/core/emulator/strategies/duckstation_strategy.dart';
import 'package:freegosy/core/emulator/strategies/flycast_strategy.dart';
import 'package:freegosy/core/emulator/strategies/melonds_strategy.dart';
import 'package:freegosy/core/emulator/strategies/xemu_strategy.dart';
import 'package:freegosy/core/emulator/strategies/xenia_strategy.dart';
import 'package:freegosy/core/emulator/emulator_registry_data.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/emulator/strategies/windows_strategy.dart';

class StrategyRegistry {
  final DirectoryService _directoryService;
  late final List<EmulatorStrategy> _strategies;
  final Map<String, String> _slugPreferences = {};

  StrategyRegistry(this._directoryService) {
    final List<EmulatorStrategy> allPossibleStrategies = [
      RetroArchStrategy(_directoryService),
      DolphinStrategy(_directoryService),
      EdenStrategy(_directoryService),
      Rpcs3Strategy(_directoryService),
      Pcsx2Strategy(_directoryService),
      AzaharStrategy(_directoryService),
      CemuStrategy(_directoryService),
      DuckstationStrategy(_directoryService),
      FlycastStrategy(_directoryService),
      MelonDSStrategy(_directoryService),
      XemuStrategy(_directoryService),
      XeniaStrategy(_directoryService),
      WindowsStrategy(_directoryService),
    ];

    _strategies = allPossibleStrategies.where((strategy) {
      final definition = getDefinition(strategy.emulatorId);
      if (definition == null) return true; // Default to including if no definition found
      final supported = List<String>.from(definition['supported_platforms'] ?? []);
      if (Platform.isWindows && supported.contains('windows')) return true;
      if (Platform.isLinux && supported.contains('linux')) return true;
      return false;
    }).toList();
  }

  Map<String, List<EmulatorStrategy>> detectConflicts() {
    final Map<String, List<EmulatorStrategy>> slugToStrategies = {};
    for (final strategy in _strategies) {
      for (final slug in strategy.supportedSlugs) {
        slugToStrategies.putIfAbsent(slug, () => []).add(strategy);
      }
    }

    final Map<String, List<EmulatorStrategy>> conflicts = {};
    slugToStrategies.forEach((slug, list) {
      if (list.length > 1) {
        conflicts[slug] = list;
      }
    });
    return conflicts;
  }

  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (key.startsWith('emulator_pref_')) {
        final slug = key.replaceFirst('emulator_pref_', '');
        final emulatorId = prefs.getString(key);
        if (emulatorId != null) {
          _slugPreferences[slug] = emulatorId;
        }
      }
    }
  }

  Future<void> setPreference(String slug, String emulatorId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('emulator_pref_$slug', emulatorId);
    _slugPreferences[slug] = emulatorId;
  }

  EmulatorStrategy? getStrategyForSlug(String platformSlug) {
    if (kIsWeb) return null;

    final preferredId = _slugPreferences[platformSlug];
    if (preferredId != null) {
      for (final strategy in _strategies) {
        if (strategy.emulatorId == preferredId) {
          return strategy;
        }
      }
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