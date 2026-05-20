import 'dart:convert';
import 'dart:io' as io;
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../save_strategy.dart';

/// Save strategy for Dolphin emulator (GameCube / Wii).
///
/// Refined to support macOS and Windows user directories and Wii/GC specific paths.
class DolphinSaveStrategy extends SaveStrategy {
  // ignore: unused_field
  final DirectoryService _directoryService;

  DolphinSaveStrategy(this._directoryService);

  @override
  String get strategyId => 'dolphin';

  String _getEmuExe() {
    if (io.Platform.isWindows) return 'Dolphin.exe';
    if (io.Platform.isMacOS) return 'Dolphin.app/Contents/MacOS/Dolphin';
    return 'Dolphin';
  }

  /// Returns the base user directory for Dolphin.
  Future<String> _getUserDir({String? platformSlug}) async {
    // 1. Check portable mode first — User folder next to exe
    final exePath = await _directoryService.findEmulatorExecutable(
        'dolphin', _getEmuExe());
    if (exePath != null) {
      String exeDir = io.File(exePath).parent.path;
      if (io.Platform.isMacOS && exePath.contains('.app/Contents/MacOS/')) {
        exeDir = io.File(exePath).parent.parent.parent.parent.path;
      } else if (await io.FileSystemEntity.isDirectory(exePath)) {
        exeDir = exePath;
      }
      final portableUser = p.join(exeDir, 'User');
      if (await io.Directory(portableUser).exists()) {
        return portableUser;
      }
    }

    // 2. On Linux, if running via Flatpak, which is the default installation method of Dolphin
    if (io.Platform.isLinux){
      final home = io.Platform.environment['HOME'] ?? '';
      final flatpakPath = "$home/.var/app/org.DolphinEmu.dolphin-emu/data/dolphin-emu";
      if (await io.Directory(flatpakPath).exists()) {
        return flatpakPath;
      }
    }
    

    // 3. Fall back to app support directory
    final resolvedPath = await _directoryService.getEmulatorAppSupportDirectory('Dolphin', platformSlug: platformSlug);
    if (!await io.Directory(resolvedPath).exists()) {
      throw Exception('Save directory not found for Dolphin at $resolvedPath. Please launch Dolphin at least once to generate save data.');
    }
    return resolvedPath;
  }

  /// Detects region code from [romPath].
  String _detectRegion(String romPath) {
    final upper = romPath.toUpperCase();
    if (upper.contains('EUR') || upper.contains('PAL')) return 'EUR';
    if (upper.contains('JAP') || upper.contains('JPN')) return 'JAP';
    return 'USA';
  }

  /// Normalizes game name for comparison.
  String _normalizeGameName(String name) {
    return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }


  bool _isValidGameIdByte(int byte) {
    final c = String.fromCharCode(byte);

    final isUpper =
        c.codeUnitAt(0) >= 'A'.codeUnitAt(0) &&
        c.codeUnitAt(0) <= 'Z'.codeUnitAt(0);

    final isDigit =
        c.codeUnitAt(0) >= '0'.codeUnitAt(0) &&
        c.codeUnitAt(0) <= '9'.codeUnitAt(0);

    return isUpper || isDigit;
  }

  /// Extracts Game ID/Code from file if possible.
  /// Often formatted as [GAMEID] Name.ext or Name [GAMEID].ext
  Future<String?> _extractGameId(String romPath) async {

    // Attempt to read the game ID from the file
    final allowedFileExtensions = [".rvz", ".iso"];
    final fileExtension = p.extension(romPath).toLowerCase();
    if (allowedFileExtensions.contains(fileExtension)) {
      
      final file = await File(romPath).open(mode: FileMode.read);
      final bytes = Uint8List(4);
      
      int offset = 0;

      switch (fileExtension){
        case ".rvz":
          offset = 0x58;
          break;
        case ".iso":
          offset = 0x00;
          break;
      }

      await file.setPosition(offset);
      await file.readInto(bytes);
      await file.close();
    
      for (final b in bytes) {
        if (!_isValidGameIdByte(b)) {
          return null;
        }
      }

      return ascii.decode(bytes);
    }


    final filename = p.basename(romPath);
    final base = p.basenameWithoutExtension(filename);
    // Look for 4 or 6 character uppercase alphanumeric codes
    final match = RegExp(r'\[([A-Z0-9]{4,6})\]').firstMatch(base);
    if (match != null) return match.group(1);
    
    // Also try 6 char codes at the start of filename (common in some sets)
    final startMatch = RegExp(r'^([A-Z0-9]{6})').firstMatch(base);
    if (startMatch != null) return startMatch.group(1);

    return null;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final userDir = await _getUserDir(platformSlug: game.platformSlug);
    final bool isIntegratedEnv = io.Platform.isLinux && 
                                (_directoryService.linuxSyncPreset == 'emudeck' || 
                                 _directoryService.linuxSyncPreset == 'retrodeck');

    final isWii = game.platformSlug?.toLowerCase() == 'wii';

    if (isWii) {
      // Wii saves are in Wii/title/00010000/[TITLE_ID_HEX]
      String? titleId = await _extractGameId(romPath);
      
      final String wiiBase = (isIntegratedEnv && p.basename(userDir).toLowerCase() == 'wii')
          ? userDir
          : p.join(userDir, 'Wii');

      if (titleId != null && titleId.length >= 4) {
        final hexId = titleId.substring(0, 4).codeUnits
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join();
        final wiiPath = p.join(wiiBase, 'title', '00010000', hexId);
        if (await io.Directory(wiiPath).exists()) return wiiPath;
      }
      
      return p.join(wiiBase, 'title', '00010000');
    } else {
      // GameCube
      final region = _detectRegion(romPath);
      final String gcBase = (isIntegratedEnv && p.basename(userDir).toLowerCase() == 'gc')
          ? userDir
          : p.join(userDir, 'GC');
      
      // First, check for GCI folder (preferred for sync)
      final gciPath = p.join(gcBase, region, 'Card A');
      if (await io.Directory(gciPath).exists()) return gciPath;

      // Fallback to the general GC folder for memory cards
      return gcBase;
    }
  }

  @override
  Future<List<io.File>> getSaveFiles(
      Game game,
      String romPath,
      {DateTime? sessionStart,
      String syncMode = 'both'}) async {
    final userDir = await _getUserDir(platformSlug: game.platformSlug);
    final rootSaveDir = await getSaveDir(game, romPath);
    if (rootSaveDir == null) return [];

    final isWii = game.platformSlug?.toLowerCase() == 'wii';
    final result = <io.File>[];

    if (syncMode == 'saves' || syncMode == 'both') {
      if (isWii) {
        // For Wii, if we have the specific folder, sync it (SaveSyncService will zip it)
        if (p.basename(rootSaveDir) != '00010000') {
          result.add(io.File(rootSaveDir));
        }
      } else {
        // GameCube fuzzy matching
        final dir = io.Directory(rootSaveDir);
        if (await dir.exists()) {
          final gameId = (await _extractGameId(romPath))?.toUpperCase();
          final normalizedTarget = _normalizeGameName(game.displayName);

          await for (final entity in dir.list(recursive: true)) {
            if (entity is! io.File) continue;
            final filename = p.basename(entity.path).toUpperCase();

            // 1. Match .gci files by ID or name
            if (filename.endsWith('.GCI')) {
              bool match = false;
              if (gameId != null && filename.contains(gameId)) {
                match = true;
              } else {
                final normalizedGci = _normalizeGameName(filename);
                if (normalizedGci.contains(normalizedTarget) || normalizedTarget.contains(normalizedGci)) {
                  match = true;
                }
              }

              if (match) {
                if (sessionStart == null || (await entity.stat()).modified.isAfter(sessionStart)) {
                  result.add(entity);
                }
              }
            } 
            
            // 2. Match Memory Card files (.raw, .mcp) - only if they match region
            else if (filename.startsWith('MEMORYCARDA') && (filename.endsWith('.RAW') || filename.endsWith('.MCP'))) {
              final region = _detectRegion(romPath);
              if (filename.contains(region)) {
                if (sessionStart == null || (await entity.stat()).modified.isAfter(sessionStart)) {
                  result.add(entity);
                }
              }
            }
          }
        }
      }
    }

    // Handle States
    if (syncMode == 'states' || syncMode == 'both') {
      final stateDir = p.join(userDir, 'StateSaves');
      final stateDirObj = io.Directory(stateDir);
      if (await stateDirObj.exists()) {
        final gameId = (await _extractGameId(romPath))?.toUpperCase();
        final romStem = p.basenameWithoutExtension(romPath).toUpperCase();

        await for (final entity in stateDirObj.list()) {
          if (entity is! io.File) continue;
          final filename = p.basename(entity.path).toUpperCase();
          
          // Dolphin states are usually [GameID].s00, [GameID].sav, etc.
          // or [Filename].s00
          if (filename.endsWith('.SAV') || filename.contains(RegExp(r'\.S\d{2}$'))) {
            if ((gameId != null && filename.startsWith(gameId)) || filename.startsWith(romStem)) {
              if (sessionStart == null || (await entity.stat()).modified.isAfter(sessionStart)) {
                result.add(entity);
              }
            }
          }
        }
      }
    }

    return result;
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final saveDir = await getSaveDir(game, destPath);
      if (saveDir == null) return false;

      final dir = io.Directory(saveDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final targetPath = p.normalize(p.join(saveDir, filename));
      await backupSave(targetPath);
      await io.File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}
