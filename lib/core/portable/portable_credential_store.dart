import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

import '../platform/platform_info.dart';
import '../storage/secret_store.dart';
import 'dpapi.dart';

/// A portable copy's secrets for one PC and Windows user: a DPAPI-encrypted
/// JSON map in `userdata\credentials\<PC>-<user>-<id>.dat`. Each PC keeps its own
/// file, so signing in once per PC is enough.
class PortableCredentialStore implements SecretStore {
  PortableCredentialStore({
    required this.dir,
    required DataProtector protector,
    required this.machineName,
    required this.userName,
    required this.machineId,
  }) : _protector = protector;

  factory PortableCredentialStore.forThisPc(String dir) {
    final env = PlatformInfo.current.environment;
    return PortableCredentialStore(
      dir: dir,
      protector: DpapiDataProtector(),
      machineName: env['COMPUTERNAME'] ?? 'PC',
      userName: env['USERNAME'] ?? 'user',
      machineId: readMachineGuid() ?? env['COMPUTERNAME'] ?? '',
    );
  }

  final String dir;
  final DataProtector _protector;
  final String machineName;
  final String userName;
  final String machineId;
  final _lock = Lock();
  Map<String, String>? _cache;

  static String _safe(String s) => s.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

  String get fileName {
    final id = sha256.convert(utf8.encode('$machineId\n$userName')).toString().substring(0, 8);
    return '${_safe(machineName)}-${_safe(userName)}-$id.dat';
  }

  io.File get _file => io.File(p.join(dir, fileName));

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    if (!await _file.exists()) return _cache = {};
    final plain = _protector.unprotect(await _file.readAsBytes());
    if (plain == null) {
      debugPrint('[Portable] Credentials in $fileName can\'t be decrypted on this PC; sign in again');
      return _cache = {};
    }
    try {
      return _cache = Map<String, String>.from(jsonDecode(utf8.decode(plain)) as Map);
    } on Object catch (e) {
      // Decrypted but unusable (bad UTF-8, bad JSON, wrong shape). Never log content.
      debugPrint('[Portable] Credentials in $fileName are unreadable (${e.runtimeType}); sign in again');
      return _cache = {};
    }
  }

  Future<void> _save() async {
    final bytes = _protector.protect(Uint8List.fromList(utf8.encode(jsonEncode(_cache))));
    await io.Directory(dir).create(recursive: true);
    final tmp = io.File('${_file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(_file.path);
  }

  @override
  Future<String?> read(String key) => _lock.synchronized(() async => (await _load())[key]);

  @override
  Future<Map<String, String>> readAll() => _lock.synchronized(() async => Map.of(await _load()));

  @override
  Future<void> write(String key, String value) => _lock.synchronized(() async {
        (await _load())[key] = value;
        await _save();
      });

  @override
  Future<void> delete(String key) => _lock.synchronized(() async {
        if ((await _load()).remove(key) != null) await _save();
      });

  Future<void> writeAll(Map<String, String> values) => _lock.synchronized(() async {
        _cache = Map.of(values);
        await _save();
      });
}
