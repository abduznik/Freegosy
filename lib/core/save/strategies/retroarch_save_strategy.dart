import 'dart:io' as io;
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import '../../disc/serial_extraction_service.dart';
import '../../platform/platform_info.dart';
import '../../romm/game_id_resolver.dart';
import '../../romm/romm_models.dart';
import '../../storage/app_preferences.dart';
import '../../storage/directory_service.dart';
import '../formats/ps1_memory_card.dart';
import '../formats/ps2_memory_card.dart';
import '../formats/save_format_registry.dart';
import '../save_state_info.dart';
import '../save_strategy.dart';
import '../state_sync_capable.dart';
import '../state_sync_service.dart';
import 'ps2_save_folders.dart';
import 'pcsx2_save_strategy.dart';
import 'package:path/path.dart' as p; // Import path package
import '../../emulator/platform_slugs.dart';
import '../../emulator/retroarch_core_list.dart';
import '../../emulator/retroarch_core_names.dart';

/// Save strategy for RetroArch emulator.
///
/// Save files live next to RetroArch.exe in saves/{coreName}/.
/// Core name mapping is derived from the platform slug.
///
/// Save states (`<content>.state`, `.stateN`, `.state.auto`) sync through
/// [StateSyncCapable] / StateSyncService when the user turns "Sync save
/// states" on for RetroArch. With it off they still travel inside the game
/// save, as before.
class RetroArchSaveStrategy extends SaveStrategy with StateSyncCapable {
  final DirectoryService _directoryService;
  final PlatformInfo _platform;
  final AppPreferences? _prefs;
  String _ndsCore = 'melonds'; // Default NDS core
  String? _cachedSaveRoot; // Cached from retroarch.cfg

  /// Cached RetroArch config flags read from retroarch.cfg.
  bool? _cachedSortSavefiles;
  bool? _cachedSortSavefilesByContent;
  bool? _cachedSavefilesInContentDir;

  /// The last-loaded RetroArch core ID parsed from `libretro_path` in retroarch.cfg.
  /// Used to resolve the correct save folder when a platform has multiple cores.
  String? _cachedActiveCore;

  /// Cached EmuDeck-for-Windows RetroArch root, once detected.
  String? _cachedEmuDeckWindowsRoot;

  /// The folder of the retroarch.cfg in use, and the `system_directory` /
  /// `rgui_config_directory` it sets (null: RetroArch's default).
  String? _cachedConfigDir;
  String? _cachedSystemDir;
  String? _cachedCoreOptionsDir;

  /// `savestate_directory` (null: RetroArch's default `states` folder) and the
  /// state sort flags from retroarch.cfg.
  String? _cachedStateDir;
  bool? _cachedSortSavestates;
  bool? _cachedSortSavestatesByContent;
  bool? _cachedSavestatesInContentDir;

  /// RetroArch's config folder for a portable AppImage: the AppImage runtime
  /// uses `<AppImage>.home` as `$HOME` when that folder sits beside it, so
  /// the config, saves and states are in `<AppImage>.home/.config/retroarch`.
  /// Null for any other install (and until the AppImage has run once).
  String? _appImageConfig;
  bool _appImageResolved = false;

  /// The portable AppImage's `$HOME` (`<AppImage>.home`): what `~` means in its
  /// retroarch.cfg. Set once [_appImageConfigDir] has found the AppImage.
  String? _appImageHome;

  Future<String?> _appImageConfigDir() async {
    if (!_platform.isLinux) return null;
    if (_appImageResolved) return _appImageConfig;
    try {
      var exe = await _directoryService.findEmulatorExecutable('retroarch', _getRetroArchExe());
      if (exe != null && !exe.startsWith('flatpak ')) {
        // The AppImage runtime looks for <AppImage>.home beside the real file,
        // so a symlink to it (e.g. one named "retroarch") must be followed.
        try {
          exe = await io.File(exe).resolveSymbolicLinks();
        } catch (_) {}
        final home = '$exe.home';
        final cfg = p.join(home, '.config', 'retroarch');
        if (await io.Directory(cfg).exists()) {
          _appImageHome = home;
          _appImageConfig = cfg;
        }
      }
    } catch (_) {}
    _appImageResolved = true;
    return _appImageConfig;
  }

  /// What `~` stands for in retroarch.cfg: the portable AppImage's home when
  /// that is the install in use, else the user's.
  String? get _configHome =>
      _appImageHome ?? _platform.environment['HOME'] ?? _platform.environment['USERPROFILE'];

  /// RetroArch's config folder (holding `saves/` and `states/`) on Linux:
  /// the portable AppImage's, else the preset's (`~/.config/retroarch`, the
  /// Flatpak's, EmuDeck's, RetroDECK's).
  Future<String> _linuxBaseDir(String? slug) async =>
      await _appImageConfigDir() ?? await _directoryService.getEmulatorAppSupportDirectory('retroarch', platformSlug: slug);

  final SerialExtractionService? _serials;

  // Test-only override to skip reading the real retroarch.cfg.
  @visibleForTesting
  bool skipConfigRead = false;

  /// Test-only: the PS2 serial of a ROM, instead of reading the disc.
  @visibleForTesting
  Future<String?> Function(String romPath)? ps2SerialOverride;

  RetroArchSaveStrategy(this._directoryService,
      {PlatformInfo? platform, AppPreferences? prefs, SerialExtractionService? serialExtractionService})
      : _platform = platform ?? PlatformInfo.current,
        _prefs = prefs,
        _serials = serialExtractionService ??
            (prefs == null ? null : SerialExtractionService(_directoryService, prefs, platform: platform));

  /// The core [game]'s saves come from, as RomM and other clients name it:
  /// its id without `_libretro` (e.g. `pcsx_rearmed`), or null when unknown.
  String? coreIdFor(Game game) {
    final core = _getCoreInfo(game.platformSlug?.toLowerCase() ?? '')?.coreName;
    if (core == null || core.isEmpty) return null;
    return core.replaceAll(RegExp(r'\.(dll|so|dylib)$'), '').replaceAll(RegExp(r'_libretro$'), '');
  }

  void setNdsCore(String core) {
    _ndsCore = core;
  }

  /// Per-platform core overrides (slug -> coreId). Set from StrategyRegistry.
  final Map<String, String> _coreOverrides = {};

  void loadCoreOverrides(Map<String, String> overrides) {
    _coreOverrides
      ..clear()
      ..addAll(overrides);
  }

  /// Temporarily overrides the core for a single push/pull operation.
  /// Used when the launch code knows which core was used (from the core picker)
  /// but the strategy registry hasn't been updated yet.
  String? _launchCoreOverride;
  void setLaunchCoreOverride(String? coreId) => _launchCoreOverride = coreId;

  /// The core [slug]'s saves belong to, with its save and state folders:
  /// the core the game is launched with, the same way RetroArchStrategy
  /// picks it (the game's core, the platform's chosen core, else the
  /// platform's default core), so a pulled save lands where that core reads
  /// it. Without a launch or chosen core, RetroArch's last-used core
  /// (retroarch.cfg's libretro_path) counts when it runs this platform.
  _CoreInfo? _getCoreInfo(String slug) {
    slug = canonicalPlatformSlug(slug);
    debugPrint('[SaveSync] [retroarch] _getCoreInfo: slug="$slug"  ndsCore=$_ndsCore');

    // 1. NDS dynamic override (backward compat)
    if (slug == 'nds' || slug == 'nintendo-ds') {
      final info = _infoForCore(_ndsCore == 'desmume' ? 'desmume2015_libretro' : 'melonds_libretro');
      debugPrint('[SaveSync] [retroarch]   → NDS override: core=${info?.coreName}');
      return info;
    }

    // 2. Launch-time core override (from core picker dialog)
    if (_launchCoreOverride != null) {
      final info = _infoForCore(_launchCoreOverride!, fallback: true);
      debugPrint('[SaveSync] [retroarch] _getCoreInfo launch override → core=${info?.coreName}');
      return info;
    }

    // 3. The platform's chosen core (Settings), from the registry
    final overrideCoreId = _coreOverrides[slug];
    if (overrideCoreId != null) {
      final info = _infoForCore(overrideCoreId, fallback: true);
      debugPrint('[SaveSync] [retroarch] _getCoreInfo registry override → core=${info?.coreName}');
      return info;
    }

    // 4. RetroArch's last-used core, when it runs this platform. A core for
    // another system (mGBA before a PS1 pull) says nothing about this one.
    final active = _cachedActiveCore;
    if (active != null && getCoresForSlug(slug).any((c) => _bare(c.id) == active)) {
      final info = _infoForCore(active);
      if (info != null) {
        debugPrint('[SaveSync] [retroarch] _getCoreInfo active core → core=${info.coreName}');
        return info;
      }
    }

    // 5. The platform's default core, the one RetroArchStrategy launches
    final defaultCore = getDefaultCoreForSlug(slug);
    final info = defaultCore == null ? null : _infoForCore(defaultCore);
    debugPrint('[SaveSync] [retroarch] _getCoreInfo default core → ${info?.coreName ?? "null"}');
    return info;
  }

  /// Save and state folders for [coreId] (`mgba`, `mgba_libretro` or
  /// `mgba_libretro.dll`): named after its library_name, or its own layout.
  /// With [fallback], a core Freegosy doesn't know keeps its bare name.
  static _CoreInfo? _infoForCore(String coreId, {bool fallback = false}) {
    final base = _bare(coreId);
    final core = '${base}_libretro';
    final own = _ownLayouts[base];
    if (own != null) return own;
    final name = kRetroArchCoreLibraryNames[core];
    if (name != null) return _CoreInfo(core, name, name);
    return fallback ? _CoreInfo(base, base, 'States/$base') : null;
  }

  /// `mgba` for `mgba`, `mgba_libretro` and `mgba_libretro.dll`.
  static String _bare(String coreId) => coreBaseName(coreId).replaceAll(RegExp(r'_libretro$'), '');

  /// Cores that don't keep their saves in a folder named after their
  /// library_name: PPSSPP keeps PSP saves in its own memory-stick layout,
  /// Azahar a 3DS layout, and Mupen64Plus states under States/.
  static const Map<String, _CoreInfo> _ownLayouts = {
    'ppsspp':      _CoreInfo('ppsspp_libretro',      'PPSSPP/PSP/SAVEDATA', 'PPSSPP'),
    'azahar':      _CoreInfo('azahar_libretro',      '3DS',                 'States/3DS'),
    'mupen64plus': _CoreInfo('mupen64plus_libretro', 'Mupen64Plus',         'States/Mupen64Plus'),
  };

  @override
  String get strategyId => 'retroarch';

  @override
  bool get shouldZip => false;

  /// Save file extensions recognized by RetroArch cores.
  /// N64 cores use .sra/.eep/.fla/.mpk; most others use .srm/.sav/.mcd.
  static const _saveExtensions = {'.srm', '.sav', '.mcd', '.sra', '.eep', '.fla', '.mpk', '.ps2'};

  static bool _isSaveFile(String filename) {
    final ext = p.extension(filename).toLowerCase();
    return _saveExtensions.contains(ext);
  }

  /// Reads `savefile_directory` and sort flags from retroarch.cfg.
  ///
  /// Parses these RetroArch config keys:
  /// - `savefile_directory` — base save directory
  /// - `sort_savefiles_enable` — when "true", saves go into core subfolders
  /// - `sort_savefiles_by_content_enable` — when "true", saves go into ROM parent folder subfolders
  /// - `savefiles_in_content_dir` — when "true", saves go next to the ROM
  Future<String?> _readConfigSaveRoot() async {
    if (skipConfigRead) return null;
    if (_cachedSaveRoot != null) return _cachedSaveRoot;

    final List<String> candidates = [];

    // RetroArch's own config folder first: the Flatpak keeps its retroarch.cfg
    // under ~/.var/app, which none of the fixed paths below reach.
    if (_platform.isLinux) {
      try {
        final baseDir = await _linuxBaseDir(null);
        candidates.add(p.join(baseDir, 'retroarch.cfg'));
      } catch (_) {}
    }

    if (_platform.isMacOS) {
      final home = _platform.environment['HOME'] ?? '';
      candidates.add(p.join(home, 'Library', 'Application Support', 'RetroArch', 'config', 'retroarch.cfg'));
      candidates.add(p.join(home, '.config', 'retroarch', 'retroarch.cfg'));
    } else if (_platform.isLinux) {
      final home = _platform.environment['HOME'] ?? '';
      candidates.add(p.join(home, '.config', 'retroarch', 'retroarch.cfg'));
    } else if (_platform.isWindows) {
      final appData = _platform.environment['APPDATA'] ?? '';
      candidates.add(p.join(appData, 'RetroArch', 'retroarch.cfg'));
    }

    // Also check next to the bundled exe
    final exePath = await _directoryService.findEmulatorExecutable('retroarch', _getRetroArchExe());
    if (exePath != null) {
      String exeDir = _platform.isMacOS
          ? p.join(io.File(exePath).parent.parent.parent.parent.path)
          : io.File(exePath).parent.path;
      if (await io.FileSystemEntity.isDirectory(exePath)) exeDir = exePath;
      candidates.add(p.join(exeDir, 'retroarch.cfg'));
    }
    debugPrint('[SaveSync] [retroarch] _readConfigSaveRoot candidates=${candidates.length}: ${candidates.map((c) => p.basename(p.dirname(c))).join(', ')}');

    final savefileDirRe = RegExp(r'^\s*savefile_directory\s*=\s*"([^"]*)"');
    final systemDirRe = RegExp(r'^\s*system_directory\s*=\s*"([^"]*)"');
    final coreOptionsDirRe = RegExp(r'^\s*rgui_config_directory\s*=\s*"([^"]*)"');
    final stateDirRe = RegExp(r'^\s*savestate_directory\s*=\s*"([^"]*)"');
    final boolRe = RegExp(
        r'^\s*(sort_savefiles_enable|sort_savefiles_by_content_enable|savefiles_in_content_dir|sort_savestates_enable|sort_savestates_by_content_enable|savestates_in_content_dir)\s*=\s*"?(true|false)"?');
    final libretroPathRe = RegExp(r'^\s*libretro_path\s*=\s*"([^"]*)"');

    for (final cfgPath in candidates) {
      final cfgFile = io.File(cfgPath);
      if (!await cfgFile.exists()) {
        debugPrint('[SaveSync] [retroarch] _readConfigSaveRoot not found: $cfgPath');
        continue;
      }
      debugPrint('[SaveSync] [retroarch] _readConfigSaveRoot reading: $cfgPath');
      try {
        final lines = await cfgFile.readAsLines();
        final cfgDir = p.dirname(cfgPath);
        _cachedConfigDir = cfgDir;
        for (final line in lines) {
          final systemMatch = systemDirRe.firstMatch(line);
          if (systemMatch != null) _cachedSystemDir = _configPath(systemMatch.group(1)!, cfgDir);
          final stateDirMatch = stateDirRe.firstMatch(line);
          if (stateDirMatch != null) _cachedStateDir = _configPath(stateDirMatch.group(1)!, cfgDir);
          final optionsMatch = coreOptionsDirRe.firstMatch(line);
          if (optionsMatch != null) _cachedCoreOptionsDir = _configPath(optionsMatch.group(1)!, cfgDir);

          final saveMatch = savefileDirRe.firstMatch(line);
          if (saveMatch != null) {
            var dir = saveMatch.group(1)!;
            if (dir.startsWith('~')) {
              final home = _configHome;
              if (home != null) dir = dir.replaceFirst('~', home);
            }
            if (await io.Directory(dir).exists()) {
              _cachedSaveRoot = dir;
              debugPrint('[SaveSync] [retroarch] _readConfigSaveRoot savefile_directory=$dir');
            } else {
              debugPrint('[SaveSync] [retroarch] _readConfigSaveRoot savefile_directory=$dir (dir does not exist)');
            }
          }

          final boolMatch = boolRe.firstMatch(line);
          if (boolMatch != null) {
            final key = boolMatch.group(1)!;
            final value = boolMatch.group(2)!.toLowerCase() == 'true';
            switch (key) {
              case 'sort_savefiles_enable':
                _cachedSortSavefiles = value;
                debugPrint('[SaveSync] [retroarch] _readConfigSaveRoot sort_savefiles_enable=$value');
                break;
              case 'sort_savefiles_by_content_enable':
                _cachedSortSavefilesByContent = value;
                debugPrint('[SaveSync] [retroarch] _readConfigSaveRoot sort_savefiles_by_content_enable=$value');
                break;
              case 'savefiles_in_content_dir':
                _cachedSavefilesInContentDir = value;
                debugPrint('[SaveSync] [retroarch] _readConfigSaveRoot savefiles_in_content_dir=$value');
                break;
              case 'sort_savestates_enable':
                _cachedSortSavestates = value;
                break;
              case 'sort_savestates_by_content_enable':
                _cachedSortSavestatesByContent = value;
                break;
              case 'savestates_in_content_dir':
                _cachedSavestatesInContentDir = value;
                break;
            }
          }

          // Parse libretro_path to detect the last-used core.
          // Example: libretro_path = "/path/to/parallel_n64_libretro.dylib"
          final coreMatch = libretroPathRe.firstMatch(line);
          if (coreMatch != null) {
            final corePath = coreMatch.group(1)!;
            if (corePath.isNotEmpty && corePath != 'default') {
              final coreFilename = p.basename(corePath);
              // Strip extension and _libretro suffix to get the base core ID
              // e.g. "parallel_n64_libretro.dylib" → "parallel_n64"
              final coreBase = coreFilename
                  .replaceAll(RegExp(r'\.(dll|so|dylib)$'), '')
                  .replaceAll(RegExp(r'_libretro$'), '');
              if (coreBase.isNotEmpty) {
                _cachedActiveCore = coreBase;
                debugPrint('[SaveSync] [retroarch] _readConfigSaveRoot activeCore=$coreBase (from $coreFilename)');
              }
            }
          }
        }
        if (_cachedSaveRoot != null) break;
      } catch (_) {}
    }
    debugPrint('[SaveSync] [retroarch] _readConfigSaveRoot result: saveRoot=${_cachedSaveRoot ?? "null"}');
    return _cachedSaveRoot;
  }

  /// Whether RetroArch sorts saves into core subfolders (e.g. `saves/mGBA/`).
  /// Defaults to `true` (RetroArch's default).
  bool get _sortSavefiles => _cachedSortSavefiles ?? true;

  /// Whether RetroArch sorts saves into ROM parent folder subfolders.
  /// Parsed from config but currently unused in path resolution — RetroArch
  /// handles this internally when the flag is set. Kept for future use if
  /// we need to construct paths including the content directory name.
  // ignore: unused_element
  bool get _sortSavefilesByContent => _cachedSortSavefilesByContent ?? false;

  /// Whether RetroArch saves are placed next to the ROM instead of a central dir.
  bool get _savefilesInContentDir => _cachedSavefilesInContentDir ?? false;

  /// Resolves the save root directory: retroarch.cfg first, then exe-relative.
  Future<String> _resolveSaveRoot() async {
    if (_platform.isWindows) {
      final emuDeckRoot = await _emuDeckWindowsRetroArchRoot();
      if (emuDeckRoot != null) return p.join(emuDeckRoot, 'saves');
    }
    final cfg = await _readConfigSaveRoot();
    if (cfg != null) return cfg;
    final exePath = await _directoryService.findEmulatorExecutable('retroarch', _getRetroArchExe());
    String exeDir = _platform.isMacOS
        ? p.join(io.File(exePath!).parent.parent.parent.parent.path)
        : io.File(exePath!).parent.path;
    if (await io.FileSystemEntity.isDirectory(exePath)) exeDir = exePath;
    return p.join(exeDir, 'saves');
  }

  /// Detects an EmuDeck-for-Windows install and returns its RetroArch root
  /// if present: `%USERPROFILE%\EmuDeck\Emulators\RetroArch` (issue #79), or
  /// `%USERPROFILE%\emudeck\EmulationStation-DE\Emulators\RetroArch`.
  ///
  /// EmuDeck for Windows installs RetroArch there directly and exposes a
  /// `Emulation\saves\retroarch\...` junction pointing back to it. We resolve
  /// to the real path instead of the junction to avoid Windows "untrusted
  /// mount point" errors when traversing reparse points without admin rights.
  Future<String?> _emuDeckWindowsRetroArchRoot() async {
    if (_cachedEmuDeckWindowsRoot != null) return _cachedEmuDeckWindowsRoot;
    final userProfile = _platform.environment['USERPROFILE'];
    if (userProfile == null || userProfile.isEmpty) return null;
    for (final candidate in [
      p.join(userProfile, 'EmuDeck', 'Emulators', 'RetroArch'),
      p.join(userProfile, 'emudeck', 'EmulationStation-DE', 'Emulators', 'RetroArch'),
    ]) {
      if (await io.Directory(candidate).exists()) {
        _cachedEmuDeckWindowsRoot = candidate;
        debugPrint('[SaveSync] [retroarch] detected EmuDeck-for-Windows root=$candidate');
        return candidate;
      }
    }
    return null;
  }

  /// A directory setting from retroarch.cfg as a path: `:` stands for the
  /// folder of the config (a portable install), `~` for the home folder;
  /// empty or `default` means RetroArch's default (null).
  String? _configPath(String value, String cfgDir) {
    var v = value.trim();
    if (v.isEmpty || v == 'default') return null;
    if (v.startsWith(':')) return p.normalize(p.join(cfgDir, v.substring(1).replaceFirst(RegExp(r'^[\\/]+'), '')));
    if (v.startsWith('~')) {
      final home = _configHome;
      if (home != null) v = v.replaceFirst('~', home);
    }
    return v;
  }

  // ─── LRPS2 (PS2) memory cards ─────────────────────────────────────────

  static const _ps2Slugs = {'ps2', 'playstation-2', 'playstation2'};

  bool _isLrps2(String slug) => _ps2Slugs.contains(slug) && _getCoreInfo(slug)?.coreName == 'pcsx2_libretro';

  /// RetroArch's own folder: where its retroarch.cfg is, else above the saves.
  Future<String> _retroArchDir() async {
    await _readConfigSaveRoot();
    return _cachedConfigDir ?? p.dirname(await _resolveSaveRoot());
  }

  /// LRPS2's memory cards for [romPath]: its two shared cards in the system
  /// folder, or the game's own card in the save folder when *Shared Memory
  /// Cards* is off (see [Ps2SaveFolders]).
  Future<({List<io.File> cards, bool shared})> _lrps2Cards(Game game, String romPath) async {
    final raDir = await _retroArchDir();
    final optionsDir = _cachedCoreOptionsDir ?? p.join(raDir, 'config');
    final optionFiles = <String>[];
    for (final path in [
      p.join(optionsDir, 'LRPS2', '${p.basenameWithoutExtension(romPath)}.opt'),
      p.join(optionsDir, 'LRPS2', '${p.basename(p.dirname(romPath))}.opt'),
      p.join(optionsDir, 'LRPS2', 'LRPS2.opt'),
      p.join(raDir, 'retroarch-core-options.cfg'),
    ]) {
      final f = io.File(path);
      if (await f.exists()) optionFiles.add(await f.readAsString());
    }
    if (Ps2SaveFolders.lrps2UsesSharedCards(optionFiles)) {
      final memcards = p.join(_cachedSystemDir ?? p.join(raDir, 'system'), 'pcsx2', 'memcards');
      return (cards: [io.File(p.join(memcards, 'Mcd001.ps2')), io.File(p.join(memcards, 'Mcd002.ps2'))], shared: true);
    }
    final saveDir = await getSaveDir(game, romPath) ?? p.join(await _resolveSaveRoot(), 'LRPS2');
    return (cards: [io.File(p.join(saveDir, '${p.basenameWithoutExtension(romPath)}.ps2'))], shared: false);
  }

  Future<String?> _ps2Serial(Game game, String romPath) => GameIdResolver.resolve(
      label: 'LRPS2 ${game.name}',
      server: GameIdResolver.discSerial(game, romPath),
      shape: GameIdResolver.ps1ps2Serial,
      local: () async => ps2SerialOverride != null ? ps2SerialOverride!(romPath) : _serials?.extractSerial(
          romPath: romPath, bootLinePattern: Pcsx2SaveStrategy.bootLinePattern, chdmanCandidates: const []));

  /// Which saves on LRPS2's cards are [romPath]'s: those named after its
  /// serial; every save on a per-game card when the serial is unknown. Null
  /// when it can't be told (shared cards, serial unknown).
  Future<bool Function(String)?> _lrps2SavesOf(Game game, String romPath, bool shared) async {
    final serial = await _ps2Serial(game, romPath);
    if (serial != null) return (name) => Ps2SaveFolders.isSaveOf(name, serial);
    return shared ? null : (_) => true;
  }

  static const _lrps2NoSerial = "Freegosy couldn't read this PS2 game's serial (e.g. SLUS-20851), which is how it "
      "tells this game's saves from the others on LRPS2's shared memory cards, so its saves weren't synced. "
      'Putting the serial in the file name, e.g. "Ace Combat 5 (SLUS-20851).chd", fixes it.';

  String get _lrps2TempRoot => p.join(io.Directory.systemTemp.path, 'freegosy_lrps2');

  /// This game's saves on LRPS2's cards, written out as save folders to
  /// upload (`BASLUS-20851AC5/…`). Nothing when no card changed since
  /// [sessionStart].
  Future<List<io.File>> _lrps2SaveFolders(Game game, String romPath, DateTime? sessionStart) async {
    final setup = await _lrps2Cards(game, romPath);
    final existing = [for (final c in setup.cards) if (await c.exists()) c];
    if (existing.isEmpty) return const [];
    if (sessionStart != null) {
      final since = sessionStart.subtract(const Duration(seconds: 2));
      var changed = false;
      for (final c in existing) {
        if (!(await c.stat()).modified.isBefore(since)) changed = true;
      }
      if (!changed) return const [];
    }
    final belongs = await _lrps2SavesOf(game, romPath, setup.shared);
    if (belongs == null) {
      debugPrint("[SaveSync] [retroarch] LRPS2: serial unknown — can't tell this game's saves on the shared cards");
      return const [];
    }
    final outDir = io.Directory(p.join(_lrps2TempRoot, game.id));
    if (await outDir.exists()) await outDir.delete(recursive: true);
    await outDir.create(recursive: true);
    final folders = <io.File>[];
    for (final card in existing) {
      final bytes = await card.readAsBytes();
      if (Ps2MemoryCard.isUnformatted(bytes)) continue;
      final List<Ps2CardSave> saves;
      try {
        saves = await Isolate.run(() => Ps2MemoryCard.parse(bytes).saves.where((s) => belongs(s.name)).toList());
      } on FormatException catch (e) {
        debugPrint('[SaveSync] [retroarch] LRPS2: ${card.path} not readable, skipped: $e');
        continue;
      }
      for (final save in saves) {
        final dir = io.Directory(p.join(outDir.path, save.name));
        if (await dir.exists()) continue; // the same save on both cards: the first card's
        await dir.create();
        for (final f in save.files) {
          await io.File(p.join(dir.path, f.name)).writeAsBytes(f.data);
        }
        folders.add(io.File(dir.path));
      }
    }
    debugPrint('[SaveSync] [retroarch] LRPS2: ${folders.length} save folder(s) of this game: '
        '${folders.map((f) => p.basename(f.path)).toList()}');
    return folders;
  }

  /// Puts the PS2 saves in a downloaded save onto LRPS2's card, replacing
  /// this game's and leaving every other game's as it is: the card that
  /// already holds this game's saves (else the first), after a `.bak`,
  /// written to a temporary file and swapped in.
  Future<void> _restoreLrps2(Game game, String romPath, Uint8List data, String filename) async {
    final List<Ps2CardSave> incoming;
    try {
      incoming = Ps2SaveFolders.savesFromUpload(data, filename);
    } on FormatException catch (e) {
      throw SaveSyncNotPossibleException(
          "The PS2 memory card from RomM ($filename) isn't one Freegosy can read ($e). Nothing was changed.");
    }
    final setup = await _lrps2Cards(game, romPath);
    final belongs = await _lrps2SavesOf(game, romPath, setup.shared);
    if (belongs == null) throw SaveSyncNotPossibleException(_lrps2NoSerial);
    final mine = incoming.where((s) => belongs(s.name)).toList();
    if (mine.isEmpty) {
      debugPrint('[SaveSync] [retroarch] LRPS2: $filename holds no saves of this game — cards left as they are');
      return;
    }

    var target = setup.cards.first;
    Uint8List? targetBytes;
    for (final card in setup.cards) {
      if (!await card.exists()) continue;
      final bytes = await card.readAsBytes();
      final holdsGame = await Isolate.run(() {
        try {
          return Ps2MemoryCard.parse(bytes).saves.any((s) => belongs(s.name));
        } on FormatException {
          return false;
        }
      });
      if (holdsGame || card.path == setup.cards.first.path) {
        target = card;
        targetBytes = bytes;
        if (holdsGame) break;
      }
    }

    final Uint8List merged;
    try {
      final source = targetBytes;
      merged = await Isolate.run(() => Ps2SaveFolders.merge(source, mine, belongs));
    } on FormatException catch (e) {
      throw SaveSyncNotPossibleException(
          "LRPS2's memory card (${p.basename(target.path)}) doesn't look like a PS2 memory card Freegosy can "
          'safely change ($e), so it was left as it is.');
    } on Ps2CardFullException catch (e) {
      throw SaveSyncNotPossibleException(
          "The save from RomM doesn't fit on LRPS2's memory card (${p.basename(target.path)}) with the saves "
          'already on it: ${e.needed} KB needed, ${e.capacity} KB on the card. Nothing was changed. Free some '
          "space in the PS2 BIOS's memory card screen, then pull again.");
    }
    if (SaveRestoreGuard.restoreTooLate) {
      debugPrint('[SaveSync] [retroarch] LRPS2: RetroArch has started without this pull — ${target.path} left as it is');
      return;
    }
    await target.parent.create(recursive: true);
    if (await target.exists()) await backupSave(target.path);
    final temp = io.File('${target.path}.freegosy_tmp');
    await temp.writeAsBytes(merged, flush: true);
    await temp.rename(target.path);
    debugPrint('[SaveSync] [retroarch] LRPS2: put ${mine.map((s) => s.name).toList()} on ${target.path}');
  }

  @override
  Future<String?> saveSyncBlockedReason(Game game, String romPath) async {
    final slug = game.platformSlug?.toLowerCase() ?? '';
    if (!_isLrps2(slug)) return null;
    try {
      final setup = await _lrps2Cards(game, romPath);
      return await _lrps2SavesOf(game, romPath, setup.shared) == null ? _lrps2NoSerial : null;
    } catch (e) {
      debugPrint('[SaveSync] [retroarch] LRPS2: cannot tell whether saves can be synced: $e');
      return null;
    }
  }

  /// LRPS2 opens its shared cards when a game starts, so a pull that lands
  /// after that would be overwritten when the game saves.
  @override
  Future<bool> pullMustFinishBeforeLaunch(Game game, String romPath) async {
    final slug = game.platformSlug?.toLowerCase() ?? '';
    if (!_isLrps2(slug)) return false;
    try {
      return (await _lrps2Cards(game, romPath)).shared;
    } catch (_) {
      return false;
    }
  }


  String _getRetroArchExe() {
    if (_platform.isWindows) return 'RetroArch.exe';
    if (_platform.isMacOS) return 'RetroArch.app/Contents/MacOS/RetroArch';
    return 'retroarch';
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final slug = game.platformSlug?.toLowerCase() ?? '';
    final coreInfo = _getCoreInfo(slug);

    if (coreInfo == null) {
      debugPrint('[SaveSync] [retroarch] getSaveDir: no core info for slug="$slug"');
      return null;
    }

    // Ensure config flags are parsed on all platforms (Linux, macOS, Windows).
    await _readConfigSaveRoot();

    debugPrint('[SaveSync] [retroarch] getSaveDir: slug="$slug" core=${coreInfo.coreName} saveFolder=${coreInfo.saveFolder}');

    if (_platform.isLinux) {
      final baseDir = await _linuxBaseDir(slug);
      final isEmuDeck = _directoryService.linuxSyncPreset == 'emudeck' || baseDir.contains('Emulation/saves');
      debugPrint('[SaveSync] [retroarch] getSaveDir linux baseDir=$baseDir emudeck=$isEmuDeck');

      if (isEmuDeck) {
        // EmuDeck structure: Emulation/saves/retroarch/saves/CoreName
        final result = p.basename(baseDir) == 'saves'
            ? p.join(baseDir, coreInfo.saveFolder)
            : p.join(baseDir, 'saves', coreInfo.saveFolder);
        debugPrint('[SaveSync] [retroarch] getSaveDir emudeck → $result');
        return result;
      }

      // Non-EmuDeck Linux: prefer the parsed savefile_directory from retroarch.cfg
      // (honors custom save locations); fall back to baseDir/saves otherwise.
      final saveRoot = (_cachedSaveRoot != null && await io.Directory(_cachedSaveRoot!).exists())
          ? _cachedSaveRoot!
          : p.join(baseDir, 'saves');
      debugPrint('[SaveSync] [retroarch] getSaveDir linux saveRoot=$saveRoot');

      // Non-EmuDeck Linux: respect sort_savefiles_enable config flag
      if (!_sortSavefiles) {
        // sort_savefiles_enable=false: saves go flat into saveRoot, no core subfolder
        debugPrint('[SaveSync] [retroarch] getSaveDir linux no-sort → $saveRoot');
        return saveRoot;
      }

      // Try the expected core subfolder first
      final expectedDir = p.join(saveRoot, coreInfo.saveFolder);
      if (await io.Directory(expectedDir).exists()) {
        debugPrint('[SaveSync] [retroarch] getSaveDir linux expectedDir exists → $expectedDir');
        return expectedDir;
      }

      // Fallback: scan saveRoot subdirectories for the ROM's save file, since
      // RetroArch core folder names are unpredictable (e.g. "ParaLLEl N64"
      // vs "Parallel N64" vs "N64").
      final romStem = p.basenameWithoutExtension(romPath).toLowerCase();
      final rootDir = io.Directory(saveRoot);
      if (await rootDir.exists()) {
        await for (final entity in rootDir.list()) {
          if (entity is! io.Directory) continue;
          final subdir = entity.path;
          await for (final f in io.Directory(subdir).list()) {
            if (f is! io.File) continue;
            final fname = p.basename(f.path).toLowerCase();
            if (isSaveNamedFor(fname, romStem) && _isSaveFile(fname)) {
              debugPrint('[SaveSync] [retroarch] getSaveDir linux fallback scan matched → $subdir');
              return subdir;
            }
          }
        }
      }

      debugPrint('[SaveSync] [retroarch] getSaveDir linux fallback expectedDir → $expectedDir');
      return expectedDir;
    }

    // macOS / Windows: respect sort_savefiles_enable config flag
    if (_savefilesInContentDir) {
      // savefiles_in_content_dir=true: saves go next to the ROM
      final result = io.File(romPath).parent.path;
      debugPrint('[SaveSync] [retroarch] getSaveDir savefilesInContentDir → $result');
      return result;
    }
    final saveRoot = await _resolveSaveRoot();
    if (!_sortSavefiles) {
      // sort_savefiles_enable=false: saves go flat into saveRoot, no core subfolder
      debugPrint('[SaveSync] [retroarch] getSaveDir no-sort → $saveRoot');
      return saveRoot;
    }

    // Try the expected core subfolder first
    final expectedDir = p.join(saveRoot, coreInfo.saveFolder);
    if (await io.Directory(expectedDir).exists()) {
      debugPrint('[SaveSync] [retroarch] getSaveDir expectedDir exists → $expectedDir');
      return expectedDir;
    }

    // Fallback 1: scan saveRoot subdirectories for the ROM's save file.
    // RetroArch core folder names are unpredictable (e.g. "ParaLLEl N64"
    // vs "Parallel N64" vs "N64"). Scanning finds the actual folder.
    final romStem = p.basenameWithoutExtension(romPath).toLowerCase();
    final rootDir = io.Directory(saveRoot);
    if (await rootDir.exists()) {
      // A save directly in saveRoot: RetroArch doesn't sort into core
      // folders, though the flag couldn't be read (issue #79, EmuDeck).
      await for (final f in rootDir.list()) {
        if (f is io.File && isSaveNamedFor(p.basename(f.path), romStem) && _isSaveFile(p.basename(f.path).toLowerCase())) {
          debugPrint('[SaveSync] [retroarch] getSaveDir save in saveRoot → $saveRoot');
          return saveRoot;
        }
      }
      await for (final entity in rootDir.list()) {
        if (entity is! io.Directory) continue;
        final subdir = entity.path;
        await for (final f in io.Directory(subdir).list()) {
          if (f is! io.File) continue;
          final fname = p.basename(f.path).toLowerCase();
          if (isSaveNamedFor(fname, romStem) && _isSaveFile(fname)) {
            debugPrint('[SaveSync] [retroarch] getSaveDir fallback1 scan matched → $subdir');
            return subdir;
          }
        }
      }
    }

    // No save for this game yet (first pull): the core's own folder, which
    // RetroArch names after the core's library_name. Never another core's
    // folder: guessing "the most recently modified one" wrote PS2 memory
    // cards into the N64 core's folder.
    debugPrint('[SaveSync] [retroarch] getSaveDir fallback expectedDir → $expectedDir');
    return expectedDir;
  }

  /// Whether [fileName] is a save named after [stem]: the stem followed by
  /// an extension, e.g. `Pokemon.srm` or `Pokemon.0.mcr`. A bare prefix is
  /// not enough: "Crash Bandicoot" must not claim `Crash Bandicoot 2.srm`.
  /// Case-insensitive.
  @visibleForTesting
  static bool isSaveNamedFor(String fileName, String stem) =>
      fileName.toLowerCase().startsWith('${stem.toLowerCase()}.');

  /// Whether the save file [fileName] has the same title as the ROM [stem],
  /// ignoring case, punctuation, word order and `(…)` / `[…]` tags, so
  /// `Legend of Zelda, The (Europe).srm` matches "The Legend of Zelda (USA)".
  /// Every word counts, numbers included: "Crash Bandicoot 2" does not match
  /// `Crash Bandicoot (Europe).srm`, and neither does "Crash Bandicoot" match
  /// `Crash Bandicoot 2.srm`.
  @visibleForTesting
  static bool isSameTitle(String stem, String fileName) {
    final a = _titleWords(stem);
    return a.isNotEmpty && setEquals(a, _titleWords(p.basenameWithoutExtension(fileName)));
  }

  static Set<String> _titleWords(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toSet();

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    final map = await getSaveFilesWithScreenshots(game, romPath, sessionStart: sessionStart, syncMode: syncMode);
    final slug = game.platformSlug?.toLowerCase() ?? '';
    if (!_isLrps2(slug)) return map.keys.toList();
    // Local backups keep LRPS2's whole cards, not the save folders the sync
    // takes out of them.
    final files = [for (final f in map.keys) if (!p.isWithin(_lrps2TempRoot, f.path)) f];
    if (files.length != map.length) {
      for (final card in (await _lrps2Cards(game, romPath)).cards) {
        if (await card.exists()) files.add(card);
      }
    }
    return files;
  }

  /// Whether the user turned on "Sync save states" for RetroArch. States then
  /// sync through StateSyncService and stay out of the game-save upload.
  bool get _stateSyncOn => _prefs?.getBool(StateSyncService.enabledKey('retroarch')) ?? false;

  /// RetroArch's default states folder for [slug], without the per-core
  /// subfolder: `<RetroArch>/states` (EmuDeck and RetroDECK have their own
  /// roots).
  Future<String> _defaultStatesRoot(String slug) async {
    if (_platform.isLinux) {
      final baseDir = await _linuxBaseDir(slug);
      switch (_directoryService.linuxSyncPreset) {
        case 'emudeck':
          // baseDir is .../Emulation/saves/retroarch
          return p.join(p.dirname(p.dirname(baseDir)), 'states', 'retroarch');
        case 'retrodeck':
        default:
          // baseDir is RetroArch's own config folder (~/.config/retroarch, or
          // the Flatpak's config/retroarch), which holds states/ and saves/.
          return p.join(baseDir, 'states');
      }
    }
    final saveRoot = await _resolveSaveRoot();
    return p.join(io.Directory(saveRoot).parent.path, 'states');
  }

  /// Where RetroArch keeps [coreInfo]'s save states for [romPath], following
  /// retroarch.cfg the way RetroArch does: next to the ROM with
  /// `savestates_in_content_dir`, else `savestate_directory` (default
  /// `<RetroArch>/states`), then the ROM's folder name with
  /// `sort_savestates_by_content_enable`, then the core's folder with
  /// `sort_savestates_enable` (on by default). Needs retroarch.cfg to have
  /// been read.
  Future<String> _statesDir(String slug, _CoreInfo coreInfo, String romPath) async {
    if (_cachedSavestatesInContentDir ?? false) return io.File(romPath).parent.path;
    var dir = _cachedStateDir ?? await _defaultStatesRoot(slug);
    if (_cachedSortSavestatesByContent ?? false) {
      dir = p.join(dir, p.basename(io.File(romPath).parent.path));
    }
    if (_cachedSortSavestates ?? true) dir = p.join(dir, coreInfo.statesFolder);
    return dir;
  }

  // ─── Save states (StateSyncCapable) ───────────────────────────────────
  //
  // RetroArch names a state after the content file, never the core:
  // `<content>.state` (slot 0), `<content>.stateN` (slots 1+) and
  // `<content>.state.auto` (the auto slot), with an optional `<state>.png`
  // thumbnail beside it. By default they live in a per-core folder (see
  // [_statesDir]), so only the states of the core the game runs with are
  // synced.

  static final _stateSuffixPattern = RegExp(r'\.state(\d{1,3}|\.auto)?$');

  /// Forgets everything read from retroarch.cfg and the install found, so the
  /// next lookup starts from what is on disk now (RetroArch rewrites its
  /// config on exit, and the emulator can be installed or switched while
  /// Freegosy runs).
  void _forgetConfig() {
    _appImageResolved = false;
    _appImageConfig = null;
    _appImageHome = null;
    _cachedSaveRoot = null;
    _cachedStateDir = null;
    _cachedSortSavefiles = null;
    _cachedSortSavefilesByContent = null;
    _cachedSavefilesInContentDir = null;
    _cachedSortSavestates = null;
    _cachedSortSavestatesByContent = null;
    _cachedSavestatesInContentDir = null;
    _cachedConfigDir = null;
    _cachedSystemDir = null;
    _cachedCoreOptionsDir = null;
    _cachedActiveCore = null;
  }

  /// Every state lookup (the game page's Resume list, sync) rereads the
  /// config first, like PCSX2's, instead of trusting what an earlier launch or
  /// page saw.
  @override
  Future<String> stateDirectory(Game game, String romPath) async {
    _forgetConfig();
    final slug = game.platformSlug?.toLowerCase() ?? '';
    final coreInfo = _getCoreInfo(slug);
    if (coreInfo == null) {
      throw Exception('No RetroArch core is known for platform "$slug", so its save states folder is unknown.');
    }
    await _readConfigSaveRoot();
    return _statesDir(slug, coreInfo, romPath);
  }

  @override
  Future<bool Function(String fileName)?> stateFileMatcher(Game game, String romPath) async {
    final stems = {getRomStem(game), p.basenameWithoutExtension(romPath)}..removeWhere((s) => s.isEmpty);
    if (stems.isEmpty) return null;
    return (String fileName) {
      if (fileName != p.basename(fileName) || fileName.contains('\\')) return false;
      final match = _stateSuffixPattern.firstMatch(fileName);
      return match != null && stems.contains(fileName.substring(0, match.start));
    };
  }

  /// A state is `RASTATE` + a version byte followed by blocks, or the same
  /// wrapped in RetroArch's compressed `#RZIPv` container. Older frontends
  /// wrote bare core data, which can't be told from garbage, so it isn't
  /// accepted.
  @override
  bool looksLikeValidState(Uint8List bytes) => _stateFormat(bytes) != null;

  static String? _stateFormat(List<int> head) {
    bool startsWith(String magic) {
      if (head.length < magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (head[i] != magic.codeUnitAt(i)) return false;
      }
      return true;
    }

    if (startsWith('RASTATE') && head.length >= 8) return 'RASTATE v${head[7]}';
    if (startsWith('#RZIPv') && head.length >= 8 && head[7] == 0x23) return 'RetroArch compressed state';
    return null;
  }

  @override
  StateSlot slotOf(String fileName) {
    final match = _stateSuffixPattern.firstMatch(fileName);
    if (match == null) return UnknownStateSlot(fileName);
    final slot = match.group(1);
    if (slot == '.auto') return const AutoStateSlot();
    return NumberedStateSlot(slot == null ? 0 : int.parse(slot));
  }

  @override
  Future<StateFileInfo> describeState(io.File file) async {
    final base = await super.describeState(file);
    io.RandomAccessFile? raf;
    try {
      raf = await file.open();
      return StateFileInfo(savedAt: base.savedAt, formatId: _stateFormat(await raf.read(8)));
    } catch (_) {
      return base;
    } finally {
      await raf?.close();
    }
  }

  /// RetroArch writes the thumbnail beside the state as `<state>.png` when
  /// "Save State Thumbnails" is on.
  @override
  Future<Uint8List?> stateScreenshot(io.File file) async {
    try {
      final png = io.File('${file.path}.png');
      return await png.exists() ? await png.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<io.File, io.File?>> getSaveFilesWithScreenshots(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    final slug = game.platformSlug?.toLowerCase() ?? '';
    final coreInfo = _getCoreInfo(slug);

    if (coreInfo == null) return {};

    final rootSaveDir = await getSaveDir(game, romPath);
    await _readConfigSaveRoot();
    final statesRoot = await _statesDir(slug, coreInfo, romPath);

    debugPrint('[SaveSync] [retroarch] getSaveFilesWithScreenshots slug=$slug rootSaveDir=$rootSaveDir statesRoot=$statesRoot');

    if (rootSaveDir == null) return {};

    final stem = getRomStem(game);
    final List<io.File> filesToCheck = [];
    debugPrint('[SaveSync] [retroarch] getSaveFilesWithScreenshots stem=$stem syncMode=$syncMode');

    // Special case for PSP saves
    if (slug == 'psp' || slug == 'playstation-portable') {
      if (syncMode == 'saves' || syncMode == 'both') {
        final pspDir = io.Directory(rootSaveDir);
        if (await pspDir.exists()) {
          bool hasFiles = false;
          await for (final _ in pspDir.list(recursive: true)) {
            hasFiles = true;
            break;
          }
          if (hasFiles) {
            filesToCheck.add(io.File(rootSaveDir));
            debugPrint('[SaveSync] [retroarch] getSaveFilesWithScreenshots PSP dir has files');
          }
        }
      }
    } else if (_isLrps2(slug)) {
      if (syncMode == 'saves' || syncMode == 'both') {
        filesToCheck.addAll(await _lrps2SaveFolders(game, romPath, sessionStart));
      }
    } else {
      if (syncMode == 'saves' || syncMode == 'both') {
        final savesDirObj = io.Directory(rootSaveDir);
        if (await savesDirObj.exists()) {
          final stemLower = stem.toLowerCase();
          bool found = false;
          await for (final entity in savesDirObj.list()) {
            if (entity is! io.File) continue;
            final fname = p.basename(entity.path).toLowerCase();
            if (isSaveNamedFor(fname, stemLower) && _isSaveFile(fname)) {
              filesToCheck.add(entity);
              found = true;
              debugPrint('[SaveSync] [retroarch] getSaveFilesWithScreenshots exact match: $fname');
              break;
            }
          }
          if (!found) {
            await for (final entity in savesDirObj.list()) {
              if (entity is! io.File) continue;
              final fname = p.basename(entity.path).toLowerCase();
              if (_isSaveFile(fname) && isSameTitle(stem, fname)) {
                filesToCheck.add(entity);
                found = true;
                debugPrint('[SaveSync] [retroarch] getSaveFilesWithScreenshots title match: $fname');
                break;
              }
            }
          }
          if (!found) {
            // No save file matches this game by name (exact stem or same title). Do NOT fall back to "any .srm/.sav file in the directory" —
            // that previously caused an unrelated game's save (e.g. a different
            // ROM's leftover .srm sitting in the same core folder) to be picked up
            // and uploaded under the current game's RomM entry (see issue #95).
            // It is much safer to find nothing than to grab the wrong file.
            //
            // We still probe for the exact expected filename ($stem.srm); if it
            // doesn't exist, the existence check below drops it and no save is
            // reported — which is correct for save-state-only platforms/cores
            // (e.g. Atari 2600/Stella) that have no battery-backed save file.
            debugPrint('[SaveSync] [retroarch] getSaveFilesWithScreenshots no name-matching save found, probing for $stem.srm only');
            filesToCheck.add(io.File(p.join(rootSaveDir, '$stem.srm')));
          }
        } else {
          debugPrint('[SaveSync] [retroarch] getSaveFilesWithScreenshots rootSaveDir does not exist');
          filesToCheck.add(io.File(p.join(rootSaveDir, '$stem.srm')));
        }
      }
    }

    // Handle States
    if ((syncMode == 'states' || syncMode == 'both') && !_stateSyncOn) {
      final romStem = io.File(romPath).uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      for (final checkStem in [stem, romStem]) {
        filesToCheck.add(io.File('$statesRoot/$checkStem.state.auto'));
        filesToCheck.add(io.File('$statesRoot/$checkStem.state')); // slot 0 has no number
        for (int i = 0; i <= 9; i++) {
          filesToCheck.add(io.File('$statesRoot/$checkStem.state$i'));
        }
      }
    }

    // Filter out non-existent files and apply sessionStart filter
    final finalResult = <io.File, io.File?>{};
    for (final f in filesToCheck) {
      final existsAsFile = await f.exists();
      final existsAsDir = await io.Directory(f.path).exists();
      if (!existsAsFile && !existsAsDir) continue;
      if (sessionStart != null && existsAsFile) {
        final stat = await f.stat();
        if (stat.modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) continue;
      }

      // Check for screenshots if it's a state file
      io.File? screenshot;
      if (f.path.contains('.state')) {
        final screenshotPath = '${f.path}.png';
        final screenFile = io.File(screenshotPath);
        if (await screenFile.exists()) {
          screenshot = screenFile;
        }
      }

      finalResult[f] = screenshot;
    }
    debugPrint('[SaveSync] [retroarch] getSaveFilesWithScreenshots result: ${finalResult.length} file(s) found');
    return finalResult;
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final slug = game.platformSlug?.toLowerCase() ?? '';
      final coreInfo = _getCoreInfo(slug);

      if (coreInfo == null) return false;
      await _readConfigSaveRoot();

      // LRPS2: the saves go onto its memory card; states below as usual.
      final lrps2 = _isLrps2(slug);
      if (lrps2 && !filename.contains('.state')) {
        await _restoreLrps2(game, destPath, data, filename);
        if (!filename.toLowerCase().endsWith('.zip')) return true;
      }

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final file in archive) {
          if (!file.isFile) continue;
          if (file.name == 'freegosy_sync.txt') continue;

          final isFileState = file.name.contains('.state');
          if (lrps2 && !isFileState) continue;
          String? fileTargetDir;
          if (isFileState) {
            if (_stateSyncOn) continue; // states sync through StateSyncService
            fileTargetDir = await _statesDir(slug, coreInfo, destPath);
          } else {
            fileTargetDir = await getSaveDir(game, destPath);
          }
          if (fileTargetDir == null) return true;
          final dir = io.Directory(fileTargetDir);
          if (!await dir.exists()) await dir.create(recursive: true);

          final content = Uint8List.fromList(file.content as List<int>);
          var outputs = [SaveBlob(file.name, content)];
          if (!isFileState && file.name.toLowerCase().endsWith('.sav')) {
            outputs = [SaveBlob('${p.basenameWithoutExtension(file.name)}.srm', content)];
          } else if (!isFileState) {
            // A save from another emulator in the bundle, e.g. a DuckStation
            // PS1 card, in the format and under the name this core reads.
            final conversion = convertSave(
              platformSlug: slug,
              files: [SaveBlob(p.basename(file.name), content)],
              targetTag: coreIdFor(game) ?? '',
              stem: getRomStem(game),
            );
            if (conversion is SaveConverted) outputs = conversion.files;
          }

          for (final out in outputs) {
            final targetPath = p.normalize(p.join(fileTargetDir, out.name));
            await backupSave(targetPath);
            await io.File(targetPath).writeAsBytes(out.bytes);
          }
        }
        return true;
      }

      String? targetDir;
      final isState = filename.contains('.state');

      if (isState) {
        if (_stateSyncOn) {
          debugPrint('[SaveSync] [retroarch] ignoring state in save restore (state sync is on): $filename');
          return true;
        }
        targetDir = await _statesDir(slug, coreInfo, destPath);
      } else {
        // For saves: use getSaveDir() which scans for the actual folder
        targetDir = await getSaveDir(game, destPath);
      }

      if (targetDir == null) return false;
      final dir = io.Directory(targetDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      // Handle .sav to .srm renaming for RetroArch NDS cores. A save from
      // another emulator (e.g. a DuckStation PS1 card) arrives already
      // converted by SaveSyncService (save/formats).
      String targetFilename = filename;
      // RomM's web player names saves "<game> [timestamp].srm"; RetroArch only
      // opens "<rom>.srm", so a save it can't match by name is renamed to it.
      if (!isState && RegExp(r'\]\.(sav|srm)$', caseSensitive: false).hasMatch(filename)) {
        targetFilename = '${p.basenameWithoutExtension(destPath)}.srm';
      } else if (!isState && filename.toLowerCase().endsWith('.sav')) {
        targetFilename = '${p.basenameWithoutExtension(filename)}.srm';
      }

      final targetPath = p.normalize(p.join(targetDir, targetFilename));
      await backupSave(targetPath); // Backup existing file
      await io.File(targetPath).writeAsBytes(data);
      return true;
    } on SaveSyncNotPossibleException {
      rethrow;
    } catch (e) {
      debugPrint('[SaveSync] [retroarch] restoreSave failed: $e');
      return false;
    }
  }
}

class _CoreInfo {
  final String coreName;
  final String saveFolder;
  final String statesFolder;
  const _CoreInfo(this.coreName, this.saveFolder, this.statesFolder);
}
