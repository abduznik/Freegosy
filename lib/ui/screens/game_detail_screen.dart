import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:developer' as dev;
import '../../core/storage/system_utils.dart';
import '../../core/romm/romm_models.dart';
import '../../core/romm/romm_service.dart';
import '../../core/error/error_handler.dart';
import '../../core/save/backup_entry.dart';
import '../../core/save/background_sync_queue.dart';
import '../../providers/download_provider.dart';
import '../../providers/romm_provider.dart';
import '../../providers/shared_prefs_provider.dart';
import '../widgets/screenshot_gallery_dialog.dart';
import '../widgets/download_progress_indicator.dart';
import '../widgets/backup_history_sheet.dart';
import '../widgets/game_detail/game_action_button.dart';
import '../widgets/game_detail/game_metadata_chip.dart';
import '../widgets/game_detail/game_details_grid.dart';
import '../widgets/game_detail/game_notes_section.dart';
import '../widgets/game_detail/game_personal_section.dart';
import '../widgets/focus_effect_wrapper.dart';
import '../widgets/controller_hints_bar.dart';
import '../../providers/ui_provider.dart';
import '../../core/input/input_action_bus.dart';
import '../../core/input/gamepad_service.dart';
import 'dart:async';

class GameDetailScreen extends ConsumerStatefulWidget {
  final Game game;
  final String rommBaseUrl;
  final bool isDownloaded;
  final dynamic onLaunch;
  final dynamic onDownload;
  final dynamic onPushSaves;
  final dynamic onPullSaves;
  final dynamic onDelete;
  final RommService? rommService;

  const GameDetailScreen({
    super.key,
    required this.game,
    required this.rommBaseUrl,
    required this.isDownloaded,
    required this.onLaunch,
    required this.onDownload,
    required this.onPushSaves,
    required this.onPullSaves,
    required this.onDelete,
    this.rommService,
  });

  @override
  ConsumerState<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends ConsumerState<GameDetailScreen> {
  late Game _currentGame;
  late bool _isDownloaded;
  late bool _backlogged;
  late bool _nowPlaying;
  late int _rating;
  late String? _status;
  late int _completion;
   bool _isSaving = false;
  bool _adjustingRating = false;
  bool _adjustingCompletion = false;
  bool _justEnteredRating = false;
  bool _justEnteredCompletion = false;
  StreamSubscription<GameAction>? _inputSub;
  final FocusNode _focusNode = FocusNode();
  late ProviderContainer _container;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context);
  }

  @override
  void initState() {
    super.initState();
    _currentGame = widget.game;
    _isDownloaded = widget.isDownloaded;
    _syncStateWithGame(_currentGame);
    _checkDownloadStatus();
    _lazySync();
    _refreshGame();

    // Action Bus: Listen for Back command regardless of focus state
    _inputSub = inputActionBus.stream.listen((action) {
      if (mounted) {
        if (_adjustingCompletion) {
          if (_justEnteredCompletion) {
            _justEnteredCompletion = false;
            return;
          }
          if (action == GameAction.left) {
            setState(() {
              _completion = (_completion - 5).clamp(0, 100);
            });
          } else if (action == GameAction.right) {
            setState(() {
              _completion = (_completion + 5).clamp(0, 100);
            });
          } else if (action == GameAction.confirm || action == GameAction.back) {
            _toggleAdjustingCompletion();
          }
          return;
        }

        if (_adjustingRating) {
          if (_justEnteredRating) {
            _justEnteredRating = false;
            return;
          }
          if (action == GameAction.left) {
            setState(() {
              _rating = (_rating - 1).clamp(0, 10);
            });
          } else if (action == GameAction.right) {
            setState(() {
              _rating = (_rating + 1).clamp(0, 10);
            });
          } else if (action == GameAction.confirm || action == GameAction.back) {
            _toggleAdjustingRating();
          }
          return;
        }

        if (action == GameAction.back) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      }
    });

    // Autofocus: Ensure the screen is ready for input on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _toggleAdjustingRating() {
    setState(() {
      _adjustingRating = !_adjustingRating;
      _adjustingCompletion = false;
      if (_adjustingRating) {
        _justEnteredRating = true;
      }
      ref.read(navigationLockedProvider.notifier).state = _adjustingRating;
    });
  }

  void _toggleAdjustingCompletion() {
    setState(() {
      _adjustingCompletion = !_adjustingCompletion;
      _adjustingRating = false;
      if (_adjustingCompletion) {
        _justEnteredCompletion = true;
      }
      ref.read(navigationLockedProvider.notifier).state = _adjustingCompletion;
    });
  }

  @override
  void dispose() {
    _inputSub?.cancel();
    _focusNode.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _container.read(navigationLockedProvider.notifier).state = false;
    });
    super.dispose();
  }

  Future<void> _lazySync() async {
    final scanner = ref.read(romScannerServiceProvider);
    if (scanner != null) {
      await scanner.syncSingleGame(_currentGame);
      if (!mounted) return;
      _checkDownloadStatus();
    }
  }

  void _syncStateWithGame(Game game) {
    _backlogged = game.backlogged;
    _nowPlaying = game.nowPlaying;
    _rating = game.userRating;
    _status = game.status;
    _completion = game.completion;
  }

  Future<void> _checkDownloadStatus() async {
    if (!mounted) return;
    final ds = ref.read(directoryServiceProvider).value;
    if (ds != null) {
      final exists = await ds.isRomDownloaded(_currentGame);
      if (mounted) setState(() => _isDownloaded = exists);
    }
  }

  Future<void> _refreshGame() async {
    if (!mounted || widget.rommService == null) return;
    try {
      final updated = await widget.rommService!.getGame(_currentGame.id);
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _currentGame = updated;
          _syncStateWithGame(updated);
        });
        _checkDownloadStatus();
        final cacheService = ref.read(metadataCacheServiceProvider).asData?.value;
        if (cacheService != null) await cacheService.saveGames([updated]);
      }
    } catch (_) {}
  }

  Future<void> _addNote() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Note'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.indigoAccent)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'Content',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.indigoAccent)),
                ),
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          FocusEffectWrapper(
            onTap: () => Navigator.pop(context, false),
            borderRadius: 12.0,
            scaleFactor: 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
          ),
          const SizedBox(width: 8),
          FocusEffectWrapper(
            onTap: () => Navigator.pop(context, true),
            borderRadius: 12.0,
            scaleFactor: 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.indigo.withValues(alpha: 0.1),
                border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
              ),
              child: const Text('Add Note', style: TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );

    if (result == true && widget.rommService != null) {
      final title = titleController.text.trim();
      final content = contentController.text.trim();
      if (title.isNotEmpty || content.isNotEmpty) {
        final success = await widget.rommService!.createRomNote(_currentGame.id, title, content);
        if (success) {
          if (!mounted) return;
          _refreshGame();
        } else if (mounted) {
          ErrorHandler.showException(context, Exception('Failed to create note'), contextLabel: 'Add Note');
        }
      }
    }
  }

  Future<void> _deleteNote(int noteId) async {
    if (widget.rommService == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text('Are you sure you want to delete this note?'),
        actions: [
          FocusEffectWrapper(
            onTap: () => Navigator.pop(context, false),
            borderRadius: 12.0,
            scaleFactor: 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
          ),
          const SizedBox(width: 8),
          FocusEffectWrapper(
            onTap: () => Navigator.pop(context, true),
            borderRadius: 12.0,
            scaleFactor: 1.0,
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
    if (confirm == true) {
      final success = await widget.rommService!.deleteRomNote(_currentGame.id, noteId);
      if (success) {
        if (!mounted) return;
        _refreshGame();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete note')));
      }
    }
  }

  void _viewNote(RomNote note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note.title.isNotEmpty ? note.title : 'Note'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Text(note.content, style: const TextStyle(height: 1.5)),
          ),
        ),
        actions: [
          FocusEffectWrapper(
            onTap: () => Navigator.pop(context),
            borderRadius: 12.0,
            scaleFactor: 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Text('Close', style: TextStyle(color: Colors.white70)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProps(BuildContext context) async {
    if (widget.rommService == null) return;
    setState(() => _isSaving = true);
    final prefs = ref.read(sharedPreferencesProvider);
    final success = await widget.rommService!.updateRomProps(
      _currentGame.id, prefs, backlogged: _backlogged, nowPlaying: _nowPlaying,
      rating: _rating, status: _status, completion: _completion,
    );
    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        _refreshGame();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Properties saved successfully')));
      } else if (mounted) {
        ErrorHandler.showException(context, Exception('Failed to update properties'), contextLabel: 'Update Status');
      }
    }
  }

  String _normalizeUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final base = widget.rommBaseUrl.endsWith('/') ? widget.rommBaseUrl.substring(0, widget.rommBaseUrl.length - 1) : widget.rommBaseUrl;
    return '$base${path.startsWith('/') ? path : '/$path'}';
  }

  Future<bool> _showCancelConfirmation(BuildContext context, String gameName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Download'),
        content: Text('Are you sure you want to cancel downloading $gameName? This will delete the partial file.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel Download', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(downloadProvider, (prev, next) {
      final progress = next[_currentGame.id];
      if (progress != null && progress.isComplete) {
        _checkDownloadStatus();
        ref.read(downloadProvider.notifier).removeDownload(_currentGame.id);
      }
    });

    final theme = Theme.of(context);
    final headerHeight = MediaQuery.of(context).size.height * 0.4;
    String? backgroundUrl = _currentGame.screenshotUrl != null && _currentGame.screenshotUrl!.isNotEmpty
        ? _normalizeUrl(_currentGame.screenshotUrl)
        : (_currentGame.mergedScreenshots.isNotEmpty ? _normalizeUrl(_currentGame.mergedScreenshots.first) : null);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroHeader(context, headerHeight, backgroundUrl, theme),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildActionsRow(),
                  const SizedBox(height: 24),
                  _buildMetadataChips(),
                  const SizedBox(height: 24),
                  _buildSectionTitle(theme, 'About'),
                  const SizedBox(height: 8),
                  Text(_currentGame.summary ?? 'No description available', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70, height: 1.5)),
                  const SizedBox(height: 24),
                  _buildSectionTitle(theme, 'Details'),
                  const SizedBox(height: 12),
                  GameDetailsGrid(game: _currentGame),
                  const SizedBox(height: 24),
                  GameNotesSection(notes: _currentGame.notes, onAddNote: _addNote, onDeleteNote: _deleteNote, onViewNote: _viewNote),
                  const SizedBox(height: 24),
                  _buildScreenshotsSection(theme),
                  GamePersonalSection(
                    status: _status,
                    rating: _rating,
                    completion: _completion,
                    backlogged: _backlogged,
                    nowPlaying: _nowPlaying,
                    isSaving: _isSaving,
                    adjustingRating: _adjustingRating,
                    adjustingCompletion: _adjustingCompletion,
                    onStatusChanged: (val) => setState(() => _status = val),
                    onRatingChanged: (val) => setState(() => _rating = val),
                    onCompletionChanged: (val) => setState(() => _completion = val),
                    onBacklogChanged: (val) => setState(() => _backlogged = val),
                    onNowPlayingChanged: (val) => setState(() => _nowPlaying = val),
                    onToggleAdjustingRating: _toggleAdjustingRating,
                    onToggleAdjustingCompletion: _toggleAdjustingCompletion,
                    onSave: () => _saveProps(context),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
        child: ref.watch(inputModeProvider) != InputMode.mouse
            ? ControllerHintsBar(
                hints: [
                  ControllerHintItem(
                    label: _isDownloaded ? 'Play' : 'Download', 
                    button: 'A'
                  ),
                  const ControllerHintItem(label: 'Back', button: 'B'),
                ],
              )
            : const SizedBox.shrink(key: ValueKey('hide_detail_hints')),
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context, double height, String? backgroundUrl, ThemeData theme) {
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: backgroundUrl != null
                ? CachedNetworkImage(imageUrl: backgroundUrl, fit: BoxFit.cover, placeholder: (_, __) => Container(color: Colors.grey[900]), errorWidget: (_, __, ___) => Container(color: Colors.grey[900]))
                : Container(color: Colors.grey[900]),
          ),
          Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87, Colors.black], stops: [0.5, 0.8, 1.0])))),
          Positioned(top: MediaQuery.of(context).padding.top + 8, left: 16, child: CircleAvatar(backgroundColor: Colors.black54, child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.of(context).pop()))),
          Positioned(
            bottom: 16, left: 16, right: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Hero(
                  tag: 'game_cover_${_currentGame.id}',
                  child: Container(
                    width: 130, height: 180,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10, offset: const Offset(0, 4))]),
                    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: _normalizeUrl(_currentGame.pathCoverLarge), fit: BoxFit.cover, placeholder: (_, __) => Container(color: Colors.grey[800]), errorWidget: (_, __, ___) => const Icon(Icons.image_not_supported))),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_currentGame.name, style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (_currentGame.platformDisplayName != null) Text(_currentGame.platformDisplayName!, style: theme.textTheme.titleMedium?.copyWith(color: Colors.white70)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsRow() {
    return Consumer(builder: (context, ref, _) {
      final theme = Theme.of(context);
      final downloads = ref.watch(downloadProvider);
      final progress = downloads[_currentGame.id];
      if (!_isDownloaded) {
        if (progress != null) {
          return Column(children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: DownloadProgressIndicator(progress: progress, compact: true)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (!progress.isComplete && progress.error == null) ...[
                GameActionButton(icon: progress.isPaused ? Icons.play_arrow : Icons.pause, label: progress.isPaused ? 'Resume' : 'Pause', onPressed: () {
                  if (progress.isPaused) { if (progress.game != null && progress.downloadUrl != null) ref.read(downloadProvider.notifier).startDownload(progress.game!, progress.downloadUrl!); }
                  else { ref.read(downloadProvider.notifier).pauseDownload(_currentGame.id); }
                }),
                const SizedBox(width: 16),
              ],
              GameActionButton(icon: Icons.close, label: 'Cancel', color: Colors.red, onPressed: () async {
                if (progress.isComplete || progress.error != null) ref.read(downloadProvider.notifier).cancelDownload(_currentGame.id);
                else if (await _showCancelConfirmation(context, progress.gameName)) ref.read(downloadProvider.notifier).cancelDownload(_currentGame.id);
              }),
            ]),
          ]);
        }
        return Center(
          child: SizedBox(
            width: 280,
            child: GameActionButton(
              focusNode: _focusNode,
              icon: Icons.download, 
              label: 'Download Game', 
              isPrimary: true,
              onPressed: () async { await widget.onDownload(); _checkDownloadStatus(); }
            ),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SizedBox(
              width: 280,
              child: GameActionButton(
                focusNode: _focusNode,
                icon: Icons.play_arrow, 
                label: 'Play Game', 
                isPrimary: true,
                onPressed: () async { if (_isDownloaded) await widget.onLaunch(); }
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 480,
              child: Row(
                children: [
                  Expanded(
                    child: GameActionButton(icon: Icons.cloud_upload, label: 'Push', onPressed: () async { if (_isDownloaded) await widget.onPushSaves(); }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GameActionButton(icon: Icons.cloud_download, label: 'Pull', onPressed: () async { if (_isDownloaded) await widget.onPullSaves(); }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GameActionButton(icon: Icons.folder, label: 'Folder', onPressed: () async {
                      final ds = ref.read(directoryServiceProvider).value;
                      if (ds != null) await SystemUtils.openDirectory(await ds.getRomDirectory(_currentGame));
                    }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GameActionButton(icon: Icons.delete, label: 'Delete', color: Colors.red, onPressed: () async { await widget.onDelete(); ref.invalidate(downloadProvider); _checkDownloadStatus(); }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),
          _buildSectionTitle(theme, 'Local Saves'),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 320,
              child: Row(
                children: [
                  Expanded(
                    child: GameActionButton(icon: Icons.save_alt_outlined, label: 'Backup', onPressed: () async => _handleLocalBackup(ref)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GameActionButton(icon: Icons.history, label: 'Restore', onPressed: () async => _handleLocalRestore(ref)),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  Future<void> _handleLocalBackup(WidgetRef ref) async {
    try {
      final syncService = await ref.read(saveSyncServiceProvider.future);
      if (!mounted) return;
      final ds = await ref.read(directoryServiceProvider.future);
      if (!mounted || syncService == null || ds == null) return;
      final backupService = ref.read(backupServiceProvider);
      final result = await backupService.createImmediate(_currentGame, await ds.getRomFilePath(_currentGame), syncService);
      if (!mounted) return;
      if (result != null) {
        final backupRepo = ref.read(backupRepositoryProvider);
        await backupRepo.addEntry(_currentGame.id, BackupEntry(timestamp: DateTime.now(), md5Hash: result.md5, localZipPath: result.zipPath));
        if (!mounted) return;
        ErrorHandler.showSuccess(context, 'Backup Created', message: 'Local restore point saved.');
        final rommService = ref.read(rommServiceProvider);
        if (rommService != null && !rommService.isOffline.value) BackgroundSyncQueue.processQueue(rommService, backupRepo);
      } else {
        ErrorHandler.showInfo(context, 'No Saves', message: 'No save files found to back up.');
      }
    } catch (e) { if (mounted) ErrorHandler.showException(context, e, contextLabel: 'Local Backup'); }
  }

  Future<void> _handleLocalRestore(WidgetRef ref) async {
    try {
      final ds = ref.read(directoryServiceProvider).value;
      if (mounted) await BackupHistorySheet.show(context, game: _currentGame, romPath: ds != null ? await ds.getRomFilePath(_currentGame) : '');
    } catch (e) { if (mounted) ErrorHandler.showException(context, e, contextLabel: 'Local Restore'); }
  }

  Widget _buildMetadataChips() {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      ..._currentGame.genres.take(2).map((g) => GameMetadataChip(label: g)),
      if (_currentGame.playerCount?.isNotEmpty ?? false) GameMetadataChip(label: _currentGame.playerCount!, icon: Icons.people_outline),
      if (_currentGame.averageRating != null) GameMetadataChip(label: '${_currentGame.averageRating!.toStringAsFixed(0)}/100', icon: Icons.star_outline),
      if (_currentGame.firstReleaseDate != null) GameMetadataChip(label: DateTime.fromMillisecondsSinceEpoch(_currentGame.firstReleaseDate!).year.toString(), icon: Icons.calendar_today_outlined),
    ]);
  }

  Widget _buildScreenshotsSection(ThemeData theme) {
    if (_currentGame.mergedScreenshots.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildSectionTitle(theme, 'Screenshots'),
      const SizedBox(height: 12),
      SizedBox(
        height: 120,
        child: ListView.separated(
          scrollDirection: Axis.horizontal, itemCount: _currentGame.mergedScreenshots.length, separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (ctx, index) {
            final url = _normalizeUrl(_currentGame.mergedScreenshots[index]);
            return GestureDetector(
              onTap: () => showDialog(context: context, useRootNavigator: true, builder: (_) => ScreenshotGalleryDialog(initialIndex: index, imageUrls: _currentGame.mergedScreenshots.map(_normalizeUrl).toList())),
              child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: url, width: 200, height: 120, fit: BoxFit.cover, placeholder: (_, __) => Container(color: Colors.grey[900]), errorWidget: (_, __, ___) => const Icon(Icons.image_not_supported))),
            );
          },
        ),
      ),
      const SizedBox(height: 24),
    ]);
  }

  Widget _buildSectionTitle(ThemeData theme, String title) => Text(title, style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold));
}
