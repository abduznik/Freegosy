import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum InputMode { mouse, gamepad, keyboard }

final currentTabIndexProvider = StateProvider<int>((ref) => 0);
final inputModeProvider = StateProvider<InputMode>((ref) => InputMode.mouse);
final focusedActionProvider = StateProvider<VoidCallback?>((ref) => null);
