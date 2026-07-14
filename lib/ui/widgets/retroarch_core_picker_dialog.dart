import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/emulator/retroarch_core_list.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/providers/library_provider.dart';
import 'package:freegosy/ui/widgets/focus_effect_wrapper.dart';

class CorePickerResult {
  final String emulatorId;
  final String? coreId;
  final bool remember;

  const CorePickerResult({
    required this.emulatorId,
    this.coreId,
    this.remember = false,
  });
}

class RetroArchCorePickerDialog extends ConsumerStatefulWidget {
  final Game game;
  final List<EmulatorStrategy> availableStrategies;
  final StrategyRegistry registry;
  final String? currentEmulatorId;
  final String? currentCoreId;

  const RetroArchCorePickerDialog({
    super.key,
    required this.game,
    required this.availableStrategies,
    required this.registry,
    this.currentEmulatorId,
    this.currentCoreId,
  });

  static Future<CorePickerResult?> show(
    BuildContext context, {
    required Game game,
    required List<EmulatorStrategy> availableStrategies,
    required StrategyRegistry registry,
    String? currentEmulatorId,
    String? currentCoreId,
  }) {
    return showModalBottomSheet<CorePickerResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => RetroArchCorePickerDialog(
        game: game,
        availableStrategies: availableStrategies,
        registry: registry,
        currentEmulatorId: currentEmulatorId,
        currentCoreId: currentCoreId,
      ),
    );
  }

  @override
  ConsumerState<RetroArchCorePickerDialog> createState() => _RetroArchCorePickerDialogState();
}

class _RetroArchCorePickerDialogState extends ConsumerState<RetroArchCorePickerDialog> {
  late String _selectedEmulatorId;
  String? _selectedCoreId;
  bool _remember = false;

  @override
  void initState() {
    super.initState();
    _selectedEmulatorId = widget.currentEmulatorId ?? widget.availableStrategies.first.emulatorId;
    _selectedCoreId = widget.currentCoreId;
  }

  List<RetroArchCore> get _availableCores {
    final slug = widget.game.platformSlug ?? '';
    return getCoresForSlug(slug);
  }

  bool get _isRetroArch => _selectedEmulatorId == 'retroarch';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slug = widget.game.platformSlug ?? '';
    final cores = _availableCores;
    final favCoreIds = ref.watch(retroarchFavoriteCoresProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            'Launch: ${widget.game.displayName}',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Platform: $slug',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Emulator selection (only if multiple options)
          if (widget.availableStrategies.length > 1) ...[
            Text(
              'Emulator',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ...widget.availableStrategies.map((strategy) {
              final isSelected = strategy.emulatorId == _selectedEmulatorId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FocusEffectWrapper(
                  onTap: () => setState(() {
                    _selectedEmulatorId = strategy.emulatorId;
                    if (strategy.emulatorId != 'retroarch') {
                      _selectedCoreId = null;
                    }
                  }),
                  borderRadius: 12.0,
                  useSafeScale: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isSelected
                          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.primary.withValues(alpha: 0.4)
                            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.check_circle : Icons.radio_button_off,
                          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          strategy.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
          ],

          // Core selection (only for RetroArch, when cores available)
          if (_isRetroArch && cores.isNotEmpty) ...[
            Text(
              'Core',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.3,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: cores.length,
                itemBuilder: (ctx, i) {
                  final core = cores[i];
                  final isSelected = _selectedCoreId == core.id;
                  final isFav = favCoreIds.contains(core.id);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: FocusEffectWrapper(
                      onTap: () => setState(() => _selectedCoreId = core.id),
                      borderRadius: 12.0,
                      useSafeScale: false,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: isSelected
                              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary.withValues(alpha: 0.4)
                                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.check_circle : Icons.radio_button_off,
                              color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                              size: 16,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        core.displayName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      if (core.isRecommended) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'REC',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: theme.colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (core.description != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        core.description!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Favorite star
                            FocusEffectWrapper(
                              onTap: () {
                                ref.read(retroarchFavoriteCoresProvider.notifier).toggle(core.id);
                              },
                              borderRadius: 8.0,
                              useSafeScale: false,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  isFav ? Icons.star : Icons.star_border,
                                  color: isFav ? Colors.amber : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Remember toggle
          FocusEffectWrapper(
            onTap: () => setState(() => _remember = !_remember),
            borderRadius: 12.0,
            useSafeScale: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
              ),
              child: Row(
                children: [
                  Icon(
                    _remember ? Icons.check_box : Icons.check_box_outline_blank,
                    color: _remember ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Remember for this game',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: FocusEffectWrapper(
                  onTap: () => Navigator.pop(context),
                  borderRadius: 12.0,
                  useSafeScale: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                    ),
                    child: Center(
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FocusEffectWrapper(
                  onTap: () {
                    Navigator.pop(
                      context,
                      CorePickerResult(
                        emulatorId: _selectedEmulatorId,
                        coreId: _isRetroArch ? _selectedCoreId : null,
                        remember: _remember,
                      ),
                    );
                  },
                  borderRadius: 12.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Launch',
                        style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
