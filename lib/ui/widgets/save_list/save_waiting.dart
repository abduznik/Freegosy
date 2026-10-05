import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/romm_provider.dart';

/// Shown while a game's saves are being listed: a spinner and, when another
/// save operation holds the save lock (an upload after a session can take
/// minutes), what it is waiting for.
class SaveWaiting extends ConsumerWidget {
  const SaveWaiting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(saveSyncServiceProvider).valueOrNull;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          if (sync != null)
            ValueListenableBuilder<String?>(
              valueListenable: sync.activity,
              builder: (context, what, _) => what == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('Waiting for: $what',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
            ),
        ]),
      ),
    );
  }
}
