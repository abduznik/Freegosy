import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gamepads/gamepads.dart';
import '../../core/input/gamepad_service.dart';
import '../../core/input/known_controllers.dart';
import '../../core/input/custom_controller_mappings.dart';
import '../widgets/dialog_back_bridge.dart';

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
  GameAction.l2,
  GameAction.r2,
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
  GameAction.l2: 'L2 / Left Trigger',
  GameAction.r2: 'R2 / Right Trigger',
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
    return GestureDetector(
      onTap: onTap,
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
                                if (mapped)
                                  _buildDialogButton(
                                    theme,
                                    icon: Icons.edit,
                                    label: 'Edit Mapping',
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
  }) {
    return GestureDetector(
      onTap: onTap,
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

  void _startSniffing(BuildContext context, String controllerId, String name) {
    final service = ref.read(gamepadServiceProvider);
    final sniffedMapping = <String, GameAction>{};

    int currentActionIndex = 0;

    StreamSubscription<GamepadEvent>? rawSubscription;

    void showSniffDialog() {
      final isComplete = currentActionIndex >= _mappableActions.length;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final theme = Theme.of(context);
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              if (isComplete) {
                return DialogBackBridge(
                  child: AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    title: const Text('Mapping Complete'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle,
                            size: 48, color: Colors.green),
                        const SizedBox(height: 12),
                        Text(
                            '${sniffedMapping.length} button${sniffedMapping.length == 1 ? '' : 's'} mapped for $name.'),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          rawSubscription?.cancel();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Cancel'),
                      ),
                      _buildDialogButton(
                        theme,
                        icon: Icons.save,
                        label: 'Save Mapping',
                        isPrimary: true,
                        onTap: () {
                          rawSubscription?.cancel();
                          service.updateCustomMapping(
                              controllerId, sniffedMapping);
                          Navigator.pop(ctx);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                );
              }

              final currentAction = _mappableActions[currentActionIndex];
              final actionLabel = _actionLabels[currentAction] ?? currentAction.name;

              return DialogBackBridge(
                child: AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  title: Text('Mapping: $name'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.primary.withValues(alpha: 0.15),
                              theme.colorScheme.secondary
                                  .withValues(alpha: 0.05),
                            ],
                          ),
                          border: Border.all(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.touch_app,
                                size: 32,
                                color: theme.colorScheme.primary),
                            const SizedBox(height: 8),
                            Text(
                              'Press the button for:',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              actionLabel,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Mapped so far (${sniffedMapping.length}/${_mappableActions.length}):',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (sniffedMapping.isEmpty)
                        Text(
                          'No buttons mapped yet.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                        )
                      else
                        ...sniffedMapping.entries.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                children: [
                                  Text(
                                    '${_actionLabels[e.value] ?? e.value.name}: ',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(4),
                                      color: theme
                                          .colorScheme.surfaceContainerHighest,
                                    ),
                                    child: Text(
                                      e.key,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                        color: theme
                                            .colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        rawSubscription?.cancel();
                        Navigator.pop(ctx);
                      },
                      child: const Text('Cancel Mapping'),
                    ),
                    _buildDialogButton(
                      theme,
                      icon: Icons.skip_next,
                      label: 'Skip',
                      onTap: () {
                        if (mounted) {
                          setDialogState(() {
                            currentActionIndex++;
                          });
                          Navigator.pop(ctx);
                          showSniffDialog();
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    }

    showSniffDialog();

    rawSubscription = service.rawEvents.listen((event) {
      if (event.gamepadId != controllerId) return;
      if (event.value.abs() < 0.5) return;

      if (mounted) {
        final currentAction = _mappableActions[currentActionIndex];
        sniffedMapping[event.key] = currentAction;
        currentActionIndex++;

        // Close current dialog, reopen with next action
        Navigator.of(context).popUntil((route) => route.isFirst);
        showSniffDialog();
      }
    });
  }
}
