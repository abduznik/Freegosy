import 'package:flutter/material.dart';

import '../../core/portable/portable_migration.dart';
import '../../core/portable/portable_mode.dart';
import '../widgets/portable_mode_settings.dart';

/// A new portable copy on a PC that has an installed Freegosy: offer to bring
/// its settings over before normal onboarding.
class PortableImportScreen extends StatefulWidget {
  const PortableImportScreen({super.key, required this.onStartFresh, this.importWork, this.restart});

  final VoidCallback onStartFresh;

  /// For tests: replace copying the PC's data, and restarting.
  final Future<void> Function()? importWork;
  final Future<void> Function()? restart;

  /// True for a portable copy that started empty while the PC has data.
  static bool shouldOffer() {
    final mode = PortableMode.current;
    if (mode == null) return false;
    return offerFor(
      startedEmpty: mode.startedEmpty,
      skipOffer: mode.prefsStore.valueOf('flutter.${PortableMigration.skipImportOfferKey}') == true,
      installedHasData: PortableMigration(
              root: mode.root,
              installedSupportDir: mode.installedSupportDir,
              installedDocumentsDir: mode.installedDocumentsDir)
          .installedHasData,
    );
  }

  /// [skipOffer]: the copy was made portable without copying, so the user
  /// already chose not to bring the PC's settings over.
  @visibleForTesting
  static bool offerFor({required bool startedEmpty, required bool skipOffer, required bool installedHasData}) =>
      startedEmpty && !skipOffer && installedHasData;

  @override
  State<PortableImportScreen> createState() => _PortableImportScreenState();
}

class _PortableImportScreenState extends State<PortableImportScreen> {
  bool _busy = false;

  Future<void> _copyIn() async {
    final mode = PortableMode.current!;
    final migration = PortableMigration(
        root: mode.root, installedSupportDir: mode.installedSupportDir, installedDocumentsDir: mode.installedDocumentsDir);
    final values = await migration.importInstalled(includeDefaultFolders: false);
    await mode.prefsStore.replaceAll(values);
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context, rootNavigator: true);
    try {
      await PortableModeSettings.runThenRestart(context, navigator, widget.importWork ?? _copyIn,
          restart: widget.restart);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.usb, size: 48),
              const SizedBox(height: 16),
              const Text('This is a new portable copy of Freegosy.', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Freegosy is also installed on this PC. Bring its settings, backups and sign-in over?',
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: [
                OutlinedButton(onPressed: _busy ? null : widget.onStartFresh, child: const Text('Start fresh')),
                FilledButton(
                    onPressed: _busy ? null : _import,
                    child: const Text('Import settings from the Freegosy installed on this PC')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
