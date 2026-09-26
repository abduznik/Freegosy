import 'dart:async';
import 'dart:io';
import 'dart:io' as io;
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/error/error_handler.dart';
import '../../core/platform/platform_info.dart';
import '../../providers/library_provider.dart';
import '../../providers/ui_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/romm_provider.dart';
import '../../core/romm/romm_service.dart';
import '../../providers/shared_prefs_provider.dart';
import '../../providers/downloaded_games_cache_provider.dart';
import '../../core/storage/directory_service.dart';
import '../../core/romm/romm_models.dart';
import '../../core/save/save_strategy.dart';
import '../../core/save/strategies/eden_save_strategy.dart';
import '../../core/save/strategies/ryujinx_save_strategy.dart';
import '../../core/save/strategies/azahar_save_strategy.dart';
import '../../core/emulator/strategies/windows_strategy.dart';
import '../../core/emulator/emulator_strategy.dart';
import '../../core/emulator/game_launch_service.dart' show LaunchResult;
import '../../core/emulator/strategies/retroarch_strategy.dart';
import '../widgets/retroarch_core_picker_dialog.dart';
import '../widgets/windows_game_config_dialog.dart';
import '../widgets/multi_disc_picker.dart';
import '../../core/save/save_sync_service.dart';
import '../../core/save/state_sync_service.dart';
import '../../core/save/resume_service.dart';
import '../../providers/resume_provider.dart';
import './library_dialog_service.dart';
import '../widgets/focus_effect_wrapper.dart';
import '../widgets/state_version_dialog.dart';

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

    // Multi-file game: show selection dialog
    if (game.hasMultipleFiles && game.files.isNotEmpty) {
      _showMultiFileDownloadDialog(context, ref, game, service);
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

  void _showMultiFileDownloadDialog(BuildContext context, WidgetRef ref, Game game, RommService service) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Multi-File Game'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${game.name} has ${game.files.length} files:',
              style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            ...game.files.take(5).map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• ${f['file_name'] ?? 'Unknown'}',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            )),
            if (game.files.length > 5)
              Text(
                '...and ${game.files.length - 5} more',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadAllFiles(context, ref, game, service);
            },
            child: const Text('Download All'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showFileSelectionDialog(context, ref, game, service);
            },
            child: const Text('Select Files'),
          ),
        ],
      ),
    );
  }

  void _downloadAllFiles(BuildContext context, WidgetRef ref, Game game, RommService service) {
    final url = service.getDownloadUrl(game);
    final headers = <String, String>{'Authorization': service.authHeader};
    ref.read(downloadProvider.notifier).startDownload(game, url, headers: headers);
    if (context.mounted) {
      ErrorHandler.showInfo(context, 'Download Started', message: 'Downloading all files for ${game.name}...');
    }
  }

  void _showFileSelectionDialog(BuildContext context, WidgetRef ref, Game game, RommService service) {
    final selectedFiles = <int>{};
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Select Files'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select which files to download:',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                ...game.files.asMap().entries.map((entry) {
                  final i = entry.key;
                  final file = entry.value;
                  final isSelected = selectedFiles.contains(i);
                  final sizeMB = ((file['file_size_bytes'] ?? 0) / (1024 * 1024)).toStringAsFixed(1);
                  return CheckboxListTile(
                    dense: true,
                    value: isSelected,
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) {
                          selectedFiles.add(i);
                        } else {
                          selectedFiles.remove(i);
                        }
                      });
                    },
                    title: Text(
                      file['file_name'] ?? 'Unknown',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '$sizeMB MB',
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedFiles.isEmpty
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _downloadSelectedFiles(context, ref, game, service, selectedFiles.toList());
                    },
              child: Text('Download ${selectedFiles.length} File${selectedFiles.length == 1 ? '' : 's'}'),
            ),
          ],
        ),
      ),
    );
  }

  void _downloadSelectedFiles(BuildContext context, WidgetRef ref, Game game, RommService service, List<int> fileIndices) {
    final headers = <String, String>{'Authorization': service.authHeader};
    final baseUrl = service.config.baseUrl;

    for (final i in fileIndices) {
      final file = game.files[i];
      final fileName = file['file_name'] ?? '';
      if (fileName.isEmpty) continue;

      final encoded = Uri.encodeComponent(fileName);
      final url = '$baseUrl/api/roms/${game.id}/content/$encoded';

      // Create a temporary game-like object for the download
      final tempGame = Game(
        id: '${game.id}_$i',
        name: fileName,
        fileSize: file['file_size_bytes'] ?? 0,
        platformSlug: game.platformSlug,
        hasMultipleFiles: false,
      );

      ref.read(downloadProvider.notifier).startDownload(tempGame, url, headers: headers);
    }

    if (context.mounted) {
      ErrorHandler.showInfo(
        context,
        'Download Started',
        message: 'Downloading ${fileIndices.length} file${fileIndices.length == 1 ? '' : 's'} for ${game.name}...',
      );
    }
  }

  Future<void> handleLaunch(BuildContext context, WidgetRef ref, Game game, {ResumeEntry? resume}) async {
    debugPrint('[Launch] Starting launch for: ${game.name} (id: ${game.id})');
    debugPrint('[Launch] Platform: ${game.platformSlug}, hasMultipleFiles: ${game.hasMultipleFiles}, files: ${game.files.length}');

    final registryReady = await ref.read(strategyRegistryProvider.future);
    if (!context.mounted || registryReady == null) return;

    EmulatorStrategy? strategy;
    String? overrideCoreId;

    if (resume != null) {
      // Resume starts the emulator that owns the state: no picker, no preference.
      strategy = registryReady.getStrategyById(resume.emulatorId);
      debugPrint('[Resume] resume ${game.name}: ${resume.slot.label} ${resume.fileName} '
          '(emulator ${resume.emulatorId}, where ${resume.where.name})');
      if (strategy == null) {
        ErrorHandler.showInfo(context, 'Not Available', message: "${resume.emulatorName} isn't set up.");
        return;
      }
    } else {
      // Check per-game emulator preference first
      final gamePrefEmulator = registryReady.getGameEmulatorPreference(game.id);
      final gamePrefCore = registryReady.getGameCorePreference(game.id);
      debugPrint('[Launch] Per-game preference: emulator=$gamePrefEmulator, core=$gamePrefCore');

      if (gamePrefEmulator != null) {
        // Use saved per-game preference
        strategy = registryReady.getStrategyById(gamePrefEmulator);
        overrideCoreId = gamePrefCore;
      } else {
        // Check if platform has multiple emulator options
        final allStrategies = registryReady.getAllStrategiesForSlug(game.platformSlug ?? '');
        final perGameEnabled = ref.read(perGameLauncherEnabledProvider);

        if (allStrategies.length > 1 && perGameEnabled && context.mounted) {
          // Per-game picker enabled — show dialog
          final choice = await RetroArchCorePickerDialog.show(
            context,
            game: game,
            availableStrategies: allStrategies,
            registry: registryReady,
          );
          if (choice == null) return; // cancelled

          strategy = registryReady.getStrategyById(choice.emulatorId);
          overrideCoreId = choice.coreId;

          // Save preference if "remember" was checked
          if (choice.remember) {
            await registryReady.setGameEmulatorPreference(game.id, choice.emulatorId);
            if (choice.coreId != null) {
              await registryReady.setGameCorePreference(game.id, choice.coreId!);
            }
            ref.read(gamePreferenceVersionProvider.notifier).state++;
          }
        } else {
          strategy = registryReady.getStrategyForSlug(game.platformSlug ?? '');
        }
      }
    }

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

    final launchService = await ref.read(gameLaunchServiceProvider.future);
    if (!context.mounted || launchService == null) {
      ErrorHandler.showInfo(context, 'Not Available', message: 'Launch service not available');
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

    // A save state belongs to one disc (its serial): a resume boots exactly the
    // ROM file the state was identified with, so no disc/file picker is shown.
    final resumeRomPath = resume?.romPath;
    final resumeUsesItsOwnRom = resumeRomPath != null && await io.File(resumeRomPath).exists();
    if (resumeUsesItsOwnRom) {
      romPath = resumeRomPath;
      debugPrint('[Resume] booting the ROM the state belongs to: $romPath');
    }

    // If romPath is a directory, scan for disc files and show picker if multiple found.
    // This handles cases where RomM doesn't set hasMultipleFiles correctly
    // (e.g. GameCube multidisc with .m3u).
    if (!resumeUsesItsOwnRom && !game.hasMultipleFiles && await io.Directory(existingRomPath).exists()) {
      debugPrint('[Launch] romPath is a directory: $existingRomPath');
      final discFiles = await launchService.scanForDiscFiles(existingRomPath);
      debugPrint('[Launch] Scan complete: ${discFiles.length} disc files');
      // Show picker if multiple launchable files found (including .m3u playlists)
      if (discFiles.length > 1) {
        debugPrint('[Launch] Multi-disc detected (${discFiles.length} files), showing picker');
        if (!context.mounted) return;
        String? selectedFilePath;
        await MultiDiscPicker.show(context, game: game, files: discFiles, onSelect: (file) {
          selectedFilePath = file['file_name']?.toString();
        });
        if (selectedFilePath == null) return;
        romPath = p.join(existingRomPath, selectedFilePath);
        debugPrint('[Launch] Resolved romPath: $romPath');
      }
    }

    if (!resumeUsesItsOwnRom && game.hasMultipleFiles) {
      debugPrint('[Launch] Multi-file game detected, fetching/filtering launchable files...');
      final result = await launchService.launchableFilesFor(game);
      final files = result.files;
      final launchableFiles = result.launchableFiles;
      debugPrint('[Launch] Launchable files: ${launchableFiles.length} (from ${files.length} total)');

      if (files.isNotEmpty) {
        if (launchableFiles.isEmpty) {
          // All files are non-launchable, try using the ROM path directly
          debugPrint('[Launch] All files non-launchable, using romPath: $romPath');
        } else if (isAutoDetected && !await io.Directory(romPath).exists()) {
          debugPrint('[Launch] Automatic detection found file: $romPath. Skipping picker.');
        } else {
          debugPrint('[Launch] Showing multi-file picker with ${launchableFiles.length} files...');
          if (!context.mounted) return;
          String? selectedFilePath;
          await MultiDiscPicker.show(context, game: game, files: launchableFiles, onSelect: (file) {
            // Use file_name for the actual filename, not full_path which includes platform prefix
            selectedFilePath = file['file_name']?.toString();
            debugPrint('[Launch] User selected file: $selectedFilePath');
          });
          if (selectedFilePath == null) {
            debugPrint('[Launch] User cancelled file selection');
            return;
          }
          
          // The selected file is relative to the game's directory (existingRomPath)
          // existingRomPath is already the correct directory on disk
          romPath = p.join(existingRomPath, selectedFilePath);
          debugPrint('[Launch] Resolved romPath: $romPath');
        }
      } else {
        debugPrint('[Launch] No files available for multi-file game, using romPath: $romPath');
      }
    }

    // If romPath points to a directory try to find the actual rom inside it, unless platform is windows (folder based games)
    if (await io.Directory(romPath).exists()) {
      debugPrint('[Launch] Searching for a valid rom in: $romPath');
      romPath = await launchService.resolveRomFileInDirectory(romPath, game.platformSlug);
      debugPrint('[Launch] Resolved: $romPath');
    }


    if (!await io.File(romPath).exists() && !await io.Directory(romPath).exists()) {
       if (context.mounted) ErrorHandler.showInfo(context, 'File Not Found', message: 'The ROM was not found at the expected location.');
       return;
    }

    if (!context.mounted) return;

    // Save states: pull before launch and AWAIT it (unlike the save pull below)
    // so a conflict dialog can still influence what the user is about to play.
    // Never blocks on failure: a network error just launches with local states,
    // and nothing in here (not even resolving the service) can abort the launch.
    // An offline RomM skips the pull altogether so launching stays instant; the
    // service also bounds its list call, for a server that is up but not answering.
    // The pull's result (null when none ran) tells a resume whether its state
    // was brought down or was a conflict the user just settled.
    StateSyncResult? statePull;
    try {
      final stateSync = await ref.read(stateSyncServiceProvider.future);
      if (!context.mounted) return;
      if (stateSync != null && stateSync.isAvailableFor(game, emulatorId: strategy.emulatorId)) {
        if (_rommOffline(ref)) {
          debugPrint('[StateSync] RomM is offline — skipping the pre-launch state pull');
        } else {
          ErrorHandler.showInfo(context, 'Syncing', message: 'Checking save states...');
          final pull = await stateSync.pullStates(game, romPath, emulatorId: strategy.emulatorId, priority: resume?.fileName);
          statePull = pull;
          if (context.mounted) await _resolveStateConflicts(context, stateSync, pull.conflicts);
        }
      } else {
        debugPrint('[StateSync] not running for ${game.name}: '
            '${_stateSyncUnavailableReason(stateSync, game, emulatorId: strategy.emulatorId)}');
      }
    } catch (e) {
      debugPrint('[StateSync] Pre-launch pull failed: $e');
    }
    if (!context.mounted) return;

    String? loadStatePath;
    String? staleResumeNotice;
    if (resume != null) {
      final resumeService = await ref.read(resumeServiceProvider.future);
      if (!context.mounted) return;
      final check = resumeService == null
          ? const ResumeMissing()
          : await resumeService.checkBeforeLaunch(resume, game, romPath,
              pulled: statePull?.currentFiles,
              conflicted: statePull?.conflicts.map((c) => c.fileName).toSet());
      if (!context.mounted) return;
      switch (check) {
        case ResumeMissing():
          ErrorHandler.showInfo(context, 'Resume failed',
              message: resumeMissingMessage(resume, serviceAvailable: resumeService != null));
          return;
        case ResumeReady(:final path, :final stale, :final prompt):
          if (prompt != null) {
            final load = await showStateVersionDialog(context,
                slotLabel: resume.slot.label,
                emulatorName: resume.emulatorName,
                stateVersion: prompt.stateVersion,
                installed: prompt.installed);
            if (!load || !context.mounted) return;
          }
          if (stale) {
            // A separate toast here would be cleared almost immediately by the
            // 'Launching' toast below (ErrorHandler.show clears prior snack
            // bars); fold the notice into that one instead so it's seen.
            staleResumeNotice =
                "Couldn't update ${resume.slot.label} from RomM. Loading the copy on this PC.";
            debugPrint('[Resume] ${resume.fileName} is stale: newer RomM copy did not arrive, loading the local copy');
          }
          debugPrint('[Resume] will load $path');
          loadStatePath = path;
      }
    }

    // Pull save in background — don't block the launch.
    // Previously, the save pull was a blocking await (10-15s of HTTP requests
    // before the emulator started). Now it's fire-and-forget: the save is
    // usually already on disk from the last session, and the pull cooldown
    // (60s) prevents redundant network requests on rapid re-launches.
    // The actual save sync happens post-exit in the unawaited block below.
    if (syncService != null) {
      debugPrint('[SaveSync] Auto-pulling save before launch: game="${game.displayName}"');
      // Snapshot the current local save before overwriting it — the pull
      // path used to rely on Pcsx2SaveStrategy's per-file .bak rotation for
      // this, but that was removed because leaving .bak files inside a
      // PCSX2 folder-type memcard made PCSX2 itself refuse to save (issue
      // discovered testing #98). This restores a safety net without
      // reintroducing files inside the emulator-managed folder.
      final backupService = ref.read(backupServiceProvider);
      final resolvedEmulatorId = strategy.emulatorId;
      unawaited(
        backupService
            .createImmediate(game, romPath, syncService, emulatorId: resolvedEmulatorId)
            .then((_) => syncService.pullSave(game, romPath, coreOverride: overrideCoreId, emulatorId: resolvedEmulatorId))
            .catchError((_) => false),
      );
    }

    // Platform-specific checks (e.g. 3DS keys)
    if (await launchService.needs3dsKeysWarning(game, strategy)) {
      final prefs = ref.read(sharedPreferencesProvider);
      if (!(prefs.getBool('shown_3ds_keys_warning') ?? false) && context.mounted) {
        await showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Missing 3DS Keys'), content: const Text('Note: Decrypted 3DS ROMs require aes_keys.txt in your emulator system folder.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]));
        await prefs.setBool('shown_3ds_keys_warning', true);
      }
    }

    try {
      if (!context.mounted) return;
      debugPrint('[Launch] Strategy: ${strategy.name}, ROM: $romPath');
      ErrorHandler.showInfo(context, 'Launching',
          message: staleResumeNotice ?? 'Launching ${game.name}...');

      final session = await launchService.launch(game, romPath, strategy, overrideCoreId: overrideCoreId, loadStatePath: loadStatePath);
      if (!context.mounted) return;
      if (session.process != null && syncService != null) {
        final syncMode = ref.read(retroarchSyncModeProvider);
        unawaited(Future.delayed(Duration.zero, () async {
          try {
            debugPrint('[SaveSync] Auto-pushing saves after exit: game="${game.displayName}" syncMode=$syncMode');
            // The resume list is refreshed as soon as the emulator exits (the
            // states it just wrote), and again once the pipeline is over,
            // even if it throws (what the push changed on RomM).
            final LaunchResult? result;
            try {
              result = await launchService.awaitExitAndSync(
                session, game, romPath,
                syncMode: syncMode,
                overrideCoreId: overrideCoreId,
                onExited: () => ref.invalidate(resumeEntriesProvider),
              );
            } finally {
              ref.invalidate(resumeEntriesProvider);
            }
            if (!context.mounted || result == null) return;
            if (result.syncOk) ErrorHandler.showSuccess(context, 'Save Synced', message: 'Saves synced');
            else ErrorHandler.showSuccess(context, 'Up to Date', message: 'No files to upload');
            if (result.stateConflictCount > 0) {
              ErrorHandler.showWithAction(context, 'Save State Conflict',
                  message: '${result.stateConflictCount} save state(s) changed on both this PC and RomM. Press Resolve to choose which copy to keep.',
                  severity: ErrorSeverity.warning,
                  actionLabel: 'Resolve',
                  onAction: () {
                    if (context.mounted) handleSyncStates(context, ref, game);
                  });
            }
          } catch (_) {}
        }));
      }
    } catch (e) {
      // Log unconditionally before the mounted check — otherwise a widget
      // unmounted by the time the exception surfaces (e.g. window/focus
      // lifecycle quirks on Steam Deck) silently drops the failure with no
      // toast and no debug log entry. See issue #84.
      debugPrint('[Launch] Launch failed: $e');
      if (!context.mounted) return;
      if (e is MissingRetroArchCoreException) {
        final shouldInstall = await _showMissingCoreDialog(context, e.coreName);
        if (shouldInstall == true && context.mounted) {
          showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator()));
          try {
            await (strategy as RetroArchStrategy).downloadCore(e.coreName, File(e.corePath).parent.path, Dio());
            if (context.mounted) { Navigator.pop(context); await handleLaunch(context, ref, game, resume: resume); }
          } catch (err) { if (context.mounted) { Navigator.pop(context); ErrorHandler.showException(context, err, contextLabel: 'Download Core Failed'); } }
        }
      } else if ((['windows', 'pc', 'win'].contains(game.platformSlug?.toLowerCase() ?? '')) && (e.toString().contains('No executable') || e.toString().contains('not found'))) {
        await handleWindowsConfig(context, ref, game, fromError: true);
      } else { ErrorHandler.showException(context, e, contextLabel: 'Launch Failed'); }
    }
  }

  Future<void> handleWindowsConfig(BuildContext context, WidgetRef ref, Game game, {bool fromError = false}) async {
    final registry = ref.read(strategyRegistryProvider).asData?.value;
    final windowsStrategy = registry?.getStrategyForSlug(game.platformSlug ?? '') as WindowsStrategy?;
    final syncService = await ref.read(saveSyncServiceProvider.future);
    if (!context.mounted) return;
    final currentArgs = windowsStrategy?.getLaunchArgs(game.id).join(' ') ?? '';
    final currentFilter = syncService?.windowsSaveStrategy.getSaveFilter(game.id) ?? '';
    final currentWikiFilter = syncService?.windowsSaveStrategy.getWikiSaveFilter(game.id) ?? '';
    final currentWikiSavePath = syncService?.windowsSaveStrategy.getPcGamingWikiSavePath(game.id) ?? '';
    final result = await showDialog<Map<String, String>>(context: context, builder: (ctx) => WindowsGameConfigDialog(game: game, directoryService: ref.read(directoryServiceProvider).value, currentExePath: windowsStrategy?.getExeOverride(game.id), currentSavePath: syncService?.windowsSaveStrategy.getManualOverride(game.id), currentWikiSavePath: currentWikiSavePath, currentLaunchArgs: currentArgs, currentSaveFilter: currentFilter, currentWikiFileFilter: currentWikiFilter));
    if (result == null) return;
    if (result['exe']?.isNotEmpty ?? false) await windowsStrategy?.setExeOverride(game.id, result['exe']!);
    await syncService?.windowsSaveStrategy.setManualOverride(game.id, result['save']!);
    await syncService?.windowsSaveStrategy.setPcGamingWikiSavePath(game.id, result['wikiSavePath']!);
    final filter = result['filter'] ?? '';
    final wikiFilter = result['wikiFilter'] ?? '';
    await syncService?.windowsSaveStrategy.setSaveFilter(game.id, filter);
    await syncService?.windowsSaveStrategy.setWikiSaveFilter(game.id, wikiFilter);
    final argsStr = result['args'] ?? '';
    final argsList = argsStr.isNotEmpty ? argsStr.split(RegExp(r'\s+')) : <String>[];
    await windowsStrategy?.setLaunchArgs(game.id, argsList);
    // Only auto-relaunch if this Configure dialog was opened as part of the
    // error-recovery flow (a failed launch) and the user actually set an exe path.
    // A deliberate Configure button press should just save settings, not launch the game.
    if (fromError) {
      if (result['exe']?.isNotEmpty ?? false) {
        if (context.mounted) await handleLaunch(context, ref, game);
      } else {
        // User clicked Save without setting an exe — can't auto-detect
        if (context.mounted) ErrorHandler.showInfo(context, 'No Executable Set', message: 'Please set the game executable path to launch it.');
      }
    }
  }

  Future<void> handleDeleteRom(BuildContext context, WidgetRef ref, Game game) async {
    final dirService = ref.read(directoryServiceProvider).asData?.value;
    if (dirService == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete ROM?'),
        content: Text('Are you sure you want to delete the local files for ${game.name}?'),
        actions: [
          FocusEffectWrapper(
            useSafeScale: false,
            onTap: () => Navigator.pop(ctx, false),
            borderRadius: 12.0,
            autofocus: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: Border.all(color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.3)),
              ),
              child: Text('Cancel', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ),
          ),
          const SizedBox(width: 8),
          FocusEffectWrapper(
            useSafeScale: false,
            onTap: () => Navigator.pop(ctx, true),
            borderRadius: 12.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.red.withValues(alpha: 0.1),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await dirService.deleteRom(game);
      ref.read(downloadedGamesCacheProvider.notifier).refresh();
      if (context.mounted) ErrorHandler.showSuccess(context, 'ROM Deleted', message: 'Local files removed.');
    } catch (e) { if (context.mounted) ErrorHandler.showException(context, e, contextLabel: 'Delete Failed'); }
  }

  Future<void> handleSyncStates(BuildContext context, WidgetRef ref, Game game) async {
    final stateSync = await ref.read(stateSyncServiceProvider.future);
    if (!context.mounted) return;
    if (stateSync == null || !stateSync.isAvailableFor(game)) {
      debugPrint('[StateSync] not running for ${game.name}: '
          '${_stateSyncUnavailableReason(stateSync, game)}');
      ErrorHandler.showInfo(context, 'Sync Unavailable', message: 'Save state sync is not enabled for this emulator.');
      return;
    }
    // Fail fast like the pre-launch pull does, instead of waiting out the list timeout.
    if (_rommOffline(ref)) {
      debugPrint('[StateSync] manual sync skipped for ${game.name}: RomM is offline');
      ErrorHandler.showInfo(context, 'RomM offline', message: 'Save state sync needs a connection to RomM.');
      return;
    }
    final dir = ref.read(directoryServiceProvider).asData?.value;
    String romPath = '';
    if (dir != null) {
      romPath = await dir.findExistingRomPath(game) ?? await dir.getRomFilePath(game);
    }
    if (!context.mounted) return;
    ErrorHandler.showInfo(context, 'Syncing', message: 'Syncing save states for ${game.name}...');
    try {
      final pull = await stateSync.pullStates(game, romPath);
      if (!context.mounted) return;
      if (pull.busy) {
        _showSyncBusy(context, game);
        return;
      }
      await _resolveStateConflicts(context, stateSync, pull.conflicts);
      if (!context.mounted) return;
      final push = await stateSync.pushStates(game, romPath);
      if (!context.mounted) return;
      if (push.busy) {
        _showSyncBusy(context, game);
        return;
      }
      // A slot the user just cancelled shows up again in the push result: ask once.
      final newConflicts = push.conflicts
          .where((c) => !pull.conflicts.any((earlier) => earlier.fileName == c.fileName))
          .toList();
      await _resolveStateConflicts(context, stateSync, newConflicts);
      if (!context.mounted) return;
      if (pull.skipped && push.skipped) {
        // The service could not even start (game not identified, state folder
        // not found): don't report that as a successful "0 downloaded" sync.
        ref.invalidate(resumeEntriesProvider);
        ErrorHandler.showInfo(context, 'Nothing to sync',
            message: "Couldn't identify the game or find the save state folder for ${game.name}.");
        return;
      }
      ref.invalidate(resumeEntriesProvider);
      ErrorHandler.showSuccess(context, 'States Synced',
          message: '${pull.downloaded} downloaded, ${push.uploaded} uploaded');
    } catch (e) {
      if (context.mounted) ErrorHandler.showException(context, e, contextLabel: 'State Sync Failed');
    }
  }

  /// Why no state sync runs for [game], for the log.
  String _stateSyncUnavailableReason(StateSyncService? stateSync, Game game,
          {String? emulatorId}) =>
      stateSync == null
          ? 'RomM/save-sync service not available'
          : stateSync.availabilityReason(game, emulatorId: emulatorId);

  /// True when RomM is known to be unreachable, so a state sync would only
  /// wait out its list timeout.
  bool _rommOffline(WidgetRef ref) =>
      ref.read(rommServiceProvider)?.isOffline.value == true;

  /// Another state sync for [game] (e.g. the post-exit push) is still running,
  /// so this one did nothing.
  void _showSyncBusy(BuildContext context, Game game) {
    ErrorHandler.showInfo(context, 'Sync already running',
        message: 'Another save state sync for ${game.name} is still running. Try again in a moment.');
  }

  /// Asks about each conflicting state in turn. Cancelling keeps the local
  /// file and leaves the slot flagged (push skips it until resolved).
  Future<void> _resolveStateConflicts(
      BuildContext context, StateSyncService stateSync, List<StateConflict> conflicts) async {
    for (final conflict in conflicts) {
      if (!context.mounted) return;
      final choice = await LibraryDialogService.showStateConflictDialog(context, conflict);
      if (choice == null) continue;
      final ok = await stateSync.resolveConflict(conflict, choice: choice);
      if (context.mounted) {
        ErrorHandler.showInfo(
          context,
          ok ? 'Sync Resolved' : 'Sync Failed',
          message: ok
              ? (choice == 'local' ? 'Local state uploaded' : 'Cloud state restored')
              : 'Could not resolve ${conflict.fileName}',
        );
      }
    }
  }

  Future<void> handlePushSaves(BuildContext context, WidgetRef ref, Game game) async {
    final syncService = await ref.read(saveSyncServiceProvider.future);
    if (!context.mounted || syncService == null) { ErrorHandler.showInfo(context, 'Sync Unavailable', message: 'Save sync not available'); return; }
    final dir = ref.read(directoryServiceProvider).asData?.value;
    String romPath = '';
    if (dir != null) {
      romPath = await dir.findExistingRomPath(game) ?? await dir.getRomFilePath(game);
    }
    
    if (!context.mounted) return;
    final syncMode = ref.read(retroarchSyncModeProvider);
    debugPrint('[SaveSync] handlePushSaves: game="${game.displayName}" romPath=$romPath syncMode=$syncMode');
    try {
      ErrorHandler.showInfo(context, 'Syncing', message: 'Uploading saves for ${game.name}...');
      final ok = await syncService.pushSaves(game, romPath, syncMode: syncMode, force: true);
      if (context.mounted) {
        if (ok) ErrorHandler.showSuccess(context, 'Save Synced', message: 'Saves uploaded');
        else ErrorHandler.showInfo(context, 'No Saves Found', message: 'No save files found for ${game.name}. Have you played the game first?');
      }
    } catch (e) { if (context.mounted) await _handleSyncError(context, e, game, romPath, syncService, syncMode, push: true); }
  }

  Future<void> handlePullSaves(BuildContext context, WidgetRef ref, Game game) async {
    final syncService = await ref.read(saveSyncServiceProvider.future);
    if (!context.mounted || syncService == null) { ErrorHandler.showInfo(context, 'Sync Unavailable', message: 'Save sync not available'); return; }
    final dir = ref.read(directoryServiceProvider).asData?.value;
    //Changed : For Win Games, this used to return the game ZIP path. 
    //Added a check for Win games to make sure it returns the current install folder.
    final String romPath = dir != null ? (game.platformSlug != 'win' ? await dir.getRomFilePath(game) : await dir.findExistingRomPath(game) ?? '') : '';
    if (!context.mounted) return;
    debugPrint('[SaveSync] handlePullSaves: game="${game.displayName}" romPath=$romPath');
    try {
      ErrorHandler.showInfo(context, 'Syncing', message: 'Fetching cloud saves...');
      final saves = await syncService.getSavesForGame(game.id);
      if (!context.mounted) return;
      if (saves.isEmpty) { ErrorHandler.showInfo(context, 'No Saves', message: 'No cloud saves found.'); return; }
      final selectedSave = await LibraryDialogService.showSaveSelectionDialog(context, saves);
      if (selectedSave == null || !context.mounted) return;
      ErrorHandler.showInfo(context, 'Syncing', message: 'Downloading selected save...');
      // Snapshot the current local save before overwriting it with the
      // chosen cloud save, same as the auto-pull-before-launch path.
      await ref.read(backupServiceProvider).createImmediate(game, romPath, syncService);
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
      final strategy = syncService.getStrategyForGame(game);
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
        await syncService.resolveConflict(game, romPath, e, choice: choice!, syncMode: syncMode);
        if (context.mounted) ErrorHandler.showSuccess(context, 'Sync Resolved', message: 'Local save uploaded');
      } else if (choice == 'cloud' && context.mounted) {
        await syncService.resolveConflict(game, romPath, e, choice: choice!, syncMode: syncMode);
        if (context.mounted) ErrorHandler.showSuccess(context, 'Sync Resolved', message: 'Cloud save restored');
      }
    } else if (!push) {
       return await showDialog<bool>(
         context: context,
         builder: (ctx) => AlertDialog(
           title: const Text('Save Sync Warning'),
           content: Text('${e.toString().replaceAll('Exception: ', '')}\n\nPlay anyway?'),
           actions: [
             FocusEffectWrapper(
               useSafeScale: false,
               onTap: () => Navigator.pop(ctx, false),
               borderRadius: 12.0,
               autofocus: true,
               child: Container(
                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                 decoration: BoxDecoration(
                   borderRadius: BorderRadius.circular(12),
                   color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                   border: Border.all(color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.3)),
                 ),
                 child: Text('Cancel', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
               ),
             ),
             const SizedBox(width: 8),
             FocusEffectWrapper(
               onTap: () => Navigator.pop(ctx, true),
               borderRadius: 12.0,
               child: Container(
                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                 decoration: BoxDecoration(
                   borderRadius: BorderRadius.circular(12),
                   color: Colors.indigo.withValues(alpha: 0.1),
                   border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
                 ),
                 child: const Text('Play Anyway', style: TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold)),
               ),
             ),
           ],
         ),
       );
    } else { ErrorHandler.showException(context, e, contextLabel: push ? 'Push Saves Error' : 'Pull Saves Error'); }
    return null;
  }

  Future<bool?> _showMissingRomDialog(BuildContext context, String gameName, String expectedPath) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ROM not found', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('$gameName is not downloaded yet.'),
            const SizedBox(height: 8),
            const Text('Expected location:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SelectableText(expectedPath, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            const Text('Download now?'),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              FocusEffectWrapper(
                onTap: () => Navigator.pop(ctx, false),
                borderRadius: 12.0, autofocus: true, useSafeScale: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    border: Border.all(color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.3)),
                  ),
                  child: Text('Cancel', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ),
              ),
              const SizedBox(width: 8),
              FocusEffectWrapper(
                onTap: () => Navigator.pop(ctx, true),
                borderRadius: 12.0, useSafeScale: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.indigo.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
                  ),
                  child: const Text('Download', style: TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<bool?> _showMissingCoreDialog(BuildContext context, String coreName) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('RetroArch Core Missing', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('The core $coreName is required. Download and install it automatically?'),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              FocusEffectWrapper(
                onTap: () => Navigator.pop(ctx, false),
                borderRadius: 12.0, autofocus: true, useSafeScale: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    border: Border.all(color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.3)),
                  ),
                  child: Text('Cancel', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ),
              ),
              const SizedBox(width: 8),
              FocusEffectWrapper(
                onTap: () => Navigator.pop(ctx, true),
                borderRadius: 12.0, useSafeScale: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.indigo.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
                  ),
                  child: const Text('Install', style: TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
