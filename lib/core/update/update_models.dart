/// Which releases the updater considers.
enum UpdateChannel {
  stable,
  prerelease;

  String get label => this == stable ? 'Stable releases only' : 'Stable + pre-releases';

  static UpdateChannel parse(String? raw) =>
      raw == 'prerelease' ? UpdateChannel.prerelease : UpdateChannel.stable;
}

/// How this copy of Freegosy was installed, which decides how it can update.
enum InstallKind {
  /// Linux AppImage: the file is swapped in place.
  appImage,

  /// Windows Inno Setup install: the new installer runs silently.
  windowsInstaller,

  /// Windows portable zip: the new zip is extracted over the install folder.
  windowsPortable,

  /// macOS `.app` bundle: the bundle is replaced.
  macApp,

  /// Portable zip/tarball, Nix, Flatpak, dev builds…: can't replace itself,
  /// so the user is pointed at the release page.
  manual,
}

/// A release newer than the running build, plus the asset to install it from.
class UpdateInfo {
  final String version;
  final String tag;
  final bool prerelease;

  /// Same version as the running build, but the published files differ.
  final bool isRebuild;
  final String notes;
  final String pageUrl;

  /// Null when the release has no asset for this install type.
  final String? assetName;
  final String? assetUrl;
  final int? assetSize;

  /// Lowercase hex SHA-256 published by GitHub for the asset, if any.
  final String? sha256;

  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.prerelease,
    this.isRebuild = false,
    required this.notes,
    required this.pageUrl,
    this.assetName,
    this.assetUrl,
    this.assetSize,
    this.sha256,
  });

  bool get hasAsset => assetUrl != null;
}
