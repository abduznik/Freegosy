import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import '../emulator_strategy.dart';
import '../custom_emulator_config.dart';

class CustomEmulatorStrategy extends EmulatorStrategy {
  final CustomEmulatorConfig config;
  @override
  final DirectoryService directoryService;

  CustomEmulatorStrategy(this.config, this.directoryService);

  @override
  String get name => config.name;

  @override
  String get emulatorId => config.id;

  @override
  List<String> get supportedSlugs => config.platforms;

  @override
  String get windowsExecutable => config.executablePath;

  @override
  String get linuxExecutable => config.executablePath;

  @override
  bool get supportsSaveSync => true;

  @override
  Future<String?> findExecutable() async {
    // If a command override is set (e.g. "flatpak run ..."), accept it
    // without checking for a file — the launch method handles it.
    if (config.isCommandOverride) {
      return config.commandOverride;
    }

    // For custom emulators, the user provides the absolute path.
    if (await io.File(config.executablePath).exists()) {
      return config.executablePath;
    }
    return null;
  }

  @override
  String resolveSavePath(Game game) {
    if (config.saveMethod == CustomSaveMethod.file) {
      final pattern = config.savePattern ?? '';
      if (pattern.contains('*')) {
        final ext = pattern.replaceAll('*', '');
        return p.join(config.savePath, '${game.displayName}$ext');
      } else if (pattern.isNotEmpty) {
        return p.join(config.savePath, pattern);
      } else {
        // Fallback: just game name
        return p.join(config.savePath, game.displayName);
      }
    } else {
      // Folder based
      return p.join(config.savePath, game.displayName);
    }
  }

  @override
  Future<void> launch(Game game, String romPath) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('Custom emulator executable not found at: ${config.executablePath}');

    final normalizedRomPath = p.absolute(p.normalize(romPath));

    if (config.isCommandOverride) {
      // Treat commandOverride as a full shell command line.
      // Split into executable + arguments and run with runInShell.
      final parts = _splitShellCommand(config.commandOverride!);
      await io.Process.run(
        parts.first,
        [...parts.sublist(1), normalizedRomPath],
        runInShell: true,
      );
    } else {
      // We use a raw process start because custom emulators might not be in the standard EmuDeck structure
      await io.Process.run(exePath, [normalizedRomPath], runInShell: true);
    }
  }

  /// Splits a shell command string into parts respecting quoted segments.
  /// e.g. "flatpak run org.libretro.RetroArch" -> ["flatpak", "run", "org.libretro.RetroArch"]
  List<String> _splitShellCommand(String command) {
    final parts = <String>[];
    final buf = StringBuffer();
    bool inQuote = false;
    bool inSingle = false;

    for (int i = 0; i < command.length; i++) {
      final ch = command[i];
      if (ch == '"' && !inSingle) {
        inQuote = !inQuote;
      } else if (ch == "'" && !inQuote) {
        inSingle = !inSingle;
      } else if (ch == ' ' && !inQuote && !inSingle) {
        if (buf.isNotEmpty) {
          parts.add(buf.toString());
          buf.clear();
        }
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) {
      parts.add(buf.toString());
    }
    return parts;
  }
}
