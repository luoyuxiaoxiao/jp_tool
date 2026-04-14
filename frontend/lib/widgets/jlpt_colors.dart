/// JLPT level color mapping used across all widgets.
library;

import 'package:flutter/material.dart';

class JlptColors {
  static const Map<String, Color> level = {
    'N5': Color(0xFF4CAF50), // green
    'N4': Color(0xFF2196F3), // blue
    'N3': Color(0xFFFF9800), // orange
    'N2': Color(0xFF9C27B0), // purple
    'N1': Color(0xFFF44336), // red
  };

  static Color of(String lvl) => level[lvl.toUpperCase()] ?? Colors.grey;

  static const levelOrder = ['N5', 'N4', 'N3', 'N2', 'N1'];
}
