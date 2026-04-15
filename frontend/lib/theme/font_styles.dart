library;

import 'package:flutter/material.dart';

const String kZhPrimaryFamily = 'LXGWWenKaiScreen';
const String kJaPrimaryFamily = 'KleeOne';

const List<String> _commonFallback = [
  'KleeOne',
  'Noto Sans CJK SC',
  'Noto Sans CJK JP',
  'Microsoft YaHei UI',
  'Yu Gothic UI',
  'Segoe UI',
  'Segoe UI Emoji',
];

const List<String> _japaneseFallback = [
  'LXGWWenKaiScreen',
  'Noto Sans CJK JP',
  'Yu Gothic UI',
  'Microsoft YaHei UI',
  'Segoe UI Emoji',
];

bool containsJapanese(String text) {
  return RegExp(r'[\u3040-\u30ff\u31f0-\u31ff\u3400-\u9fff々]').hasMatch(text);
}

String kataToHira(String input) {
  final codeUnits = input.codeUnits.toList();
  for (var i = 0; i < codeUnits.length; i++) {
    final c = codeUnits[i];
    if (c >= 0x30A1 && c <= 0x30F6) {
      codeUnits[i] = c - 0x60;
    }
  }
  return String.fromCharCodes(codeUnits);
}

TextStyle zhTextStyle(
  TextStyle? base, {
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  TextDecoration? decoration,
  Color? decorationColor,
  double? decorationThickness,
}) {
  return (base ?? const TextStyle()).copyWith(
    fontFamily: kZhPrimaryFamily,
    fontFamilyFallback: _commonFallback,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    decoration: decoration,
    decorationColor: decorationColor,
    decorationThickness: decorationThickness,
  );
}

TextStyle jaTextStyle(
  TextStyle? base, {
  bool decorative = false,
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  TextDecoration? decoration,
  Color? decorationColor,
  double? decorationThickness,
}) {
  return (base ?? const TextStyle()).copyWith(
    fontFamily: kJaPrimaryFamily,
    fontFamilyFallback: _japaneseFallback,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    decoration: decoration,
    decorationColor: decorationColor,
    decorationThickness: decorationThickness,
  );
}

TextStyle cjkTextStyle(
  String text,
  TextStyle? base, {
  bool decorativeJapanese = false,
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  TextDecoration? decoration,
  Color? decorationColor,
  double? decorationThickness,
}) {
  if (containsJapanese(text)) {
    return jaTextStyle(
      base,
      decorative: decorativeJapanese,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationThickness: decorationThickness,
    );
  }

  return zhTextStyle(
    base,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    decoration: decoration,
    decorationColor: decorationColor,
    decorationThickness: decorationThickness,
  );
}

TextTheme buildCjkTextTheme(TextTheme base) {
  TextStyle style(TextStyle? s) => zhTextStyle(s);

  return base.copyWith(
    displayLarge: style(base.displayLarge),
    displayMedium: style(base.displayMedium),
    displaySmall: style(base.displaySmall),
    headlineLarge: style(base.headlineLarge),
    headlineMedium: style(base.headlineMedium),
    headlineSmall: style(base.headlineSmall),
    titleLarge: style(base.titleLarge),
    titleMedium: style(base.titleMedium),
    titleSmall: style(base.titleSmall),
    bodyLarge: style(base.bodyLarge),
    bodyMedium: style(base.bodyMedium),
    bodySmall: style(base.bodySmall),
    labelLarge: style(base.labelLarge),
    labelMedium: style(base.labelMedium),
    labelSmall: style(base.labelSmall),
  );
}
