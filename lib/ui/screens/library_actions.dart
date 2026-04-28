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
import '../widgets/save_conflict_dialog.dart';
import '../../core/save/save_sync_service.dart';

mixin LibraryActionsMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  // These need to be implemented by the state class
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
        // Refresh the new background cache
        ref.read(downloadedGamesCacheProvider.notifier).refresh();
      });
    }
  }

  Future<void> handleLaunch(BuildContext context, WidgetRef ref, Game game) async {
    // Ensure strategy registry preferences are loaded
    final registryReady = await ref.read(strategyRegistryProvider.future);
    if (!context.mounted) return;
    if (registryReady == null) return;
    final strategy = registryReady.getStrategyForSlug(game.platformSlug ?? '');

    if (strategy == null) {
      ErrorHandler.showInfo(context, 'No Emulator', message: 'No emulator configured for ${game.platformDisplayName ?? game.platformSlug ?? 'this platform'}');
      return;
    }

    // Wait for save sync service to be ready (FutureProvider chain)
    final syncService = await ref.read(saveSyncServiceProvider.future);
    if (!context.mounted) return;

    final dir = await ref.read(directoryServiceProvider.future);
    if (!context.mounted) return;
    if (dir == null) {
      ErrorHandler.showInfo(context, 'Not Available', message: 'Storage service not available');
      return;
    }

    final existingRomPath = await dir.findExistingRomPath(game);
    final expectedRomPath = await dir.getRomFilePath(game);
    if (!context.mounted) return;

    if (existingRomPath == null) {
      if (!context.mounted) return;
      final shouldDownload = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ROM not found'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${game.name} is not downloaded yet.'),
              const SizedBox(height: 8),
              const Text('Expected location:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              SelectableText(
                expectedRomPath,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              const Text(
                'You can also manually place the ROM file there.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              const Text('Would you like to download it now?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Download'),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      if (shouldDownload == true) {
        startDownload(context, ref, game);
      }
      return;
    }

    String romPath = existingRomPath;
    bool isAutoDetected = await io.File(existingRomPath).exists();

    // Multi-disc picker logic
    if (game.hasMultipleFiles && game.files.isNotEmpty) {
      // If we already auto-detected a specific file (not a folder) that exists, skip the picker
      if (isAutoDetected && !await io.Directory(romPath).exists()) {
        debugPrint('[LibraryActions] Automatic detection found file: $romPath. Skipping picker.');
      } else {
        if (!context.mounted) return;
        String? selectedFilePath;
        await MultiDiscPicker.show(
          context,
          game: game,
          files: game.files,
          onSelect: (file) {
            selectedFilePath = file['full_path']?.toString() ?? file['file_name']?.toString();
          },
        );
        if (selectedFilePath == null) return; // user dismissed
        
        debugPrint('[LibraryActions] Raw selectedFilePath from RomM: $selectedFilePath');

        // SANITIZE: Multi-disc file paths from RomM might contain characters like ':'
        // We must sanitize them segment by segment to preserve path separators (folders)
        // while matching how DirectoryService stores them on disk (spaces instead of invalid chars, collapsed spaces)
        final segments = selectedFilePath!.split(RegExp(r'[/\\]'));
        final sanitizedSegments = segments.map((s) => 
          s.replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()
        ).toList();
        
        romPath = sanitizedSegments.join(io.Platform.isWindows ? '\\' : '/');
        
        if (!context.mounted) return;
        // Prefix with ROMs root if not absolute
        if (!romPath.startsWith('/') && !romPath.contains(':\\')) {
          final romsRoot = await dir.getRomsDirectory();
          romPath = p.join(romsRoot, romPath);
        }
      }
    }

    // FINAL VALIDATION: Ensure the path actually exists on disk before handing to emulator
    if (!await io.File(romPath).exists() && !await io.Directory(romPath).exists()) {
       debugPrint('[LibraryActions] ERROR: romPath does not exist on disk: $romPath');
       // One last try: if it has 'roms/' in path, try without it? Or vice-versa?
       // For now, show error to help debug
       if (context.mounted) {
         ErrorHandler.showInfo(context, 'File Not Found', message: 'The ROM was not found at the expected location. Please try downloading it again.');
       }
       return;
    }

    if (!context.mounted) return;
    if (syncService != null) {
      final syncMode = ref.read(retroarchSyncModeProvider);
      ErrorHandler.showInfo(context, 'Syncing Saves', message: 'Pushing saves for ${game.name}...');
      try {
        await syncService.pushSaves(game, romPath, syncMode: syncMode);
      } on SaveMappingRequiredException {
        if (!context.mounted) return;
        final strategy = syncService.getStrategyForSlug(game.platformSlug);
        if (strategy is EdenSaveStrategy || strategy is RyujinxSaveStrategy || strategy is AzaharSaveStrategy) {
          final selectedFolder = await showFolderMappingDialog(context, strategy);
          if (selectedFolder != null) {
            await syncService.saveMappedFolder(game.id, selectedFolder);
            if (context.mounted) {
              await syncService.pushSaves(game, romPath, syncMode: syncMode);
            }
          }
        }
      } on ProfileConflictException catch (e) {
        if (!context.mounted) return;
        final selectedProfile = await showProfileConflictDialog(context, e.profiles);
        if (selectedProfile != null) {
          await syncService.saveActiveProfile(selectedProfile);
          if (context.mounted) {
            await syncService.pushSaves(game, romPath, syncMode: syncMode);
          }
        }
      } on SaveConflictException catch (e) {
        if (!context.mounted) return;
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => SaveConflictDialog(conflict: e),
        );
        if (choice == 'local' && context.mounted) {
          await syncService.pushSaves(game, romPath, syncMode: syncMode, force: true);
        } else if (choice == 'cloud' && context.mounted) {
          await syncService.pullSave(game, romPath);
        }
      } catch (e) {
        // Ignore other push errors during launch to not block playing
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      try {
        final pulled = await syncService.pullSave(game, romPath);
        if (!context.mounted) return;
        if (pulled) {
          ErrorHandler.showSuccess(context, 'Save Synced', message: 'Cloud save restored');
        }
      } on SaveMappingRequiredException {
        if (!context.mounted) return;
        final strategy = syncService.getStrategyForSlug(game.platformSlug);
        if (strategy is EdenSaveStrategy || strategy is RyujinxSaveStrategy || strategy is AzaharSaveStrategy) {
          final selectedFolder = await showFolderMappingDialog(context, strategy);
          if (selectedFolder != null) {
            await syncService.saveMappedFolder(game.id, selectedFolder);
            if (context.mounted) {
              await syncService.pullSave(game, romPath);
            }
          }
        }
      } on ProfileConflictException catch (e) {
        if (!context.mounted) return;
        final selectedProfile = await showProfileConflictDialog(context, e.profiles);
        if (selectedProfile != null) {
          await syncService.saveActiveProfile(selectedProfile);
          if (context.mounted) {
            await syncService.pullSave(game, romPath);
          }
        }
      } catch (e) {
        if (!context.mounted) return;
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Save Sync Warning'),
            content: Text(
                '${e.toString().replaceAll('Exception: ', '')}\n\nYou can still play, but your cloud save will not be restored. After playing once, exit the game and sync saves manually.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Play Anyway'),
              ),
            ],
          ),
        );
        if (!context.mounted) return;
        if (shouldContinue != true) return;
      }
    }

    // Check for 3DS keys before starting
    final is3ds = [
      '3ds', 'n3ds', 'nintendo-3ds', 'nintendo3ds',
      'new-nintendo-3ds', 'new-nintendo-3ds-xl'
    ].contains(game.platformSlug?.toLowerCase());

    if (is3ds) {
      final systemDir = await dir.getEmulatorSystemDirectory(strategy.emulatorId);
      final keysSubPath = strategy.emulatorId == 'retroarch' ? 'citra/sysdata/aes_keys.txt' : 'sysdata/aes_keys.txt';
      final keysPath = '$systemDir/$keysSubPath';

      if (!await File(keysPath).exists()) {
        final prefs = ref.read(sharedPreferencesProvider);
        final shownOnce = prefs.getBool('shown_3ds_keys_warning') ?? false;
        if (!shownOnce && context.mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Missing 3DS Keys'),
              content: const Text('Note: Decrypted 3DS ROMs require aes_keys.txt in your emulator system folder to run correctly.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          await prefs.setBool('shown_3ds_keys_warning', true);
        }
      }
    }

    try {
      if (!context.mounted) return;
      ErrorHandler.showInfo(context, 'Launching', message: 'Launching ${game.name}...');

      // --- Safety Sandwich: pre-launch restore-point ---
      BackupResult? preBackup;
      if (syncService != null) {
        try {
          final backupService = ref.read(backupServiceProvider);
          final backupRepo = ref.read(backupRepositoryProvider);
          preBackup = await backupService.createImmediate(game, romPath, syncService);
          if (preBackup != null) {
            await backupRepo.addEntry(
              game.id,
              BackupEntry(
                timestamp: DateTime.now(),
                md5Hash: preBackup.md5,
                localZipPath: preBackup.zipPath,
              ),
            );
            debugPrint('[SafetySandwich] Pre-launch restore point created: ${preBackup.zipPath}');
          }
        } catch (e, st) {
          dev.log('Safety Sandwich pre-launch backup failed', error: e, stackTrace: st);
        }
      }

      Process? process = await strategy.launchWithHandle(game, romPath);
      if (!context.mounted) return;
      if (process == null) {
        // Fall back to regular launch if no process handle available
        await strategy.launch(game, romPath);
      } else {
        // Start background Future to handle process exit
        unawaited(Future.delayed(Duration.zero, () async {
          try {
            await process.exitCode;
            if (!context.mounted) return;

            ErrorHandler.showInfo(context, 'Syncing', message: 'Auto-syncing saves...');

            if (syncService != null) {
              final syncMode = ref.read(retroarchSyncModeProvider);
              await syncService.pushSaves(game, romPath, syncMode: syncMode);

              // --- Safety Sandwich: post-exit backup if save changed ---
              try {
                final backupService = ref.read(backupServiceProvider);
                final backupRepo = ref.read(backupRepositoryProvider);
                final postBackup = await backupService.createImmediate(game, romPath, syncService);
                if (postBackup != null && postBackup.md5 != preBackup?.md5) {
                  await backupRepo.addEntry(
                    game.id,
                    BackupEntry(
                      timestamp: DateTime.now(),
                      md5Hash: postBackup.md5,
                      localZipPath: postBackup.zipPath,
                    ),
                  );
                  debugPrint('[SafetySandwich] Post-exit backup saved: ${postBackup.zipPath}');
                } else if (postBackup != null) {
                  // No change — discard the redundant zip
                  final f = io.File(postBackup.zipPath);
                  if (await f.exists()) await f.delete();
                }
              } catch (e, st) {
                dev.log('Safety Sandwich post-exit backup failed', error: e, stackTrace: st);
              }
            }

            if (!context.mounted) return;
            ErrorHandler.showSuccess(context, 'Save Synced', message: 'Saves synced');
          } catch (e) {
            // Silently ignore errors in auto-sync / backup
          }
        }));
      }
    } catch (e) {
      if (!context.mounted) return;

      if (e is MissingRetroArchCoreException) {
        final shouldDownload = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('RetroArch Core Missing'),
            content: Text(
                'The core ${e.coreName} is required for this game but is not installed. Would you like Freegosy to download and install it automatically?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Install'),
              ),
            ],
          ),
        );
        if (shouldDownload == true && context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => const Center(child: CircularProgressIndicator()),
          );
          try {
            final raStrategy = strategy as RetroArchStrategy;
            final coresDir = File(e.corePath).parent.path;
            await raStrategy.downloadCore(e.coreName, coresDir, Dio());
            if (context.mounted) {
              Navigator.of(context).pop();
              await handleLaunch(context, ref, game);
            }
          } catch (err) {
            if (context.mounted) {
              Navigator.of(context).pop();
              ErrorHandler.showException(context, err, contextLabel: 'Download Core Failed');
            }
          }
        }
        return;
      }

      final isWindows =
          ['windows', 'pc', 'win'].contains(game.platformSlug?.toLowerCase() ?? '');
      final isMissingExe =
          e.toString().contains('No executable') || e.toString().contains('not found');
      if (isWindows && isMissingExe) {
        await handleWindowsConfig(context, ref, game);
      } else {
        ErrorHandler.showException(context, e, contextLabel: 'Launch Failed');
      }
    }
  }

  Future<void> handleWindowsConfig(
      BuildContext context, WidgetRef ref, Game game) async {
    final registry = ref.read(strategyRegistryProvider).asData?.value;
    final windowsStrategy =
        registry?.getStrategyForSlug(game.platformSlug ?? '') as WindowsStrategy?;
    final syncService = await ref.read(saveSyncServiceProvider.future);
      if (!context.mounted) return;
      final result = await showDialog<Map<String, String>>(
        context: context,
      builder: (ctx) => WindowsGameConfigDialog(
        game: game,
        currentExePath: windowsStrategy?.getExeOverride(game.id),
        currentSavePath:
            syncService?.windowsSaveStrategy.getManualOverride(game.id),
      ),
    );
    if (result == null) return;
    final exe = result['exe'] ?? '';
    final save = result['save'] ?? '';
    if (exe.isNotEmpty) {
      await windowsStrategy?.setExeOverride(game.id, exe);
    }
    if (save.isNotEmpty) {
      await syncService?.windowsSaveStrategy.setManualOverride(game.id, save);
    }
    if (!context.mounted) return;
    await handleLaunch(context, ref, game);
  }

  Future<void> handleDeleteRom(BuildContext context, WidgetRef ref, Game game) async {
    final dirService = ref.read(directoryServiceProvider).asData?.value;
    if (dirService == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete ROM?'),
        content: Text('Are you sure you want to delete the local files for ${game.name}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await dirService.deleteRom(game);
      if (!context.mounted) return;
      
      // Refresh the new background cache
      ref.read(downloadedGamesCacheProvider.notifier).refresh();
      
      if (!context.mounted) return;
      ErrorHandler.showSuccess(context, 'ROM Deleted', message: 'Local files for ${game.name} were removed.');
    } catch (e) {
      if (!context.mounted) return;
      ErrorHandler.showException(context, e, contextLabel: 'Delete Failed');
    }
  }

  Future<void> handlePushSaves(
      BuildContext context, WidgetRef ref, Game game) async {
    final syncService = await ref.read(saveSyncServiceProvider.future);
    if (!context.mounted) return;
    if (syncService == null) {
      ErrorHandler.showInfo(context, 'Sync Unavailable', message: 'Save sync not available');
      return;
    }

    final dir = ref.read(directoryServiceProvider).asData?.value;
    final romPath = dir != null ? await dir.getRomFilePath(game) : '';
    if (!context.mounted) return;
    final syncMode = ref.read(retroarchSyncModeProvider);

    try {
      if (!context.mounted) return;
      ErrorHandler.showInfo(context, 'Syncing', message: 'Uploading saves for ${game.name}...');
      final ok = await syncService.pushSaves(game, romPath, syncMode: syncMode, force: true);
      if (!context.mounted) return;
      if (ok) {
        ErrorHandler.showSuccess(context, 'Save Synced', message: 'Saves uploaded');
      } else {
        ErrorHandler.show(context, ErrorHandler.parse(Exception('No saves found'), context: 'Push Saves'));
      }
    } on SaveMappingRequiredException {
      if (!context.mounted) return;
      final strategy = syncService.getStrategyForSlug(game.platformSlug);
      final selectedFolder = await showFolderMappingDialog(context, strategy);
      if (selectedFolder != null) {
        await syncService.saveMappedFolder(game.id, selectedFolder);
        if (!context.mounted) return;
        // Retry
        return handlePushSaves(context, ref, game);
      }
    } on ProfileConflictException catch (e) {
      if (!context.mounted) return;
      final selectedProfile = await showProfileConflictDialog(context, e.profiles);
      if (selectedProfile != null) {
        await syncService.saveActiveProfile(selectedProfile);
        if (!context.mounted) return;
        return handlePushSaves(context, ref, game);
      }
    } on SaveConflictException catch (e) {
      if (!context.mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => SaveConflictDialog(conflict: e),
      );
      if (choice == 'local' && context.mounted) {
        await syncService.pushSaves(game, romPath, syncMode: syncMode, force: true);
        if (context.mounted) ErrorHandler.showSuccess(context, 'Sync Resolved', message: 'Local save uploaded');
      } else if (choice == 'cloud' && context.mounted) {
        await syncService.pullSave(game, romPath);
        if (context.mounted) ErrorHandler.showSuccess(context, 'Sync Resolved', message: 'Cloud save restored');
      }
    } catch (e) {
      if (!context.mounted) return;
      ErrorHandler.showException(context, e, contextLabel: 'Push Saves Error');
    }
  }

  Future<void> handlePullSaves(
      BuildContext context, WidgetRef ref, Game game) async {
    final syncService = await ref.read(saveSyncServiceProvider.future);
    if (!context.mounted) return;
    if (syncService == null) {
      ErrorHandler.showInfo(context, 'Sync Unavailable', message: 'Save sync not available');
      return;
    }

    final dir = ref.read(directoryServiceProvider).asData?.value;
    final romPath = dir != null ? await dir.getRomFilePath(game) : '';
    if (!context.mounted) return;

    try {
      if (!context.mounted) return;
      ErrorHandler.showInfo(context, 'Syncing', message: 'Fetching cloud saves for ${game.name}...');
      final saves = await syncService.getSavesForGame(game.id);
      if (!context.mounted) return;

      if (saves.isEmpty) {
        if (!context.mounted) return;
        ErrorHandler.showInfo(context, 'No Saves', message: 'No cloud saves found for this game.');
        return;
      }

      if (!context.mounted) return;
      final selectedSave = await showSaveSelectionDialog(context, saves);
      if (selectedSave == null) return;

      if (!context.mounted) return;
      ErrorHandler.showInfo(context, 'Syncing', message: 'Downloading selected save...');
      final ok = await syncService.pullSave(game, romPath, saveData: selectedSave);

      if (!context.mounted) return;
      if (ok) {
        ErrorHandler.showSuccess(context, 'Save Synced', message: 'Saves downloaded');
      } else {
        if (!context.mounted) return;
        ErrorHandler.showInfo(context, 'Retry Sync', message: 'Save appears unchanged. Retrying with force...');
        // Force pull by clearing the pull timestamp
        final prefs = ref.read(sharedPreferencesProvider);
        await prefs.remove('last_pull_${game.id}');
        if (context.mounted) {
          final retryOk = await syncService.pullSave(game, romPath, saveData: selectedSave);
          if (context.mounted) {
            if (retryOk) {
              ErrorHandler.showSuccess(context, 'Save Synced', message: 'Saves downloaded');
            } else {
              // Should not reach here if pullSave throws, but for safety:
              ErrorHandler.showInfo(context, 'Sync Incomplete', message: 'Save file was downloaded but the emulator strategy could not apply it.');
            }
          }
        }
      }
    } on SaveMappingRequiredException {
      if (!context.mounted) return;
      final strategy = syncService.getStrategyForSlug(game.platformSlug);
      final selectedFolder = await showFolderMappingDialog(context, strategy);
      if (selectedFolder != null) {
        await syncService.saveMappedFolder(game.id, selectedFolder);
        if (!context.mounted) return;
        // Retry
        return handlePullSaves(context, ref, game);
      }
    } on ProfileConflictException catch (e) {
      if (!context.mounted) return;
      final selectedProfile = await showProfileConflictDialog(context, e.profiles);
      if (selectedProfile != null) {
        await syncService.saveActiveProfile(selectedProfile);
        if (!context.mounted) return;
        return handlePullSaves(context, ref, game);
      }
    } catch (e) {
      if (!context.mounted) return;
      ErrorHandler.showException(context, e, contextLabel: 'Pull Saves Error');
    }
  }

  Future<Map<String, dynamic>?> showSaveSelectionDialog(BuildContext context, List<Map<String, dynamic>> saves) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Cloud Save'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: saves.length,
            itemBuilder: (context, index) {
              final save = saves[index];
              final fileName = save['file_name_no_ext'] ?? save['file_name'] ?? 'Unknown Save';
              final createdAtStr = save['created_at'] ?? save['updated_at'] ?? '';
              final createdAt = DateTime.tryParse(createdAtStr.toString());

              String subtitle = 'Unknown date';
              if (createdAt != null) {
                final diff = DateTime.now().difference(createdAt);
                if (diff.inDays > 0) {
                  subtitle = '${diff.inDays}d ago';
                } else if (diff.inHours > 0) {
                  subtitle = '${diff.inHours}h ago';
                } else if (diff.inMinutes > 0) {
                  subtitle = '${diff.inMinutes}m ago';
                } else {
                  subtitle = 'just now';
                }
              }

              return ListTile(
                title: Text(fileName.toString()),
                subtitle: Text(subtitle),
                onTap: () => Navigator.pop(context, save),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }


  Future<String?> showProfileConflictDialog(BuildContext context, List<Map<String, dynamic>> profiles) async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Multiple Profiles Detected'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Multiple save profiles have recent activity. Which one would you like to use?'),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final id = profile['id'] as String;
                    final lastActive = profile['newestFile'] as DateTime;
                    
                    final diff = DateTime.now().difference(lastActive);
                    String timeAgo;
                    if (diff.inDays > 0) {
                      timeAgo = '${diff.inDays}d ago';
                    } else if (diff.inHours > 0) {
                      timeAgo = '${diff.inHours}h ago';
                    } else if (diff.inMinutes > 0) {
                      timeAgo = '${diff.inMinutes}m ago';
                    } else {
                      timeAgo = 'just now';
                    }

                    return ListTile(
                      title: Text(id),
                      subtitle: Text('Last active: $timeAgo'),
                      onTap: () => Navigator.pop(context, id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<String?> showFolderMappingDialog(BuildContext context, dynamic strategy) async {
    final folders = await strategy.getAvailableSaveFolders();
    if (!context.mounted) return null;

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Save Folder'),
        content: SizedBox(
          width: double.maxFinite,
          child: folders.isEmpty
              ? const Text('No saves found. Launch the game in the emulator first.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: folders.length,
                  itemBuilder: (context, index) {
                    final folder = folders[index];
                    final name = folder['name'] as String;
                    final path = (folder['path'] ?? folder['name']) as String;
                    final date = folder['lastModified'] as DateTime;
                    
                    // Simple relative time string
                    final diff = DateTime.now().difference(date);
                    String timeAgo;
                    if (diff.inDays > 0) {
                      timeAgo = '${diff.inDays}d ago';
                    } else if (diff.inHours > 0) {
                      timeAgo = '${diff.inHours}h ago';
                    } else if (diff.inMinutes > 0) {
                      timeAgo = '${diff.inMinutes}m ago';
                    } else {
                      timeAgo = 'just now';
                    }

                    return ListTile(
                      title: Text(name),
                      subtitle: Text('Last played: $timeAgo'),
                      onTap: () => Navigator.pop(context, path),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
