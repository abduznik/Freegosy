import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../disc/serial_extraction_service.dart';
import 'romm_models.dart';

/// Where a save strategy gets a game's id (a disc serial, a title id): the
/// id RomM read from the ROM when it scanned it (RomM 5.3+, `title_id` /
/// `save_target`), else the strategy's own reader. Logs the source, so a
/// save found in the wrong place can be traced to it.
///
/// RomM's values end up in file paths, so a strategy passes the [shape] its
/// id must have; anything else is ignored and the strategy reads the ROM.
abstract final class GameIdResolver {
  /// A PS1/PS2 serial after `normalizeSerial`: `SLUS-21050`.
  static final ps1ps2Serial = RegExp(r'^[A-Z]{4}-\d{5}$');

  /// A Switch title id: `0100ABCD12345000`.
  static final switchTitleId = RegExp(r'^01[0-9A-F]{14}$');

  /// A PSP disc id or PS3 title id, letters and digits only: `ULUS10064`.
  static final sonyDiscId = RegExp(r'^[A-Z]{4}\d{5}$');

  /// [value] trimmed; null when it is null, empty or only spaces.
  static String? clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// RomM's [value] (cleaned), logged when there is one; null when it doesn't
  /// match [shape]. For a strategy whose own reader is synchronous or sits
  /// inside other logic.
  static String? server(String label, String? value, {RegExp? shape}) {
    final id = clean(value);
    if (id == null) return null;
    if (shape != null && !shape.hasMatch(id)) {
      debugPrint('[GameId] $label: server value "$id" is not an id of this kind, ignored');
      return null;
    }
    debugPrint('[GameId] $label: server $id');
    return id;
  }

  /// RomM's [server] value (if it matches [shape]); else [local] is called
  /// (never when RomM answered). Logs which source answered.
  static Future<String?> resolve({
    required String label,
    String? server,
    RegExp? shape,
    required Future<String?> Function() local,
  }) async {
    final fromRomm = GameIdResolver.server(label, server, shape: shape);
    if (fromRomm != null) return fromRomm;
    final fromRom = clean(await local());
    debugPrint('[GameId] $label: ${fromRom == null ? 'none' : 'local $fromRom'}');
    return fromRom;
  }

  /// The PSP/PS3 id whose folders hold [game]'s saves (`ULUS10064`): RomM's
  /// `save_target`, else its `title_id`, with any `-`/`_` taken out (RomM may
  /// send `ULUS-10064`). Null when neither is such an id.
  static String? discFolderId(String label, Game game) {
    for (final value in [game.saveTarget, game.titleId]) {
      final id = clean(value)?.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      if (id != null && sonyDiscId.hasMatch(id)) return server(label, id);
    }
    return null;
  }

  /// RomM's PS1/PS2 serial for [game] launched from [romPath], normalised
  /// like a read one (`slus_210.50` → `SLUS-21050`). RomM reads the first
  /// disc only (a playlist by its first disc too), so it is null when
  /// [romPath] is a later disc: that disc's own serial is read instead.
  static String? discSerial(Game game, String romPath) {
    final id = clean(game.titleId);
    return id == null || isLaterDisc(game, romPath) ? null : SerialExtractionService.normalizeSerialText(id);
  }

  static final _discNumber = RegExp(r'(?:[(\[]|\s-)\s*(?:disc|disk|cd)\s*(\d+)', caseSensitive: false);
  static const _discImages = {'.chd', '.iso', '.cue', '.cso', '.zso', '.ccd', '.mds', '.pbp', '.gdi'};

  /// Whether [romPath] is disc 2 or later of [game]: its name says so
  /// (`(Disc 2)`, `[CD 3]`, ` - Disc 2`), or it comes after the first disc image in
  /// [game]'s files. The library list sends no files, so the name comes
  /// first. A playlist (`.m3u`) or a folder is never a later disc.
  static bool isLaterDisc(Game game, String romPath) {
    final name = p.basename(romPath);
    final number = _discNumber.firstMatch(name);
    if (number != null) return int.parse(number.group(1)!) > 1;
    if (!_discImages.contains(p.extension(name).toLowerCase())) return false;
    final discs = [
      for (final f in game.files)
        if (_discImages.contains(p.extension('${f['file_name'] ?? ''}').toLowerCase())) '${f['file_name']}'
    ]..sort();
    return discs.length > 1 && discs.contains(name) && discs.first != name;
  }
}
