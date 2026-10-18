import 'package:flutter/material.dart';
import '../../core/romm/discover.dart';
import '../../providers/paginated_games_provider.dart';

class FilterBottomSheet extends StatefulWidget {
  final ActiveFilters currentFilters;
  final List<String> availableGenres;
  final List<String> availableRegions;
  final List<String> availableLanguages;
  final List<String> availableFranchises;
  final List<String> availablePlayerCounts;
  final List<Map<String, dynamic>> availableCollections;
  final Map<String, ActiveFilters> savedFilters;
  final Future<void> Function(String name, ActiveFilters filters)? onSaveFilter;
  final Future<void> Function(String name)? onDeleteSavedFilter;
  final Function(ActiveFilters) onApply;

  const FilterBottomSheet({
    super.key,
    required this.currentFilters,
    required this.availableGenres,
    required this.availableRegions,
    required this.availableLanguages,
    this.availableFranchises = const [],
    this.availablePlayerCounts = const [],
    required this.availableCollections,
    this.savedFilters = const {},
    this.onSaveFilter,
    this.onDeleteSavedFilter,
    required this.onApply,
  });

  static Future<void> show(
    BuildContext context, {
    required ActiveFilters currentFilters,
    required List<String> availableGenres,
    required List<String> availableRegions,
    required List<String> availableLanguages,
    List<String> availableFranchises = const [],
    List<String> availablePlayerCounts = const [],
    required List<Map<String, dynamic>> availableCollections,
    Map<String, ActiveFilters> savedFilters = const {},
    Future<void> Function(String name, ActiveFilters filters)? onSaveFilter,
    Future<void> Function(String name)? onDeleteSavedFilter,
    required Function(ActiveFilters) onApply,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FilterBottomSheet(
        currentFilters: currentFilters,
        availableGenres: availableGenres,
        availableRegions: availableRegions,
        availableLanguages: availableLanguages,
        availableFranchises: availableFranchises,
        availablePlayerCounts: availablePlayerCounts,
        availableCollections: availableCollections,
        savedFilters: savedFilters,
        onSaveFilter: onSaveFilter,
        onDeleteSavedFilter: onDeleteSavedFilter,
        onApply: onApply,
      ),
    );
  }

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late List<String> _selectedGenres;
  late List<String> _selectedRegions;
  late List<String> _selectedLanguages;
  late List<String> _selectedCollections;
  late List<String> _selectedStatuses;
  late List<String> _selectedFranchises;
  late List<String> _selectedPlayerCounts;
  late GameSort _sort;
  late bool _sortDescending;
  late Map<String, ActiveFilters> _saved;
  bool _downloadedOnly = false;
  bool _notDownloadedOnly = false;

  @override
  void initState() {
    super.initState();
    _selectedGenres = List.from(widget.currentFilters.genres);
    _selectedRegions = List.from(widget.currentFilters.regions);
    _selectedLanguages = List.from(widget.currentFilters.languages);
    _selectedCollections = List.from(widget.currentFilters.collections);
    _selectedStatuses = List.from(widget.currentFilters.statuses);
    _selectedFranchises = List.from(widget.currentFilters.franchises);
    _selectedPlayerCounts = List.from(widget.currentFilters.playerCounts);
    _sort = widget.currentFilters.sort;
    _sortDescending = widget.currentFilters.sortDescending;
    _saved = Map.of(widget.savedFilters);
    _downloadedOnly = widget.currentFilters.downloadedOnly;
    _notDownloadedOnly = widget.currentFilters.notDownloadedOnly;
  }

  ActiveFilters _collect() => ActiveFilters(
        genres: _selectedGenres,
        regions: _selectedRegions,
        languages: _selectedLanguages,
        collections: _selectedCollections,
        statuses: _selectedStatuses,
        franchises: _selectedFranchises,
        playerCounts: _selectedPlayerCounts,
        sort: _sort,
        sortDescending: _sortDescending,
        downloadedOnly: _downloadedOnly,
        notDownloadedOnly: _notDownloadedOnly,
      );

  void _load(ActiveFilters f) {
    setState(() {
      _selectedGenres = List.from(f.genres);
      _selectedRegions = List.from(f.regions);
      _selectedLanguages = List.from(f.languages);
      _selectedCollections = List.from(f.collections);
      _selectedStatuses = List.from(f.statuses);
      _selectedFranchises = List.from(f.franchises);
      _selectedPlayerCounts = List.from(f.playerCounts);
      _sort = f.sort;
      _sortDescending = f.sortDescending;
      _downloadedOnly = f.downloadedOnly;
      _notDownloadedOnly = f.notDownloadedOnly;
    });
  }

  Future<void> _saveCurrent() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save these filters'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    final filters = _collect();
    await widget.onSaveFilter!(trimmed, filters);
    if (!mounted) return;
    setState(() {
      _saved.removeWhere((k, _) => k.toLowerCase() == trimmed.toLowerCase());
      _saved[trimmed] = filters;
    });
  }

  void _clearAll() {
    setState(() {
      _selectedGenres.clear();
      _selectedRegions.clear();
      _selectedLanguages.clear();
      _selectedCollections.clear();
      _selectedStatuses.clear();
      _selectedFranchises.clear();
      _selectedPlayerCounts.clear();
      _sort = GameSort.name;
      _sortDescending = false;
      _downloadedOnly = false;
      _notDownloadedOnly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkSurface = theme.brightness == Brightness.dark 
        ? Colors.grey[900] 
        : theme.colorScheme.surface;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: darkSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // SECTION 1 - Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Filters',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onSaveFilter != null)
                          TextButton(onPressed: _saveCurrent, child: const Text('Save')),
                        TextButton(
                          onPressed: _clearAll,
                          child: const Text('Clear All'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (_saved.isNotEmpty) ...[
                      _buildSectionTitle('Saved filters'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            for (final entry in _saved.entries)
                              InputChip(
                                label: Text(entry.key),
                                onPressed: () => _load(entry.value),
                                onDeleted: widget.onDeleteSavedFilter == null
                                    ? null
                                    : () async {
                                        await widget.onDeleteSavedFilter!(entry.key);
                                        if (mounted) setState(() => _saved.remove(entry.key));
                                      },
                              ),
                          ],
                        ),
                      ),
                    ],

                    // SECTION 2 - Quick toggles
                    _buildSectionTitle('Quick Toggles'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Downloaded'),
                            selected: _downloadedOnly,
                            onSelected: (selected) {
                              setState(() {
                                _downloadedOnly = selected;
                                if (selected) _notDownloadedOnly = false;
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Not Downloaded'),
                            selected: _notDownloadedOnly,
                            onSelected: (selected) {
                              setState(() {
                                _notDownloadedOnly = selected;
                                if (selected) _downloadedOnly = false;
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Backlog'),
                            selected: _selectedStatuses.contains('backlogged'),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedStatuses.add('backlogged');
                                } else {
                                  _selectedStatuses.remove('backlogged');
                                }
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Now Playing'),
                            selected: _selectedStatuses.contains('now_playing'),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedStatuses.add('now_playing');
                                } else {
                                  _selectedStatuses.remove('now_playing');
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    // SECTION 3 - Collections
                    if (widget.availableCollections.isNotEmpty) ...[
                      _buildSectionTitle('Collections'),
                      SizedBox(
                        height: 50,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: widget.availableCollections.length,
                          itemBuilder: (context, index) {
                            final collection = widget.availableCollections[index];
                            final name = collection['name']?.toString() ?? 'Unknown';
                            final id = collection['id']?.toString() ?? name;
                            final isSelected = _selectedCollections.contains(id);
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(name),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    // The server filters by one collection id.
                                    _selectedCollections.clear();
                                    if (selected) _selectedCollections.add(id);
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    _buildSectionTitle('Sort by'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final option in GameSort.values)
                            ChoiceChip(
                              label: Text(option.label),
                              selected: _sort == option,
                              onSelected: (_) => setState(() {
                                _sort = option;
                                _sortDescending = option.newestFirst;
                              }),
                            ),
                          FilterChip(
                            label: Text(_sortDescending ? 'Descending' : 'Ascending'),
                            avatar: Icon(_sortDescending ? Icons.arrow_downward : Icons.arrow_upward, size: 16),
                            onSelected: (_) => setState(() => _sortDescending = !_sortDescending),
                          ),
                        ],
                      ),
                    ),

                    if (widget.availableFranchises.isNotEmpty) ...[
                      _buildSectionTitle('Franchises'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 0,
                          children: widget.availableFranchises.map((value) {
                            return FilterChip(
                              label: Text(value),
                              selected: _selectedFranchises.contains(value),
                              onSelected: (selected) => setState(() {
                                if (selected) {
                                  _selectedFranchises.add(value);
                                } else {
                                  _selectedFranchises.remove(value);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                      ),
                    ],

                    if (widget.availablePlayerCounts.isNotEmpty) ...[
                      _buildSectionTitle('Players'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 0,
                          children: widget.availablePlayerCounts.map((value) {
                            return FilterChip(
                              label: Text(value),
                              selected: _selectedPlayerCounts.contains(value),
                              onSelected: (selected) => setState(() {
                                if (selected) {
                                  _selectedPlayerCounts.add(value);
                                } else {
                                  _selectedPlayerCounts.remove(value);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                      ),
                    ],

                    // SECTION 4 - Genres
                    if (widget.availableGenres.isNotEmpty) ...[
                      _buildSectionTitle('Genres'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 0,
                          children: widget.availableGenres.map((genre) {
                            final isSelected = _selectedGenres.contains(genre);
                            return FilterChip(
                              label: Text(genre),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedGenres.add(genre);
                                  } else {
                                    _selectedGenres.remove(genre);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ],

                    // SECTION 5 - Regions
                    if (widget.availableRegions.isNotEmpty) ...[
                      _buildSectionTitle('Regions'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 0,
                          children: widget.availableRegions.map((region) {
                            final isSelected = _selectedRegions.contains(region);
                            return FilterChip(
                              label: Text(region),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedRegions.add(region);
                                  } else {
                                    _selectedRegions.remove(region);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ],

                    // SECTION 6 - Languages
                    if (widget.availableLanguages.isNotEmpty) ...[
                      _buildSectionTitle('Languages'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 0,
                          children: widget.availableLanguages.map((lang) {
                            final isSelected = _selectedLanguages.contains(lang);
                            return FilterChip(
                              label: Text(lang),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedLanguages.add(lang);
                                  } else {
                                    _selectedLanguages.remove(lang);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // SECTION 7 - Apply button
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      final newFilters = _collect();
                      widget.onApply(newFilters);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }
}
