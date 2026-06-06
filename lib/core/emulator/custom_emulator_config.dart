enum CustomSaveMethod {
  file,
  folder,
}

class CustomEmulatorConfig {
  final String id;
  final String name;
  final List<String> platforms;
  final String executablePath;
  final String? commandOverride; // e.g. "flatpak run org.libretro.RetroArch"
  final CustomSaveMethod saveMethod;
  final String savePath;
  final String? savePattern; // e.g. "*.srm" for file-based

  CustomEmulatorConfig({
    required this.id,
    required this.name,
    required this.platforms,
    required this.executablePath,
    this.commandOverride,
    required this.saveMethod,
    required this.savePath,
    this.savePattern,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'platforms': platforms,
    'executablePath': executablePath,
    if (commandOverride != null) 'commandOverride': commandOverride,
    'saveMethod': saveMethod.name,
    'savePath': savePath,
    'savePattern': savePattern,
  };

  factory CustomEmulatorConfig.fromJson(Map<String, dynamic> json) => CustomEmulatorConfig(
    id: json['id'],
    name: json['name'],
    platforms: List<String>.from(json['platforms']),
    executablePath: json['executablePath'],
    commandOverride: json['commandOverride'],
    saveMethod: CustomSaveMethod.values.byName(json['saveMethod']),
    savePath: json['savePath'],
    savePattern: json['savePattern'],
  );

  bool get isCommandOverride => commandOverride != null && commandOverride!.isNotEmpty;
}
