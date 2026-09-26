import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/save/resume_service.dart';
import '../../../core/save/save_state_info.dart';
import '../focus_effect_wrapper.dart';

/// The ▾ list: every resumable state, newest first. Returns the picked entry,
/// or null when closed.
Future<ResumeEntry?> showResumeSlotsDialog(
  BuildContext context,
  List<ResumeEntry> entries, {
  Future<Uint8List?> Function(ResumeEntry entry)? thumbnailFor,
}) {
  final showEmulator = entries.map((e) => e.emulatorId).toSet().length > 1;
  return showDialog<ResumeEntry>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.all(8),
          itemCount: entries.length,
          itemBuilder: (context, i) => _SlotRow(
            key: ValueKey('${entries[i].emulatorId}|${entries[i].fileName}'),
            entry: entries[i],
            autofocus: i == 0,
            showEmulator: showEmulator,
            thumbnailFor: thumbnailFor,
            onTap: () => Navigator.pop(ctx, entries[i]),
          ),
        ),
      ),
    ),
  );
}

class _SlotRow extends StatefulWidget {
  const _SlotRow({
    super.key,
    required this.entry,
    required this.autofocus,
    required this.showEmulator,
    required this.thumbnailFor,
    required this.onTap,
  });

  final ResumeEntry entry;
  final bool autofocus;
  final bool showEmulator;
  final Future<Uint8List?> Function(ResumeEntry entry)? thumbnailFor;
  final VoidCallback onTap;

  @override
  State<_SlotRow> createState() => _SlotRowState();
}

class _SlotRowState extends State<_SlotRow> {
  Future<Uint8List?>? _thumbnail;

  @override
  void initState() {
    super.initState();
    // Fetched once per row, not on every rebuild of the dialog.
    _thumbnail = widget.thumbnailFor?.call(widget.entry);
  }

  String get _where => switch (widget.entry.where) {
        ResumeWhere.thisPc => 'this PC',
        ResumeWhere.romm => 'RomM',
        ResumeWhere.both => widget.entry.newerOnRomm ? 'newer on RomM' : 'this PC',
      };

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final theme = Theme.of(context);
    final details = [
      DateFormat('d MMM HH:mm').format(entry.savedAt),
      entry.emulatorVersion == null
          ? 'version unknown'
          : '${entry.emulatorName} ${entry.emulatorVersion}',
      _where,
      // Don't repeat the emulator name: it's already in the version part
      // above, unless the version is unknown and that part just says so.
      if (widget.showEmulator && entry.emulatorVersion == null) entry.emulatorName,
    ].join(' · ');
    return FocusEffectWrapper(
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      borderRadius: 10.0,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          SizedBox(
            width: 64,
            height: 36,
            child: FutureBuilder<Uint8List?>(
              future: _thumbnail,
              builder: (context, snap) => snap.data == null
                  ? Icon(Icons.save_outlined, color: theme.colorScheme.onSurfaceVariant)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.memory(snap.data!, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(Icons.save_outlined)),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.slot.label, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(details, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
              if (entry.compat == StateCompat.mismatch)
                Text('Made with ${entry.emulatorVersion}, you have ${entry.installedVersion}. May not load.',
                    style: const TextStyle(fontSize: 12, color: Colors.orangeAccent)),
            ]),
          ),
        ]),
      ),
    );
  }
}
