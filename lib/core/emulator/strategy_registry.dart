import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/emulator/strategies/retroarch_strategy.dart';
import 'package:freegosy/core/emulator/strategies/dolphin_strategy.dart';
import 'package:freegosy/core/emulator/strategies/eden_strategy.dart';
import 'package:freegosy/core/emulator/strategies/ryujinx_strategy.dart';
import 'package:freegosy/core/emulator/strategies/rpcs3_strategy.dart';
import 'package:freegosy/core/emulator/strategies/ares_strategy.dart';
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
  final PlatformInfo _platform;
  late final List<EmulatorStrategy> _strategies;
  final List<CustomEmulatorConfig> _customEmulatorConfigs;
  final Map<String, String> _slugPreferences = {};

  // Per-game emulator preference (gameId -> emulatorId)
  static const String _gameEmulatorPrefix = 'game_emu_';
  final Map<String, String> _gameEmulatorPrefs = {};

  // Per-game RetroArch core preference (gameId -> coreId)
  static const String _gameCorePrefix = 'retroarch_core_';
  final Map<String, String> _gameCorePrefs = {};

  // Per-platform RetroArch core overrides (slug -> coreId)
  static const String _coreOverridePrefix = 'ra_core_';
  final Map<String, String> _coreOverrides = {};

  StrategyRegistry(this._directoryService, this._prefs, {List<CustomEmulatorConfig> customEmulators = const [], PlatformInfo? platform}) 
    : _customEmulatorConfigs = customEmulators,
      _platform = platform ?? PlatformInfo.current {
    final List<EmulatorStrategy> allPossibleStrategies = [
      RetroArchStrategy(_directoryService, platform: _platform),
      DolphinStrategy(_directoryService, platform: _platform),
      EdenStrategy(_directoryService, platform: _platform),
      RyujinxStrategy(_directoryService, platform: _platform),
      Rpcs3Strategy(_directoryService),
      Pcsx2Strategy(_directoryService, platform: _platform),
      AzaharStrategy(_directoryService),
      CemuStrategy(_directoryService),
      DuckstationStrategy(_directoryService, platform: _platform),
      FlycastStrategy(_directoryService),
      MelonDSStrategy(_directoryService, platform: _platform),
      PPSSPPStrategy(_directoryService),
      MGBAStrategy(_directoryService),
      AresStrategy(_directoryService, platform: _platform),
      MAMEStrategy(_directoryService),
      XemuStrategy(_directoryService),
      XeniaStrategy(_directoryService),
      WindowsStrategy(_directoryService, _prefs),
      ..._customEmulatorConfigs.map((config) => CustomEmulatorStrategy(config, _directoryService)),
    ];

    _strategies = allPossibleStrategies.where((strategy) {
      final definition = getDefinition(strategy.emulatorId);
      if (definition == null) return true;
      final supported = List<String>.from(definition['supported_platforms'] ?? []);
      if (_platform.isWindows && supported.contains('windows')) return true;
      if (_platform.isLinux && supported.contains('linux')) return true;
      if (_platform.isMacOS && supported.contains('macos')) return true;
      return false;
    }).toList();
    
    _loadPreferences();
    _loadCoreOverrides();
    _loadGamePreferences();
    _applyCoreOverridesToRetroArch();
  }

  // ── Conflict detection ───────────────────────────────────────

  Map<String, ({List<EmulatorStrategy> strategies, List<String> mergedSlugs})> detectConflicts() {
    final Map<String, List<EmulatorStrategy>> slugToStrategies = {};
    for (final strategy in _strategies) {
      for (final slug in strategy.supportedSlugs) {
        slugToStrategies.putIfAbsent(slug, () => []).add(strategy);
      }
    }

    final Map<String, List<EmulatorStrategy>> allConflicts = {};
    slugToStrategies.forEach((slug, list) {
      if (list.length > 1) {
        allConflicts[slug] = list;
      }
    });

    if (allConflicts.isEmpty) return {};

    final Map<String, List<String>> groups = {};
    allConflicts.forEach((slug, strategies) {
      final ids = strategies.map((s) => s.emulatorId).toList()..sort();
      final key = ids.join('|');
      groups.putIfAbsent(key, () => []).add(slug);
    });

    final result = <String, ({List<EmulatorStrategy> strategies, List<String> mergedSlugs})>{};
    groups.forEach((key, slugs) {
      // Pick most recognizable slug: shortest without hyphens, fallback to shortest
      final canonical = slugs.firstWhere(
        (s) => !s.contains('-'),
        orElse: () => slugs.reduce((a, b) => a.length < b.length ? a : b),
      );
      final merged = slugs.where((s) => s != canonical).toList()..sort();
      result[canonical] = (strategies: allConflicts[slugs.first]!, mergedSlugs: merged);
    });

    return result;
  }

  // ── Per-platform emulator preference ─────────────────────────

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
    final slugToStrategies = <String, List<String>>{};
    for (final strategy in _strategies) {
      for (final slug in strategy.supportedSlugs) {
        slugToStrategies.putIfAbsent(slug, () => []).add(strategy.emulatorId);
      }
    }
    
    final targetStrategies = slugToStrategies[canonicalSlug];
    if (targetStrategies == null) {
      await _prefs.setString('emulator_pref_$canonicalSlug', emulatorId);
      _slugPreferences[canonicalSlug] = emulatorId;
      return;
    }
    
    targetStrategies.sort();
    final targetKey = targetStrategies.join('|');
    
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

  // ── Per-game emulator preference ─────────────────────────────

  void _loadGamePreferences() {
    for (final key in _prefs.getKeys()) {
      if (key.startsWith(_gameEmulatorPrefix)) {
        final gameId = key.substring(_gameEmulatorPrefix.length);
        final emulatorId = _prefs.getString(key);
        if (emulatorId != null) {
          _gameEmulatorPrefs[gameId] = emulatorId;
        }
      }
      if (key.startsWith(_gameCorePrefix)) {
        final gameId = key.substring(_gameCorePrefix.length);
        final coreId = _prefs.getString(key);
        if (coreId != null) {
          _gameCorePrefs[gameId] = coreId;
        }
      }
    }
  }

  /// Set which emulator to use for a specific game.
  Future<void> setGameEmulatorPreference(String gameId, String emulatorId) async {
    _gameEmulatorPrefs[gameId] = emulatorId;
    await _prefs.setString('$_gameEmulatorPrefix$gameId', emulatorId);
  }

  /// Get the preferred emulator for a specific game.
  String? getGameEmulatorPreference(String gameId) => _gameEmulatorPrefs[gameId];

  /// Remove per-game emulator preference.
  Future<void> clearGameEmulatorPreference(String gameId) async {
    _gameEmulatorPrefs.remove(gameId);
    await _prefs.remove('$_gameEmulatorPrefix$gameId');
  }

  // ── Per-game RetroArch core preference ───────────────────────

  /// Set which RetroArch core to use for a specific game.
  Future<void> setGameCorePreference(String gameId, String coreId) async {
    _gameCorePrefs[gameId] = coreId;
    await _prefs.setString('$_gameCorePrefix$gameId', coreId);
  }

  /// Get the preferred RetroArch core for a specific game.
  String? getGameCorePreference(String gameId) => _gameCorePrefs[gameId];

  /// Remove per-game core preference.
  Future<void> clearGameCorePreference(String gameId) async {
    _gameCorePrefs.remove(gameId);
    await _prefs.remove('$_gameCorePrefix$gameId');
  }

  // ── Per-platform RetroArch core overrides ─────────────────────

  void _loadCoreOverrides() {
    for (final key in _prefs.getKeys()) {
      if (key.startsWith(_coreOverridePrefix)) {
        final slug = key.substring(_coreOverridePrefix.length);
        final coreId = _prefs.getString(key);
        if (coreId != null) {
          _coreOverrides[slug] = coreId;
        }
      }
    }
  }

  /// Set a default RetroArch core for a platform slug.
  Future<void> setCoreOverride(String slug, String coreId) async {
    _coreOverrides[slug] = coreId;
    await _prefs.setString('$_coreOverridePrefix$slug', coreId);
    _applyCoreOverridesToRetroArch();
  }

  /// Get the default RetroArch core for a platform slug.
  String? getCoreOverride(String slug) => _coreOverrides[slug];

  /// Get all platform core overrides.
  Map<String, String> get coreOverrides => Map.unmodifiable(_coreOverrides);

  /// Remove a platform core override.
  Future<void> clearCoreOverride(String slug) async {
    _coreOverrides.remove(slug);
    await _prefs.remove('$_coreOverridePrefix$slug');
    _applyCoreOverridesToRetroArch();
  }

  /// Remove all platform core overrides.
  Future<void> clearAllCoreOverrides() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_coreOverridePrefix)).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
    _coreOverrides.clear();
    _applyCoreOverridesToRetroArch();
  }

  void _applyCoreOverridesToRetroArch() {
    final retroarch = getStrategyById('retroarch');
    if (retroarch is RetroArchStrategy) {
      retroarch.loadCoreOverrides(_coreOverrides);
    }
  }

  // ── Strategy resolution ──────────────────────────────────────

  EmulatorStrategy? getStrategyForSlug(String platformSlug, {String? gameId}) {
    if (kIsWeb) return null;

    // 1. Per-game emulator preference
    if (gameId != null) {
      final preferredId = _gameEmulatorPrefs[gameId];
      if (preferredId != null) {
        for (final strategy in _strategies) {
          if (strategy.emulatorId == preferredId) {
            debugPrint("[Registry] Using per-game emulator for $gameId: $preferredId");
            return strategy;
          }
        }
      }
    }

    // 2. Per-platform emulator preference
    final preferredId = _slugPreferences[platformSlug];
    if (preferredId != null) {
      for (final strategy in _strategies) {
        if (strategy.emulatorId == preferredId) {
          debugPrint("[Registry] Using preferred emulator for $platformSlug: $preferredId");
          return strategy;
        }
      }
    }

    // 3. First supported strategy
    for (final strategy in _strategies) {
      if (strategy.supportedSlugs.contains(platformSlug)) {
        debugPrint("[Registry] Falling back to first supported emulator for $platformSlug: ${strategy.emulatorId}");
        return strategy;
      }
    }
    debugPrint("[Registry] No emulator found for slug: $platformSlug");
    return null;
  }

  /// Returns all strategies that support a given platform slug.
  List<EmulatorStrategy> getAllStrategiesForSlug(String platformSlug) {
    return _strategies.where((s) => s.supportedSlugs.contains(platformSlug)).toList();
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
