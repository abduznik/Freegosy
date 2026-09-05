import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gamepads/gamepads.dart';
import '../../core/input/gamepad_service.dart';
import '../../core/input/gamepad_utils.dart';
import '../../core/input/known_controllers.dart';
import '../../core/input/custom_controller_mappings.dart';
import '../../core/input/input_action_bus.dart';
import '../widgets/dialog_back_bridge.dart';
import '../widgets/focus_effect_wrapper.dart';

const _mappableActions = [
  GameAction.confirm,
  GameAction.back,
  GameAction.detail,
  GameAction.favorite,
  GameAction.up,
  GameAction.down,
  GameAction.left,
  GameAction.right,
  GameAction.l1,
  GameAction.r1,
  GameAction.start,
  GameAction.select,
];

const _actionLabels = {
  GameAction.confirm: 'Confirm (A)',
  GameAction.back: 'Back (B)',
  GameAction.detail: 'Detail (X)',
  GameAction.favorite: 'Favorite (Y)',
  GameAction.up: 'D-Pad Up',
  GameAction.down: 'D-Pad Down',
  GameAction.left: 'D-Pad Left',
  GameAction.right: 'D-Pad Right',
  GameAction.l1: 'L1 / Left Bumper',
  GameAction.r1: 'R1 / Right Bumper',
  GameAction.start: 'Start / Menu',
  GameAction.select: 'Select / View',
};

class SettingsControllerSection extends ConsumerStatefulWidget {
  const SettingsControllerSection({super.key});

  @override
  ConsumerState<SettingsControllerSection> createState() =>
      _SettingsControllerSectionState();
}

class _SettingsControllerSectionState
    extends ConsumerState<SettingsControllerSection> {
  List<Map<String, String>> _controllers = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _scanControllers();
  }

  void _scanControllers() {
    final service = ref.read(gamepadServiceProvider);
    setState(() {
      _controllers = service.getDetectedControllers();
      _isScanning = false;
    });
  }

  String _mappingStatus(String controllerId) {
    final name =
        _controllers.firstWhere((c) => c['id'] == controllerId)['name'] ?? '';

    if (customControllerMappings.entries.any(
        (e) => name.toLowerCase().contains(e.key.toLowerCase()))) {
      return 'Custom';
    }

    for (final entry in kControllerMappings.entries) {
      if (name.toLowerCase().contains(entry.key.toLowerCase())) {
        return 'Built-in';
      }
    }

    return 'UNMAPPED';
  }

  bool _isMapped(String controllerId) {
    return _mappingStatus(controllerId) != 'UNMAPPED';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'View and configure gamepad button mappings for detected controllers.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildActionButton(
              context,
              icon: Icons.refresh,
              label: _isScanning ? 'Scanning...' : 'Refresh',
              onTap: _isScanning ? null : _scanControllers,
            ),
            const SizedBox(width: 10),
            _buildActionButton(
              context,
              icon: Icons.tune,
              label: 'Open Setup',
              onTap: () => _openSetupDialog(context),
            ),
          ],
        ),
        if (_controllers.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${_controllers.length} controller${_controllers.length == 1 ? '' : 's'} detected',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
        if (_controllers.isEmpty && !_isScanning) ...[
          const SizedBox(height: 12),
          Text(
            'No controllers detected. Connect a gamepad and press Refresh.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isPrimary = false,
  }) {
    final theme = Theme.of(context);
    return FocusEffectWrapper(
      onTap: onTap,
      borderRadius: 12.0,
      useSafeScale: false,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: isPrimary
              ? LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.8)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isPrimary
              ? null
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          border: Border.all(
            color: isPrimary
                ? theme.colorScheme.primary.withValues(alpha: 0.3)
                : theme.colorScheme.outline.withValues(alpha: 0.3),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18,
                color: isPrimary
                    ? theme.colorScheme.onPrimary
                    : onTap == null
                        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                        : theme.colorScheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isPrimary
                      ? theme.colorScheme.onPrimary
                      : onTap == null
                          ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                          : theme.colorScheme.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSetupDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => DialogBackBridge(
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(Icons.gamepad, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              const Text('Controller Setup'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: _controllers.isEmpty
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sports_esports_outlined,
                          size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('No controllers detected.'),
                      const SizedBox(height: 8),
                      Text(
                        'Connect a gamepad and press Refresh.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _controllers.length,
                    itemBuilder: (ctx, index) {
                      final c = _controllers[index];
                      final id = c['id'] ?? '?';
                      final name = c['name'] ?? 'Unknown Controller';
                      final status = _mappingStatus(id);
                      final mapped = _isMapped(id);

                      final isFirst = index == 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          border: Border.all(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.gamepad,
                                    size: 20,
                                    color: mapped
                                        ? Colors.green
                                        : Colors.orange),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: mapped
                                        ? Colors.green.withValues(alpha: 0.15)
                                        : Colors.orange
                                            .withValues(alpha: 0.15),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: mapped
                                          ? Colors.green
                                          : Colors.orange,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'ID: $id',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.5),
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Reset button — only shown when a custom mapping exists
                                if (_hasCustomMapping(id)) ...[
                                  _buildDialogButton(
                                    theme,
                                    icon: Icons.restore,
                                    label: 'Reset',
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _resetMapping(context, id, name);
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                _buildDialogButton(
                                  theme,
                                  icon: Icons.auto_fix_high,
                                  label: 'Auto-Map',
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _tryAutoMap(context, id, name);
                                  },
                                ),
                                const SizedBox(width: 8),
                                if (mapped)
                                  _buildDialogButton(
                                    theme,
                                    icon: Icons.edit,
                                    label: 'Edit Mapping',
                                    autofocus: isFirst,
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _startSniffing(context, id, name);
                                    },
                                  )
                                else
                                  _buildDialogButton(
                                    theme,
                                    icon: Icons.build,
                                    label: 'Configure',
                                    isPrimary: true,
                                    autofocus: isFirst,
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _startSniffing(context, id, name);
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            Row(
              children: [
                _buildDialogButton(
                  theme,
                  icon: Icons.refresh,
                  label: 'Refresh',
                  onTap: () {
                    _scanControllers();
                    Navigator.pop(ctx);
                    Future.delayed(const Duration(milliseconds: 400), () {
                      if (mounted) _openSetupDialog(context);
                    });
                  },
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogButton(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isPrimary = false,
    bool autofocus = false,
  }) {
    return FocusEffectWrapper(
      onTap: onTap,
      borderRadius: 10.0,
      autofocus: autofocus,
      useSafeScale: false,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: isPrimary
              ? LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.8)
                  ],
                )
              : null,
          color: isPrimary
              ? null
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: isPrimary
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isPrimary
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _tryAutoMap(BuildContext context, String controllerId, String name) {
    final service = ref.read(gamepadServiceProvider);
    final result = service.tryAutoMap(controllerId);
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (ctx) => DialogBackBridge(
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(Icons.auto_fix_high, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              const Text('Auto-Map'),
            ],
          ),
          content: result == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_off, size: 48, color: Colors.orange),
                    const SizedBox(height: 12),
                    Text(
                      'No automatic mapping found for:\n"$name"',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try using "Configure" to set up buttons manually.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Found via ${result.source == 'sdl' ? 'SDL database' : result.source == 'builtin' ? 'built-in list' : 'custom mappings'}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: result.mapping.entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Text(
                                '${_actionLabels[e.value] ?? e.value.name}: ',
                                style: theme.textTheme.bodySmall,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: theme.colorScheme.surfaceContainerHighest,
                                ),
                                child: Text(
                                  e.key,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${result.mapping.length} button${result.mapping.length == 1 ? '' : 's'} will be saved as a custom mapping.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            if (result != null)
              _buildDialogButton(
                theme,
                icon: Icons.save,
                label: 'Apply Mapping',
                isPrimary: true,
                autofocus: true,
                onTap: () {
                  service.updateCustomMapping(controllerId, result.mapping);
                  Navigator.pop(ctx);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Auto-mapping applied for $name!')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  bool _hasCustomMapping(String controllerId) {
    final name =
        _controllers.firstWhere((c) => c['id'] == controllerId, orElse: () => {})['name'] ?? '';
    return customControllerMappings.keys.any(
        (k) => name.toLowerCase().contains(k.toLowerCase()) ||
                k.toLowerCase().contains(name.toLowerCase()));
  }

  void _resetMapping(BuildContext context, String controllerId, String name) {
    final service = ref.read(gamepadServiceProvider);
    showDialog(
      context: context,
      builder: (ctx) => DialogBackBridge(
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Reset Controller Mapping'),
          content: Text(
            'Remove the custom mapping for "$name"?\n\n'
            'The controller will fall back to the built-in or SDL database mapping.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                await service.clearCustomMapping(controllerId);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(() {});
              },
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }

  void _startSniffing(BuildContext context, String controllerId, String name) {
    final service = ref.read(gamepadServiceProvider);
    final backendHandled = service.getBackendHandledActions(controllerId);

    // Only ask the user to map actions the backend can't handle automatically
    final manualActions = _mappableActions
        .where((a) => !backendHandled.contains(a))
        .toList();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ButtonSniffDialog(
        service: service,
        controllerId: controllerId,
        controllerName: name,
        manualActions: manualActions,
        skippedActions: backendHandled,
        onComplete: (mapping) {
          service.updateCustomMapping(controllerId, mapping);
          if (mounted) setState(() {});
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Self-contained sniff dialog with charge-bar visualizer
// ---------------------------------------------------------------------------

class _ButtonSniffDialog extends StatefulWidget {
  final GamepadService service;
  final String controllerId;
  final String controllerName;
  final List<GameAction> manualActions;
  final Set<GameAction> skippedActions;
  final void Function(Map<String, GameAction> mapping) onComplete;

  const _ButtonSniffDialog({
    required this.service,
    required this.controllerId,
    required this.controllerName,
    required this.manualActions,
    required this.skippedActions,
    required this.onComplete,
  });

  @override
  State<_ButtonSniffDialog> createState() => _ButtonSniffDialogState();
}

class _ButtonSniffDialogState extends State<_ButtonSniffDialog>
    with SingleTickerProviderStateMixin {
  static const _chargeDuration = Duration(milliseconds: 600);

  final Map<String, GameAction> _sniffedMapping = {};
  int _currentActionIndex = 0;
  bool _complete = false;

  late AnimationController _chargeController;
  StreamSubscription<GamepadEvent>? _rawSubscription;
  StreamSubscription<GameAction>? _backSubscription;

  // Latch: after a button registers we record BOTH the key and the value polarity
  // (+1 / -1). For digital buttons "released" means value < 0.5 on the same key.
  // For axes (POV/triggers) the value never goes to 0 — it just changes sign or
  // goes back toward center. We clear the latch as soon as abs(value) < 0.3,
  // OR if the value flips polarity (e.g. left-trigger vs right-trigger share one axis).
  String? _latchedKey;
  int _latchedPolarity = 0; // +1 or -1
  String? _pendingKey;
  int _pendingPolarity = 0;
  KeyType? _pendingType;

  @override
  void initState() {
    super.initState();
    _chargeController = AnimationController(vsync: this, duration: _chargeDuration);
    _chargeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _registerCurrent();
      }
    });
    _rawSubscription = widget.service.rawEvents.listen(_onRawEvent);
    // Listen for back action on the action bus — skip current step instead
    // of closing the dialog (DialogBackBridge is intentionally NOT used here).
    _backSubscription = inputActionBus.stream.listen((action) {
      if (action == GameAction.back && mounted && !_complete) {
        _skip();
      }
    });
  }

  @override
  void dispose() {
    _chargeController.dispose();
    _rawSubscription?.cancel();
    _backSubscription?.cancel();
    super.dispose();
  }

  void _onRawEvent(GamepadEvent event) {
    if (event.gamepadId != widget.controllerId) return;
    if (_complete) return;

    final v = GamepadUtils.normalizeAxisValueForKey(event.key, event.value);
    final abs = v.abs();
    final polarity = v >= 0 ? 1 : -1;
    final isPressed = abs >= 0.5;
    final isReleased = abs < 0.3;

    // --- Latch release check ---
    // Clear latch when: value drops near center, OR polarity flips (axis shared
    // by two directions, e.g. dwZPos for L2/R2, or POV returning to center).
    if (_latchedKey == event.key) {
      if (isReleased || polarity != _latchedPolarity) {
        setState(() {
          _latchedKey = null;
          _latchedPolarity = 0;
        });
      } else {
        // Still held in same direction — stay latched, ignore
        return;
      }
    }

    if (isPressed) {
      final sameKeySamePolarity =
          _pendingKey == event.key && _pendingPolarity == polarity;

      if (!sameKeySamePolarity) {
        // New key or flipped polarity — restart charge
        _chargeController.stop();
        _chargeController.reset();
        setState(() {
          _pendingKey = event.key;
          _pendingPolarity = polarity;
          _pendingType = event.type;
        });
        _chargeController.forward();
      }
      // else: same key same direction, already charging — do nothing
    } else if (isReleased) {
      if (_pendingKey == event.key) {
        // Released before bar filled — cancel charge
        _chargeController.stop();
        _chargeController.reset();
        setState(() {
          _pendingKey = null;
          _pendingPolarity = 0;
          _pendingType = null;
        });
      }
    }
  }

  void _registerCurrent() {
    if (_pendingKey == null) return;
    final rawKey = _pendingKey!;
    final polarity = _pendingPolarity;
    final eventType = _pendingType;
    final action = widget.manualActions[_currentActionIndex];

    // Encode polarity into the storage key for any input that isn't a clean
    // digital button (i.e. anything that came in with a non-1 absolute value,
    // or where we tracked a negative polarity).  This is the Dolphin / RetroArch
    // convention: "Axis 0+" / "Axis 0-" so a single physical axis can map two
    // separate directions without one overwriting the other.
    //
    // Digital buttons always arrive with value ±1.0 and polarity +1, but we
    // only skip the suffix when the raw key looks like a plain named button
    // (letters/underscores only).  Numeric keys (e.g. "6", "7" from Linux
    // /dev/input/js* hat switches) always get the suffix so Up and Down on
    // the same hat axis are stored as distinct entries.
    //
    // Numeric keys are also tagged by event type first (see
    // GamepadUtils.disambiguateKey): on Linux a button and an axis can share
    // the same raw index (Xbox 360 pad: button 6 = Back, axis 6 = D-pad X),
    // so without the tag, sniffing one would silently overwrite the other.
    final bool isNamedButton = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_ ./-]*$').hasMatch(rawKey);
    final String disambiguatedKey = isNamedButton
        ? rawKey
        : GamepadUtils.disambiguateKey(rawKey, isButton: eventType == KeyType.button);
    final String storageKey = (isNamedButton && polarity >= 0)
        ? disambiguatedKey
        : GamepadUtils.encodeKey(disambiguatedKey, polarity);

    setState(() {
      _sniffedMapping[storageKey] = action;
      _currentActionIndex++;
      _latchedKey = rawKey;
      _latchedPolarity = polarity;
      _pendingKey = null;
      _pendingPolarity = 0;
      _pendingType = null;
      if (_currentActionIndex >= widget.manualActions.length) _complete = true;
    });
    _chargeController.reset();
  }

  void _skip() {
    _chargeController.stop();
    _chargeController.reset();
    setState(() {
      _pendingKey = null;
      _pendingPolarity = 0;
      _pendingType = null;
      _latchedKey = null;
      _latchedPolarity = 0;
      _currentActionIndex++;
      if (_currentActionIndex >= widget.manualActions.length) _complete = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_complete) {
      return DialogBackBridge(
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Mapping Complete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _sniffedMapping.isEmpty ? Icons.warning_amber_rounded : Icons.check_circle,
                size: 48,
                color: _sniffedMapping.isEmpty ? Colors.orange : Colors.green,
              ),
              const SizedBox(height: 12),
              Text(
                _sniffedMapping.isEmpty
                    ? 'No buttons were mapped for ${widget.controllerName}.'
                    : '${_sniffedMapping.length} button${_sniffedMapping.length == 1 ? '' : 's'} manually mapped for ${widget.controllerName}.',
              ),
              if (_sniffedMapping.isEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.orange.withValues(alpha: 0.08),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    'Saving an empty mapping would disable your controller. '
                    'Use "Cancel" to discard, or go back and map at least one button.',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (widget.skippedActions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.green.withValues(alpha: 0.08),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_fix_high, size: 14, color: Colors.green),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${widget.skippedActions.map((a) => _actionLabels[a] ?? a.name).join(', ')} handled automatically by your controller.',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            _sniffButton(
              theme,
              icon: Icons.save,
              label: 'Save Mapping',
              isPrimary: true,
              autofocus: true,
              onTap: _sniffedMapping.isEmpty
                  ? null
                  : () {
                      widget.onComplete(_sniffedMapping);
                      Navigator.pop(context);
                    },
            ),
          ],
        ),
      );
    }

    final currentAction = widget.manualActions[_currentActionIndex];
    final actionLabel = _actionLabels[currentAction] ?? currentAction.name;
    final progress = _currentActionIndex / widget.manualActions.length;

    return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Mapping: ${widget.controllerName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overall progress
            Row(
              children: [
                Text(
                  'Step ${_currentActionIndex + 1} of ${widget.manualActions.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                const Spacer(),
                Text(
                  '${(_sniffedMapping.length)} mapped',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary.withValues(alpha: 0.4)),
              ),
            ),
            const SizedBox(height: 16),

            // Prompt box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.12),
                    theme.colorScheme.secondary.withValues(alpha: 0.04),
                  ],
                ),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _pendingKey != null ? Icons.radio_button_checked : Icons.touch_app,
                    size: 28,
                    color: _pendingKey != null ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _pendingKey != null ? 'Hold it...' : 'Press & hold the button for:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    actionLabel,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Charge bar
                  AnimatedBuilder(
                    animation: _chargeController,
                    builder: (_, __) {
                      final v = _chargeController.value;
                      final isCharging = v > 0;
                      return Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: v,
                              minHeight: 14,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                              valueColor: AlwaysStoppedAnimation(
                                isCharging
                                    ? Color.lerp(theme.colorScheme.primary, Colors.green, v)!
                                    : theme.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isCharging
                                ? v >= 1.0 ? 'Registered!' : 'Charging...'
                                : 'Waiting for input',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isCharging
                                  ? Color.lerp(theme.colorScheme.primary, Colors.green, v)
                                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            // Already-mapped list
            if (_sniffedMapping.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Mapped so far:',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              ..._sniffedMapping.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        Text(
                          '${_actionLabels[e.value] ?? e.value.name}: ',
                          style: theme.textTheme.bodySmall,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          child: Text(
                            e.key,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _rawSubscription?.cancel();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          _sniffButton(
            theme,
            icon: Icons.skip_next,
            label: 'Skip',
            autofocus: true,
            onTap: _skip,
          ),
        ],
      );
  }

  Widget _sniffButton(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isPrimary = false,
    bool autofocus = false,
  }) {
    return FocusEffectWrapper(
      onTap: onTap,
      borderRadius: 10.0,
      autofocus: autofocus,
      useSafeScale: false,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: isPrimary
              ? LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)])
              : null,
          color: isPrimary ? null : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isPrimary ? theme.colorScheme.onPrimary : theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isPrimary ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
