import 'discover.dart';

class ActiveFilters {
  final List<String> genres;
  final List<String> regions;
  final List<String> languages;
  final List<String> collections;
  final List<String> statuses;
  final List<String> franchises;
  final List<String> playerCounts;
  final GameSort sort;
  final bool sortDescending;
  final bool downloadedOnly;
  final bool notDownloadedOnly;

  const ActiveFilters({
    this.genres = const [],
    this.regions = const [],
    this.languages = const [],
    this.collections = const [],
    this.statuses = const [],
    this.franchises = const [],
    this.playerCounts = const [],
    this.sort = GameSort.name,
    this.sortDescending = false,
    this.downloadedOnly = false,
    this.notDownloadedOnly = false,
  });

  bool get hasActiveFilters =>
      genres.isNotEmpty ||
      regions.isNotEmpty ||
      languages.isNotEmpty ||
      collections.isNotEmpty ||
      statuses.isNotEmpty ||
      franchises.isNotEmpty ||
      playerCounts.isNotEmpty ||
      sort != GameSort.name ||
      downloadedOnly ||
      notDownloadedOnly;

  ActiveFilters copyWith({
    List<String>? genres,
    List<String>? regions,
    List<String>? languages,
    List<String>? collections,
    List<String>? statuses,
    List<String>? franchises,
    List<String>? playerCounts,
    GameSort? sort,
    bool? sortDescending,
    bool? downloadedOnly,
    bool? notDownloadedOnly,
  }) {
    return ActiveFilters(
      genres: genres ?? this.genres,
      regions: regions ?? this.regions,
      languages: languages ?? this.languages,
      collections: collections ?? this.collections,
      statuses: statuses ?? this.statuses,
      franchises: franchises ?? this.franchises,
      playerCounts: playerCounts ?? this.playerCounts,
      sort: sort ?? this.sort,
      sortDescending: sortDescending ?? this.sortDescending,
      downloadedOnly: downloadedOnly ?? this.downloadedOnly,
      notDownloadedOnly: notDownloadedOnly ?? this.notDownloadedOnly,
    );
  }

  Map<String, dynamic> toJson() => {
        if (genres.isNotEmpty) 'genres': genres,
        if (regions.isNotEmpty) 'regions': regions,
        if (languages.isNotEmpty) 'languages': languages,
        if (collections.isNotEmpty) 'collections': collections,
        if (statuses.isNotEmpty) 'statuses': statuses,
        if (franchises.isNotEmpty) 'franchises': franchises,
        if (playerCounts.isNotEmpty) 'playerCounts': playerCounts,
        'sort': sort.name,
        'sortDescending': sortDescending,
        if (downloadedOnly) 'downloadedOnly': true,
        if (notDownloadedOnly) 'notDownloadedOnly': true,
      };

  factory ActiveFilters.fromJson(Map<String, dynamic> json) {
    List<String> list(String key) => (json[key] as List?)?.map((e) => e.toString()).toList() ?? const [];
    return ActiveFilters(
      genres: list('genres'),
      regions: list('regions'),
      languages: list('languages'),
      collections: list('collections'),
      statuses: list('statuses'),
      franchises: list('franchises'),
      playerCounts: list('playerCounts'),
      sort: GameSort.parse(json['sort']?.toString()) ?? GameSort.name,
      sortDescending: json['sortDescending'] == true,
      downloadedOnly: json['downloadedOnly'] == true,
      notDownloadedOnly: json['notDownloadedOnly'] == true,
    );
  }
}
