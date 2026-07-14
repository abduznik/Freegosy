import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ui_provider.dart';

class FocusEffectWrapper extends ConsumerStatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleFactor;
  final double borderRadius;
  final bool showGlow;
  final FocusNode? focusNode;
  final bool autofocus;
  final FocusOnKeyEventCallback? onKeyEvent;
  final bool useSafeScale;

  const FocusEffectWrapper({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleFactor = 1.005,
    this.borderRadius = 12.0,
    this.showGlow = false,
    this.focusNode,
    this.autofocus = false,
    this.onKeyEvent,
    this.useSafeScale = true,
  });

  @override
  ConsumerState<FocusEffectWrapper> createState() => _FocusEffectWrapperState();
}

class _FocusEffectWrapperState extends ConsumerState<FocusEffectWrapper> {
  bool _isFocused = false;
  bool _isHovered = false;
  DateTime? _keyDownTime;
  Timer? _longPressTimer;

  void _handleFocusChange(bool hasFocus) {
    if (!mounted) return;
    setState(() => _isFocused = hasFocus);
    if (hasFocus) {
      ref.read(focusedActionProvider.notifier).state = widget.onTap;
      ref.read(focusedLongPressActionProvider.notifier).state = widget.onLongPress;
    } else {
      if (ref.read(focusedActionProvider) == widget.onTap) {
        ref.read(focusedActionProvider.notifier).state = null;
      }
      if (ref.read(focusedLongPressActionProvider) == widget.onLongPress) {
        ref.read(focusedLongPressActionProvider.notifier).state = null;
      }
    }
  }

  @override
  void didUpdateWidget(FocusEffectWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isFocused && oldWidget.onTap != widget.onTap) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isFocused) {
          ref.read(focusedActionProvider.notifier).state = widget.onTap;
        }
      });
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputMode = ref.watch(inputModeProvider);
    final showEffect = (inputMode == InputMode.mouse) ? _isHovered : _isFocused;

    final isFocused = showEffect;
    final borderColor = isFocused
        ? (Theme.of(context).brightness == Brightness.light
            ? Colors.black.withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.8))
        : Colors.transparent;
    final borderWidth = isFocused ? 2.5 : 0.0;

    return Focus(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onFocusChange: _handleFocusChange,
      onKeyEvent: (node, event) {
        if (widget.onKeyEvent != null) {
          final res = widget.onKeyEvent!(node, event);
          if (res == KeyEventResult.handled) return KeyEventResult.handled;
        }
        final isAction = event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space;
        if (event is KeyDownEvent && isAction) {
          _keyDownTime = DateTime.now();
          _longPressTimer?.cancel();
          _longPressTimer = Timer(const Duration(milliseconds: 500), () {
            if (mounted && _keyDownTime != null && widget.onLongPress != null) {
              widget.onLongPress!.call();
              _keyDownTime = null;
            }
          });
          return KeyEventResult.handled;
        }
        if (event is KeyUpEvent && isAction) {
          _longPressTimer?.cancel();
          if (_keyDownTime != null) {
            final held = DateTime.now().difference(_keyDownTime!);
            if (held.inMilliseconds < 500) {
              widget.onTap?.call();
            }
          }
          _keyDownTime = null;
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(color: borderColor, width: borderWidth),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
