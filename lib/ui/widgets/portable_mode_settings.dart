import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/platform_info.dart';
import '../../core/portable/portable_credential_store.dart';
import '../../core/portable/portable_handover.dart' show FlutterSecretStore;
import '../../core/portable/portable_migration.dart';
import '../../core/portable/portable_mode.dart';
import '../../core/storage/system_utils.dart';

enum PortableRowState { normalWritable, notWritable, portable }

/// Settings → Storage: turn portable mode on or off (Windows only).
class PortableModeSettings extends StatelessWidget {
  const PortableModeSettings({super.key, this.stateOverride, this.folderOverride});

  final PortableRowState? stateOverride;
  final String? folderOverride;

  static PortableRowState? _state;

  /// Worked out once per run (the folder is probed by writing a file); the
  /// app restarts whenever portable mode changes.
  static PortableRowState currentState(
          {String? folder, bool Function(String path)? exists, bool Function(String dir)? writable}) =>
      _state ??= stateFor(
          portable: PortableMode.current != null,
          folder: folder ?? p.dirname(io.Platform.resolvedExecutable),
          exists: exists,
          writable: writable);

  @visibleForTesting
  static void resetStateForTesting() => _state = null;

  /// An installer copy is never eligible, even in a writable folder: the next
  /// installer run deletes its whole folder, `data` included.
  @visibleForTesting
  static PortableRowState stateFor(
      {required bool portable,
      required String folder,
      bool Function(String path)? exists,
      bool Function(String dir)? writable}) {
    if (portable) return PortableRowState.portable;
    if (PortableMode.isInstallerCopy(folder, exists: exists)) return PortableRowState.notWritable;
    return (writable ?? PortableMode.folderWritable)(folder)
        ? PortableRowState.normalWritable
        : PortableRowState.notWritable;
  }

  static String _gb(int bytes) => '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';

  // Portable mode is Windows-only, so shown/opened paths are always Windows paths.
  static String _dataPath(String folder) => p.windows.join(folder, PortableMode.dataFolderName);

  @override
  Widget build(BuildContext context) {
    if (stateOverride == null && !PlatformInfo.current.isWindows) return const SizedBox.shrink();
    final state = stateOverride ?? currentState();
    final folder = folderOverride ?? PortableMode.current?.root ?? p.dirname(io.Platform.resolvedExecutable);
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Portable mode', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
        const SizedBox(height: 4),
        switch (state) {
          PortableRowState.normalWritable => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Keep all of Freegosy\'s data in its own folder, e.g. to run it from a USB stick.', style: muted),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => _makePortable(context, folder), child: const Text('Make this copy portable…')),
            ]),
          PortableRowState.notWritable => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Portable mode needs the zip version of Freegosy (this copy was installed with the installer or is in a protected folder).', style: muted),
              TextButton(
                onPressed: () => launchUrl(Uri.parse('https://github.com/abduznik/Freegosy/releases')),
                child: const Text('Get the zip version'),
              ),
            ]),
          PortableRowState.portable => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Portable — data is stored in ${_dataPath(folder)}', style: muted),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 8, children: [
                OutlinedButton(onPressed: () => SystemUtils.openDirectory(_dataPath(folder)), child: const Text('Open folder')),
                OutlinedButton(onPressed: () => _stopPortable(context), child: const Text('Stop being portable…')),
              ]),
            ]),
        },
      ]),
    );
  }


  static String _date(DateTime when) => DateFormat.yMMMd().format(when);

  Future<void> _makePortable(BuildContext context, String folder) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final installed = await _installedDirs();
    final migration = PortableMigration(
        root: folder, installedSupportDir: installed.support, installedDocumentsDir: installed.documents);
    final size = await migration.defaultFoldersSize(portable: false);
    if (!context.mounted) return;
    final earlier = migration.portableDataModified; // left from an earlier portable period
    final choice = await confirmDialog(
      context,
      title: 'Make this copy portable?',
      body: 'Freegosy will keep its settings, backups and caches in ${_dataPath(folder)} and restart. '
          'Copying leaves the originals on this PC.',
      copyNote: earlier != null
          ? 'This folder already has Freegosy settings from ${_date(earlier)}. They\'ll be replaced.'
          : null,
      noCopyNote: earlier != null
          ? 'This folder already has Freegosy settings from ${_date(earlier)}. They\'ll be used.'
          : null,
      copyLabel: 'Copy my current settings, backups and sign-in',
      foldersLabel: size > 0 ? 'Also copy ROMs and emulators from the default folders (${_gb(size)})' : null,
      action: 'Make portable',
    );
    if (choice == null || !context.mounted) return;
    await runThenRestart(context, navigator, () async {
      if (choice.copy) {
        await migration.toPortable(
          includeDefaultFolders: choice.includeFolders,
          installedSecrets: const FlutterSecretStore(),
          portableSecrets: PortableCredentialStore.forThisPc(p.join(migration.dataDir, 'credentials')),
        );
      } else {
        await migration.makePortableFresh();
      }
    });
  }

  Future<void> _stopPortable(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final mode = PortableMode.current!;
    final migration = PortableMigration(
        root: mode.root, installedSupportDir: mode.installedSupportDir, installedDocumentsDir: mode.installedDocumentsDir);
    final size = await migration.defaultFoldersSize(portable: true);
    if (!context.mounted) return;
    final modified = migration.installedDataModified;
    final pcFolders = migration.installedDefaultFolders;
    final choice = await confirmDialog(
      context,
      title: 'Stop being portable?',
      body: 'Freegosy restarts and keeps its data on this PC instead. '
          'The data folder stays where it is.'
          '${size > 0 ? '\n\nROMs and emulators you don\'t copy stay in the data folder and are only found while this drive is plugged in at the same letter.' : ''}',
      copyNote: modified != null
          ? 'This PC already has Freegosy settings from ${_date(modified)}. They\'ll be kept as a backup and replaced.'
          : null,
      noCopyNote: modified != null ? 'This PC\'s own Freegosy settings from ${_date(modified)} will be used.' : null,
      copyLabel: 'Copy this copy\'s settings, backups and sign-in to this PC',
      foldersLabel: size > 0 ? 'Also copy ROMs and emulators from the default folders (${_gb(size)})' : null,
      foldersNote: pcFolders.isNotEmpty
          ? 'This PC already has its own ${pcFolders.join(' and ')} folder${pcFolders.length > 1 ? 's' : ''}. '
              'It\'s kept as it is; the data folder\'s copy isn\'t copied over it.'
          : null,
      action: 'Stop being portable',
    );
    if (choice == null || !context.mounted) return;
    await runThenRestart(context, navigator, () async {
      if (choice.copy) {
        // toInstalled reads userdata\shared_preferences.json, so pending writes go first.
        await mode.prefsStore.flush();
        await migration.toInstalled(includeDefaultFolders: choice.includeFolders);
      } else {
        final marker = io.File(migration.markerPath);
        if (marker.existsSync()) await marker.delete();
      }
    });
  }

  static Future<({String support, String documents})> _installedDirs() async {
    // Not portable here, so path_provider gives the PC's normal folders.
    return (
      support: (await getApplicationSupportDirectory()).path,
      documents: (await getApplicationDocumentsDirectory()).path,
    );
  }

  /// Null when cancelled.
  @visibleForTesting
  static Future<({bool copy, bool includeFolders})?> confirmDialog(BuildContext context,
      {required String title,
      required String body,
      String? copyNote,
      String? noCopyNote,
      required String copyLabel,
      required String? foldersLabel,
      String? foldersNote,
      required String action}) {
    var copy = true;
    var includeFolders = false;
    return showDialog<({bool copy, bool includeFolders})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(body),
              // Notes that only hold for one choice: e.g. nothing is replaced when not copying.
              if (copy && copyNote != null) ...[const SizedBox(height: 12), Text(copyNote)],
              if (!copy && noCopyNote != null) ...[const SizedBox(height: 12), Text(noCopyNote)],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: copy,
                onChanged: (v) => setState(() => copy = v ?? true),
                title: Text(copyLabel),
              ),
              if (foldersLabel != null && copy)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includeFolders,
                  onChanged: (v) => setState(() => includeFolders = v ?? false),
                  title: Text(foldersLabel),
                ),
              if (copy && includeFolders && foldersNote != null) Text(foldersNote),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, (copy: copy, includeFolders: copy && includeFolders)),
                child: Text(action)),
          ],
        ),
      ),
    );
  }

  static bool _running = false;

  /// Runs [work] (copying data) behind a progress dialog, then restarts.
  /// A failed copy and a failed restart get their own messages; a second
  /// call while one is copying is ignored. [restart] is for tests.
  static Future<void> runThenRestart(BuildContext context, NavigatorState navigator, Future<void> Function() work,
      {Future<void> Function()? restart}) async {
    if (_running) return;
    _running = true;
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(content: Row(children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Copying… Freegosy restarts when done.')),
            ])));
    String? title, text;
    try {
      await work();
      try {
        await (restart ?? PortableMode.restart)();
      } catch (e) {
        title = 'Restart Freegosy';
        text = 'Done — please close Freegosy and start it again.\n\n(Restarting automatically failed: $e)';
      }
    } catch (e) {
      title = 'Nothing was changed';
      text = 'Copying failed: $e';
    } finally {
      _running = false;
    }
    if (title == null || text == null) return;
    navigator.pop(); // the progress dialog
    if (!context.mounted) return;
    await _message(context, title, text);
  }

  static Future<void> _message(BuildContext context, String title, String text) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(text),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ));
}
