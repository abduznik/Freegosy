import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/emulator/retroarch_core_list.dart';
import '../../core/input/gamepad_service.dart';
import '../../core/input/input_action_bus.dart';
import '../../core/romm/romm_models.dart';
import '../../core/save/catalog/play_choice.dart';
import '../../core/save/catalog/play_request.dart';
import '../../core/save/catalog/play_view.dart';
import '../../core/save/catalog/save_entry.dart';
import '../../core/save/catalog/save_fit.dart';
import '../../core/save/catalog/save_maker.dart';
import '../../core/save/resume_service.dart';
import '../../providers/resume_provider.dart';
import '../../providers/romm_provider.dart';
import '../../providers/save_catalog_provider.dart';
import '../../providers/ui_provider.dart';
import '../play/emulator_choices.dart';
import '../widgets/controller_dialogs.dart';
import '../widgets/controller_hints_bar.dart';
import '../widgets/focus_effect_wrapper.dart';
import '../widgets/save_list/save_labels.dart';
import '../widgets/save_list/save_list.dart';
import '../widgets/save_list/state_list.dart';
import '../widgets/save_list/save_waiting.dart';
import '../widgets/shoulder_owner.dart';

/// Where you choose which save (or state) a game starts with, and in which
/// emulator — like RomM's play page. Opened with ▶ Play on the game page.
class PlayScreen extends ConsumerStatefulWidget {
  const PlayScreen(
      {super.key, required this.game, required this.coverUrl, required this.onPlay, this.onResume, this.initialTab});

  /// The tab to open on (1: States, its newest state chosen); null: the tab
  /// of what is preselected.
  final int? initialTab;

  final Game game;
  final String coverUrl;
  /// Starts the game; true once the emulator started (the play screen then
  /// closes).
  final Future<bool> Function(PlayRequest request) onPlay;

  /// Resumes a state; without it the States tab is empty.
  final Future<void> Function(ResumeEntry entry)? onResume;

  @override
  ConsumerState<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends ConsumerState<PlayScreen> {
  bool _choicesRead = false;
  SaveMaker? _picked;
  bool _remember = false;
  bool _showAll = false;

  /// Whether [PlayScreen.initialTab]'s newest state was chosen yet (once
  /// the states are listed).
  bool _initialStateChosen = false;
  int? _tab; // 0 saves, 1 states; null: the preselected item's tab
  PlayItem? _chosen;
  bool _starting = false;
  StreamSubscription<GameAction>? _sub;
  final _mainFocus = FocusNode();

  SaveCatalogKey get _key => SaveCatalogKey(widget.game);

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    // The RomM list is read fresh each time the screen opens.
    Future.microtask(() {
      if (mounted) ref.invalidate(saveCatalogProvider(_key));
    });
    _sub = inputActionBus.stream.listen((action) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      switch (action) {
        case GameAction.l1 || GameAction.r1:
          setState(() => _tab = action == GameAction.l1 ? 0 : 1);
        case GameAction.favorite:
          _pickEmulator();
        case GameAction.back:
          Navigator.of(context).maybePop();
        default:
          break;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mainFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _mainFocus.dispose();
    super.dispose();
  }

  /// [watch]: from build (watches the providers); false from event handlers,
  /// where Riverpod allows only reads.
  EmulatorChoices? _choices({bool watch = true}) {
    final registry = (watch ? ref.watch(strategyRegistryProvider) : ref.read(strategyRegistryProvider)).valueOrNull;
    final installed = (watch ? ref.watch(emulatorStatusProvider) : ref.read(emulatorStatusProvider)).valueOrNull;
    if (registry == null || installed == null) return null;
    final choices = EmulatorChoices.of(registry, installed, widget.game);
    if (!_choicesRead) {
      _choicesRead = true;
      _picked = choices.remembered;
      _remember = choices.remembered != null;
    }
    return choices;
  }

  void _setPicked(SaveMaker? maker, EmulatorChoices choices) => setState(() {
        _picked = maker;
        _remember = maker != null && maker == choices.remembered;
        _chosen = null;
        _tab = null;
      });

  Future<int?> _chooseFrom(String title, List<String> labels, {int? current}) =>
      showControllerChoice(context, title: title, labels: labels, current: current);

  Future<void> _pickEmulator() async {
    final choices = _choices(watch: false);
    if (choices == null) return;
    final labels = ['Any', for (final e in choices.emulators) e.name];
    final current = _picked == null ? 0 : 1 + choices.emulators.indexWhere((e) => e.emulatorId == _picked!.emulatorId);
    final i = await _chooseFrom('Emulator', labels, current: current);
    if (i == null || !mounted) return;
    if (i == 0) return _setPicked(null, choices);
    final id = choices.emulators[i - 1].emulatorId;
    final keepCore = choices.remembered?.emulatorId == id ? choices.remembered!.coreId : null;
    _setPicked(choices.makerFor(id, core: keepCore), choices);
  }

  Future<void> _pickCore() async {
    final choices = _choices(watch: false);
    if (choices == null || _picked?.emulatorId != 'retroarch') return;
    final cores = getCoresForSlug(widget.game.platformSlug ?? '');
    final i = await _chooseFrom('Core', [for (final c in cores) c.displayName]);
    if (i == null || !mounted) return;
    _setPicked(choices.makerFor('retroarch', core: cores[i].id), choices);
  }

  String _sourceLabel(SaveEntry e) => switch (e.source) {
        SaveSource.local => 'local save',
        SaveSource.backup => 'backup',
        SaveSource.romm => 'RomM save',
      };

  String _describe(PlayItem? item, EmulatorChoices? choices, SaveMaker? fallback) {
    String name(SaveMaker m) => choices?.nameOf(m) ?? m.emulatorId;
    return switch (item) {
      SavePlay(:final entry, :final fit) =>
        'in ${fit.playsIn == null ? '?' : name(fit.playsIn!)} · ${_sourceLabel(entry)}, ${formatSaveTime(entry.savedAt)}',
      StatePlay(:final entry) => '${entry.slot.label} in ${entry.emulatorName} · ${formatSaveTime(entry.savedAt)}',
      null => fallback == null ? 'No emulator for this game is installed' : 'in ${name(fallback)} · starts without a save',
    };
  }

  Future<bool> _confirm(PlayPrompt prompt, PlayItem item, PlayView view, EmulatorChoices? choices) async {
    String name(SaveMaker m) => choices?.nameOf(m) ?? m.emulatorId;
    final (title, body, yes) = switch ((prompt, item)) {
      (PlayPrompt.olderSave, SavePlay(:final entry, :final fit)) => (
          'Play an older save?',
          'This replaces your ${name(fit.playsIn!)} save from ${formatSaveTime(view.newestLocalFor(fit.playsIn!)!)} '
              'with the ${_sourceLabel(entry)} from ${formatSaveTime(entry.savedAt)}'
              '${fit.kind == SaveFitKind.converted ? ', converted for ${name(fit.playsIn!)}' : ''}.\n\n'
              'Your current save is backed up first, so you can get it back from the backups.',
          'Replace and play',
        ),
      (PlayPrompt.notOnRomm, SavePlay(:final entry, :final fit)) => (
          "Your save on this PC isn't on RomM",
          'Your ${name(fit.playsIn!)} save on this PC changed since its last upload (played offline?). '
              'Playing the ${_sourceLabel(entry)} from ${formatSaveTime(entry.savedAt)} replaces it.\n\n'
              'A backup of it is kept on this PC.',
          'Replace and play',
        ),
      (_, StatePlay(:final entry)) => (
          'Resume an older state?',
          'This state is from ${formatSaveTime(entry.savedAt)}, but your save is from '
              '${formatSaveTime(view.newestSave!)}. Resuming may roll your save back.',
          'Resume anyway',
        ),
      _ => ('', '', ''),
    };
    return showControllerConfirm(context, title: title, body: body, yes: yes, focusYes: false);
  }

  /// RomM's copy of the local save [entry] in [view] (marked "on this PC"),
  /// by content hash or the RomM save it was last synced with.
  static Map<String, dynamic>? _rommCopyOf(SaveEntry entry, PlayView? view) {
    if (view == null) return null;
    for (final g in view.romm) {
      for (final r in [g.newest, ...g.older]) {
        final save = r.entry.rommSave;
        if (!r.sameAsLocal || save == null) continue;
        final hash = save['content_hash']?.toString();
        if ((hash != null && entry.contentHashes.contains(hash)) || save['id']?.toString() == entry.sameAsRommId) return save;
      }
    }
    return null;
  }

  Future<void> _start(PlayView? view, EmulatorChoices? choices) async {
    if (_starting) return;
    final item = _chosen ?? view?.preselected;
    if (item != null && view != null) {
      final prompt = view.promptFor(item);
      if (prompt != null && !await _confirm(prompt, item, view, choices)) return;
    }
    final fallback = _picked ?? choices?.platformDefault;
    if (!mounted) return;
    // "Remember" turned off for the remembered emulator: forget it.
    final forget = !_remember && _picked != null && _picked == choices?.remembered;
    setState(() => _starting = true);
    try {
      var started = true;
      switch (item) {
        case StatePlay(:final entry):
          await widget.onResume?.call(entry);
        case SavePlay(:final entry, :final fit):
          final target = fit.playsIn!;
          final own = entry.source == SaveSource.local && entry.maker == target;
          started = await widget.onPlay(PlayRequest(
            emulator: target,
            save: own ? null : entry,
            remember: _remember && _picked == target,
            forget: forget,
            rommCopy: entry.source == SaveSource.local ? _rommCopyOf(entry, view) : null,
          ));
        case null:
          if (fallback == null) return;
          started = await widget.onPlay(
              PlayRequest(emulator: fallback, remember: _remember && _picked == fallback, forget: forget));
      }
      if (started && mounted) Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Widget _button(String label, {required VoidCallback? onTap, Key? key, bool primary = false, FocusNode? focusNode}) {
    final theme = Theme.of(context);
    return FocusEffectWrapper(
      key: key,
      focusNode: focusNode,
      onTap: onTap,
      borderRadius: 10,
      useSafeScale: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: primary ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontWeight: primary ? FontWeight.bold : FontWeight.normal,
                color: primary ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface)),
      ),
    );
  }

  Widget _panel(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.12),
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choices = _choices();
    final catalog = ref.watch(saveCatalogProvider(_key));
    final states = widget.onResume == null
        ? const <ResumeEntry>[]
        : ref.watch(resumeEntriesProvider(ResumeKey(widget.game))).valueOrNull ?? const <ResumeEntry>[];
    // Only a list that is current: while it reloads (e.g. right after a
    // session, when the save on this PC just changed) its old rows would
    // start the save from before the session.
    final listed = catalog.hasValue && !catalog.isLoading && !catalog.isRefreshing;
    // Opened on the states: the newest one, of whichever emulator (once the
    // states are listed), with that emulator picked so it shows.
    if (widget.initialTab == 1 && !_initialStateChosen && choices != null && states.isNotEmpty) {
      _initialStateChosen = true;
      final newest = states.reduce((a, s) => s.savedAt.isAfter(a.savedAt) ? s : a);
      if (_picked != null && _picked!.emulatorId != newest.emulatorId) {
        _picked = choices.makerFor(newest.emulatorId);
        _remember = _picked == choices.remembered;
      }
      _chosen ??= StatePlay(newest);
    }
    final view = !listed || choices == null
        ? null
        : buildPlayView(
            catalog: catalog.valueOrNull!,
            states: states,
            platformSlug: widget.game.platformSlug ?? '',
            picked: _picked,
            platformDefault: choices.platformDefault,
            installed: choices.installedIds,
            showAll: _showAll,
          );
    final item = _chosen ?? view?.preselected;
    final tab = _tab ?? (item is StatePlay ? 1 : 0);
    final fallback = _picked ?? choices?.platformDefault;
    // Not before the saves are listed: what A would start isn't known yet.
    final canStart = !_starting && view != null && (item != null || fallback != null);
    final muted = TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant);

    final leftItems = <Widget>[
      AspectRatio(
        aspectRatio: 0.73,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: CachedNetworkImage(
            imageUrl: widget.coverUrl,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => Container(color: Colors.grey[850]),
            placeholder: (_, _) => Container(color: Colors.grey[850]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(widget.game.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
      if (widget.game.platformDisplayName != null)
        Text(widget.game.platformDisplayName!, textAlign: TextAlign.center, style: muted),
      const SizedBox(height: 12),
      _button(item is StatePlay ? '⟳ Resume' : '▶ Play',
          key: const ValueKey('play-main'),
          focusNode: _mainFocus,
          primary: true,
          onTap: canStart ? () => _start(view, choices) : null),
      const SizedBox(height: 6),
      Text(_describe(item, choices, fallback), textAlign: TextAlign.center, style: muted),
    ];

    // Like RomM's play page: back to the game page, or to the library.
    Widget link(String label, IconData icon, Key key, VoidCallback onTap) => FocusEffectWrapper(
          key: key,
          onTap: onTap,
          borderRadius: 8,
          useSafeScale: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16),
              const SizedBox(width: 6),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
            ]),
          ),
        );
    final backLinks = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Divider(color: theme.colorScheme.outline.withValues(alpha: 0.25)),
      link('Back to game', Icons.arrow_back, const ValueKey('back-to-game'), () => Navigator.of(context).maybePop()),
      link('Back to library', Icons.grid_view, const ValueKey('back-to-library'),
          () => Navigator.of(context).popUntil((route) => route.isFirst)),
    ]);

    final middle = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _button('Saves', key: const ValueKey('tab-saves'), primary: tab == 0, onTap: () => setState(() => _tab = 0)),
        const SizedBox(width: 6),
        _button('States', key: const ValueKey('tab-states'), primary: tab == 1, onTap: () => setState(() => _tab = 1)),
      ]),
      if (!listed && !catalog.hasError)
        const SaveWaiting()
      else if (view == null)
        const Padding(padding: EdgeInsets.all(24), child: Text("The saves couldn't be listed."))
      else if (tab == 0)
        SaveList(
          view: view,
          mode: SaveListMode.choose,
          selected: item is SavePlay ? item.entry : null,
          onSelect: (r) {
            setState(() => _chosen = r.item);
            _mainFocus.requestFocus();
          },
        )
      else
        StateList(
          states: view.states,
          selected: item is StatePlay ? item.entry : null,
          thumbnailFor: ref.watch(resumeServiceProvider).valueOrNull?.thumbnailFor,
          onSelect: (s) {
            setState(() => _chosen = StatePlay(s));
            _mainFocus.requestFocus();
          },
        ),
    ]);

    final settings = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('⚙ SETTINGS', style: muted.copyWith(letterSpacing: 0.8)),
      const SizedBox(height: 8),
      Text('Emulator', style: muted),
      _button(_picked == null ? 'Any' : choices?.nameOf(SaveMaker(_picked!.emulatorId)) ?? _picked!.emulatorId,
          key: const ValueKey('emulator-picker'), onTap: _pickEmulator),
      if (_picked != null && _picked == choices?.remembered)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text('remembered for this game', style: muted)),
      if (_picked?.emulatorId == 'retroarch') ...[
        const SizedBox(height: 10),
        Text('Core', style: muted),
        _button(choices?.nameOf(_picked!).split(' · ').last ?? _picked!.coreId ?? '',
            key: const ValueKey('core-picker'), onTap: _pickCore),
      ],
      if (_picked != null) ...[
        const SizedBox(height: 10),
        FocusEffectWrapper(
          key: const ValueKey('remember-toggle'),
          onTap: () => setState(() => _remember = !_remember),
          borderRadius: 8,
          useSafeScale: false,
          child: Row(children: [
            Switch(value: _remember, onChanged: (v) => setState(() => _remember = v)),
            const Expanded(child: Text('Remember for this game', style: TextStyle(fontSize: 12))),
          ]),
        ),
      ],
      if (view != null && (view.hidden > 0 || _showAll)) ...[
        const SizedBox(height: 10),
        if (view.hidden > 0)
          Text(view.hidden == 1 ? '1 save hidden' : '${view.hidden} saves hidden', style: muted.copyWith(fontSize: 12)),
        _button(_showAll ? 'Hide unusable' : 'Show all',
            key: const ValueKey('show-all'), onTap: () => setState(() => _showAll = !_showAll)),
      ],
    ]);

    return Scaffold(
      body: ShoulderOwner(
        child: SafeArea(
          child: LayoutBuilder(builder: (context, box) {
            final list = SingleChildScrollView(child: _panel(middle));
            if (box.maxWidth >= 1100) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(
                    width: 220,
                    child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      ...leftItems,
                      const Spacer(),
                      backLinks,
                    ])),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: list),
                  const SizedBox(width: 14),
                  SizedBox(width: 240, child: _panel(settings)),
                ]),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 150,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...leftItems, backLinks]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _panel(settings)),
                ]),
                const SizedBox(height: 12),
                Expanded(child: list),
              ]),
            );
          }),
        ),
      ),
      bottomNavigationBar: ref.watch(inputModeProvider) == InputMode.mouse
          ? null
          : ControllerHintsBar(hints: [
              ControllerHintItem(label: item is StatePlay ? 'Resume' : 'Play', button: 'A'),
              const ControllerHintItem(label: 'Saves / States', button: 'L1 R1'),
              const ControllerHintItem(label: 'Emulator', button: 'Y'),
              const ControllerHintItem(label: 'Back', button: 'B'),
            ]),
    );
  }
}
