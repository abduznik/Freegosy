import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ui_provider.dart';

class FocusEffectWrapper extends ConsumerStatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleFactor;
  final double borderRadius;
  final bool showGlow;
  final FocusNode? focusNode;
  final bool autofocus;
  final FocusOnKeyEventCallback? onKeyEvent;

  const FocusEffectWrapper({
    super.key,
    required this.child,
    this.onTap,
    this.scaleFactor = 1.05,
    this.borderRadius = 12.0,
    this.showGlow = true,
    this.focusNode,
    this.autofocus = false,
    this.onKeyEvent,
  });

  @override
  ConsumerState<FocusEffectWrapper> createState() => _FocusEffectWrapperState();
}

class _FocusEffectWrapperState extends ConsumerState<FocusEffectWrapper> {
  bool _isFocused = false;
  bool _isHovered = false;

  void _handleFocusChange(bool hasFocus) {
    if (!mounted) return;
    setState(() => _isFocused = hasFocus);
    
    if (hasFocus) {
      ref.read(focusedActionProvider.notifier).state = widget.onTap;
    } else {
      if (ref.read(focusedActionProvider) == widget.onTap) {
        ref.read(focusedActionProvider.notifier).state = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inputMode = ref.watch(inputModeProvider);
    
    // "One Jabber" Logic:
    // If we are in mouse mode, we ONLY care about the hover state.
    // If we are in controller/keyboard mode, we ONLY care about the focus state.
    final bool showEffect = (inputMode == InputMode.mouse) 
        ? _isHovered 
        : _isFocused;

    return Focus(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onFocusChange: _handleFocusChange,
      onKeyEvent: (node, event) {
        if (widget.onKeyEvent != null) {
          final res = widget.onKeyEvent!(node, event);
          if (res == KeyEventResult.handled) {
            return KeyEventResult.handled;
          }
        }
        if (event is KeyDownEvent && 
            (event.logicalKey == LogicalKeyboardKey.enter || 
             event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap?.call();
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
          behavior: HitTestBehavior.opaque, 
          child: AnimatedScale(
            scale: showEffect ? widget.scaleFactor : 1.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (widget.showGlow)
                  Positioned.fill(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: showEffect ? 1.0 : 0.0,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(widget.borderRadius),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.4),
                              blurRadius: 25,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                
                widget.child,

                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.borderRadius),
                        border: Border.all(
                          color: showEffect ? Colors.white : Colors.transparent,
                          width: 1.5,
                          strokeAlign: BorderSide.strokeAlignInside,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
