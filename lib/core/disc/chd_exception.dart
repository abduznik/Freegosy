/// A CHD file Freegosy can't read natively: not a CHD, damaged, or using
/// something the native reader doesn't do (an older CHD version, FLAC
/// audio, a parent CHD). chdman, when installed, may still read it.
class ChdException implements Exception {
  const ChdException(this.message);
  final String message;

  @override
  String toString() => 'ChdException: $message';
}
