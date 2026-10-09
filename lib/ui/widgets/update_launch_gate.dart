import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/platform/platform_info.dart';
import '../../providers/shared_prefs_provider.dart';
import '../../providers/update_provider.dart';
import 'dialog_back_bridge.dart';
import 'focus_effect_wrapper.dart';

/// Wraps the main screen: once, at launch, asks first-time users whether
/// Freegosy may check for updates (nothing is stored until they answer), then
/// runs the launch update check. Desktop only.
class UpdateLaunchGate extends ConsumerStatefulWidget {
  final Widget child;
  const UpdateLaunchGate({super.key, required this.child});

  @override
  ConsumerState<UpdateLaunchGate> createState() => _UpdateLaunchGateState();
}

class _UpdateLaunchGateState extends ConsumerState<UpdateLaunchGate> {
  @override
  void initState() {
    super.initState();
    final p = PlatformInfo.current;
    if (p.isWindows || p.isLinux || p.isMacOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  Future<void> _run() async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (!prefs.containsKey(updateCheckPrefKey)) {
      final choice = await showDialog<UpdateConsent>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _ConsentDialog(),
      );
      if (!mounted) return;
      final c = choice ?? UpdateConsent.never;
      ref.read(updateCheckOnLaunchProvider.notifier).update(c != UpdateConsent.never);
      ref.read(updateAutoDownloadProvider.notifier).update(c == UpdateConsent.auto);
    }
    await ref.read(updateControllerProvider.notifier).checkOnLaunch();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum UpdateConsent { auto, checkOnly, never }

class _ConsentDialog extends StatelessWidget {
  const _ConsentDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget option(String label, String sub, UpdateConsent value, {bool autofocus = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: FocusEffectWrapper(
            onTap: () => Navigator.pop(context, value),
            borderRadius: 16.0,
            autofocus: autofocus,
            useSafeScale: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(sub, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        );

    return DialogBackBridge(
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Keep Freegosy up to date?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Freegosy can look for new releases on GitHub each time it starts. You can change this any time in Settings → Updates.'),
              const SizedBox(height: 12),
              option('Check and download automatically', 'You only need to press "Restart to update".', UpdateConsent.auto, autofocus: true),
              option('Check only', 'Tell me when an update exists; I will download it.', UpdateConsent.checkOnly),
              option('Don\'t check', 'Only update when I press "Check for updates".', UpdateConsent.never),
            ],
          ),
        ),
      ),
    );
  }
}
