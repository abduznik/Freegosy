import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// [bytes] as RomM shows sizes: B, KB, MB or GB with one decimal.
String formatSaveSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// When a save was made: `today 09:56`, `yesterday 21:12`, `28 Sep 18:40`,
/// or `24 Dec 2025` for another year.
String formatSaveTime(DateTime time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final t = time.toLocal();
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(n.year, n.month, n.day);
  final hm = DateFormat('HH:mm').format(t);
  if (day == today) return 'today $hm';
  if (day == today.subtract(const Duration(days: 1))) return 'yesterday $hm';
  if (t.year == n.year) return '${DateFormat('d MMM').format(t)} $hm';
  return DateFormat('d MMM y').format(t);
}

/// A small outlined label, like RomM's save chips.
class SaveChip extends StatelessWidget {
  const SaveChip(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: color)),
      );
}
