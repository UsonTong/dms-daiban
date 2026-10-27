import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 跟随 DankMaterialShell 的配色：读 ~/.cache/DankMaterialShell/dms-colors.json
/// （DMS 按壁纸用 matugen 生成的完整 Material 3 调色板），深浅色跟 DMS 的设置走。
/// 文件变了（换壁纸、切深浅色）就实时更新；不在 Linux 或没装 DMS 时 value 为 null，用默认主题。
class DmsTheme extends ValueNotifier<DmsColors?> {
  DmsTheme._() : super(null) {
    if (kIsWeb || !Platform.isLinux) return;
    _load();
    _watch(_colorsFile.parent, 'dms-colors.json');
    _watch(_sessionFile.parent, 'session.json');
    _poll();
    Timer.periodic(const Duration(seconds: 30), (_) => _poll());
  }

  static final instance = DmsTheme._();

  static String get _home => Platform.environment['HOME'] ?? '';
  static File get _colorsFile => File(
    '${Platform.environment['XDG_CACHE_HOME'] ?? '$_home/.cache'}/DankMaterialShell/dms-colors.json',
  );
  static File get _sessionFile => File(
    '${Platform.environment['XDG_STATE_HOME'] ?? '$_home/.local/state'}/DankMaterialShell/session.json',
  );

  Timer? _debounce;

  // 监听目录而不是文件：DMS 用"写临时文件再改名"的方式更新，文件本身会被替换。
  // 改名事件里 path 是临时文件名，目标文件名在 destination 里，两个都要看
  void _watch(Directory dir, String name) {
    if (!dir.existsSync()) return;
    dir.watch().listen((e) {
      final dest = e is FileSystemMoveEvent ? e.destination : null;
      if (!e.path.endsWith('/$name') && !(dest?.endsWith('/$name') ?? false)) {
        return;
      }
      _schedule();
    }, onError: (_) {});
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  // 兜底：有的写法不会产生能识别的事件，每 30 秒比一次修改时间
  final _mtimes = <String, DateTime?>{};
  void _poll() {
    var changed = false;
    for (final f in [_colorsFile, _sessionFile]) {
      DateTime? m;
      try {
        m = f.lastModifiedSync();
      } catch (_) {}
      if (_mtimes.containsKey(f.path) && _mtimes[f.path] != m) changed = true;
      _mtimes[f.path] = m;
    }
    if (changed) _schedule();
  }

  void _load() {
    try {
      final j =
          jsonDecode(_colorsFile.readAsStringSync()) as Map<String, dynamic>;
      final colors = j['colors'] as Map<String, dynamic>;
      var light = j['mode'] == 'light';
      try {
        final s =
            jsonDecode(_sessionFile.readAsStringSync()) as Map<String, dynamic>;
        if (s['isLightMode'] is bool) light = s['isLightMode'] as bool;
      } catch (_) {}
      value = DmsColors(
        light: _scheme(
          colors['light'] as Map<String, dynamic>,
          Brightness.light,
        ),
        dark: _scheme(colors['dark'] as Map<String, dynamic>, Brightness.dark),
        mode: light ? ThemeMode.light : ThemeMode.dark,
      );
    } catch (_) {
      // 文件不存在或格式不对：保持上一次的配色
    }
  }

  static ColorScheme _scheme(Map<String, dynamic> m, Brightness b) {
    Color c(String key) {
      final hex = (m[key] as String).replaceFirst('#', '');
      return Color(0xFF000000 | int.parse(hex, radix: 16));
    }

    return ColorScheme(
      brightness: b,
      primary: c('primary'),
      onPrimary: c('on_primary'),
      primaryContainer: c('primary_container'),
      onPrimaryContainer: c('on_primary_container'),
      primaryFixed: c('primary_fixed'),
      primaryFixedDim: c('primary_fixed_dim'),
      onPrimaryFixed: c('on_primary_fixed'),
      onPrimaryFixedVariant: c('on_primary_fixed_variant'),
      secondary: c('secondary'),
      onSecondary: c('on_secondary'),
      secondaryContainer: c('secondary_container'),
      onSecondaryContainer: c('on_secondary_container'),
      secondaryFixed: c('secondary_fixed'),
      secondaryFixedDim: c('secondary_fixed_dim'),
      onSecondaryFixed: c('on_secondary_fixed'),
      onSecondaryFixedVariant: c('on_secondary_fixed_variant'),
      tertiary: c('tertiary'),
      onTertiary: c('on_tertiary'),
      tertiaryContainer: c('tertiary_container'),
      onTertiaryContainer: c('on_tertiary_container'),
      tertiaryFixed: c('tertiary_fixed'),
      tertiaryFixedDim: c('tertiary_fixed_dim'),
      onTertiaryFixed: c('on_tertiary_fixed'),
      onTertiaryFixedVariant: c('on_tertiary_fixed_variant'),
      error: c('error'),
      onError: c('on_error'),
      errorContainer: c('error_container'),
      onErrorContainer: c('on_error_container'),
      surface: c('surface'),
      onSurface: c('on_surface'),
      surfaceDim: c('surface_dim'),
      surfaceBright: c('surface_bright'),
      surfaceContainerLowest: c('surface_container_lowest'),
      surfaceContainerLow: c('surface_container_low'),
      surfaceContainer: c('surface_container'),
      surfaceContainerHigh: c('surface_container_high'),
      surfaceContainerHighest: c('surface_container_highest'),
      onSurfaceVariant: c('on_surface_variant'),
      outline: c('outline'),
      outlineVariant: c('outline_variant'),
      shadow: c('shadow'),
      scrim: c('scrim'),
      inverseSurface: c('inverse_surface'),
      onInverseSurface: c('inverse_on_surface'),
      inversePrimary: c('inverse_primary'),
      surfaceTint: c('surface_tint'),
    );
  }
}

class DmsColors {
  final ColorScheme light;
  final ColorScheme dark;
  final ThemeMode mode;
  const DmsColors({
    required this.light,
    required this.dark,
    required this.mode,
  });
}
