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
    );
  }
}

class Platform {
  final int id;
  final String name;
  final String slug;

  Platform({
    required this.id,
    required this.name,
    required this.slug,
  });

  factory Platform.fromJson(Map<String, dynamic> json) {
    return Platform(
      id: json['id'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
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

  RomMConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  factory RomMConfig.fromJson(Map<String, dynamic> json) {
    return RomMConfig(
      baseUrl: json['baseUrl']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'username': username,
      'password': password,
    };
  }
}
