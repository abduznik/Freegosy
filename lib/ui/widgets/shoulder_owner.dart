import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/global_actions.dart';

/// Claims LB/RB for the screen it wraps while it is mounted, so they switch
/// that screen's tabs and not the app's main tabs.
class ShoulderOwner extends ConsumerStatefulWidget {
  const ShoulderOwner({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ShoulderOwner> createState() => _ShoulderOwnerState();
}

class _ShoulderOwnerState extends ConsumerState<ShoulderOwner> {
  late ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    // Providers can't change while the tree builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(shoulderOwnersProvider.notifier).state++;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context);
  }

  @override
  void dispose() {
    final container = _container;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final n = container.read(shoulderOwnersProvider);
        if (n > 0) container.read(shoulderOwnersProvider.notifier).state = n - 1;
      } catch (_) {
        // Container already disposed (test teardown).
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
