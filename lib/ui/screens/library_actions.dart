import 'dart:async';
import 'dart:io';
import 'dart:io' as io;
import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/error/error_handler.dart';
import '../../providers/library_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/romm_provider.dart';
import '../../providers/shared_prefs_provider.dart';
import '../../providers/downloaded_games_cache_provider.dart';
import '../../core/storage/directory_service.dart';
import '../../core/romm/romm_models.dart';
import '../../core/save/save_strategy.dart';
import '../../core/save/backup_entry.dart';
import '../../core/save/backup_service.dart';
import '../../core/save/strategies/eden_save_strategy.dart';
import '../../core/save/strategies/ryujinx_save_strategy.dart';
import '../../core/save/strategies/azahar_save_strategy.dart';
import '../../core/emulator/strategies/windows_strategy.dart';
import '../../core/emulator/strategies/retroarch_strategy.dart';
import '../widgets/windows_game_config_dialog.dart';
import '../widgets/multi_disc_picker.dart';
import '../../core/save/save_sync_service.dart';
import './library_dialog_service.dart';

mixin LibraryActionsMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Map<String, bool> get downloadedStates;
  void refreshDownloadState(DirectoryService dirService, Game game);
  void refreshAllDownloadStates();

  void startDownload(BuildContext context, WidgetRef ref, Game game) {
    final service = ref.read(rommServiceProvider);
    if (service == null) {
      ErrorHandler.showInfo(context, 'Not Connected', message: 'Not connected to RomM');
      return;
    }
    final url = service.getDownloadUrl(game);
    final headers = <String, String>{'Authorization': service.authHeader};
    ref.read(downloadProvider.notifier).startDownload(game, url, headers: headers);
    if (context.mounted) {
      ErrorHandler.showInfo(context, 'Download Started', message: '${game.name} is downloading...');
    }
    final dirService = ref.read(directoryServiceProvider).asData?.value;
    if (dirService != null) {
      Future.delayed(const Duration(seconds: 2), () {
        ref.read(downloadedGamesCacheProvider.notifier).refresh();
      });
    }
  }

  Future<void> handleLaunch(BuildContext context, WidgetRef ref, Game game) async {
    final registryReady = await ref.read(strategyRegistryProvider.future);
    if (!context.mounted || registryReady == null) return;
    final strategy = registryReady.getStrategyForSlug(game.platformSlug ?? '');

    if (strategy == null) {
      ErrorHandler.showInfo(context, 'No Emulator', message: 'No emulator configured for ${game.platformDisplayName ?? game.platformSlug ?? 'this platform'}');
      return;
    }

    final syncService = await ref.read(saveSyncServiceProvider.future);
    if (!context.mounted) return;

    final dir = await ref.read(directoryServiceProvider.future);
    if (!context.mounted || dir == null) {
      ErrorHandler.showInfo(context, 'Not Available', message: 'Storage service not available');
      return;
    }

    final existingRomPath = await dir.findExistingRomPath(game);
    final expectedRomPath = await dir.getRomFilePath(game);
    if (!context.mounted) return;

    if (existingRomPath == null) {
      if (!context.mounted) return;
      final shouldDownload = await _showMissingRomDialog(context, game.name, expectedRomPath);
      if (context.mounted && shouldDownload == true) startDownload(context, ref, game);
      return;
    }

    String romPath = existingRomPath;
    bool isAutoDetected = await io.File(existingRomPath).exists();

    if (game.hasMultipleFiles && game.files.isNotEmpty) {
      if (isAutoDetected && !await io.Directory(romPath).exists()) {
        debugPrint('[LibraryActions] Automatic detection found file: $romPath. Skipping picker.');
      } else {
        if (!context.mounted) return;
        String? selectedFilePath;
        await MultiDiscPicker.show(context, game: game, files: game.files, onSelect: (file) {
          selectedFilePath = file['full_path']?.toString() ?? file['file_name']?.toString();
        });
        if (selectedFilePath == null) return;
        
        final segments = selectedFilePath!.split(RegExp(r'[/\\]'));
        final sanitizedSegments = segments.map((s) => s.replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()).toList();
        romPath = sanitizedSegments.join(io.Platform.isWindows ? '\\' : '/');
        
        if (!context.mounted) return;
        if (!romPath.startsWith('/') && !romPath.contains(':\\')) {
          final romsRoot = await dir.getRomsDirectory();
          romPath = p.join(romsRoot, romPath);
        }
      }
    }

    if (!await io.File(romPath).exists() && !await io.Directory(romPath).exists()) {
       if (context.mounted) ErrorHandler.showInfo(context, 'File Not Found', message: 'The ROM was not found at the expected location.');
       return;
    }

    if (!context.mounted) return;
    if (syncService != null) {
      final syncMode = ref.read(retroarchSyncModeProvider);
      ErrorHandler.showInfo(context, 'Syncing Saves', message: 'Pushing saves for ${game.name}...');
      try {
        await syncService.pushSaves(game, romPath, syncMode: syncMode);
      } catch (e) {
        if (context.mounted) await _handleSyncError(context, e, game, romPath, syncService, syncMode, push: true);
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      try {
        final pulled = await syncService.pullSave(game, romPath);
        if (context.mounted && pulled) ErrorHandler.showSuccess(context, 'Save Synced', message: 'Cloud save restored');
      } catch (e) {
        if (context.mounted) {
          final playAnyway = await _handleSyncError(context, e, game, romPath, syncService, 'both', push: false);
          if (playAnyway != true) return;
        }
      }
    }

    // Platform-specific checks (e.g. 3DS keys)
    if (['3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds', 'new-nintendo-3ds', 'new-nintendo-3ds-xl'].contains(game.platformSlug?.toLowerCase())) {
      final systemDir = await dir.getEmulatorSystemDirectory(strategy.emulatorId);
      final keysPath = '$systemDir/${strategy.emulatorId == 'retroarch' ? 'citra/sysdata/aes_keys.txt' : 'sysdata/aes_keys.txt'}';
      if (!await File(keysPath).exists()) {
        final prefs = ref.read(sharedPreferencesProvider);
        if (!(prefs.getBool('shown_3ds_keys_warning') ?? false) && context.mounted) {
          await showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Missing 3DS Keys'), content: const Text('Note: Decrypted 3DS ROMs require aes_keys.txt in your emulator system folder.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]));
          await prefs.setBool('shown_3ds_keys_warning', true);
        }
      }
    }

    try {
      if (!context.mounted) return;
      ErrorHandler.showInfo(context, 'Launching', message: 'Launching ${game.name}...');

      BackupResult? preBackup;
      if (syncService != null) {
        try {
          final backupService = ref.read(backupServiceProvider);
          preBackup = await backupService.createImmediate(game, romPath, syncService);
          if (preBackup != null) await ref.read(backupRepositoryProvider).addEntry(game.id, BackupEntry(timestamp: DateTime.now(), md5Hash: preBackup.md5, localZipPath: preBackup.zipPath));
        } catch (e) { dev.log('Pre-launch backup failed', error: e); }
      }

      Process? process = await strategy.launchWithHandle(game, romPath);
      if (!context.mounted) return;
      if (process == null) await strategy.launch(game, romPath);
      else {
        unawaited(Future.delayed(Duration.zero, () async {
          try {
            await process.exitCode;
            if (!context.mounted) return;
            ErrorHandler.showInfo(context, 'Syncing', message: 'Auto-syncing saves...');
            if (syncService != null) {
              final syncMode = ref.read(retroarchSyncModeProvider);
              final ok = await syncService.pushSaves(game, romPath, syncMode: syncMode);
              try {
                final backupService = ref.read(backupServiceProvider);
                final postBackup = await backupService.createImmediate(game, romPath, syncService);
                if (postBackup != null && postBackup.md5 != preBackup?.md5) {
                  await ref.read(backupRepositoryProvider).addEntry(game.id, BackupEntry(timestamp: DateTime.now(), md5Hash: postBackup.md5, localZipPath: postBackup.zipPath));
                } else if (postBackup != null) {
                  final f = io.File(postBackup.zipPath);
                  if (await f.exists()) await f.delete();
                }
              } catch (e) { dev.log('Post-exit backup failed', error: e); }
              if (context.mounted) {
                if (ok) ErrorHandler.showSuccess(context, 'Save Synced', message: 'Saves synced');
                else ErrorHandler.showSuccess(context, 'Up to Date', message: 'No files to upload');
              }
            }
          } catch (_) {}
        }));
      }
    } catch (e) {
      if (!context.mounted) return;
      if (e is MissingRetroArchCoreException) {
        final shouldInstall = await _showMissingCoreDialog(context, e.coreName);
        if (shouldInstall == true && context.mounted) {
          showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator()));
          try {
            await (strategy as RetroArchStrategy).downloadCore(e.coreName, File(e.corePath).parent.path, Dio());
            if (context.mounted) { Navigator.pop(context); await handleLaunch(context, ref, game); }
          } catch (err) { if (context.mounted) { Navigator.pop(context); ErrorHandler.showException(context, err, contextLabel: 'Download Core Failed'); } }
        }
      } else if ((['windows', 'pc', 'win'].contains(game.platformSlug?.toLowerCase() ?? '')) && (e.toString().contains('No executable') || e.toString().contains('not found'))) {
        await handleWindowsConfig(context, ref, game);
      } else { ErrorHandler.showException(context, e, contextLabel: 'Launch Failed'); }
    }
  }

  Future<void> handleWindowsConfig(BuildContext context, WidgetRef ref, Game game) async {
    final registry = ref.read(strategyRegistryProvider).asData?.value;
    final windowsStrategy = registry?.getStrategyForSlug(game.platformSlug ?? '') as WindowsStrategy?;
    final syncService = await ref.read(saveSyncServiceProvider.future);
    if (!context.mounted) return;
    final result = await showDialog<Map<String, String>>(context: context, builder: (ctx) => WindowsGameConfigDialog(game: game, currentExePath: windowsStrategy?.getExeOverride(game.id), currentSavePath: syncService?.windowsSaveStrategy.getManualOverride(game.id)));
    if (result == null) return;
    if (result['exe']?.isNotEmpty ?? false) await windowsStrategy?.setExeOverride(game.id, result['exe']!);
    if (result['save']?.isNotEmpty ?? false) await syncService?.windowsSaveStrategy.setManualOverride(game.id, result['save']!);
    if (context.mounted) await handleLaunch(context, ref, game);
  }

  Future<void> handleDeleteRom(BuildContext context, WidgetRef ref, Game game) async {
    final dirService = ref.read(directoryServiceProvider).asData?.value;
    if (dirService == null) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Delete ROM?'), content: Text('Are you sure you want to delete the local files for ${game.name}?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
    if (confirmed != true) return;
    try {
      await dirService.deleteRom(game);
      ref.read(downloadedGamesCacheProvider.notifier).refresh();
      if (context.mounted) ErrorHandler.showSuccess(context, 'ROM Deleted', message: 'Local files removed.');
    } catch (e) { if (context.mounted) ErrorHandler.showException(context, e, contextLabel: 'Delete Failed'); }
  }

  Future<void> handlePushSaves(BuildContext context, WidgetRef ref, Game game) async {
    final syncService = await ref.read(saveSyncServiceProvider.future);
    if (!context.mounted || syncService == null) { ErrorHandler.showInfo(context, 'Sync Unavailable', message: 'Save sync not available'); return; }
    final dir = ref.read(directoryServiceProvider).asData?.value;
    final romPath = dir != null ? await dir.getRomFilePath(game) : '';
    if (!context.mounted) return;
    final syncMode = ref.read(retroarchSyncModeProvider);
    try {
      ErrorHandler.showInfo(context, 'Syncing', message: 'Uploading saves for ${game.name}...');
      final ok = await syncService.pushSaves(game, romPath, syncMode: syncMode, force: true);
      if (context.mounted) {
        if (ok) ErrorHandler.showSuccess(context, 'Save Synced', message: 'Saves uploaded');
        else ErrorHandler.showSuccess(context, 'Up to Date', message: 'No files to upload');
      }
    } catch (e) { if (context.mounted) await _handleSyncError(context, e, game, romPath, syncService, syncMode, push: true); }
  }

  Future<void> handlePullSaves(BuildContext context, WidgetRef ref, Game game) async {
    final syncService = await ref.read(saveSyncServiceProvider.future);
    if (!context.mounted || syncService == null) { ErrorHandler.showInfo(context, 'Sync Unavailable', message: 'Save sync not available'); return; }
    final dir = ref.read(directoryServiceProvider).asData?.value;
    final romPath = dir != null ? await dir.getRomFilePath(game) : '';
    if (!context.mounted) return;
    try {
      ErrorHandler.showInfo(context, 'Syncing', message: 'Fetching cloud saves...');
      final saves = await syncService.getSavesForGame(game.id);
      if (!context.mounted) return;
      if (saves.isEmpty) { ErrorHandler.showInfo(context, 'No Saves', message: 'No cloud saves found.'); return; }
      final selectedSave = await LibraryDialogService.showSaveSelectionDialog(context, saves);
      if (selectedSave == null || !context.mounted) return;
      ErrorHandler.showInfo(context, 'Syncing', message: 'Downloading selected save...');
      final ok = await syncService.pullSave(game, romPath, saveData: selectedSave);
      if (context.mounted) {
        if (ok) ErrorHandler.showSuccess(context, 'Save Synced', message: 'Saves downloaded');
        else {
          ErrorHandler.showInfo(context, 'Retry Sync', message: 'Save unchanged. Retrying with force...');
          await ref.read(sharedPreferencesProvider).remove('last_pull_${game.id}');
          if (context.mounted) {
            final retryOk = await syncService.pullSave(game, romPath, saveData: selectedSave);
            if (context.mounted) {
              if (retryOk) ErrorHandler.showSuccess(context, 'Save Synced', message: 'Saves downloaded');
              else ErrorHandler.showInfo(context, 'Sync Incomplete', message: 'Save applied but strategy failed.');
            }
          }
        }
      }
    } catch (e) { if (context.mounted) await _handleSyncError(context, e, game, romPath, syncService, 'both', push: false); }
  }

  Future<dynamic> _handleSyncError(BuildContext context, dynamic e, Game game, String romPath, SaveSyncService syncService, String syncMode, {required bool push}) async {
    if (e is SaveMappingRequiredException) {
      final strategy = syncService.getStrategyForSlug(game.platformSlug);
      final selectedFolder = await LibraryDialogService.showFolderMappingDialog(context, strategy);
      if (selectedFolder != null) {
        await syncService.saveMappedFolder(game.id, selectedFolder);
        if (context.mounted) return push ? handlePushSaves(context, ref, game) : handlePullSaves(context, ref, game);
      }
    } else if (e is ProfileConflictException) {
      final selectedProfile = await LibraryDialogService.showProfileConflictDialog(context, e.profiles);
      if (selectedProfile != null) {
        await syncService.saveActiveProfile(selectedProfile);
        if (context.mounted) return push ? handlePushSaves(context, ref, game) : handlePullSaves(context, ref, game);
      }
    } else if (e is SaveConflictException) {
      final choice = await LibraryDialogService.showSaveConflictDialog(context, e);
      if (choice == 'local' && context.mounted) {
        await syncService.pushSaves(game, romPath, syncMode: syncMode, force: true);
        if (context.mounted) ErrorHandler.showSuccess(context, 'Sync Resolved', message: 'Local save uploaded');
      } else if (choice == 'cloud' && context.mounted) {
        await syncService.pullSave(game, romPath);
        if (context.mounted) ErrorHandler.showSuccess(context, 'Sync Resolved', message: 'Cloud save restored');
      }
    } else if (!push) {
       return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Save Sync Warning'), content: Text('${e.toString().replaceAll('Exception: ', '')}\n\nPlay anyway?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Play Anyway'))]));
    } else { ErrorHandler.showException(context, e, contextLabel: push ? 'Push Saves Error' : 'Pull Saves Error'); }
    return null;
  }

  Future<bool?> _showMissingRomDialog(BuildContext context, String gameName, String expectedPath) {
    return showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('ROM not found'), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$gameName is not downloaded yet.'), const SizedBox(height: 8), const Text('Expected location:', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), SelectableText(expectedPath, style: const TextStyle(fontSize: 12, color: Colors.grey)), const SizedBox(height: 12), const Text('Download now?')]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Download'))]));
  }

  Future<bool?> _showMissingCoreDialog(BuildContext context, String coreName) {
    return showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('RetroArch Core Missing'), content: Text('The core $coreName is required. Download and install it automatically?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Install'))]));
  }
}
