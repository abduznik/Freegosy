import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/romm/romm_models.dart';
import '../../core/romm/romm_service.dart';
import '../../core/error/error_handler.dart';
import '../../providers/download_provider.dart';
import '../../providers/romm_provider.dart';
import '../../providers/shared_prefs_provider.dart';
import '../widgets/screenshot_gallery_dialog.dart';
import '../widgets/download_progress_indicator.dart';

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

  @override
  void initState() {
    super.initState();
    _currentGame = widget.game;
    _isDownloaded = widget.isDownloaded;
    _syncStateWithGame(_currentGame);
    _checkDownloadStatus();
    // Initial refresh to get latest notes and status
    _refreshGame();
  }

  void _syncStateWithGame(Game game) {
    _backlogged = game.backlogged;
    _nowPlaying = game.nowPlaying;
    _rating = game.userRating;
    _status = game.status;
    _completion = game.completion;
  }

  Future<void> _checkDownloadStatus() async {
    final ds = ref.read(directoryServiceProvider).value;
    if (ds != null) {
      final exists = await ds.isRomDownloaded(_currentGame);
      if (mounted) {
        setState(() => _isDownloaded = exists);
      }
    }
  }

  Future<void> _refreshGame() async {
    if (widget.rommService == null) return;
    try {
      final updated = await widget.rommService!.getGame(_currentGame.id);
      if (updated != null && mounted) {
        setState(() {
          _currentGame = updated;
          _syncStateWithGame(updated);
        });
        _checkDownloadStatus();
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: contentController,
              decoration: const InputDecoration(labelText: 'Content'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
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
          _refreshGame();
        } else {
          if (mounted) {
            // ignore: use_build_context_synchronously
            ErrorHandler.showException(context, Exception('Failed to create note'), contextLabel: 'Add Note');
          }
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await widget.rommService!.deleteRomNote(_currentGame.id, noteId);
      if (success) {
        _refreshGame();
      } else {
        if (mounted) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete note')));
        }
      }
    }
  }

  void _viewNote(RomNote note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note.title.isNotEmpty ? note.title : 'Note'),
        content: SingleChildScrollView(
          child: Text(note.content),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProps(BuildContext context) async {
    if (widget.rommService == null) return;
    
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSaving = true);
    
    final prefs = ref.read(sharedPreferencesProvider);
    final success = await widget.rommService!.updateRomProps(
      _currentGame.id,
      prefs,
      backlogged: _backlogged,
      nowPlaying: _nowPlaying,
      rating: _rating,
      status: _status,
      completion: _completion,
    );
    
    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        _refreshGame();
        messenger.showSnackBar(
          const SnackBar(content: Text('Properties saved successfully')),
        );
      } else {
        // Safe to use ErrorHandler here if it's a global/static UI helper
        // but let's be double sure and check mounted again
        if (mounted) {
          // ignore: use_build_context_synchronously
          ErrorHandler.showException(context, Exception('Failed to update properties'), contextLabel: 'Update Status');
        }
      }
    }
  }

  void _showScreenshotFullscreen(BuildContext context, int initialIndex, List<String> imageUrls) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => ScreenshotGalleryDialog(
        initialIndex: initialIndex,
        imageUrls: imageUrls,
      ),
    );
  }

  String _normalizeUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final base = widget.rommBaseUrl.endsWith('/')
        ? widget.rommBaseUrl.substring(0, widget.rommBaseUrl.length - 1)
        : widget.rommBaseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$base$normalizedPath';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(downloadProvider, (prev, next) {
      final progress = next[_currentGame.id];
      if (progress != null && progress.isComplete) {
        // Download just finished
        _checkDownloadStatus();
        // Remove from progress map so we show the action buttons instead of "100% Done"
        ref.read(downloadProvider.notifier).removeDownload(_currentGame.id);
      }
    });

    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final headerHeight = size.height * 0.4;

    String? backgroundUrl;
    if (_currentGame.screenshotUrl != null && _currentGame.screenshotUrl!.isNotEmpty) {
      backgroundUrl = _normalizeUrl(_currentGame.screenshotUrl);
    } else if (_currentGame.mergedScreenshots.isNotEmpty) {
      backgroundUrl = _normalizeUrl(_currentGame.mergedScreenshots.first);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SECTION 1 - Hero header
            SizedBox(
              height: headerHeight,
              child: Stack(
                children: [
                  // Background Image
                  Positioned.fill(
                    child: backgroundUrl != null
                        ? CachedNetworkImage(
                            imageUrl: backgroundUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: Colors.grey[900]),
                            errorWidget: (context, url, error) => Container(color: Colors.grey[900]),
                          )
                        : Container(color: Colors.grey[900]),
                  ),
                  // Gradient Overlay
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black87,
                            Colors.black,
                          ],
                          stops: [0.5, 0.8, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Back Button
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 16,
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                  // Content (Cover + Title)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Cover Image
                        Hero(
                          tag: 'game_cover_${_currentGame.id}',
                          child: Container(
                            width: 130,
                            height: 180,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: _normalizeUrl(_currentGame.pathCoverLarge),
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(color: Colors.grey[800]),
                                errorWidget: (context, url, error) => const Icon(Icons.image_not_supported),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Title and Platform
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentGame.name,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_currentGame.platformDisplayName != null)
                                Text(
                                  _currentGame.platformDisplayName!,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white70,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // SECTION 2 - Action buttons row
                  Consumer(
                    builder: (context, ref, _) {
                      final downloads = ref.watch(downloadProvider);
                      final downloadProgress = downloads[_currentGame.id];

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (!_isDownloaded)
                            if (downloadProgress != null)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                  child: DownloadProgressIndicator(
                                    progress: downloadProgress,
                                    compact: true,
                                  ),
                                ),
                              )
                            else
                              _ActionButton(
                                icon: Icons.download,
                                label: 'Download',
                                onPressed: () async {
                                  await widget.onDownload();
                                  _checkDownloadStatus();
                                },
                              )
                          else ...[
                            _ActionButton(
                              icon: Icons.play_arrow,
                              label: 'Play',
                              onPressed: () async {
                                if (_isDownloaded) {
                                  await widget.onLaunch();
                                }
                              },
                            ),
                            _ActionButton(
                              icon: Icons.cloud_upload,
                              label: 'Push',
                              onPressed: () async {
                                if (_isDownloaded) {
                                  await widget.onPushSaves();
                                }
                              },
                            ),
                            _ActionButton(
                              icon: Icons.cloud_download,
                              label: 'Pull',
                              onPressed: () async {
                                if (_isDownloaded) {
                                  await widget.onPullSaves();
                                }
                              },
                            ),
                            _ActionButton(
                              icon: Icons.delete,
                              label: 'Delete',
                              onPressed: () async {
                                await widget.onDelete();
                                // Invalidate download provider to clear "100% done" sticky state
                                ref.invalidate(downloadProvider);
                                _checkDownloadStatus();
                              },
                              color: Colors.red,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // SECTION 3 - Metadata chips row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Genres (first 2)
                      ..._currentGame.genres.take(2).map((g) => _MetadataChip(label: g)),
                      // Player Count
                      if (_currentGame.playerCount != null && _currentGame.playerCount!.isNotEmpty)
                        _MetadataChip(
                          label: _currentGame.playerCount!,
                          icon: Icons.people_outline,
                        ),
                      // Average Rating
                      if (_currentGame.averageRating != null)
                        _MetadataChip(
                          label: '${_currentGame.averageRating!.toStringAsFixed(0)}/100',
                          icon: Icons.star_outline,
                        ),
                      // Release Year
                      if (_currentGame.firstReleaseDate != null)
                        _MetadataChip(
                          label: DateTime.fromMillisecondsSinceEpoch(_currentGame.firstReleaseDate!).year.toString(),
                          icon: Icons.calendar_today_outlined,
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // SECTION 4 - Description
                  Text(
                    'About',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currentGame.summary ?? 'No description available',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // SECTION 5 - Details grid
                  Text(
                    'Details',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DetailsGrid(game: _currentGame),
                  const SizedBox(height: 24),

                  // SECTION 6 - Notes
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Notes',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_comment, color: Colors.blue),
                        onPressed: _addNote,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_currentGame.notes.isEmpty)
                    const Text('No notes added yet.', style: TextStyle(color: Colors.white54, fontSize: 13))
                  else
                    ..._currentGame.notes.map((note) => Card(
                      color: Colors.white10,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => _viewNote(note),
                        title: Text(
                          note.title.isNotEmpty ? note.title : 'Note',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          note.content,
                          style: const TextStyle(color: Colors.white70),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
                          onPressed: () => _deleteNote(note.id),
                        ),
                      ),
                    )),
                  const SizedBox(height: 24),

                  // SECTION 7 - Screenshots
                  if (_currentGame.mergedScreenshots.isNotEmpty) ...[
                    Text(
                      'Screenshots',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _currentGame.mergedScreenshots.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final imageUrl = _normalizeUrl(_currentGame.mergedScreenshots[index]);
                          return GestureDetector(
                            onTap: () {
                              final allUrls = _currentGame.mergedScreenshots
                                  .map((path) => _normalizeUrl(path))
                                  .toList();
                              _showScreenshotFullscreen(context, index, allUrls);
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: imageUrl,
                                width: 200,
                                height: 120,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(color: Colors.grey[900]),
                                errorWidget: (context, url, error) => const Icon(Icons.image_not_supported),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // SECTION 7 - Personal
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 8),
                  Text('Personal', style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  // Status dropdown
                  Row(
                    children: [
                      const Text('Status', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      const Spacer(),
                      DropdownButton<String>(
                        value: const [
                          'never_playing',
                          'incomplete',
                          'finished',
                          'completed_100',
                          'retired'
                        ].contains(_status) ? _status : null,
                        dropdownColor: Colors.grey[900],
                        style: const TextStyle(color: Colors.white),
                        hint: const Text('Not set', style: TextStyle(color: Colors.white54)),
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'never_playing', child: Text('Never Played')),
                          DropdownMenuItem(value: 'incomplete', child: Text('Incomplete')),
                          DropdownMenuItem(value: 'finished', child: Text('Finished')),
                          DropdownMenuItem(value: 'completed_100', child: Text('100% Completed')),
                          DropdownMenuItem(value: 'retired', child: Text('Dropped')),
                        ],
                        onChanged: (val) => setState(() => _status = val),
                      ),
                    ],
                  ),

                  // Rating stars
                  Row(
                    children: [
                      const Text('Rating', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      const Spacer(),
                      Row(
                        children: List.generate(10, (i) => GestureDetector(
                          onTap: () => setState(() => _rating = i + 1),
                          child: Icon(
                            i < _rating ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                            size: 20,
                          ),
                        )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Completion slider
                  Row(
                    children: [
                      const Text('Completion', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      const Spacer(),
                      Text('$_completion%', style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                  Slider(
                    value: _completion.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '$_completion%',
                    onChanged: (val) => setState(() => _completion = val.toInt()),
                  ),

                  // Toggles row
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          title: const Text('Backlog', style: TextStyle(fontSize: 13)),
                          value: _backlogged,
                          onChanged: (val) => setState(() => _backlogged = val),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: SwitchListTile(
                          title: const Text('Now Playing', style: TextStyle(fontSize: 13)),
                          value: _nowPlaying,
                          onChanged: (val) => setState(() => _nowPlaying = val),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : () => _saveProps(context),
                      child: _isSaving
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: onPressed,
          icon: Icon(icon, color: color),
          style: IconButton.styleFrom(
            padding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color ?? Colors.white70),
        ),
      ],
    );
  }
}

class _MetadataChip extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _MetadataChip({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DetailsGrid extends StatelessWidget {
  final Game game;

  const _DetailsGrid({required this.game});

  @override
  Widget build(BuildContext context) {
    final details = <String, String>{};
    if (game.companies.isNotEmpty) details['Developer'] = game.companies.join(', ');
    if (game.regions.isNotEmpty) details['Regions'] = game.regions.join(', ');
    if (game.languages.isNotEmpty) details['Languages'] = game.languages.join(', ');
    if (game.playerCount != null && game.playerCount!.isNotEmpty) details['Players'] = game.playerCount!;

    if (details.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 40,
        crossAxisSpacing: 16,
        mainAxisSpacing: 8,
      ),
      itemCount: details.length,
      itemBuilder: (context, index) {
        final entry = details.entries.elementAt(index);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.key,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            Text(
              entry.value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}
