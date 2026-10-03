import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_models.dart';
import '../../../core/save/catalog/play_choice.dart';
import '../../../core/save/catalog/play_view.dart';
import '../../../core/save/catalog/save_entry.dart';
import '../../../core/save/catalog/save_fit.dart';
import '../../../core/save/catalog/save_maker.dart';
import '../../../core/save/resume_service.dart';
import '../../../providers/resume_provider.dart';
import '../../../providers/romm_provider.dart';
import '../../../providers/save_catalog_provider.dart';
import '../../play/emulator_choices.dart';
import '../controller_dialogs.dart';
import '../focus_effect_wrapper.dart';
import '../save_list/save_labels.dart';
import '../save_list/save_list.dart';
import '../save_list/save_waiting.dart';
import '../save_list/state_list.dart';

/// The game page's Saves tab: the play screen's lists, to look at and
/// manage. A row is never launched here; X restores it to this PC.
class SavesTab extends ConsumerStatefulWidget {
  const SavesTab({
    super.key,
    required this.game,
    required this.onPush,
    required this.onBackupNow,
    required this.onRestore,
    required this.onDelete,
  });

  final Game game;
  final Future<void> Function() onPush;
  final Future<void> Function() onBackupNow;

  /// Puts [save] in place for [target] without launching.
  final Future<void> Function(SaveEntry save, SaveMaker target) onRestore;
  final Future<void> Function(SaveEntry save) onDelete;

  @override
  ConsumerState<SavesTab> createState() => _SavesTabState();
}

class _SavesTabState extends ConsumerState<SavesTab> {
  bool _states = false;
  bool _busy = false;
  SaveEntry? _selected;

  SaveCatalogKey get _key => SaveCatalogKey(widget.game);

  @override
  void initState() {
    super.initState();
    // The RomM list is read fresh each time the tab opens.
    Future.microtask(() {
      if (mounted) ref.invalidate(saveCatalogProvider(_key));
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(saveCatalogProvider(_key));
      }
    }
  }

  Future<bool> _ask(String title, String body, String yes) =>
      showControllerConfirm(context, title: title, body: body, yes: yes);

  Future<void> _restore(PlayRow row, PlayView view, EmulatorChoices choices) async {
    // Into the emulator the game plays in when the save fits it (as it is or
    // converted), else back into the one that made it.
    final own = choices.forThisGame;
    final ownFit = own == null
        ? null
        : fitFor(row.entry,
            platformSlug: widget.game.platformSlug ?? '',
            picked: own,
            platformDefault: own,
            installed: choices.installedIds);
    final fit = ownFit != null && ownFit.usable ? ownFit : row.fit;
    final target = fit.playsIn;
    if (target == null) return;
    final prompt = view.promptFor(SavePlay(row.entry, fit));
    if (prompt == PlayPrompt.notOnRomm &&
        !await _ask(
            "Your save on this PC isn't on RomM",
            'Your ${choices.nameOf(target)} save on this PC changed since its last upload (played offline?). '
                'Restoring ${row.entry.fileName} replaces it. A backup of it is kept on this PC.',
            'Replace')) {
      return;
    }
    if (prompt == PlayPrompt.olderSave &&
        !await _ask(
            'Restore an older save?',
            'This replaces your ${choices.nameOf(target)} save from ${formatSaveTime(view.newestLocalFor(target)!)} '
                'with the save from ${formatSaveTime(row.entry.savedAt)}. Your current save is backed up first.',
            'Restore')) {
      return;
    }
    await _run(() => widget.onRestore(row.entry, target));
  }

  Future<void> _delete(PlayRow row) async {
    final fromRomm = row.entry.source == SaveSource.romm;
    if (!await _ask(
        'Delete this save?',
        fromRomm
            ? '${row.entry.fileName} is deleted from RomM, for every device.'
            : 'The backup ${row.entry.fileName} is deleted from this PC.',
        'Delete')) {
      return;
    }
    await _run(() => widget.onDelete(row.entry));
  }

  Widget _tool(String label, IconData icon, Key key, Future<void> Function() action) => FocusEffectWrapper(
        key: key,
        onTap: _busy ? null : () => _run(action),
        borderRadius: 16,
        useSafeScale: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(label)]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(strategyRegistryProvider).valueOrNull;
    final installed = ref.watch(emulatorStatusProvider).valueOrNull;
    final catalog = ref.watch(saveCatalogProvider(_key));
    final states = ref.watch(resumeEntriesProvider(ResumeKey(widget.game))).valueOrNull ?? const <ResumeEntry>[];
    final choices = registry == null || installed == null ? null : EmulatorChoices.of(registry, installed, widget.game);
    // Not while the list is re-read (e.g. right after a session): a restore
    // would weigh the saves as they were before it.
    final listed = catalog.hasValue && !catalog.isLoading && !catalog.isRefreshing;
    final view = !listed || choices == null
        ? null
        : buildPlayView(
            catalog: catalog.valueOrNull!,
            states: states,
            platformSlug: widget.game.platformSlug ?? '',
            picked: null,
            // A save whose maker isn't installed (or isn't known) goes to the
            // emulator this game plays in.
            platformDefault: choices.forThisGame,
            installed: choices.installedIds,
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        _tool('Push to RomM', Icons.cloud_upload_outlined, const ValueKey('push-to-romm'), widget.onPush),
        _tool('Backup now', Icons.add, const ValueKey('backup-now'), widget.onBackupNow),
        _tool(_states ? 'Show saves' : 'Show states', Icons.swap_horiz, const ValueKey('saves-states'),
            () async => setState(() => _states = !_states)),
      ]),
      if (view == null)
        const SaveWaiting()
      else if (_states)
        StateList(states: view.states, onSelect: (_) {})
      else
        SaveList(
          view: view,
          mode: SaveListMode.manage,
          selected: _selected,
          onSelect: (r) => setState(() => _selected = r.entry),
          onRestore: (r) => _restore(r, view, choices!),
          onDelete: _delete,
        ),
    ]);
  }
}
