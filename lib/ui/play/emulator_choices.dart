import '../../core/emulator/emulator_strategy.dart';
import '../../core/emulator/retroarch_core_list.dart';
import '../../core/emulator/strategy_registry.dart';
import '../../core/romm/romm_models.dart';
import '../../core/save/catalog/save_maker.dart';

/// The emulators a game can be played in on this PC, which one it plays in
/// by default, and which one is remembered for it.
class EmulatorChoices {
  EmulatorChoices.of(this.registry, Map<String, bool> installed, this.game)
      : installedIds = {for (final e in installed.entries) if (e.value) e.key} {
    final slug = game.platformSlug ?? '';
    emulators = [
      for (final s in registry.getAllStrategiesForSlug(slug))
        if (installedIds.contains(s.emulatorId)) s,
    ];
    final rememberedId = registry.getGameEmulatorPreference(game.id);
    // One uninstalled since isn't the game's emulator any more.
    remembered = rememberedId == null || !installedIds.contains(rememberedId)
        ? null
        : makerFor(rememberedId, core: registry.getGameCorePreference(game.id));
    final def = registry.getStrategyForSlug(slug);
    final defId = def != null && installedIds.contains(def.emulatorId)
        ? def.emulatorId
        : (emulators.isEmpty ? null : emulators.first.emulatorId);
    platformDefault = defId == null ? null : makerFor(defId);
  }

  final StrategyRegistry registry;
  final Game game;
  final Set<String> installedIds;
  late final List<EmulatorStrategy> emulators;
  late final SaveMaker? remembered;
  late final SaveMaker? platformDefault;

  /// The emulator the game plays in when none is picked: the remembered
  /// one, else the platform's default.
  SaveMaker? get forThisGame => remembered ?? platformDefault;

  static String? _bare(String? core) =>
      core?.replaceAll(RegExp(r'\.(dll|so|dylib)$'), '').replaceAll(RegExp(r'_libretro$'), '');

  /// [emulatorId] as a save maker; for RetroArch with [core], else the
  /// platform's chosen core, else its default core.
  SaveMaker makerFor(String emulatorId, {String? core}) {
    if (emulatorId != 'retroarch') return SaveMaker(emulatorId);
    final slug = game.platformSlug ?? '';
    return SaveMaker('retroarch', coreId: _bare(core ?? registry.getCoreOverride(slug) ?? getDefaultCoreForSlug(slug)));
  }

  /// "ares", or "RetroArch · mupen64Plus-Next".
  String nameOf(SaveMaker maker) {
    final name = registry.getStrategyById(maker.emulatorId)?.name ?? maker.emulatorId;
    if (maker.coreId == null) return name;
    final core = kRetroArchCores.where((c) => _bare(c.id) == maker.coreId).firstOrNull;
    return '$name · ${core?.displayName ?? maker.coreId}';
  }
}
