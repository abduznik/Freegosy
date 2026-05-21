import 'dart:io' as io;
import 'package:path/path.dart' as p;

enum StorageError { none, pathNotFound, permissionDenied, unknown }

class StorageStatus {
  final StorageError error;
  final String? message;
  final String? failedPath;

  const StorageStatus({this.error = StorageError.none, this.message, this.failedPath});

  bool get hasError => error != StorageError.none;
}

class FileSystemIndex {
  final String rootPath;
  final Map<String, String> files; // lowercase name -> absolute path
  final Map<String, String> dirs;  // lowercase name -> absolute path
  final Map<String, int> fileSizes; // absolute path -> size

  FileSystemIndex({
    required this.rootPath,
    required this.files,
    required this.dirs,
    required this.fileSizes,
  });

  static Future<FileSystemIndex> build(String path) async {
    final Map<String, String> files = {};
    final Map<String, String> dirs = {};
    final Map<String, int> fileSizes = {};

    final rootDir = io.Directory(path);
    if (await rootDir.exists()) {
      try {
        await for (final entity in rootDir.list(recursive: false)) {
          final name = p.basename(entity.path).toLowerCase();
          if (entity is io.File) {
            files[name] = p.absolute(entity.path);
            try {
              fileSizes[p.absolute(entity.path)] = await entity.length();
            } catch (_) {}
          } else if (entity is io.Directory) {
            dirs[name] = p.absolute(entity.path);
          }
        }
      } catch (_) {}
    }

    return FileSystemIndex(
      rootPath: path,
      files: files,
      dirs: dirs,
      fileSizes: fileSizes,
    );
  }
}
