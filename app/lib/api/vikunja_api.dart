import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class VikunjaApi {
  String server;
  String token;

  /// Vikunja 2.x 的登录 JWT 只有 10 分钟，靠一次性、会轮换的 refresh token 续期
  String refreshToken;

  /// token 变了（登录/续期）时回调，用来持久化
  void Function(String token, String refreshToken)? onTokens;
  void Function()? onUnauthorized;
  final http.Client _http = http.Client();
  Future<bool>? _refreshing;

  VikunjaApi({this.server = '', this.token = '', this.refreshToken = ''});

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse('$server/api/v1$path');
    if (query == null) return base;
    return base.replace(
      queryParameters: {
        for (final e in query.entries)
          e.key: e.value is List
              ? (e.value as List).map((v) => '$v').toList()
              : '${e.value}',
      },
    );
  }

  static final _cookieRe = RegExp(r'vikunja_refresh_token=([^;,\s]+)');

  void _takeRefreshCookie(Map<String, String> headers) {
    final m = _cookieRe.firstMatch(headers['set-cookie'] ?? '');
    if (m != null) refreshToken = m[1]!;
  }

  /// JWT 还剩不到一分钟就提前续期，少吃一次 401
  bool get _expiringSoon {
    final parts = token.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = (payload['exp'] as num?)?.toInt();
      if (exp == null) return false;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000)
              .difference(DateTime.now()) <
          const Duration(minutes: 1);
    } catch (_) {
      return false;
    }
  }

  /// 并发请求共用同一次续期：refresh token 只能用一次，重复用会互相作废
  Future<bool> _refresh() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    if (refreshToken.isEmpty) return false;
    try {
      final res = await _http
          .post(
            _uri('/user/token/refresh'),
            headers: {'Cookie': 'vikunja_refresh_token=$refreshToken'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return false;
      token = (jsonDecode(res.body) as Map)['token'] as String;
      _takeRefreshCookie(res.headers);
      onTokens?.call(token, refreshToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<(dynamic, Map<String, String>)> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool retried = false,
  }) async {
    if (!retried && refreshToken.isNotEmpty && _expiringSoon) await _refresh();
    final sentToken = token;
    final req = http.Request(method, _uri(path, query));
    if (sentToken.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $sentToken';
    }
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    late http.Response res;
    try {
      res = await http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 15)),
      );
    } catch (_) {
      throw ApiException(0, '连不上服务器');
    }
    // 别的请求已经续过期了就直接用新 token 重试，不再重复续期
    if (res.statusCode == 401 &&
        sentToken.isNotEmpty &&
        !retried &&
        (token != sentToken || await _refresh())) {
      return _send(method, path, body: body, query: query, retried: true);
    }
    final text = utf8.decode(res.bodyBytes);
    final json = text.isEmpty ? null : jsonDecode(text);
    if (res.statusCode >= 400) {
      if (res.statusCode == 401 && token.isNotEmpty) onUnauthorized?.call();
      final msg = json is Map ? json['message'] : null;
      throw ApiException(
        res.statusCode,
        msg?.toString() ?? '请求失败 (${res.statusCode})',
      );
    }
    return (json, res.headers);
  }

  Future<dynamic> _json(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async => (await _send(method, path, body: body, query: query)).$1;

  Future<void> login(String username, String password) async {
    final (j, headers) = await _send(
      'POST',
      '/login',
      body: {'username': username, 'password': password, 'long_token': true},
    );
    token = j['token'] as String;
    _takeRefreshCookie(headers);
    onTokens?.call(token, refreshToken);
  }

  Future<User> getUser() async => User.fromJson(await _json('GET', '/user'));

  /// 创建给面板用的长期 API token（权限只覆盖任务、标签、项目），返回 (id, token)
  Future<(int, String)> createApiToken(String title, DateTime expires) async {
    final j = await _json(
      'PUT',
      '/tokens',
      body: {
        'title': title,
        'expires_at': expires.toUtc().toIso8601String(),
        // 面板要用完整应用的同一套功能：增删改任务、标签，读项目
        'permissions': {
          'tasks': ['read_all', 'read_one', 'create', 'update', 'delete'],
          'projects': ['read_all'],
          'labels': ['read_all', 'create'],
          'tasks_labels': ['read_all', 'create', 'delete'],
        },
      },
    );
    return (j['id'] as int, j['token'] as String);
  }

  Future<void> deleteApiToken(int id) => _json('DELETE', '/tokens/$id');

  Future<List<String>> listTimezones() async =>
      ((await _json('GET', '/user/timezones')) as List).cast<String>()..sort();

  /// 改账号时区（Vikunja 的提醒、逾期通知按它算）
  Future<void> setUserTimezone(User user, String timezone) => _json(
    'POST',
    '/user/settings/general',
    body: {...user.settings, 'timezone': timezone},
  );

  Future<List<Project>> listProjects() async {
    final j = await _json('GET', '/projects', query: {'per_page': 500}) as List;
    // 负数 id 是"收藏""已保存过滤器"之类的伪项目
    return j
        .map((e) => Project.fromJson(e as Map<String, dynamic>))
        .where((p) => p.id > 0 && !p.isArchived)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  Future<Project> createProject(String title, String hexColor) async =>
      Project.fromJson(
        await _json(
          'PUT',
          '/projects',
          body: {'title': title, 'hex_color': hexColor},
        ),
      );

  Future<Project> updateProject(
    Project p, {
    String? title,
    String? hexColor,
  }) async => Project.fromJson(
    await _json(
      'POST',
      '/projects/${p.id}',
      body: p.toJson(title: title, hexColor: hexColor),
    ),
  );

  Future<void> deleteProject(int id) => _json('DELETE', '/projects/$id');

  Future<List<Label>> listLabels() async {
    final j =
        await _json('GET', '/labels', query: {'per_page': 500}) as List? ?? [];
    return j.map((e) => Label.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Label> createLabel(String title, String hexColor) async =>
      Label.fromJson(
        await _json(
          'PUT',
          '/labels',
          body: {'title': title, 'hex_color': hexColor},
        ),
      );

  /// 按过滤条件拉全部任务，自动翻页
  /// [timezone] 决定过滤条件里 now/d 这类日期按哪个时区算
  Future<List<Task>> listTasks(String filter, {String? timezone}) async {
    final all = <Task>[];
    for (var page = 1; ; page++) {
      final (j, headers) = await _send(
        'GET',
        '/tasks',
        query: {
          'filter': filter,
          'page': page,
          'per_page': 50,
          'filter_timezone': ?timezone,
        },
      );
      all.addAll(
        ((j as List?) ?? []).map(
          (e) => Task.fromJson(e as Map<String, dynamic>),
        ),
      );
      final total =
          int.tryParse(headers['x-pagination-total-pages'] ?? '1') ?? 1;
      if (page >= total) break;
    }
    return all;
  }

  Future<Task> createTask(int projectId, Map<String, dynamic> body) async =>
      Task.fromJson(
        await _json('PUT', '/projects/$projectId/tasks', body: body),
      );

  Future<Task> updateTask(Task t) async =>
      Task.fromJson(await _json('POST', '/tasks/${t.id}', body: t.raw));

  Future<void> deleteTask(int id) => _json('DELETE', '/tasks/$id');

  Future<void> addLabel(int taskId, int labelId) =>
      _json('PUT', '/tasks/$taskId/labels', body: {'label_id': labelId});

  Future<void> removeLabel(int taskId, int labelId) =>
      _json('DELETE', '/tasks/$taskId/labels/$labelId');
}
