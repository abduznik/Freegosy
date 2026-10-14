import 'dart:io' as io;

import 'package:path/path.dart' as p;

/// Result of comparing a download's size with the free space on its drive.
class SpaceCheck {
  final int needed;
  final int? free;
  const SpaceCheck(this.needed, this.free);

  /// False only when free space is known and below what the download needs.
  /// An unknown amount never blocks a download.
  bool get enough => free == null || free! >= needed;
}

/// Free space on the drive a download lands on, and whether a download fits.
class DiskSpace {
  DiskSpace._();

  static const _archiveExtensions = ['.zip', '.7z', '.rar', '.tar.gz', '.tar.xz'];

  /// Slack left for the emulator's own files, saves and backups.
  static const margin = 256 * 1024 * 1024;

  /// What a download of [fileSize] bytes needs. An archive is extracted next to
  /// itself, so it needs about twice its size while both exist.
  static int neededFor(int fileSize, {String? fileName}) {
    final name = (fileName ?? '').toLowerCase();
    final isArchive = _archiveExtensions.any(name.endsWith);
    return (isArchive ? fileSize * 2 : fileSize) + margin;
  }

  /// Free bytes on the drive holding [path] (which need not exist yet), or null
  /// when it can't be found out.
  static Future<int?> freeBytes(String path, {Future<io.ProcessResult> Function(String, List<String>)? run}) async {
    run ??= (exe, args) => io.Process.run(exe, args);
    var dir = p.absolute(path);
    while (!io.Directory(dir).existsSync() && p.dirname(dir) != dir) {
      dir = p.dirname(dir);
    }
    try {
      if (io.Platform.isWindows) {
        final letter = RegExp(r'^([A-Za-z]):').firstMatch(dir)?.group(1);
        if (letter == null) return null;
        final r = await run('powershell', ['-NoProfile', '-Command', '(Get-PSDrive -Name $letter).Free']);
        return r.exitCode == 0 ? int.tryParse(r.stdout.toString().trim()) : null;
      }
      final r = await run('df', ['-Pk', dir]);
      return r.exitCode == 0 ? parseDfAvailableBytes(r.stdout.toString()) : null;
    } catch (_) {
      return null;
    }
  }

  /// Available bytes from `df -Pk` output (POSIX format, 1024-byte blocks).
  static int? parseDfAvailableBytes(String output) {
    final lines = output.trim().split('\n');
    if (lines.length < 2) return null;
    final cols = lines.last.trim().split(RegExp(r'\s+'));
    if (cols.length < 4) return null;
    final kb = int.tryParse(cols[3]);
    return kb == null ? null : kb * 1024;
  }

  static String format(int bytes) {
    const gb = 1024 * 1024 * 1024, mb = 1024 * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(bytes >= 10 * gb ? 0 : 1)} GB';
    if (bytes >= mb) return '${(bytes / mb).round()} MB';
    return '${(bytes / 1024).round()} KB';
  }
}
