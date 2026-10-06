import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'dart:developer' as dev;
import '../../core/storage/system_utils.dart';
import '../../core/romm/romm_models.dart';
import '../../core/romm/romm_service.dart';
import '../../core/error/error_handler.dart';
import '../../core/save/backup_entry.dart';
import '../../core/save/background_sync_queue.dart';
import '../../core/save/catalog/play_choice.dart';
import '../../core/save/catalog/play_request.dart';
import '../../core/save/catalog/save_entry.dart';
import '../../core/save/catalog/save_maker.dart';
import '../../core/save/resume_service.dart';
import '../../providers/download_provider.dart';
import '../../providers/resume_provider.dart';
import '../../providers/romm_provider.dart';
import '../../providers/save_catalog_provider.dart';
import '../../providers/shared_prefs_provider.dart';
import '../widgets/screenshot_gallery_dialog.dart';
import '../widgets/download_progress_indicator.dart';
import '../widgets/game_detail/game_achievements_section.dart';
import '../widgets/game_detail/game_action_button.dart';
import '../widgets/game_detail/game_banner.dart';
import '../widgets/game_detail/game_metadata_chip.dart';
import '../widgets/game_detail/game_details_grid.dart';
import '../widgets/game_detail/game_notes_section.dart';
import '../widgets/game_detail/game_personal_section.dart';
import '../widgets/game_detail/saves_tab.dart';
import '../widgets/save_list/save_labels.dart';
import '../widgets/shoulder_owner.dart';
import 'play_screen.dart';
import '../play/emulator_choices.dart';
import '../widgets/controller_dialogs.dart';
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

  /// Starts the game as the play screen asks.
  /// Starts the game; true once the emulator started.
  final Future<bool> Function(PlayRequest request) onPlay;
  final Future<void> Function(Game game) onDownload;
  final dynamic onPushSaves;
  final dynamic onSyncStates;
  final dynamic onDelete;
  final dynamic onConfigure;
  final RommService? rommService;

  /// Loads a resume entry. When null, there are no states to resume.
  final Future<void> Function(ResumeEntry entry)? onResume;

  /// Puts a save in place for an emulator without launching (Saves tab).
  final Future<void> Function(SaveEntry save, SaveMaker target)? onRestoreSave;

  const GameDetailScreen({
    super.key,
    required this.game,
    required this.rommBaseUrl,
    required this.isDownloaded,
    required this.onPlay,
    required this.onDownload,
    required this.onPushSaves,
    this.onSyncStates,
    required this.onDelete,
    this.onConfigure,
    this.rommService,
    this.onResume,
    this.onRestoreSave,
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
  bool _isAddingNote = false;
  StreamSubscription<GameAction>? _inputSub;
  final FocusNode _focusNode = FocusNode();
  List<ResumeEntry> _resumeEntries = const [];
  int _tab = 0;
  final _progressKey = GlobalKey();

  /// True while a launch started from this page (Play, Resume, a slot pick)
  /// is still running, e.g. its pre-launch state pull: a second press must
  /// not start another launch of the same game underneath it.
  bool _launchInFlight = false;
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

        // Only while this page is on top: not under the play screen or a
        // dialog, which handle B, Y and LB/RB themselves.
        if (ModalRoute.of(context)?.isCurrent != true) return;
        if (action == GameAction.favorite) {
          // Y: the play screen on the states, the newest chosen.
          if (_resumeEntries.isNotEmpty) _openPlay(initialTab: 1);
        } else if (action == GameAction.l1 || action == GameAction.r1) {
          setState(() => _tab = (_tab + (action == GameAction.l1 ? -1 : 1)).clamp(0, _tabs.length - 1));
        } else if (action == GameAction.back) {
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

  /// The game's resume entries, newest first (empty without
  /// [GameDetailScreen.onResume]). Mirrors the latest list into
  /// [_resumeEntries] for Y (no setState).
  List<ResumeEntry> _watchResumeEntries(WidgetRef ref) {
    final entries = widget.onResume == null
        ? const <ResumeEntry>[]
        // valueOrNull keeps the previous list while it reloads (a dependency
        // change makes it loading again).
        : ref.watch(resumeEntriesProvider(ResumeKey(_currentGame))).valueOrNull ?? const <ResumeEntry>[];
    _resumeEntries = entries;
    return entries;
  }

  /// True while another route (a dialog pushed over this page, or a launch
  /// already awaiting one) is on top: X or Resume must not start a second
  /// action underneath it.
  bool get _pageIsNotCurrentRoute => ModalRoute.of(context)?.isCurrent != true;

  /// Runs [launch] unless a launch from this page is already running; see
  /// [_launchInFlight].
  Future<void> _runLaunch(Future<void> Function() launch) async {
    if (_launchInFlight) return;
    _launchInFlight = true;
    try {
      await launch();
    } finally {
      _launchInFlight = false;
    }
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
      try {
        _container.read(navigationLockedProvider.notifier).state = false;
      } catch (_) {
        // Container already disposed (e.g. during test teardown), safe to ignore!
      }
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
    if (_isAddingNote) return;
    _isAddingNote = true;
    
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    bool? result;
    
    try {
      result = await showDialog<bool>(
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
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contentController,
                  decoration: InputDecoration(
                    labelText: 'Content',
                    labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)),
                ),
                child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                ),
                child: Text('Add Note', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
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
    } finally {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _isAddingNote = false;
        }
      });
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
            useSafeScale: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)),
              ),
              child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
          const SizedBox(width: 8),
          FocusEffectWrapper(
            onTap: () => Navigator.pop(context, true),
            borderRadius: 12.0,
            scaleFactor: 1.0,
            useSafeScale: false,
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
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(note.title.isNotEmpty ? note.title : 'Note', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Text(note.content, style: TextStyle(height: 1.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ),
        actions: [
          FocusEffectWrapper(
            onTap: () {
              Navigator.pop(context);
              _deleteNote(note.id);
            },
            borderRadius: 12.0,
            useSafeScale: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.red.withValues(alpha: 0.1),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: const Text('Delete Note', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 8),
          FocusEffectWrapper(
            onTap: () => Navigator.pop(context),
            borderRadius: 12.0,
            useSafeScale: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)),
              ),
              child: Text('Close', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProps(BuildContext context) async {
    if (widget.rommService == null) return;
    setState(() => _isSaving = true);
    final prefs = ref.read(appPreferencesProvider);
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

  static const _tabs = ['Overview', 'Saves', 'Achievements', 'Notes', 'Details'];

  SaveCatalogKey get _catalogKey => SaveCatalogKey(_currentGame);

  Future<void> _openPlay({int? initialTab}) async {
    if (!_isDownloaded || _launchInFlight || _pageIsNotCurrentRoute) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayScreen(
        game: _currentGame,
        initialTab: initialTab,
        coverUrl: _normalizeUrl(_currentGame.pathCoverLarge),
        onPlay: (request) async {
          var started = false;
          await _runLaunch(() async => started = await widget.onPlay(request));
          return started;
        },
        onResume: widget.onResume == null ? null : (entry) => _runLaunch(() => widget.onResume!(entry)),
      ),
    ));
  }

  Future<void> _showMore() async {
    final registry = await ref.read(strategyRegistryProvider.future);
    if (!mounted) return;
    final hasLaunchPref = registry?.getGameEmulatorPreference(_currentGame.id) != null;
    final isWindowsGame = ['windows', 'pc', 'win'].contains(_currentGame.platformSlug?.toLowerCase());
    final stateSync = widget.onSyncStates != null &&
        (ref.read(stateSyncServiceProvider).asData?.value?.isAvailableFor(_currentGame) ?? false);
    final items = <(String, IconData, Future<void> Function(), bool)>[
      ('Open folder', Icons.folder_open_outlined, () async {
        final ds = ref.read(directoryServiceProvider).value;
        if (ds != null) await SystemUtils.openDirectory(await ds.getRomDirectory(_currentGame));
      }, false),
      if (stateSync) ('Sync save states', Icons.sync, () async => await widget.onSyncStates(), false),
      if (isWindowsGame && widget.onConfigure != null)
        ('Configure', Icons.settings_outlined, () async => await widget.onConfigure(), false),
      if (hasLaunchPref) ('Forget launch choice', Icons.restart_alt, _forgetLaunch, false),
      ('Delete from this PC', Icons.delete_outline, () async {
        await widget.onDelete();
        ref.invalidate(downloadProvider);
        _checkDownloadStatus();
      }, true),
    ];
    final picked = await showControllerChoice(context,
        title: _currentGame.name, labels: [for (final i in items) i.$1], danger: [for (final i in items) i.$4]);
    if (picked != null && mounted) await items[picked].$3();
  }

  Future<void> _forgetLaunch() async {
    final registry = ref.read(strategyRegistryProvider).asData?.value;
    if (registry == null) return;
    await registry.clearGameEmulatorPreference(_currentGame.id);
    await registry.clearGameCorePreference(_currentGame.id);
    ref.invalidate(strategyRegistryProvider);
    ref.read(gamePreferenceVersionProvider.notifier).state++;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Launch preference cleared')));
  }

  Future<void> _deleteSave(SaveEntry save) async {
    switch (save.source) {
      case SaveSource.romm:
        final id = save.rommSave?['id'];
        final rommService = widget.rommService;
        if (id is! int || rommService == null) return;
        if (!await rommService.deleteSaves([id])) {
          if (mounted) ErrorHandler.showInfo(context, "Couldn't delete", message: 'RomM did not delete ${save.fileName}.');
          return;
        }
        // RomM may no longer have what this PC last synced: upload it again.
        await (await ref.read(saveSyncServiceProvider.future))?.forgetSynced(_currentGame);
      case SaveSource.backup:
        await ref.read(backupRepositoryProvider).removeEntry(_currentGame.id, save.backup!);
      case SaveSource.local:
        break;
    }
  }

  void _goToProgress() {
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _progressKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250));
    });
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

    // Rebuild when the remembered emulator changes (⋯ Forget launch choice).
    ref.watch(gamePreferenceVersionProvider);

    final theme = Theme.of(context);
    final background = _currentGame.screenshotUrl != null && _currentGame.screenshotUrl!.isNotEmpty
        ? _normalizeUrl(_currentGame.screenshotUrl)
        : (_currentGame.mergedScreenshots.isNotEmpty ? _normalizeUrl(_currentGame.mergedScreenshots.first) : null);
    final hasResume = _isDownloaded && _watchResumeEntries(ref).isNotEmpty;
    final saveCount = ref.watch(saveCatalogProvider(_catalogKey)).valueOrNull?.all.length;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ShoulderOwner(
        child: Listener(
          onPointerHover: (event) {
            if (event.delta.distance > 0 && ref.read(inputModeProvider) != InputMode.mouse) {
              ref.read(inputModeProvider.notifier).state = InputMode.mouse;
            }
          },
          child: Stack(children: [
            SafeArea(
              top: false,
              child: LayoutBuilder(builder: (context, box) {
                final narrow = box.maxWidth < 900;
                final pad = narrow ? 16.0 : 28.0;
                final bannerHeight = GameBanner.heightFor(box.maxHeight);
                // The banner scrolls with the page; the cover and title start
                // a third of the way down it, on its dimmed part.
                final top = MediaQuery.paddingOf(context).top;
                final contentTop = top + (background != null ? bannerHeight * 0.3 : 60);
                return SingleChildScrollView(
                  child: Stack(children: [
                    if (background != null)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: GameBanner(key: const ValueKey('game-banner'), imageUrl: background, height: bannerHeight),
                      ),
                    Positioned(top: top + 10, left: pad - 6, child: _backButton()),
                    Padding(
                      padding: EdgeInsets.fromLTRB(pad, contentTop, pad, pad),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _cover(narrow ? 110 : 170),
                        SizedBox(width: narrow ? 14 : 26),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_currentGame.name,
                                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            _metaLine(theme),
                            const SizedBox(height: 12),
                            _actionRow(theme),
                            const SizedBox(height: 14),
                            _tabBar(theme, saveCount: saveCount),
                            const SizedBox(height: 12),
                            _tabContent(theme),
                            const SizedBox(height: 60),
                          ]),
                        ),
                      ]),
                    ),
                  ]),
                );
              }),
            ),
          ]),
        ),
      ),
      bottomNavigationBar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
        child: ref.watch(inputModeProvider) != InputMode.mouse
            ? ControllerHintsBar(hints: [
                ControllerHintItem(label: _isDownloaded ? 'Play' : 'Download', button: 'A'),
                if (hasResume) const ControllerHintItem(label: 'States', button: 'Y'),
                if (_tab == 1) ...const [
                  ControllerHintItem(label: 'Restore', button: 'X'),
                  ControllerHintItem(label: 'Delete', button: 'hold A'),
                ],
                const ControllerHintItem(label: 'Tabs', button: 'L1 R1'),
                const ControllerHintItem(label: 'Back', button: 'B'),
              ])
            : const SizedBox.shrink(key: ValueKey('hide_detail_hints')),
      ),
    );
  }

  Widget _backButton() => FocusEffectWrapper(
        key: const ValueKey('back-button'),
        onTap: () => Navigator.of(context).maybePop(),
        borderRadius: 22,
        useSafeScale: false,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
          child: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      );

  Widget _cover(double width) => Hero(
        tag: 'game_cover_${_currentGame.id}',
        child: Container(
          width: width,
          height: width * 1.38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: _normalizeUrl(_currentGame.pathCoverLarge),
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(color: Colors.grey[850]),
              errorWidget: (_, _, _) => Container(color: Colors.grey[850], child: const Icon(Icons.image_not_supported)),
            ),
          ),
        ),
      );

  Widget _metaLine(ThemeData theme) {
    final parts = [
      if (_currentGame.platformDisplayName != null) _currentGame.platformDisplayName!,
      if (_currentGame.firstReleaseDate != null)
        DateFormat('MMM d, y').format(DateTime.fromMillisecondsSinceEpoch(_currentGame.firstReleaseDate!)),
      if (_currentGame.playerCount?.isNotEmpty ?? false) '${_currentGame.playerCount} players',
    ];
    return Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(parts.join(' · '), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      for (final r in _currentGame.regions) SaveChip(r, color: Colors.lightBlueAccent),
    ]);
  }

  Widget _roundButton(
      {required Key key, required String label, required VoidCallback onTap, FocusNode? focusNode, bool primary = false}) {
    final theme = Theme.of(context);
    return FocusEffectWrapper(
      key: key,
      focusNode: focusNode,
      onTap: onTap,
      borderRadius: 24,
      useSafeScale: false,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: primary ? 22 : 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          // Play/Download looks like the other buttons; only its size sets it apart.
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
      ),
    );
  }

  Widget _actionRow(ThemeData theme) => Consumer(builder: (context, ref, _) {
        final progress = ref.watch(downloadProvider)[_currentGame.id];
        final Widget main;
        if (!_isDownloaded && progress != null) {
          main = SizedBox(
            width: 360,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DownloadProgressIndicator(progress: progress, compact: true),
              const SizedBox(height: 8),
              Row(children: [
                if (!progress.isComplete && progress.error == null) ...[
                  GameActionButton(
                    icon: progress.isPaused ? Icons.play_arrow : Icons.pause,
                    label: progress.isPaused ? 'Resume' : 'Pause',
                    onPressed: () {
                      if (progress.isPaused) {
                        if (progress.game != null && progress.downloadUrl != null) {
                          ref.read(downloadProvider.notifier).startDownload(progress.game!, progress.downloadUrl!);
                        }
                      } else {
                        ref.read(downloadProvider.notifier).pauseDownload(_currentGame.id);
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                ],
                GameActionButton(
                  icon: Icons.close,
                  label: 'Cancel',
                  color: Colors.red,
                  onPressed: () async {
                    if (progress.isComplete || progress.error != null) {
                      ref.read(downloadProvider.notifier).cancelDownload(_currentGame.id);
                    } else if (await _showCancelConfirmation(context, progress.gameName)) {
                      ref.read(downloadProvider.notifier).cancelDownload(_currentGame.id);
                    }
                  },
                ),
              ]),
            ]),
          );
        } else if (!_isDownloaded) {
          main = _roundButton(
            key: const ValueKey('download-button'),
            focusNode: _focusNode,
            label: '⭳ Download',
            primary: true,
            onTap: () async {
              await widget.onDownload(_currentGame);
              _checkDownloadStatus();
            },
          );
        } else {
          main = _roundButton(
              key: const ValueKey('play-button'), focusNode: _focusNode, label: '▶ Play', primary: true, onTap: _openPlay);
        }
        return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          main,
          _roundButton(key: const ValueKey('more-button'), label: '⋯', onTap: _showMore),
          const SizedBox(width: 12),
          _pill('pill-status', '◔ ${_status ?? 'No status'}'),
          _pill('pill-rating', '☆ $_rating/10'),
          _pill('pill-completion', '✓ $_completion%'),
        ]);
      });

  Widget _pill(String key, String label) => FocusEffectWrapper(
        key: ValueKey(key),
        onTap: _goToProgress,
        borderRadius: 18,
        useSafeScale: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      );

  Widget _tabBar(ThemeData theme, {int? saveCount}) {
    String? badge(int i) => switch (i) {
          1 => saveCount?.toString(),
          3 => _currentGame.notes.isEmpty ? null : '${_currentGame.notes.length}',
          _ => null,
        };
    return Container(
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.25)))),
      child: Wrap(spacing: 4, children: [
        for (var i = 0; i < _tabs.length; i++)
          FocusEffectWrapper(
            key: ValueKey('tab-${_tabs[i].toLowerCase()}'),
            onTap: () => setState(() => _tab = i),
            borderRadius: 6,
            useSafeScale: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: i == _tab ? theme.colorScheme.primary : Colors.transparent, width: 2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_tabs[i],
                    style: TextStyle(color: i == _tab ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant)),
                if (badge(i) != null) ...[
                  const SizedBox(width: 4),
                  SaveChip(badge(i)!, color: theme.colorScheme.onSurfaceVariant),
                ],
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _tabContent(ThemeData theme) => switch (_tab) {
        0 => _overview(theme),
        1 => SavesTab(
            game: _currentGame,
            onPush: () async {
              if (_isDownloaded) await widget.onPushSaves();
            },
            onBackupNow: () => _handleLocalBackup(ref),
            onRestore: (save, target) async => await widget.onRestoreSave?.call(save, target),
            onDelete: _deleteSave,
          ),
        2 => _currentGame.raId == null
            ? Text('No RetroAchievements for this game.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))
            : GameAchievementsSection(game: _currentGame),
        3 => GameNotesSection(notes: _currentGame.notes, onAddNote: _addNote, onViewNote: _viewNote),
        _ => GameDetailsGrid(game: _currentGame),
      };

  Widget _overview(ThemeData theme) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_currentGame.summary ?? 'No description available',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5)),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ..._currentGame.genres.map((g) => GameMetadataChip(label: g)),
          if (_currentGame.averageRating != null)
            GameMetadataChip(label: '${_currentGame.averageRating!.toStringAsFixed(0)}/100', icon: Icons.star_outline),
          if (_currentGame.lastPlayed != null)
            GameMetadataChip(label: 'Last played ${formatSaveTime(_currentGame.lastPlayed!)}', icon: Icons.history),
        ]),
        if (_currentGame.mergedScreenshots.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _currentGame.mergedScreenshots.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (ctx, index) => FocusEffectWrapper(
                onTap: () => showDialog(
                    context: context,
                    useRootNavigator: true,
                    builder: (_) => ScreenshotGalleryDialog(
                        initialIndex: index, imageUrls: _currentGame.mergedScreenshots.map(_normalizeUrl).toList())),
                borderRadius: 8,
                useSafeScale: false,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: _normalizeUrl(_currentGame.mergedScreenshots[index]),
                    width: 200,
                    height: 120,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const Icon(Icons.image_not_supported),
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        KeyedSubtree(
          key: _progressKey,
          child: GamePersonalSection(
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
        ),
      ]);

  Future<void> _handleLocalBackup(WidgetRef ref) async {
    try {
      final syncService = await ref.read(saveSyncServiceProvider.future);
      if (!mounted) return;
      final ds = await ref.read(directoryServiceProvider.future);
      if (!mounted || syncService == null || ds == null) return;
      // The save of the emulator the game plays in (remembered, else the
      // platform's default), recorded with the backup.
      final registry = await ref.read(strategyRegistryProvider.future);
      final installed = await ref.read(emulatorStatusProvider.future);
      if (!mounted) return;
      final who = registry == null ? null : EmulatorChoices.of(registry, installed, _currentGame).forThisGame;
      final emulatorId = who?.emulatorId;
      final romPath = await ds.findExistingRomPath(_currentGame) ?? await ds.getRomFilePath(_currentGame);
      final backupService = ref.read(backupServiceProvider);
      final result = await backupService.createImmediate(_currentGame, romPath, syncService,
          emulatorId: emulatorId, coreOverride: who?.coreId == null ? null : '${who!.coreId}_libretro');
      if (!mounted) return;
      if (result != null) {
        final backupRepo = ref.read(backupRepositoryProvider);
        await backupRepo.addEntry(
            _currentGame.id,
            BackupEntry(
                timestamp: DateTime.now(),
                md5Hash: result.md5,
                localZipPath: result.zipPath,
                emulatorId: emulatorId,
                coreId: result.coreId ?? who?.coreId));
        if (!mounted) return;
        ErrorHandler.showSuccess(context, 'Backup Created', message: 'Local restore point saved.');
        final rommService = ref.read(rommServiceProvider);
        if (rommService != null && !rommService.isOffline.value) BackgroundSyncQueue.processQueue(rommService, backupRepo);
      } else {
        ErrorHandler.showInfo(context, 'No Saves', message: 'No save files found to back up.');
      }
    } catch (e) { if (mounted) ErrorHandler.showException(context, e, contextLabel: 'Local Backup'); }
  }
}

class GameDetailActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? textColor;
  final Color? iconColor;

  const GameDetailActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.textColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDestructive = textColor == Colors.red || textColor == Colors.redAccent;
    return FocusEffectWrapper(
      onTap: onTap,
      borderRadius: 14.0,
      scaleFactor: 1.005,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isDestructive
              ? Colors.red.withValues(alpha: 0.05)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDestructive
                ? Colors.red.withValues(alpha: 0.15)
                : theme.colorScheme.outline.withValues(alpha: 0.3),
            width: 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: iconColor ?? (isDestructive ? Colors.redAccent : theme.colorScheme.onSurfaceVariant)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
