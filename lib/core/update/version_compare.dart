/// Semver-ish comparison for release tags like `v0.6.1` or `0.6.1-pre.2`.
/// A version with a pre-release suffix sorts before the same version without.
class VersionCompare {
  VersionCompare._();

  static final _re = RegExp(r'^[vV]?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:[-.+]?([0-9A-Za-z.\-]+))?');

  /// Negative if [a] < [b], 0 if equal, positive if [a] > [b]. Unparseable
  /// versions compare as equal so a odd tag never triggers an update.
  static int compare(String a, String b) {
    final pa = _re.firstMatch(a.trim());
    final pb = _re.firstMatch(b.trim());
    if (pa == null || pb == null) return 0;
    for (var i = 1; i <= 3; i++) {
      final d = (int.tryParse(pa.group(i) ?? '') ?? 0) - (int.tryParse(pb.group(i) ?? '') ?? 0);
      if (d != 0) return d;
    }
    final sa = _suffix(pa.group(4));
    final sb = _suffix(pb.group(4));
    if (sa == null && sb == null) return 0;
    if (sa == null) return 1;
    if (sb == null) return -1;
    return sa.compareTo(sb);
  }

  /// Build metadata like `+1` is not a pre-release marker.
  static String? _suffix(String? s) => (s == null || s.isEmpty) ? null : s;

  static bool isNewer(String candidate, String current) => compare(candidate, current) > 0;
}
