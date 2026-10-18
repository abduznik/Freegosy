import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../constants/app_constants.dart';
import '../platform/platform_info.dart';
import 'update_models.dart';
import 'version_compare.dart';

/// Looks up GitHub releases for a newer Freegosy build and downloads the asset
/// that matches how this copy was installed. Applying it is [UpdateInstaller]'s job.
class UpdateService {
  static const repo = 'abduznik/Freegosy';
  static const releasesUrl = 'https://api.github.com/repos/$repo/releases?per_page=30';

  final Dio _dio;
  final PlatformInfo _platform;
  final Future<io.Directory> Function() _supportDir;

  /// Overridable for tests; defaults to the real executable / filesystem.
  final String Function() _resolvedExecutable;
  final bool Function(String path) _fileExists;

  UpdateService({
    Dio? dio,
    PlatformInfo? platform,
    required Future<io.Directory> Function() supportDir,
    String Function()? resolvedExecutable,
    bool Function(String path)? fileExists,
  })  : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30))),
        _platform = platform ?? PlatformInfo.current,
        _supportDir = supportDir,
        _resolvedExecutable = resolvedExecutable ?? (() => io.Platform.resolvedExecutable),
        _fileExists = fileExists ?? ((path) => io.File(path).existsSync());

  /// How this install can update itself.
  InstallKind get installKind {
    if (_platform.isLinux) {
      final appImage = _platform.environment['APPIMAGE'];
      return appImage != null && appImage.isNotEmpty ? InstallKind.appImage : InstallKind.manual;
    }
    if (_platform.isWindows) {
      // Inno Setup puts its uninstaller beside the app; the portable zip has none.
      final dir = p.dirname(_resolvedExecutable());
      return _fileExists(p.join(dir, 'unins000.exe')) ? InstallKind.windowsInstaller : InstallKind.windowsPortable;
    }
    if (_platform.isMacOS) {
      return _resolvedExecutable().contains('.app/Contents/MacOS') ? InstallKind.macApp : InstallKind.manual;
    }
    return InstallKind.manual;
  }

  /// SHA-256 of the build that is running now, when it can be known: the
  /// AppImage file itself, else [recordedSha] (digest of the last update this
  /// app applied). Null when unknown, which disables same-version rebuild checks.
  Future<String?> installedSha(String? recordedSha) async {
    if (installKind == InstallKind.appImage) {
      final f = io.File(_platform.environment['APPIMAGE']!);
      if (await f.exists()) return (await sha256.bind(f.openRead()).first).toString();
    }
    return recordedSha;
  }

  /// The newest release on [channel] that is newer than [currentVersion], or
  /// null when already up to date. A release with the *same* version but a
  /// different asset digest than [recordedSha]/the installed file counts too:
  /// pre-releases get rebuilt under the same tag. Throws on network/parse failure.
  Future<UpdateInfo?> checkForUpdate(String currentVersion, UpdateChannel channel, {String? recordedSha, bool? runningNightly}) async {
    final res = await _dio.get<List<dynamic>>(
      releasesUrl,
      options: Options(headers: {'Accept': 'application/vnd.github+json'}, responseType: ResponseType.json),
    );
    return pickUpdate(res.data ?? const [], currentVersion, channel, installKind,
        installedSha: await installedSha(recordedSha), runningNightly: runningNightly ?? AppConstants.isNightlyBuild);
  }

  /// The rolling nightly release is tagged `nightly` (older ones `v<version>-nightly`).
  /// The same tag is rebuilt every night, so it is picked by digest, never by version order.
  static bool isNightlyTag(String? tag) {
    final t = (tag ?? '').toLowerCase();
    return t == 'nightly' || t.endsWith('-nightly');
  }

  /// The release a nightly is based on, from "Based on version 0.6.1" in its notes.
  static String? nightlyBaseVersion(String? notes) =>
      RegExp(r'based on version v?(\d+\.\d+\.\d+)', caseSensitive: false).firstMatch(notes ?? '')?.group(1);

  /// Pure selection logic, split out for tests.
  ///
  /// [runningNightly]: this build is a nightly. It carries its base release's
  /// plain version number, so it only counts that release (and older) as
  /// already installed; only a strictly newer release, or a newer nightly, is an update.
  static UpdateInfo? pickUpdate(List<dynamic> releases, String currentVersion, UpdateChannel channel, InstallKind kind,
      {String? installedSha, bool runningNightly = false}) {
    final normal = _pickNormal(releases, currentVersion, channel, kind, installedSha: installedSha, runningNightly: runningNightly);
    if (channel != UpdateChannel.nightly) return normal;

    // Nightly channel: the newest nightly, unless a real release is newer than it.
    Map<String, dynamic>? nightly;
    for (final r in releases) {
      if (r is! Map<String, dynamic> || r['draft'] == true || !isNightlyTag(r['tag_name'] as String?)) continue;
      if (nightly == null || '${r['published_at'] ?? ''}'.compareTo('${nightly['published_at'] ?? ''}') > 0) nightly = r;
    }
    if (nightly == null) return normal;

    final base = nightlyBaseVersion(nightly['body'] as String?);
    if (base != null) {
      if (normal != null && VersionCompare.compare(normal.tag, base) >= 0) return normal;
      // A nightly based on an older release than this build is not an update.
      if (VersionCompare.compare(base, currentVersion.split('-').first) < 0) return normal;
    }
    final asset = _pickAsset((nightly['assets'] as List<dynamic>? ?? const []), kind);
    final sha = _digest(asset);
    if (sha != null && sha == installedSha) return normal;
    return UpdateInfo(
      version: base ?? 'nightly',
      tag: nightly['tag_name'] as String,
      prerelease: true,
      isNightly: true,
      notes: (nightly['body'] as String?) ?? '',
      pageUrl: (nightly['html_url'] as String?) ?? 'https://github.com/$repo/releases',
      assetName: asset?['name'] as String?,
      assetUrl: asset?['browser_download_url'] as String?,
      assetSize: asset?['size'] as int?,
      sha256: sha,
    );
  }

  static UpdateInfo? _pickNormal(List<dynamic> releases, String currentVersion, UpdateChannel channel, InstallKind kind,
      {String? installedSha, bool runningNightly = false}) {
    Map<String, dynamic>? best;
    String? bestVersion;
    for (final r in releases) {
      if (r is! Map<String, dynamic>) continue;
      if (r['draft'] == true) continue;
      if (r['prerelease'] == true && channel == UpdateChannel.stable) continue;
      final tag = r['tag_name'] as String?;
      if (tag == null) continue;
      // The rolling nightly is only for the nightly channel, and handled above.
      if (isNightlyTag(tag)) continue;
      if (!VersionCompare.isNewer(tag, currentVersion)) {
        // Same version rebuilt: only when both digests are known and differ.
        // Never for a nightly build, which is newer than its own release.
        if (runningNightly || VersionCompare.compare(tag, currentVersion) != 0 || installedSha == null) continue;
        final digest = _digest(_pickAsset((r['assets'] as List<dynamic>? ?? const []), kind));
        if (digest == null || digest == installedSha) continue;
      }
      if (bestVersion == null || VersionCompare.isNewer(tag, bestVersion)) {
        best = r;
        bestVersion = tag;
      }
    }
    if (best == null) return null;

    final asset = _pickAsset((best['assets'] as List<dynamic>? ?? const []), kind);
    final sha = _digest(asset);
    return UpdateInfo(
      isRebuild: VersionCompare.compare(bestVersion!, currentVersion) == 0,
      version: bestVersion.replaceFirst(RegExp(r'^[vV]'), ''),
      tag: bestVersion,
      prerelease: best['prerelease'] == true,
      notes: (best['body'] as String?) ?? '',
      pageUrl: (best['html_url'] as String?) ?? 'https://github.com/$repo/releases',
      assetName: asset?['name'] as String?,
      assetUrl: asset?['browser_download_url'] as String?,
      assetSize: asset?['size'] as int?,
      sha256: sha,
    );
  }

  static String? _digest(Map<String, dynamic>? asset) {
    final d = asset?['digest'] as String?;
    return d != null && d.startsWith('sha256:') ? d.substring(7).toLowerCase() : null;
  }

  static Map<String, dynamic>? _pickAsset(List<dynamic> assets, InstallKind kind) {
    bool Function(String) match;
    switch (kind) {
      case InstallKind.appImage:
        match = (n) => n.endsWith('.appimage');
      case InstallKind.windowsInstaller:
        match = (n) => n.endsWith('.exe');
      case InstallKind.windowsPortable:
        match = (n) => n.contains('windows') && n.endsWith('.zip');
      case InstallKind.macApp:
        match = (n) => n.contains('macos') && n.endsWith('.zip');
      case InstallKind.manual:
        return null;
    }
    for (final a in assets) {
      if (a is Map<String, dynamic> && match(((a['name'] as String?) ?? '').toLowerCase())) return a;
    }
    return null;
  }

  /// Downloads [info]'s asset into the app's update folder and returns it.
  /// An already complete download from an earlier run is reused.
  Future<io.File> download(UpdateInfo info, {void Function(double progress)? onProgress}) async {
    final url = info.assetUrl;
    final name = info.assetName;
    if (info.sha256 == null) throw StateError('Release ${info.tag} publishes no checksum for its download; update manually');
    final uri = Uri.tryParse(url ?? '');
    if (uri == null || uri.scheme != 'https' || !(uri.host == 'github.com' || uri.host.endsWith('.githubusercontent.com'))) {
      throw StateError('Refusing to download an update from an unexpected host');
    }
    if (url == null || name == null) throw StateError('Release ${info.tag} has no download for this install type');

    final dir = io.Directory(p.join((await _supportDir()).path, 'updates', info.tag));
    final target = io.File(p.join(dir.path, name));
    if (await target.exists() && await _verified(target, info)) {
      onProgress?.call(1);
      return target;
    }
    // Drop other versions' leftovers before fetching a new one.
    final root = dir.parent;
    if (await root.exists()) await root.delete(recursive: true);
    await dir.create(recursive: true);

    final part = io.File('${target.path}.part');
    await _dio.download(
      url,
      part.path,
      onReceiveProgress: (got, total) {
        final t = total > 0 ? total : (info.assetSize ?? 0);
        if (t > 0) onProgress?.call((got / t).clamp(0.0, 1.0));
      },
    );
    await part.rename(target.path);
    if (!await _verified(target, info)) {
      await target.delete();
      throw StateError('Downloaded update failed its integrity check');
    }
    return target;
  }

  Future<bool> _verified(io.File file, UpdateInfo info) async {
    final want = info.sha256;
    if (want == null) return false;
    final got = (await sha256.bind(file.openRead()).first).toString();
    return got == want;
  }
}
