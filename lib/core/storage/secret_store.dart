/// Where [SecureStorageService] keeps secrets when it isn't using the
/// platform's secure storage (e.g. a portable copy's per-PC file).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}
