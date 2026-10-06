/// How an emulator lays out a game's saves on disk under RomM's
/// `save_target` (RomM 5.3+, read by argosy-sigil when RomM scans the ROM).
enum SaveTargetLayout {
  /// One folder named exactly `save_target`.
  folderExact('folder-exact'),

  /// Several folders whose names start with `save_target` (PSP, PS2, PS3).
  folderPrefix('folder-prefix'),

  /// One file named `save_target`.
  fileExact('file-exact'),

  /// Several files whose names contain `save_target` (GameCube `.gci`).
  filePrefix('file-prefix'),

  /// `save_target` is a `/`-separated path of folders (3DS `00040000/00033500`).
  folderSplit('folder-split');

  const SaveTargetLayout(this.json);

  /// The value as RomM's API sends it (`folder-prefix`).
  final String json;

  /// RomM's value, or null for anything else (absent, unknown, not a string).
  /// The enum's names in RomM's database (`FOLDER_PREFIX`) are read too.
  static SaveTargetLayout? fromJson(Object? value) {
    if (value is! String) return null;
    final wanted = value.toLowerCase().replaceAll('_', '-');
    for (final layout in values) {
      if (layout.json == wanted) return layout;
    }
    return null;
  }

  String toJson() => json;
}
