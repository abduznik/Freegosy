class Game {
  final String id;
  final String name;
  final int? platformId;
  final String? platformSlug;
  final String? platformDisplayName;
  final String? pathCoverLarge;
  final String? pathCoverSmall;
  final String? urlCover;
  final String? fileUrl; // Now nullable, to be replaced by constructed URL
  final String? fileName; // Added: maps to 'file_name' in JSON
  final String? fsName; // Added: maps to 'fs_name' in JSON
  final int fileSize; // Kept
  final String? multiFilePath; // maps to 'multi_file_path' in JSON
  final bool hasMultipleFiles;
  final List<Map<String, dynamic>> files; // Added: list of files for multi-disc games

  // New fields
  final String? summary;
  final List<String> genres;
  final List<String> companies;
  final String? playerCount;
  final int? firstReleaseDate; // unix timestamp in milliseconds
  final double? averageRating;
  final List<String> regions;
  final List<String> languages;
  final List<String> tags;
  final List<String> mergedScreenshots; // local paths like /assets/romm/...
  final String? screenshotUrl; // from ss_metadata.screenshot_url
  final String? fanartUrl; // from ss_metadata.fanart_url
  final DateTime? lastPlayed; // from rom_user.last_played
  final int userRating; // from rom_user.rating, default 0
  final int completion; // from rom_user.completion, default 0
  final String? status; // from rom_user.status
  final bool backlogged; // from rom_user.backlogged, default false
  final bool nowPlaying; // from rom_user.now_playing, default false

  bool get isMultiFile => hasMultipleFiles;

  String get displayName {
    String cleaned = name;

    // Remove leading hex IDs like 00040000000EC400
    cleaned = cleaned.replaceAll(RegExp(r'^[0-9A-Fa-f]{16}\s*'), '');

    // Remove region/version codes in parentheses like (CTR-P-BZLP) (v0.0.0) (En)
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), '');

    // Remove region/version codes in brackets like [!] [b] [T+Eng]
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '');

    // Remove trailing dots, dashes, underscores and whitespace
    cleaned = cleaned.replaceAll(RegExp(r'[\s._-]+$'), '');

    // Collapse multiple spaces into one
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    return cleaned.trim().isEmpty ? name : cleaned.trim();
  }

  Game({
    required this.id,
    required this.name,
    this.platformId,
    this.platformSlug,
    this.platformDisplayName,
    this.pathCoverLarge,
    this.pathCoverSmall,
    this.urlCover,
    this.fileUrl, // Now nullable
    this.fileName, // Added
    this.fsName, // Added
    required this.fileSize, // Kept
    this.multiFilePath,
    this.hasMultipleFiles = false,
    this.files = const [], // Added
    this.summary,
    this.genres = const [],
    this.companies = const [],
    this.playerCount,
    this.firstReleaseDate,
    this.averageRating,
    this.regions = const [],
    this.languages = const [],
    this.tags = const [],
    this.mergedScreenshots = const [],
    this.screenshotUrl,
    this.fanartUrl,
    this.lastPlayed,
    this.userRating = 0,
    this.completion = 0,
    this.status,
    this.backlogged = false,
    this.nowPlaying = false,
  });

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      platformId: json['platform_id'] as int?,
      platformSlug: json['platform_slug']?.toString(),
      platformDisplayName: json['platform_display_name']?.toString(),
      pathCoverLarge: json['path_cover_large']?.toString(),
      pathCoverSmall: json['path_cover_small']?.toString(),
      urlCover: json['url_cover']?.toString(),
      fileUrl: json['url_download']?.toString(), // Maps to original download URL, if present
      fileName: json['file_name']?.toString(), // Mapped from JSON
      fsName: json['fs_name']?.toString(), // Mapped from JSON
      fileSize: json['file_size_bytes'] is int ? json['file_size_bytes'] : 0,
      multiFilePath: json['multi_file_path']?.toString(),
      hasMultipleFiles: json['has_multiple_files'] as bool? ?? false,
      files: (json['files'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ?? [],
      summary: json['summary']?.toString(),
      genres: (json['metadatum']?['genres'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      companies: (json['metadatum']?['companies'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      playerCount: json['metadatum']?['player_count']?.toString(),
      firstReleaseDate: json['metadatum']?['first_release_date'] as int?,
      averageRating: (json['metadatum']?['average_rating'] as num?)?.toDouble(),
      regions: (json['regions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      languages: (json['languages'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      mergedScreenshots: (json['merged_screenshots'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      screenshotUrl: json['ss_metadata']?['screenshot_url']?.toString(),
      fanartUrl: json['ss_metadata']?['fanart_url']?.toString(),
      lastPlayed: json['rom_user']?['last_played'] != null ? DateTime.tryParse(json['rom_user']['last_played'].toString()) : null,
      userRating: json['rom_user']?['rating'] as int? ?? 0,
      completion: json['rom_user']?['completion'] as int? ?? 0,
      status: json['rom_user']?['status']?.toString(),
      backlogged: json['rom_user']?['backlogged'] as bool? ?? false,
      nowPlaying: json['rom_user']?['now_playing'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'platform_id': platformId,
      'platform_slug': platformSlug,
      'platform_display_name': platformDisplayName,
      'path_cover_large': pathCoverLarge,
      'path_cover_small': pathCoverSmall,
      'url_cover': urlCover,
      'url_download': fileUrl,
      'file_name': fileName,
      'fs_name': fsName,
      'file_size_bytes': fileSize,
      'multi_file_path': multiFilePath,
      'has_multiple_files': hasMultipleFiles,
    };
  }
}

class Firmware {
  final int id;
  final String fileName;
  final String? fileNameNoTags;
  final String? fileNameNoExt;
  final String? fileExtension;
  final String? filePath;
  final int fileSizeBytes;
  final bool isVerified;
  final String? crcHash;
  final String? md5Hash;
  final String? sha1Hash;
  final bool missingFromFs;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Firmware({
    required this.id,
    required this.fileName,
    this.fileNameNoTags,
    this.fileNameNoExt,
    this.fileExtension,
    this.filePath,
    required this.fileSizeBytes,
    this.isVerified = false,
    this.crcHash,
    this.md5Hash,
    this.sha1Hash,
    this.missingFromFs = false,
    this.createdAt,
    this.updatedAt,
  });

  factory Firmware.fromJson(Map<String, dynamic> json) {
    return Firmware(
      id: json['id'] as int? ?? 0,
      fileName: json['file_name']?.toString() ?? '',
      fileNameNoTags: json['file_name_no_tags']?.toString(),
      fileNameNoExt: json['file_name_no_ext']?.toString(),
      fileExtension: json['file_extension']?.toString(),
      filePath: json['file_path']?.toString(),
      fileSizeBytes: json['file_size_bytes'] as int? ?? 0,
      isVerified: json['is_verified'] as bool? ?? false,
      crcHash: json['crc_hash']?.toString(),
      md5Hash: json['md5_hash']?.toString(),
      sha1Hash: json['sha1_hash']?.toString(),
      missingFromFs: json['missing_from_fs'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }
}

class Platform {
  final int id;
  final String name;
  final String slug;
  final String fsSlug;
  final String displayName;
  final int gamesCount;
  final List<Firmware> firmware;
  final int firmwareCount;

  Platform({
    required this.id,
    required this.name,
    required this.slug,
    this.fsSlug = '',
    this.displayName = '',
    this.gamesCount = 0,
    this.firmware = const [],
    this.firmwareCount = 0,
  });

  factory Platform.fromJson(Map<String, dynamic> json) {
    return Platform(
      id: json['id'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      fsSlug: json['fs_slug']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      gamesCount: (json['rom_count'] as int?) ?? 
                  (json['roms_count'] as int?) ?? 
                  (json['games_count'] as int?) ?? 0,
      firmware: (json['firmware'] as List<dynamic>?)?.map((e) => Firmware.fromJson(e)).toList() ?? [],
      firmwareCount: json['firmware_count'] as int? ?? 0,
    );
  }
}

class SaveFile {
  final String id;
  final String gameId;
  final String url;

  SaveFile({
    required this.id,
    required this.gameId,
    required this.url,
  });

  factory SaveFile.fromJson(Map<String, dynamic> json) {
    return SaveFile(
      id: json['id']?.toString() ?? '',
      gameId: json['game_id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }
}

class RomMConfig {
  final String baseUrl;
  final String username;
  final String password;
  final String? token;
  final String apiKey; // Added apiKey field

  RomMConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.token,
    this.apiKey = '', // Added apiKey to constructor with default
  });

  factory RomMConfig.fromJson(Map<String, dynamic> json) {
    return RomMConfig(
      baseUrl: json['baseUrl']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
      token: json['token']?.toString(),
      apiKey: json['apiKey']?.toString() ?? '', // Added apiKey from JSON with default
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'username': username,
      'password': password,
      if (token != null) 'token': token,
      'apiKey': apiKey, // Added apiKey to toJson
    };
  }
}
