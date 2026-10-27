import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/vikunja_api.dart';
import '../utils/zone.dart';
import 'app_state.dart';

/// 给 DMS 顶栏面板准备的配置：~/.config/vikunja-md/dms.json（仅本人可读）。
/// 面板拿里面的长期 API token 直接调 Vikunja，App 关着也能用。
/// token 只有读写任务、读项目的权限；快过期或换了账号/服务器时自动换新的并删掉旧的。
/// token 权限变了就加一，旧 token 会被自动换掉
const _tokenVersion = 2;

class DmsBridge {
  final AppState state;
  Timer? _debounce;
  bool _busy = false;
  bool _wasLoggedIn = false;

  DmsBridge(this.state) {
    if (kIsWeb || !Platform.isLinux) return;
    state.addListener(_schedule);
  }

  static File get _file {
    final config =
        Platform.environment['XDG_CONFIG_HOME'] ??
        '${Platform.environment['HOME']}/.config';
    return File('$config/vikunja-md/dms.json');
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), _sync);
  }

  Map<String, dynamic>? _read() {
    try {
      return jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _sync() async {
    if (_busy || !state.ready) return;
    _busy = true;
    try {
      if (!state.loggedIn) {
        // 退出登录：面板也随之失效
        if (_wasLoggedIn && _file.existsSync()) _file.deleteSync();
        _wasLoggedIn = false;
        return;
      }
      _wasLoggedIn = true;
      final user = state.user;
      if (user == null) return;

      final old = _read();
      var cfg = Map<String, dynamic>.from(old ?? {});
      final expires = DateTime.fromMillisecondsSinceEpoch(
        (cfg['tokenExpires'] as num?)?.toInt() ?? 0,
      );
      final stale =
          cfg['tokenVersion'] != _tokenVersion ||
          cfg['token'] == null ||
          cfg['server'] != state.server ||
          cfg['username'] != user.username ||
          expires.difference(DateTime.now()) < const Duration(days: 30);
      if (stale) {
        final newExpires = DateTime.now().add(const Duration(days: 365));
        final (id, token) = await state.api.createApiToken(
          'DMS 顶栏面板',
          newExpires,
        );
        final oldId = (cfg['tokenId'] as num?)?.toInt();
        if (oldId != null &&
            cfg['server'] == state.server &&
            cfg['username'] == user.username) {
          try {
            await state.api.deleteApiToken(oldId);
          } on ApiException {
            // 旧 token 删不掉也不影响
          }
        }
        cfg = {
          ...cfg,
          'token': token,
          'tokenId': id,
          'tokenExpires': newExpires.millisecondsSinceEpoch,
          'tokenVersion': _tokenVersion,
        };
      }
      cfg
        ..['server'] = state.server
        ..['username'] = user.username
        ..['defaultProjectId'] = state.defaultProjectId
        ..['tzOffsetMinutes'] = zoneOffsetMinutes()
        ..['timezone'] = zoneName
        ..['planDays'] = state.planDays;
      if (jsonEncode(cfg) == jsonEncode(old)) return;

      final f = _file;
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      // 先建空文件改成仅本人可读，再写入 token
      await tmp.writeAsString('');
      await Process.run('chmod', ['600', tmp.path]);
      await tmp.writeAsString(jsonEncode(cfg), flush: true);
      await tmp.rename(f.path);
    } on ApiException {
      // 网络或权限问题，下次数据变化再试
    } on FileSystemException {
      // 写不了就算了，不影响 App 本身
    } finally {
      _busy = false;
    }
  }
}
