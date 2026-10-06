import 'dart:typed_data';

import 'package:freegosy/core/portable/dpapi.dart';
import 'package:freegosy/core/portable/portable_credential_store.dart';

class FakeProtector implements DataProtector {
  @override
  Uint8List protect(Uint8List data) => Uint8List.fromList(data.reversed.toList());
  @override
  Uint8List? unprotect(Uint8List data) => Uint8List.fromList(data.reversed.toList());
}

PortableCredentialStore fakeCredentialStore(String dir, {String pc = 'PC', String user = 'u'}) =>
    PortableCredentialStore(dir: dir, protector: FakeProtector(), machineName: pc, userName: user, machineId: 'g');
