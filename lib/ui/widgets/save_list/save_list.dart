import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/input/gamepad_service.dart';
import '../../../core/input/input_action_bus.dart';
import '../../../core/save/catalog/play_view.dart';
import '../../../core/save/catalog/save_entry.dart';
import '../../../core/save/catalog/save_fit.dart';
import '../focus_effect_wrapper.dart';
import 'save_labels.dart';

/// [choose]: the play screen, a row is picked to play. [manage]: the Saves
/// tab, rows can be restored to this PC or deleted, never launched.
enum SaveListMode { choose, manage }

/// A game's saves: This PC (with its backups folded) and RomM (each save's
/// older versions folded), as RomM's own save lists show them.
class SaveList extends StatefulWidget {
  const SaveList({
    super.key,
    required this.view,
    required this.mode,
    required this.onSelect,
    this.selected,
    this.onRestore,
    this.onDelete,
  });

  final PlayView view;
  final SaveListMode mode;
  final ValueChanged<PlayRow> onSelect;
  final SaveEntry? selected;
  final ValueChanged<PlayRow>? onRestore;
  final ValueChanged<PlayRow>? onDelete;

  @override
  State<SaveList> createState() => _SaveListState();
}

class _SaveListState extends State<SaveList> {
  bool _backupsOpen = false;
  final _openGroups = <String>{};
  /// The focused row, by [_keyOf]: rows are rebuilt with every new view.
  String? _focusedKey;

  static String _keyOf(PlayRow r) =>
      '${r.entry.source.name}|${r.entry.fileName}|${r.entry.savedAt.millisecondsSinceEpoch}';
  StreamSubscription<GameAction>? _sub;

  @override
  void initState() {
    super.initState();
    // X restores the focused row (manage mode).
    _sub = inputActionBus.stream.listen((action) {
      if (action != GameAction.detail || widget.onRestore == null || !mounted) return;
      if (ModalRoute.of(context)?.isCurrent == false) return;
      final row = widget.view.saveRows.where((r) => _keyOf(r) == _focusedKey).firstOrNull;
      if (row != null && _canManage(row) && row.fit.usable) widget.onRestore!(row);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  bool _canManage(PlayRow row) => widget.mode == SaveListMode.manage && row.entry.source != SaveSource.local;

  Widget _header(BuildContext context, String text, {String? trailing}) {
    final theme = Theme.of(context);
    final style = TextStyle(fontSize: 11, letterSpacing: 0.8, color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(children: [
        Text(text.toUpperCase(), style: style.copyWith(fontWeight: FontWeight.w600)),
        const Spacer(),
        if (trailing != null) Text(trailing, style: style),
      ]),
    );
  }

  Widget _note(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _fold(String label, bool open, VoidCallback onTap, Key key) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: FocusEffectWrapper(
          key: key,
          onTap: onTap,
          borderRadius: 8,
          useSafeScale: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );

  Widget _row(PlayRow r) => SaveRow(
        row: r,
        selected: identical(r.entry, widget.selected),
        onTap: () {
          if (r.fit.usable) widget.onSelect(r);
        },
        onFocusChange: (focused) {
          if (focused) {
            _focusedKey = _keyOf(r);
          } else if (_focusedKey == _keyOf(r)) {
            _focusedKey = null;
          }
        },
        onRestore: _canManage(r) && r.fit.usable && widget.onRestore != null ? () => widget.onRestore!(r) : null,
        onDelete: _canManage(r) && widget.onDelete != null ? () => widget.onDelete!(r) : null,
      );

  @override
  Widget build(BuildContext context) {
    final v = widget.view;
    String plural(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(context, 'This PC'),
      if (v.thisPc.isEmpty && v.backups.isEmpty) _note(context, 'No saves on this PC'),
      ...v.thisPc.map(_row),
      if (v.backups.isNotEmpty) ...[
        _fold(plural(v.backups.length, 'backup'), _backupsOpen, () => setState(() => _backupsOpen = !_backupsOpen),
            const ValueKey('fold-backups')),
        if (_backupsOpen) ...v.backups.map(_row),
      ],
      _header(context, 'RomM', trailing: v.rommOffline ? null : 'live list · nothing downloaded yet'),
      if (v.rommOffline)
        _note(context, 'RomM is offline — only saves on this PC can be picked')
      else if (v.romm.isEmpty)
        _note(context, 'No saves on RomM'),
      for (final g in v.romm) ...[
        _row(g.newest),
        if (g.older.isNotEmpty) ...[
          _fold(
            plural(g.older.length, 'older version'),
            _openGroups.contains(g.newest.entry.groupKey),
            () => setState(() {
              final key = g.newest.entry.groupKey;
              if (!_openGroups.remove(key)) _openGroups.add(key);
            }),
            ValueKey('fold-${g.group.slot}|${g.group.tag}'),
          ),
          if (_openGroups.contains(g.newest.entry.groupKey)) ...g.older.map(_row),
        ],
      ],
    ]);
  }
}

/// One save: name, emulator tag, converted mark, size and time; greyed with
/// the reason when no installed emulator can use it.
class SaveRow extends StatelessWidget {
  const SaveRow({
    super.key,
    required this.row,
    required this.selected,
    required this.onTap,
    this.onFocusChange,
    this.onRestore,
    this.onDelete,
  });

  final PlayRow row;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final e = row.entry;
    final theme = Theme.of(context);
    final usable = row.fit.usable;
    final icon = switch (e.source) {
      SaveSource.local => Icons.save_outlined,
      SaveSource.backup => Icons.history,
      SaveSource.romm => Icons.cloud_outlined,
    };
    return Padding(
      key: ValueKey('save-row-${e.fileName}-${e.savedAt.millisecondsSinceEpoch}'),
      padding: const EdgeInsets.only(top: 4),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: onFocusChange,
        child: Opacity(
          opacity: usable ? 1 : 0.45,
          child: FocusEffectWrapper(
            onTap: onTap,
            // Hold A: delete (manage mode), the controller's way to the
            // delete button.
            onLongPress: onDelete,
            borderRadius: 10,
            useSafeScale: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.15)
                    : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                border: Border.all(color: selected ? theme.colorScheme.primary : Colors.transparent),
              ),
              child: Row(children: [
                Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.fileName,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Wrap(spacing: 6, runSpacing: 3, children: [
                      if ((e.tag ?? '').isNotEmpty)
                        SaveChip(e.tag!, key: const ValueKey('save-emulator-tag'), color: Colors.orange),
                      if (row.fit.kind == SaveFitKind.converted) const SaveChip('converted', color: Colors.tealAccent),
                      if (row.sameAsLocal) const SaveChip('on this PC', color: Colors.lightGreenAccent),
                      if (e.sizeBytes != null)
                        SaveChip(formatSaveSize(e.sizeBytes!), color: theme.colorScheme.onSurfaceVariant),
                    ]),
                    if (!usable && row.fit.reason != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(row.fit.reason!,
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                      ),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(formatSaveTime(e.savedAt), style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                if (onRestore != null)
                  IconButton(
                      tooltip: 'Restore to this PC',
                      icon: const Icon(Icons.download_for_offline_outlined),
                      onPressed: onRestore),
                if (onDelete != null)
                  IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: onDelete),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
