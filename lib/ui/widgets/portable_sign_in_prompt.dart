import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/portable/portable_mode.dart';
import '../../core/romm/romm_models.dart';
import '../../main.dart' show scaffoldMessengerKey;
import '../../providers/ui_provider.dart';

bool _shown = false;

/// A portable copy on a PC it has no credentials for: say so once and offer
/// to open Settings (the RomM URL and user name are already filled in).
void maybeShowPortableSignInPrompt(WidgetRef ref, RomMConfig config) {
  if (_shown || PortableMode.current == null || config.baseUrl.isEmpty) return;
  if (config.password.isNotEmpty || (config.token ?? '').isNotEmpty || config.apiKey.isNotEmpty) return;
  _shown = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
      duration: const Duration(seconds: 12),
      content: const Text('First time on this PC — sign in to RomM'),
      action: SnackBarAction(label: 'Sign in', onPressed: () => ref.read(currentTabIndexProvider.notifier).state = 2),
    ));
  });
}
