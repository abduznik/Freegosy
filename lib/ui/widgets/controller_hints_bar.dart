import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ui_provider.dart';

class ControllerHintItem {
  final String label;
  final String button;
  final Color buttonColor;

  const ControllerHintItem({
    required this.label,
    required this.button,
    this.buttonColor = Colors.white24,
  });
}

class ControllerHintsBar extends ConsumerWidget {
  final List<ControllerHintItem> hints;

  const ControllerHintsBar({
    super.key,
    required this.hints,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(inputModeProvider);
    
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: hints.map((hint) => _buildHint(context, hint, mode)).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildHint(BuildContext context, ControllerHintItem hint, InputMode mode) {
    String buttonText = hint.button;
    double width = 24;
    
    if (mode == InputMode.keyboard) {
      if (buttonText == 'A') {
        buttonText = 'Enter';
        width = 48;
      } else if (buttonText == 'B') {
        buttonText = 'Esc';
        width = 32;
      } else if (buttonText == 'L1') {
        buttonText = 'Q';
        width = 24;
      } else if (buttonText == 'R1') {
        buttonText = 'E';
        width = 24;
      } else if (buttonText == 'X') {
        buttonText = 'X';
        width = 24;
      } else if (buttonText == 'Y') {
        buttonText = 'Y';
        width = 24;
      }
    } else {
      if (buttonText == 'L1' || buttonText == 'R1') {
        width = 32;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(left: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Button Glyph
          Container(
            width: width,
            height: 24,
            decoration: BoxDecoration(
              color: hint.buttonColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                buttonText,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: width > 32 ? 10 : 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Label
          Text(
            hint.label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
