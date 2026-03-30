import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../storage/directory_service.dart';

Future<void> _extractZipIsolate(List<dynamic> args) async {
  final bytes = args[0] as Uint8List;
  final destDir = args[1] as String;
  final archive = ZipDecoder().decodeBytes(bytes);
  extractArchiveToDisk(archive, destDir);
}

class ExtractionService {
  final DirectoryService directoryService;

  ExtractionService(this.directoryService);

  Future<void> extract(String archivePath, String destDir) async {
    final pathLower = archivePath.toLowerCase();

    try {
      if (pathLower.endsWith('.dmg')) {
        await _handleDmg(archivePath, destDir);
      } else if (pathLower.endsWith('.tar.gz') || pathLower.endsWith('.tgz') || 
                 pathLower.endsWith('.tar.xz') || pathLower.endsWith('.tar')) {
        await _handleTar(archivePath, destDir);
      } else if (pathLower.endsWith('.zip')) {
        await _handleZip(archivePath, destDir);
      } else if (pathLower.endsWith('.7z')) {
        await _handleSevenZip(archivePath, destDir);
      } else if (pathLower.endsWith('.exe')) {
        await _handleExe(archivePath, destDir);
      } else {
        await _handleGeneric(archivePath, destDir);
      }
    } catch (e) {
      debugPrint('Extraction failed for $archivePath: $e');
      rethrow;
    }
  }

  Future<void> _handleTar(String archivePath, String destDir) async {
    if (Platform.isMacOS || Platform.isLinux) {
      try {
        // 'tar -xf' handles gzip, xz, etc. automatically on modern systems
        final result = await Process.run(
          'tar',
          ['-xf', archivePath, '-C', destDir],
          runInShell: false,
        );
        if (result.exitCode != 0) {
          throw Exception('tar failed: ${result.stderr}');
        }

        if (Platform.isMacOS) {
          // Find and sanitize any .app bundles
          final findResult = await Process.run(
            'find', [destDir, '-name', '*.app', '-maxdepth', '3'],
            runInShell: false,
          );
          for (final appPath in findResult.stdout.toString().trim().split('\n')) {
            if (appPath.isEmpty) continue;
            
            String finalAppPath = appPath;
            // Feature: Rename versioned apps to canonical names (e.g. PCSX2-v2.6.3.app -> PCSX2.app)
            final name = p.basename(appPath);
            if (name.contains('-v') || name.contains('_v')) {
              final parts = name.split(RegExp(r'[-_]v'));
              if (parts.isNotEmpty) {
                final canonicalName = '${parts.first}.app';
                final newPath = p.join(p.dirname(appPath), canonicalName);
                try {
                  await Directory(appPath).rename(newPath);
                  finalAppPath = newPath;
                } catch (_) {}
              }
            }

            await _sanitizeAppBundle(finalAppPath);
          }
        }
      } catch (e) {
        debugPrint('Error during tar extraction: $e');
        rethrow;
      }
    } else {
      throw Exception('tar extraction is not supported on this platform');
    }
  }

  Future<void> _handleDmg(String archivePath, String destDir) async {
    if (!Platform.isMacOS) {
      throw Exception('DMG extraction is only supported on macOS');
    }

    // Task Requirement 2: hdiutil attach with -nobrowse and -readonly
    final mountResult = await Process.run(
      'hdiutil',
      ['attach', archivePath, '-nobrowse', '-readonly'],
    );
    if (mountResult.exitCode != 0) {
      throw Exception('Failed to mount DMG: ${mountResult.stderr}');
    }

    String? mountPoint;
    // Robust mount point detection
    final lines = mountResult.stdout.toString().split('\n');
    for (final line in lines) {
      if (line.contains('/Volumes/')) {
        mountPoint = line.substring(line.indexOf('/Volumes/')).trim();
        break;
      }
    }

    if (mountPoint == null) {
      // Try parsing standard hdiutil output which might have mount point at the end
      final lastLine = lines.where((l) => l.trim().isNotEmpty).last;
      if (lastLine.contains('/Volumes/')) {
        mountPoint = lastLine.substring(lastLine.indexOf('/Volumes/')).trim();
      }
    }

    if (mountPoint == null) {
      throw Exception('Could not determine DMG mount point');
    }

    try {
      final volume = Directory(mountPoint);
      await for (final entity in volume.list()) {
        if (entity is Directory && entity.path.endsWith('.app')) {
          final appName = p.basename(entity.path);
          final destPath = p.join(destDir, appName);
          
          // Use cp -R to preserve symlinks and metadata which is critical for .app bundles
          final cpResult = await Process.run('cp', ['-R', entity.path, destDir]);
          if (cpResult.exitCode != 0) {
            throw Exception('Failed to copy .app bundle: ${cpResult.stderr}');
          }
          
          // Task Requirement 2: Quarantine removal and codesigning
          await _sanitizeAppBundle(destPath);
          break;
        }
      }
    } catch (e) {
      debugPrint('Error copying from DMG: $e');
      rethrow;
    } finally {
      // Task Requirement 2: hdiutil detach -force
      await Process.run('hdiutil', ['detach', mountPoint, '-force']);
    }
  }

  Future<void> _handleZip(String archivePath, String destDir) async {
    if (Platform.isMacOS || Platform.isLinux) {
      final result = await Process.run(
        'unzip',
        ['-o', archivePath, '-d', destDir],
        runInShell: false,
      );
      if (result.exitCode != 0) {
        throw Exception('unzip failed: ${result.stderr}');
      }
      
      if (Platform.isMacOS) {
        // Find and sanitize any .app bundles in the extracted files
        final findResult = await Process.run(
          'find', [destDir, '-name', '*.app', '-maxdepth', '3'],
          runInShell: false,
        );
        for (final appPath in findResult.stdout.toString().trim().split('\n')) {
          if (appPath.isEmpty) continue;
          await _sanitizeAppBundle(appPath);
        }
      }
    } else {
      final fileBytes = await File(archivePath).readAsBytes();
      await compute(_extractZipIsolate, [fileBytes, destDir]);
    }
  }

  Future<void> _handleSevenZip(String archivePath, String destDir) async {
    final sevenZipExe = await directoryService.resolveSevenZipPath();
    if (sevenZipExe == null) {
      throw Exception('7zr.exe could not be initialized. Try reinstalling Freegosy.');
    }
    final result = await Process.run(
      sevenZipExe,
      ['x', archivePath, '-o$destDir', '-y'],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw Exception('7z extraction failed: ${result.stderr}');
    }
  }

  Future<void> _handleExe(String archivePath, String destDir) async {
    var result = await Process.run(
      archivePath,
      ['-o$destDir', '-y'],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      result = await Process.run(
        archivePath,
        [],
        workingDirectory: destDir,
      );
    }
  }

  Future<void> _handleGeneric(String archivePath, String destDir) async {
    bool isZip = false;
    try {
      final raf = await File(archivePath).open();
      final header = await raf.read(4);
      await raf.close();
      isZip = header.length >= 2 && header[0] == 0x50 && header[1] == 0x4B;
    } catch (_) {}

    if (isZip) {
      await _handleZip(archivePath, destDir);
    } else {
      throw Exception('Unsupported archive format: $archivePath');
    }
  }

  Future<void> _sanitizeAppBundle(String appPath) async {
    if (!Platform.isMacOS) return;
    
    try {
      // Ensure it's executable
      await Process.run('chmod', ['-R', '+x', appPath]);
      // Task Requirement 2: Remove quarantine
      await Process.run('xattr', ['-rd', 'com.apple.quarantine', appPath]);
      // Task Requirement 2: Self-sign
      await Process.run('codesign', ['--force', '--deep', '--sign', '-', appPath]);
    } catch (e) {
      debugPrint('Warning: Could not sanitize app bundle at $appPath: $e');
    }
  }
}
