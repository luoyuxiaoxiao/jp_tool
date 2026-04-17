library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const Map<String, LogicalKeyboardKey> _tokenToKey = {
  'a': LogicalKeyboardKey.keyA,
  'b': LogicalKeyboardKey.keyB,
  'c': LogicalKeyboardKey.keyC,
  'd': LogicalKeyboardKey.keyD,
  'e': LogicalKeyboardKey.keyE,
  'f': LogicalKeyboardKey.keyF,
  'g': LogicalKeyboardKey.keyG,
  'h': LogicalKeyboardKey.keyH,
  'i': LogicalKeyboardKey.keyI,
  'j': LogicalKeyboardKey.keyJ,
  'k': LogicalKeyboardKey.keyK,
  'l': LogicalKeyboardKey.keyL,
  'm': LogicalKeyboardKey.keyM,
  'n': LogicalKeyboardKey.keyN,
  'o': LogicalKeyboardKey.keyO,
  'p': LogicalKeyboardKey.keyP,
  'q': LogicalKeyboardKey.keyQ,
  'r': LogicalKeyboardKey.keyR,
  's': LogicalKeyboardKey.keyS,
  't': LogicalKeyboardKey.keyT,
  'u': LogicalKeyboardKey.keyU,
  'v': LogicalKeyboardKey.keyV,
  'w': LogicalKeyboardKey.keyW,
  'x': LogicalKeyboardKey.keyX,
  'y': LogicalKeyboardKey.keyY,
  'z': LogicalKeyboardKey.keyZ,
  '0': LogicalKeyboardKey.digit0,
  '1': LogicalKeyboardKey.digit1,
  '2': LogicalKeyboardKey.digit2,
  '3': LogicalKeyboardKey.digit3,
  '4': LogicalKeyboardKey.digit4,
  '5': LogicalKeyboardKey.digit5,
  '6': LogicalKeyboardKey.digit6,
  '7': LogicalKeyboardKey.digit7,
  '8': LogicalKeyboardKey.digit8,
  '9': LogicalKeyboardKey.digit9,
  'f1': LogicalKeyboardKey.f1,
  'f2': LogicalKeyboardKey.f2,
  'f3': LogicalKeyboardKey.f3,
  'f4': LogicalKeyboardKey.f4,
  'f5': LogicalKeyboardKey.f5,
  'f6': LogicalKeyboardKey.f6,
  'f7': LogicalKeyboardKey.f7,
  'f8': LogicalKeyboardKey.f8,
  'f9': LogicalKeyboardKey.f9,
  'f10': LogicalKeyboardKey.f10,
  'f11': LogicalKeyboardKey.f11,
  'f12': LogicalKeyboardKey.f12,
  'enter': LogicalKeyboardKey.enter,
  'space': LogicalKeyboardKey.space,
  'tab': LogicalKeyboardKey.tab,
  'esc': LogicalKeyboardKey.escape,
  'up': LogicalKeyboardKey.arrowUp,
  'down': LogicalKeyboardKey.arrowDown,
  'left': LogicalKeyboardKey.arrowLeft,
  'right': LogicalKeyboardKey.arrowRight,
  'backspace': LogicalKeyboardKey.backspace,
  'delete': LogicalKeyboardKey.delete,
};

String normalizeShortcutText(String value) {
  return value.toLowerCase().replaceAll(' ', '').replaceAll('command', 'meta');
}

String shortcutDisplayText(String value) {
  final parts = normalizeShortcutText(value)
      .split('+')
      .where((e) => e.trim().isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';

  final rendered = <String>[];
  for (final p in parts) {
    switch (p) {
      case 'ctrl':
      case 'control':
        rendered.add('Ctrl');
        break;
      case 'shift':
        rendered.add('Shift');
        break;
      case 'alt':
        rendered.add('Alt');
        break;
      case 'meta':
      case 'cmd':
      case 'win':
        rendered.add('Meta');
        break;
      case 'enter':
      case 'return':
        rendered.add('Enter');
        break;
      case 'escape':
      case 'esc':
        rendered.add('Esc');
        break;
      default:
        rendered.add(p.toUpperCase());
        break;
    }
  }

  return rendered.join(' + ');
}

ShortcutActivator? parseShortcutActivator(String value) {
  final parts = normalizeShortcutText(value)
      .split('+')
      .where((e) => e.trim().isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;

  var control = false;
  var shift = false;
  var alt = false;
  var meta = false;
  String? mainKeyToken;

  for (final part in parts) {
    switch (part) {
      case 'ctrl':
      case 'control':
        control = true;
        continue;
      case 'shift':
        shift = true;
        continue;
      case 'alt':
        alt = true;
        continue;
      case 'meta':
      case 'cmd':
      case 'win':
        meta = true;
        continue;
      default:
        if (mainKeyToken != null) {
          return null;
        }
        mainKeyToken = _normalizeMainToken(part);
    }
  }

  if (mainKeyToken == null) return null;
  final key = _keyFromToken(mainKeyToken);
  if (key == null) return null;

  return SingleActivator(
    key,
    control: control,
    shift: shift,
    alt: alt,
    meta: meta,
  );
}

bool isValidShortcut(String value) => parseShortcutActivator(value) != null;

String? buildShortcutFromKeyEvent(KeyEvent event) {
  if (event is! KeyDownEvent) {
    return null;
  }

  final main = _tokenFromLogicalKey(event.logicalKey);
  if (main == null) {
    return null;
  }

  final pressed = HardwareKeyboard.instance.logicalKeysPressed;
  final hasCtrl = pressed.contains(LogicalKeyboardKey.controlLeft) ||
      pressed.contains(LogicalKeyboardKey.controlRight);
  final hasShift = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
      pressed.contains(LogicalKeyboardKey.shiftRight);
  final hasAlt = pressed.contains(LogicalKeyboardKey.altLeft) ||
      pressed.contains(LogicalKeyboardKey.altRight);
  final hasMeta = pressed.contains(LogicalKeyboardKey.metaLeft) ||
      pressed.contains(LogicalKeyboardKey.metaRight);

  final parts = <String>[];
  if (hasCtrl) parts.add('ctrl');
  if (hasShift) parts.add('shift');
  if (hasAlt) parts.add('alt');
  if (hasMeta) parts.add('meta');
  parts.add(main);

  return normalizeShortcutText(parts.join('+'));
}

bool isModifierLogicalKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;
}

String _normalizeMainToken(String token) {
  switch (token) {
    case 'return':
      return 'enter';
    case 'escape':
      return 'esc';
    case 'cmd':
    case 'win':
      return 'meta';
    default:
      return token;
  }
}

LogicalKeyboardKey? _keyFromToken(String token) {
  final normalized = _normalizeMainToken(token);
  return _tokenToKey[normalized];
}

String? _tokenFromLogicalKey(LogicalKeyboardKey key) {
  if (isModifierLogicalKey(key)) {
    return null;
  }

  if (key == LogicalKeyboardKey.numpadEnter) {
    return 'enter';
  }

  for (final entry in _tokenToKey.entries) {
    if (entry.value == key) {
      return entry.key;
    }
  }

  final label = key.keyLabel.trim().toLowerCase();
  if (RegExp(r'^[a-z0-9]$').hasMatch(label)) {
    return label;
  }

  return null;
}
