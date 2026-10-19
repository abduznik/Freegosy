/// Which games have synced saves on this machine, read from the records the
/// sync service keeps in preferences: `last_pull_<id>` after a save was
/// downloaded, and `last_hash_<id>_<file>` after one was uploaded.
Set<String> syncedGameIds(Iterable<String> prefKeys) {
  final ids = <String>{};
  for (final key in prefKeys) {
    if (key.startsWith('last_pull_')) {
      final id = key.substring('last_pull_'.length);
      if (id.isNotEmpty) ids.add(id);
    } else if (key.startsWith('last_hash_')) {
      final rest = key.substring('last_hash_'.length);
      final cut = rest.indexOf('_');
      if (cut > 0) ids.add(rest.substring(0, cut));
    }
  }
  return ids;
}
