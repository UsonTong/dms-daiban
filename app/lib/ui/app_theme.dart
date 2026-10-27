import 'package:flutter/material.dart';

import 'dms_theme.dart';
import 'motion.dart';

/// 完整应用和 Mod+D 面板共用同一套主题，保证两边看起来是一个东西
const _seed = Color(0xFF4A5BAB);

ThemeData buildTheme(ColorScheme scheme) => ThemeData(
  colorScheme: scheme,
  // 所有平台统一用共享轴过渡（右进左出）
  pageTransitionsTheme: PageTransitionsTheme(
    builders: {
      for (final p in TargetPlatform.values)
        p: SharedAxisPageTransitionsBuilder(),
    },
  ),
  // Linux/Windows 上补中文字体，避免回退到难看的字形
  fontFamilyFallback: const [
    'Noto Sans CJK SC',
    'Noto Sans SC',
    'Source Han Sans SC',
    'PingFang SC',
    'Microsoft YaHei',
  ],
  snackBarTheme: const SnackBarThemeData(showCloseIcon: false),
);

final _fallbackLight = buildTheme(ColorScheme.fromSeed(seedColor: _seed));
final _fallbackDark = buildTheme(
  ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
);

/// 按 DMS 配色（有的话）构建 MaterialApp；DMS 换壁纸、切深浅色时自动重建
Widget themedApp(
  Widget Function(ThemeData light, ThemeData dark, ThemeMode mode) builder,
) {
  return ValueListenableBuilder<DmsColors?>(
    valueListenable: DmsTheme.instance,
    builder: (context, dms, _) => dms == null
        ? builder(_fallbackLight, _fallbackDark, ThemeMode.system)
        : builder(buildTheme(dms.light), buildTheme(dms.dark), dms.mode),
  );
}
