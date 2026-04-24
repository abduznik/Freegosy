import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/emulator/strategies/retroarch_strategy.dart';
import 'package:freegosy/core/emulator/strategies/dolphin_strategy.dart';
import 'package:freegosy/core/emulator/strategies/eden_strategy.dart';
import 'package:freegosy/core/emulator/strategies/ryujinx_strategy.dart';
import 'package:freegosy/core/emulator/strategies/rpcs3_strategy.dart';
import 'package:freegosy/core/emulator/strategies/pcsx2_strategy.dart';
import 'package:freegosy/core/emulator/strategies/azahar_strategy.dart';
import 'package:freegosy/core/emulator/strategies/cemu_strategy.dart';
import 'package:freegosy/core/emulator/strategies/duckstation_strategy.dart';
import 'package:freegosy/core/emulator/strategies/flycast_strategy.dart';
import 'package:freegosy/core/emulator/strategies/melonds_strategy.dart';
import 'package:freegosy/core/emulator/strategies/mgba_strategy.dart';
import 'package:freegosy/core/emulator/strategies/mame_strategy.dart';
import 'package:freegosy/core/emulator/strategies/ppsspp_strategy.dart';
import 'package:freegosy/core/emulator/strategies/xemu_strategy.dart';
import 'package:freegosy/core/emulator/strategies/xenia_strategy.dart';
import 'package:freegosy/core/emulator/emulator_registry_data.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/emulator/strategies/windows_strategy.dart';
import 'package:freegosy/core/emulator/custom_emulator_config.dart';
import 'package:freegosy/core/emulator/strategies/custom_emulator_strategy.dart';

class StrategyRegistry {
  final DirectoryService _directoryService;
  final SharedPreferences _prefs;
  late final List<EmulatorStrategy> _strategies;
  final List<CustomEmulatorConfig> _customEmulatorConfigs;
  final Map<String, String> _slugPreferences = {};

  StrategyRegistry(this._directoryService, this._prefs, {List<CustomEmulatorConfig> customEmulators = const []}) 
    : _customEmulatorConfigs = customEmulators {
    final List<EmulatorStrategy> allPossibleStrategies = [
      RetroArchStrategy(_directoryService),
      DolphinStrategy(_directoryService),
      EdenStrategy(_directoryService),
      RyujinxStrategy(_directoryService),
      Rpcs3Strategy(_directoryService),
      Pcsx2Strategy(_directoryService),
      AzaharStrategy(_directoryService),
      CemuStrategy(_directoryService),
      DuckstationStrategy(_directoryService),
      FlycastStrategy(_directoryService),
      MelonDSStrategy(_directoryService),
      PPSSPPStrategy(_directoryService),
      MGBAStrategy(_directoryService),
      MAMEStrategy(_directoryService),
      XemuStrategy(_directoryService),
      XeniaStrategy(_directoryService),
      WindowsStrategy(_directoryService, _prefs),
      ..._customEmulatorConfigs.map((config) => CustomEmulatorStrategy(config, _directoryService)),
    ];

    _strategies = allPossibleStrategies.where((strategy) {
      final definition = getDefinition(strategy.emulatorId);
      if (definition == null) return true; // Default to including if no definition found
      final supported = List<String>.from(definition['supported_platforms'] ?? []);
      if (Platform.isWindows && supported.contains('windows')) return true;
      if (Platform.isLinux && supported.contains('linux')) return true;
      if (Platform.isMacOS && supported.contains('macos')) return true;
      return false;
    }).toList();
    
    _loadPreferences();
  }

  Map<String, List<EmulatorStrategy>> detectConflicts() {
    final Map<String, List<EmulatorStrategy>> slugToStrategies = {};
    for (final strategy in _strategies) {
      for (final slug in strategy.supportedSlugs) {
        slugToStrategies.putIfAbsent(slug, () => []).add(strategy);
      }
    }

    // Identify slugs with conflicts
    final Map<String, List<EmulatorStrategy>> allConflicts = {};
    slugToStrategies.forEach((slug, list) {
      if (list.length > 1) {
        allConflicts[slug] = list;
      }
    });

    if (allConflicts.isEmpty) return {};

    // Group slugs that have the exact same set of strategies
    final Map<String, List<String>> groups = {}; // key: stringified sorted emulator IDs, value: list of slugs
    allConflicts.forEach((slug, strategies) {
      final ids = strategies.map((s) => s.emulatorId).toList()..sort();
      final key = ids.join('|');
      groups.putIfAbsent(key, () => []).add(slug);
    });

    final Map<String, List<EmulatorStrategy>> canonicalConflicts = {};
    groups.forEach((key, slugs) {
      // Pick canonical name: longest slug
      final canonical = slugs.reduce((a, b) => a.length > b.length ? a : b);
      // Strategies are the same for all slugs in this group
      canonicalConflicts[canonical] = allConflicts[slugs.first]!;
    });

    return canonicalConflicts;
  }

  String? getPreferredEmulatorId(String slug) => _slugPreferences[slug];

  void _loadPreferences() {
    for (final key in _prefs.getKeys()) {
      if (key.startsWith('emulator_pref_')) {
        final slug = key.replaceFirst('emulator_pref_', '');
        final emulatorId = _prefs.getString(key);
        if (emulatorId != null) {
          _slugPreferences[slug] = emulatorId;
        }
      }
    }
  }

  Future<void> setPreference(String canonicalSlug, String emulatorId) async {
    // Find all slugs that belong to the same group as this canonicalSlug
    final slugToStrategies = <String, List<String>>{};
    for (final strategy in _strategies) {
      for (final slug in strategy.supportedSlugs) {
        slugToStrategies.putIfAbsent(slug, () => []).add(strategy.emulatorId);
      }
    }
    
    final targetStrategies = slugToStrategies[canonicalSlug];
    if (targetStrategies == null) {
      // Fallback: just set for this slug
      await _prefs.setString('emulator_pref_$canonicalSlug', emulatorId);
      _slugPreferences[canonicalSlug] = emulatorId;
      return;
    }
    
    targetStrategies.sort();
    final targetKey = targetStrategies.join('|');
    
    // Apply preference to all slugs with the same strategy set
    for (final entry in slugToStrategies.entries) {
      final ids = entry.value..sort();
      if (ids.join('|') == targetKey) {
        final slug = entry.key;
        await _prefs.setString('emulator_pref_$slug', emulatorId);
        _slugPreferences[slug] = emulatorId;
      }
    }
  }

  Future<void> clearPreferences() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith('emulator_pref_')).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
    _slugPreferences.clear();
  }

  EmulatorStrategy? getStrategyForSlug(String platformSlug) {
    if (kIsWeb) return null;

    final preferredId = _slugPreferences[platformSlug];
    if (preferredId != null) {
      for (final strategy in _strategies) {
        if (strategy.emulatorId == preferredId) {
          debugPrint("[Registry] Using preferred emulator for $platformSlug: $preferredId");
          return strategy;
        }
      }
    }

    for (final strategy in _strategies) {
      if (strategy.supportedSlugs.contains(platformSlug)) {
        debugPrint("[Registry] Falling back to first supported emulator for $platformSlug: ${strategy.emulatorId}");
        return strategy;
      }
    }
    debugPrint("[Registry] No emulator found for slug: $platformSlug");
    return null;
  }

  EmulatorStrategy? getStrategyById(String id) => _strategies.cast<EmulatorStrategy?>().firstWhere((s) => s?.emulatorId == id, orElse: () => null);

  void setNdsCore(String core) {
    final retroarch = getStrategyById('retroarch');
    if (retroarch is RetroArchStrategy) {
      retroarch.setNdsCore(core);
    }
  }

  Map<String, dynamic>? getDefinition(String emulatorId) {
    try {
      return kEmulatorDefinitions.firstWhere((def) => def['id'] == emulatorId);
    } catch (e) {
      return null;
    }
  }
}
