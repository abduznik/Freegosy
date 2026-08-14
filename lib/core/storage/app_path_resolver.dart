import 'dart:typed_data';

/// Resolves OS-level application directories and bundled assets.
///
/// [DirectoryService] depends on this instead of calling `package:path_provider`
/// directly, so a pure-Dart entry point (e.g. a CLI) can supply an
/// implementation backed by plain `dart:io` env vars instead of the Flutter
/// engine's platform channels.
abstract class AppPathResolver {
  /// The per-user, per-app directory for persistent app data (equivalent to
  /// `path_provider`'s `getApplicationSupportDirectory()`).
  Future<String> getApplicationSupportPath();

  /// A directory for transient files (equivalent to `path_provider`'s
  /// `getTemporaryDirectory()`).
  Future<String> getTemporaryPath();

  /// Loads a bundled asset by its pubspec `assets` path (e.g.
  /// `thirdparty/7zr.exe`). Returns null if assets aren't available in this
  /// runtime (e.g. a CLI with no Flutter asset bundle).
  Future<Uint8List?> loadAsset(String assetPath);
}
