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

class Platform {
  final int id;
  final String name;
  final String slug;
  final int gamesCount;

  Platform({
    required this.id,
    required this.name,
    required this.slug,
    this.gamesCount = 0,
  });

  factory Platform.fromJson(Map<String, dynamic> json) {
    return Platform(
      id: json['id'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      gamesCount: (json['rom_count'] as int?) ?? 
                  (json['roms_count'] as int?) ?? 
                  (json['games_count'] as int?) ?? 0,
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
