import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/platform/platform_info.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';

/// Maps Freegosy platform slugs to Ares --system full display names.
/// Source: mia.cpp media[] vector + mia/medium/*.cpp name() overrides.
const Map<String, String> kAresSystemNames = {
  'atari2600':       'Atari 2600',
  'nes':             'Famicom',
  'famicom':         'Famicom',
  'snes':            'Super Famicom',
  'sfc':             'Super Famicom',
  'n64':             'Nintendo 64',
  'gb':              'Game Boy',
  'gbc':             'Game Boy Color',
  'gba':             'Game Boy Advance',
  'game-boy':        'Game Boy',
  'game-boy-color':  'Game Boy Color',
  'game-boy-advance':'Game Boy Advance',
  'gamegear':        'Game Gear',
  'sms':             'Master System',
  'mastersystem':    'Master System',
  'genesis':         'Mega Drive',
  'megadrive':       'Mega Drive',
  'md':              'Mega Drive',
  'segacd':          'Mega CD',
  'psx':             'PlayStation',
  'ps1':             'PlayStation',
  'playstation':     'PlayStation',
  'pce':             'PC Engine',
  'pcengine':        'PC Engine',
  'neogeo':          'Neo Geo',
  'neo-geo':         'Neo Geo',
  'msx':             'MSX',
  'coleco':          'ColecoVision',
  'colecovision':    'ColecoVision',
  'zxspectrum':      'ZX Spectrum',
  'zx-spectrum':     'ZX Spectrum',
  'wonderswan':      'WonderSwan',
  'wonderswancolor': 'WonderSwan Color',
  'ngp':             'Neo Geo Pocket',
  'ngpc':            'Neo Geo Pocket Color',
  'neo-geo-pocket':  'Neo Geo Pocket',
};

class AresStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  AresStrategy(this._directoryService, {super.platform});

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'Ares';

  @override
  String get emulatorId => 'ares';

  @override
  List<String> get supportedSlugs => kAresSystemNames.keys.toList();

  @override
  String get windowsExecutable => 'ares.exe';

  @override
  String get linuxExecutable => 'ares.AppImage';

  @override
  String get macosExecutable => 'ares.app/Contents/MacOS/ares';

  @override
  bool get supportsSaveSync => true;

  /// Returns the Ares --system flag for a given Freegosy platform slug.
  String? getSystemNameForSlug(String? slug) {
    if (slug == null) return null;
    return kAresSystemNames[slug.toLowerCase()];
  }

  /// Builds the full argument list for launching a specific game.
  /// Format: `ares --system <name> "<rompath>"`
  List<String> _buildArgs(String systemName) {
    return ['--system', systemName];
  }

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    final systemName = getSystemNameForSlug(game.platformSlug);
    if (systemName == null) {
      throw Exception('Ares does not support platform: ${game.platformSlug}');
    }

    final normalizedRomPath = p.absolute(p.normalize(romPath));
    final args = _buildArgs(systemName);
    await preLaunch(game, romPath);
    await directoryService.launchGame(game, normalizedRomPath, emulatorId, exePath, args: args);
    await postLaunch(game, romPath);
  }

  @override
  Future<Process?> launchWithHandle(Game game, String romPath, {String? coreName}) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    final systemName = getSystemNameForSlug(game.platformSlug);
    if (systemName == null) {
      throw Exception('Ares does not support platform: ${game.platformSlug}');
    }

    final normalizedRomPath = p.absolute(p.normalize(romPath));
    final args = _buildArgs(systemName);
    await preLaunch(game, romPath);
    final process = await directoryService.launchGameWithHandle(game, normalizedRomPath, emulatorId, exePath, args: args);
    await process?.exitCode;
    await postLaunch(game, romPath);
    return process;
  }

  @override
  String resolveSavePath(Game game) => '';
}
