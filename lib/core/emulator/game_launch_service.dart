import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import '../storage/app_preferences.dart';
import '../romm/romm_models.dart';
import '../romm/romm_service.dart';
import '../romm/rom_constants.dart';
import '../storage/directory_service.dart';
import '../save/backup_entry.dart';
import '../save/backup_repository.dart';
import '../save/backup_service.dart';
import '../save/save_sync_service.dart';
import 'emulator_strategy.dart';
import 'strategies/retroarch_strategy.dart';
import 'strategy_registry.dart';

/// Result of resolving a game's ROM path when the on-disk location is
/// ambiguous (e.g. a directory containing multiple disc images).
/// If [candidates] is non-empty, the caller must let the user pick one and
/// join it onto the original directory path; otherwise [resolvedPath] is
/// the final path to launch.
class RomResolution {
  final String? resolvedPath;
  final List<Map<String, dynamic>> candidates;

  const RomResolution({this.resolvedPath, this.candidates = const []});
}

/// A launched game process plus the timestamp launch began, needed to scope
/// which save files count as part of this play session. [emulatorId]
/// records which emulator actually launched the game, so the post-exit
/// save sync uses the same emulator's strategy rather than whatever the
/// platform's global preference happens to be (see issue #79).
class GameSession {
  final io.Process? process;
  final DateTime sessionStart;
  final String emulatorId;

  const GameSession({required this.process, required this.sessionStart, required this.emulatorId});
}

/// Outcome of awaiting a launched game's exit and running the post-exit
/// save-sync/backup/play-session pipeline.
class LaunchResult {
  final bool syncOk;
  final String? backupZipPath;
  final bool playSessionRecorded;

  const LaunchResult({
    required this.syncOk,
    this.backupZipPath,
    this.playSessionRecorded = false,
  });
}

/// Orchestrates the non-UI portions of launching a game: ROM path
/// resolution, process launch, and the post-exit save-sync/backup/
/// play-session pipeline. Extracted from the widget layer so the same
/// pipeline can be reused outside Flutter (e.g. a future CLI).
class GameLaunchService {
  final DirectoryService directoryService;
  final StrategyRegistry strategyRegistry;
  final SaveSyncService saveSyncService;
  final BackupService backupService;
  final BackupRepository backupRepository;
  final RommService? rommService;
  final AppPreferences prefs;

  GameLaunchService({
    required this.directoryService,
    required this.strategyRegistry,
    required this.saveSyncService,
    required this.backupService,
    required this.backupRepository,
    required this.prefs,
    this.rommService,
  });

  /// Scans [existingRomPath] (a directory) for `.m3u` playlists or known
  /// disc-image files. Used when RomM doesn't correctly report
  /// `hasMultipleFiles` for multi-disc games (e.g. GameCube with `.m3u`).
  Future<List<Map<String, dynamic>>> scanForDiscFiles(String existingRomPath) async {
    final discFiles = <Map<String, dynamic>>[];
    final dir = io.Directory(existingRomPath);
    await for (final entity in dir.list()) {
      if (entity is! io.File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (name.endsWith('.m3u')) {
        final stat = await entity.stat();
        discFiles.add({'file_name': p.basename(entity.path), 'file_size_bytes': stat.size});
      } else if (name.endsWith('.rvz') || name.endsWith('.gcm') || name.endsWith('.iso') ||
          name.endsWith('.cso') || name.endsWith('.wbfs') ||
          name.endsWith('.bin') || name.endsWith('.img') ||
          name.endsWith('.chd') || name.endsWith('.pbp') || name.endsWith('.ccd')) {
        final stat = await entity.stat();
        discFiles.add({'file_name': p.basename(entity.path), 'file_size_bytes': stat.size});
      }
    }
    return discFiles;
  }

  /// Returns the game's full file list (fetching from RomM if [game.files]
  /// is empty, since paginated API responses omit it) alongside the subset
  /// filtered to launchable files via [RomConstants.filterLaunchableFiles].
  Future<({List<Map<String, dynamic>> files, List<Map<String, dynamic>> launchableFiles})> launchableFilesFor(Game game) async {
    List<Map<String, dynamic>> files = game.files;
    if (files.isEmpty && rommService != null) {
      try {
        final response = await rommService!.getGame(game.id);
        if (response != null) files = response.files;
      } catch (e) {
        debugPrint('[GameLaunchService] Failed to fetch game details: $e');
      }
    }
    if (files.isEmpty) return (files: const <Map<String, dynamic>>[], launchableFiles: const <Map<String, dynamic>>[]);
    return (files: files, launchableFiles: RomConstants.filterLaunchableFiles(files));
  }

  /// If [romPath] points to a directory, searches it for a file matching
  /// the platform's known extensions (skipped for Windows/PC, which are
  /// folder-based games). Returns the original path unchanged if no match
  /// is found or [romPath] is not a directory.
  Future<String> resolveRomFileInDirectory(String romPath, String? platformSlug) async {
    if (!await io.Directory(romPath).exists()) return romPath;
    final lowerPlatformSlug = (platformSlug ?? '').toLowerCase();
    if (['windows', 'pc', 'win'].contains(lowerPlatformSlug)) return romPath;

    final knownExtensions = RomConstants.platformExtensions[lowerPlatformSlug] ?? [];
    final dir = io.Directory(romPath);
    await for (final entity in dir.list()) {
      if (entity is! io.File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (knownExtensions.any((ext) => name.endsWith(ext))) {
        return entity.path;
      }
    }
    return romPath;
  }

  /// True if [game]'s platform is a 3DS variant and the emulator's
  /// aes_keys.txt is missing from its system directory.
  Future<bool> needs3dsKeysWarning(Game game, EmulatorStrategy strategy) async {
    const slugs = ['3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds', 'new-nintendo-3ds', 'new-nintendo-3ds-xl'];
    if (!slugs.contains(game.platformSlug?.toLowerCase())) return false;
    final systemDir = await directoryService.getEmulatorSystemDirectory(strategy.emulatorId);
    final keysPath = '$systemDir/${strategy.emulatorId == 'retroarch' ? 'citra/sysdata/aes_keys.txt' : 'sysdata/aes_keys.txt'}';
    return !await io.File(keysPath).exists();
  }

  /// Launches [game] via [strategy], returning the process handle (if any)
  /// and the session start time. Mirrors the exact launchWithHandle/launch
  /// fallback used previously in the UI layer — behavior-preserving.
  Future<GameSession> launch(
    Game game,
    String romPath,
    EmulatorStrategy strategy, {
    String? overrideCoreId,
  }) async {
    final sessionStart = DateTime.now();
    io.Process? process;
    if (strategy is RetroArchStrategy && overrideCoreId != null) {
      process = await strategy.launchWithHandle(game, romPath, coreName: overrideCoreId);
    } else {
      process = await strategy.launchWithHandle(game, romPath);
    }
    if (process == null) {
      await strategy.launch(game, romPath);
    }
    return GameSession(process: process, sessionStart: sessionStart, emulatorId: strategy.emulatorId);
  }

  /// Awaits the launched process's exit (no-op if [session.process] is
  /// null, i.e. the fire-and-forget `launch` path was used), then runs the
  /// post-exit pipeline: push saves, create a local backup, and report the
  /// play session to RomM (best-effort, non-fatal on failure).
  Future<LaunchResult?> awaitExitAndSync(
    GameSession session,
    Game game,
    String romPath, {
    required String syncMode,
    String? overrideCoreId,
  }) async {
    final process = session.process;
    if (process == null) return null;

    await process.exitCode;
    final sessionEnd = DateTime.now();

    final syncOk = await saveSyncService.pushSaves(
      game,
      romPath,
      sessionStart: session.sessionStart,
      syncMode: syncMode,
      coreOverride: overrideCoreId,
      emulatorId: session.emulatorId,
    );

    String? backupZipPath;
    try {
      final postBackup = await backupService.createImmediate(game, romPath, saveSyncService);
      if (postBackup != null) {
        await backupRepository.addEntry(
          game.id,
          BackupEntry(timestamp: DateTime.now(), md5Hash: postBackup.md5, localZipPath: postBackup.zipPath),
        );
        backupZipPath = postBackup.zipPath;
      }
    } catch (e) {
      dev.log('Post-exit backup failed', error: e);
    }

    var playSessionRecorded = false;
    try {
      if (rommService != null) {
        final caps = await rommService!.fetchCapabilities();
        if (caps.hasPlaySessionTracking) {
          final deviceId = prefs.getString('romm_device_id');
          if (deviceId != null) {
            await rommService!.recordPlaySession(
              romId: game.id,
              deviceId: deviceId,
              startTime: session.sessionStart,
              endTime: sessionEnd,
            );
            playSessionRecorded = true;
          }
        }
      }
    } catch (e) {
      dev.log('Play session record failed (non-fatal)', error: e);
    }

    return LaunchResult(syncOk: syncOk, backupZipPath: backupZipPath, playSessionRecorded: playSessionRecorded);
  }
}
