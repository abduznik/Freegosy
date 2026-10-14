import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/library_provider.dart';
import 'focus_effect_wrapper.dart';

/// Library app-bar button that switches between the cover grid and the list.
class LayoutToggleButton extends ConsumerWidget {
  const LayoutToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isList = ref.watch(libraryLayoutProvider) == 'list';
    void toggle() => ref.read(libraryLayoutProvider.notifier).update(isList ? 'grid' : 'list');
    return FocusEffectWrapper(
      borderRadius: 24,
      scaleFactor: 1.1,
      onTap: toggle,
      child: IconButton(
        icon: Icon(isList ? Icons.grid_view : Icons.view_list),
        tooltip: isList ? 'Show covers' : 'Show list',
        onPressed: toggle,
      ),
    );
  }
}
