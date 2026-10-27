import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';
import '../api/vikunja_api.dart';
import '../utils/dates.dart';
import '../utils/quick_add.dart';
import '../utils/zone.dart';

const defaultServer = 'http://localhost:3456';

const labelPalette = [
  'e8590c',
  '2f9e44',
  '1971c2',
  '9c36b5',
  'f08c00',
  '0c8599',
  'c2255c',
  '5c940d',
];

class AppState extends ChangeNotifier {
  /// 面板模式（Mod+D 弹出的"今天"面板，独立进程）：用 dms.json 里的长期 API token，
  /// 不读写完整应用的登录信息——两个进程共用会轮换的 refresh token 会互相挤掉线
  final bool panel;

  AppState({this.panel = false, VikunjaApi? api}) : api = api ?? VikunjaApi();

  final VikunjaApi api;
  late final SharedPreferences _prefs;

  /// 面板模式下的默认项目和错误提示
  int _panelDefaultProject = 0;
  String? panelError;

  /// 界面层注册：用来弹 SnackBar
  void Function(String message, {VoidCallback? undo})? notify;

  bool ready = false;
  bool loading = false;
  User? user;
  List<Project> projects = [];
  List<Label> labels = [];

  /// 所有未完成任务；个人规模全量放内存，切页面零等待
  List<Task> tasks = [];

  /// 今天完成的任务（按所选时区的"今天"），给"今天已完成"里反悔用
  List<Task> doneToday = [];

  /// 刚勾掉的任务先留在列表里播放划掉动画，再移除
  final Set<int> completing = {};

  /// 刚加进来的任务，列表里播放展开入场动画
  final Set<int> justAdded = {};

  Timer? _poll;

  /// 时区：默认跟随 Vikunja 账号设置（多端、Hermes、服务端提醒都一致），也可以跟随本机系统
  bool followSystemZone = false;

  /// 点"开始做"时自动排几天（含今天）；0 = 不限，只记开始日期
  int planDays = 3;

  bool get loggedIn => api.token.isNotEmpty;
  String get server => api.server;

  Future<void> init() async {
    if (panel) {
      loadPanelConfig();
      ready = true;
      notifyListeners();
      return;
    }
    _prefs = await SharedPreferences.getInstance();
    api.server = _prefs.getString('server') ?? defaultServer;
    api.token = _prefs.getString('token') ?? '';
    api.refreshToken = _prefs.getString('refresh') ?? '';
    api.onUnauthorized = logout;
    api.onTokens = (token, refresh) {
      _prefs.setString('token', token);
      _prefs.setString('refresh', refresh);
    };
    // 先用上次的时区，避免启动时日期闪一下
    followSystemZone = _prefs.getBool('tz_follow_system') ?? false;
    planDays = _prefs.getInt('plan_days') ?? 3;
    setZone(followSystemZone ? null : _prefs.getString('tz_cache'));
    ready = true;
    notifyListeners();
    if (loggedIn) await refresh();
  }

  Future<void> login(String server, String username, String password) async {
    api.server = server.trim().replaceAll(RegExp(r'/+$'), '');
    await api.login(username.trim(), password);
    await _prefs.setString('server', api.server);
    notifyListeners();
    await refresh();
  }

  Future<void> logout() async {
    api.token = '';
    api.refreshToken = '';
    await _prefs.remove('token');
    await _prefs.remove('refresh');
    _poll?.cancel();
    tasks = [];
    projects = [];
    labels = [];
    user = null;
    notifyListeners();
  }

  /// 面板模式：读完整应用写的 ~/.config/vikunja-md/dms.json；每次弹出都重读，换了账号也能跟上
  void loadPanelConfig() {
    final config =
        Platform.environment['XDG_CONFIG_HOME'] ??
        '${Platform.environment['HOME']}/.config';
    try {
      final cfg = jsonDecode(
        File('$config/vikunja-md/dms.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      api.server = cfg['server'] as String;
      api.token = cfg['token'] as String;
      api.refreshToken = '';
      _panelDefaultProject = (cfg['defaultProjectId'] as num?)?.toInt() ?? 0;
      planDays = (cfg['planDays'] as num?)?.toInt() ?? 3;
      setZone(cfg['timezone'] as String?);
      panelError = null;
    } catch (_) {
      api.token = '';
      panelError = '还没连上：先打开一次待办完整应用并登录';
    }
    api.onUnauthorized = () {
      panelError = '面板通行证失效了：打开一次完整应用会自动更新';
      notifyListeners();
    };
  }

  /// 前台时每分钟同步一次，Hermes 或其他端的改动会自动出现
  void setForeground(bool fg) {
    _poll?.cancel();
    if (fg && loggedIn) {
      refresh(silent: true);
      _poll = Timer.periodic(
        const Duration(minutes: 1),
        (_) => refresh(silent: true),
      );
    }
  }

  Future<void> refresh({bool silent = false}) async {
    if (!loggedIn) return;
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    try {
      // 面板的 token 没有读用户信息的权限，时区和默认项目来自 dms.json
      final results = await Future.wait([
        if (!panel) api.getUser(),
        api.listProjects(),
        api.listLabels(),
        api.listTasks('done = false'),
        api.listTasks('done = true && done_at >= now/d', timezone: zoneName),
      ]);
      var i = 0;
      if (!panel) user = results[i++] as User;
      projects = results[i++] as List<Project>;
      labels = results[i++] as List<Label>;
      if (!panel) _applyZone();
      // 任务是和用户信息并行拉的，按刚确定的时区重新解析一遍日期
      doneToday =
          (results[i + 1] as List<Task>)
              .map((t) => Task.fromJson(t.raw))
              .toList()
            ..sort(_byDoneAtDesc);
      final fresh = (results[i] as List<Task>)
          .map((t) => Task.fromJson(t.raw))
          .toList();
      // 正在播放完成动画的任务服务端已不返回，保留到动画结束
      tasks = [
        ...fresh,
        ...tasks.where(
          (t) => completing.contains(t.id) && !fresh.any((f) => f.id == t.id),
        ),
      ];
      if (!panel) {
        _poll ??= Timer.periodic(
          const Duration(minutes: 1),
          (_) => refresh(silent: true),
        );
      }
      panelError = null;
    } on ApiException catch (e) {
      if (!silent) _error(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _error(Object e) => notify?.call(e.toString());

  void _applyZone() {
    final name = followSystemZone ? null : user?.timezone;
    setZone(name);
    if (name != null &&
        name.isNotEmpty &&
        _prefs.getString('tz_cache') != name) {
      _prefs.setString('tz_cache', name);
    }
  }

  /// 设置页显示用
  String get zoneLabel => zoneName ?? '跟随系统（${DateTime.now().timeZoneName}）';

  Future<List<String>> listTimezones() => api.listTimezones();

  /// [name] 为 null 表示跟随系统；否则同步写回 Vikunja 账号
  Future<void> setTimezone(String? name) async {
    try {
      followSystemZone = name == null;
      await _prefs.setBool('tz_follow_system', followSystemZone);
      final u = user;
      if (name != null && u != null && u.timezone != name) {
        await api.setUserTimezone(u, name);
        user = await api.getUser();
      }
      _applyZone();
      // 已加载的任务按新时区重新解析
      tasks = tasks.map((t) => Task.fromJson(t.raw)).toList();
      notifyListeners();
    } on ApiException catch (e) {
      _error(e);
    }
  }

  Project? projectById(int id) => projects.where((p) => p.id == id).firstOrNull;

  Color? taskColor(Task t) {
    for (final l in t.labels) {
      if (l.color != null) return l.color;
    }
    return projectById(t.projectId)?.color;
  }

  int get defaultProjectId {
    final id = panel ? _panelDefaultProject : (user?.defaultProjectId ?? 0);
    if (projectById(id) != null) return id;
    return projects.isNotEmpty ? projects.first.id : 0;
  }

  // ---------- 视图用的派生数据 ----------

  static int compareTasks(Task a, Task b) {
    final ad = a.dueDate, bd = b.dueDate;
    if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
    if (ad != null && bd == null) return -1;
    if (ad == null && bd != null) return 1;
    if (a.priority != b.priority) return b.priority.compareTo(a.priority);
    return a.id.compareTo(b.id);
  }

  List<Task> get overdue {
    final t0 = today();
    return tasks
        .where((t) => t.dueDate != null && dayOf(t.dueDate!).isBefore(t0))
        .toList()
      ..sort(compareTasks);
  }

  List<Task> get dueToday {
    final t0 = today();
    return tasks
        .where((t) => t.dueDate != null && dayOf(t.dueDate!) == t0)
        .toList()
      ..sort(compareTasks);
  }

  /// 已经开始、今天还在进行的任务（截止日不在今天及以前）：
  /// 排期覆盖今天的，开始了但截止在以后的，以及只有开始日期、没有截止的"长期在做"
  /// 排期结束了还没勾掉的也留在这里（标"超出计划"），不会凭空消失
  List<Task> get inProgress {
    final t0 = today();
    return tasks.where((t) {
      if (t.dueDate != null && !dayOf(t.dueDate!).isAfter(t0)) return false;
      return t.startDate != null && !dayOf(t.startDate!).isAfter(t0);
    }).toList()..sort(_compareInProgress);
  }

  /// 有截止/计划结束日的按日子近远排，长期在做（没结束日）的放最后
  static int _compareInProgress(Task a, Task b) {
    if (a.isOngoing != b.isOngoing) return a.isOngoing ? 1 : -1;
    if (a.isOngoing) return a.startDate!.compareTo(b.startDate!);
    final ae = a.dueDate ?? a.endDate!, be = b.dueDate ?? b.endDate!;
    final c = ae.compareTo(be);
    return c != 0 ? c : compareTasks(a, b);
  }

  static int _byDoneAtDesc(Task a, Task b) => (b.raw['done_at'] ?? '')
      .toString()
      .compareTo((a.raw['done_at'] ?? '').toString());

  /// 一个日期都没有的任务（"待办"组），新加的排最前
  List<Task> get unscheduled =>
      tasks.where((t) => t.isUnscheduled).toList()..sort(
        (a, b) => a.priority != b.priority
            ? b.priority.compareTo(a.priority)
            : b.id.compareTo(a.id),
      );

  int get todayCount => overdue.length + dueToday.length;

  List<Task> tasksOfProject(int projectId) =>
      tasks.where((t) => t.projectId == projectId).toList()..sort(compareTasks);

  Future<List<Task>> doneTasksOfProject(int projectId) async {
    final list = await api.listTasks('done = true && project = $projectId');
    return list..sort(
      (a, b) => (b.raw['done_at'] ?? '').toString().compareTo(
        (a.raw['done_at'] ?? '').toString(),
      ),
    );
  }

  // ---------- 修改 ----------

  void _replace(Task t) {
    final i = tasks.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      tasks[i] = t;
    } else if (!t.done) {
      tasks.add(t);
    }
  }

  Future<Task?> quickAdd(String input, {int? projectId}) async {
    final r = parseQuickAdd(input);
    if (r.title.isEmpty) return null;
    try {
      var pid = projectId ?? defaultProjectId;
      // 找不到项目不自动新建，免得手误造出垃圾项目
      String? missingProject;
      if (r.project != null) {
        final name = r.project!.toLowerCase();
        final p = projects
            .where((p) => p.title.toLowerCase() == name)
            .firstOrNull;
        if (p != null) {
          pid = p.id;
        } else {
          missingProject = r.project;
        }
      }
      // 默认不设截止也不设排期，除非输入里写了日期；没日期的任务显示在"待办"组
      var task = await api.createTask(pid, {
        'title': r.title,
        if (r.due != null) 'due_date': formatDate(r.due),
        if (r.priority != null) 'priority': r.priority,
      });
      if (r.labels.isNotEmpty) {
        final ls = <Label>[];
        for (final name in r.labels) {
          final l = await ensureLabel(name);
          await api.addLabel(task.id, l.id);
          ls.add(l);
        }
        task = task.copyWith(labels: ls);
      }
      tasks.add(task);
      justAdded.add(task.id);
      Future.delayed(
        const Duration(seconds: 2),
        () => justAdded.remove(task.id),
      );
      notifyListeners();
      if (missingProject != null) {
        notify?.call(
          '没有项目「$missingProject」，已放进「${projectById(pid)?.title ?? '默认项目'}」',
        );
      }
      return task;
    } on ApiException catch (e) {
      _error(e);
      return null;
    }
  }

  Future<Label> ensureLabel(String title) async {
    final existing = labels
        .where((l) => l.title.toLowerCase() == title.toLowerCase())
        .firstOrNull;
    if (existing != null) return existing;
    final l = await api.createLabel(
      title,
      labelPalette[labels.length % labelPalette.length],
    );
    labels = [...labels, l];
    return l;
  }

  Future<void> toggleDone(Task task) async {
    if (task.done) return _reopen(task);
    completing.add(task.id);
    notifyListeners();
    try {
      final updated = await api.updateTask(task.copyWith(done: true));
      if (!updated.done) {
        // 重复任务：服务端把日期顺延并保持未完成
        completing.remove(task.id);
        _replace(updated);
        notify?.call(
          '已完成，下次：${updated.dueDate != null ? friendlyDate(updated.dueDate!) : '已顺延'}',
        );
        notifyListeners();
        return;
      }
      doneToday = [updated, ...doneToday.where((t) => t.id != task.id)];
      notify?.call('已完成「${task.title}」', undo: () => _reopen(updated));
      await Future.delayed(const Duration(milliseconds: 650));
      // 动画期间点了撤销：_reopen 已经把它移出 completing，不能再删
      if (completing.remove(task.id)) {
        tasks.removeWhere((t) => t.id == task.id);
      }
    } on ApiException catch (e) {
      completing.remove(task.id);
      _error(e);
    }
    notifyListeners();
  }

  Future<void> _reopen(Task task) async {
    try {
      final updated = await api.updateTask(task.copyWith(done: false));
      completing.remove(task.id);
      doneToday = doneToday.where((t) => t.id != task.id).toList();
      _replace(updated);
      notify?.call('已恢复「${task.title}」');
      notifyListeners();
    } on ApiException catch (e) {
      _error(e);
    }
  }

  /// 保存编辑器里的改动；标签走单独接口按差异增删
  Future<bool> saveTask(Task original, Task edited) async {
    try {
      final before = original.labels.map((l) => l.id).toSet();
      final after = edited.labels.map((l) => l.id).toSet();
      for (final id in after.difference(before)) {
        await api.addLabel(original.id, id);
      }
      for (final id in before.difference(after)) {
        await api.removeLabel(original.id, id);
      }
      final saved = await api.updateTask(edited);
      _replace(saved.copyWith(labels: edited.labels));
      if (saved.done) tasks.removeWhere((t) => t.id == saved.id);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error(e);
      return false;
    }
  }

  /// 甘特图拖动：先本地更新保证跟手，失败再回滚
  /// 开始做（开始日期记为今天）或暂停（清掉开始日期，回到"没安排"）
  /// 开始做：开始日期记为今天，按 [planDays] 自动排到第 N 天；暂停：清掉排期，回到待办
  Future<void> setStarted(Task task, bool started) {
    final t0 = today();
    final end = started && planDays > 0
        ? endOfDay(addDays(t0, planDays - 1))
        : null;
    return _save(
      task.copyWith(startDate: started ? t0 : null, endDate: end),
      task,
      started
          ? '开始做「${task.title}」${planDays > 0 ? '，计划 $planDays 天' : ''}'
          : '已暂停「${task.title}」，放回待办',
    );
  }

  Future<void> setPlanDays(int days) async {
    planDays = days;
    await _prefs.setInt('plan_days', days);
    notifyListeners();
  }

  /// 甘特图里拖动长期任务的开始端
  Future<void> updateStart(Task task, DateTime start) =>
      _save(task.copyWith(startDate: dayOf(start)), task, null);

  Future<void> _save(Task edited, Task original, String? message) async {
    _replace(edited);
    notifyListeners();
    try {
      _replace(await api.updateTask(edited));
      if (message != null) notify?.call(message);
    } on ApiException catch (e) {
      _replace(original);
      _error(e);
    }
    notifyListeners();
  }

  Future<void> updateRange(Task task, DateTime start, DateTime end) async {
    final edited = task.copyWith(
      startDate: dayOf(start),
      endDate: endOfDay(end),
    );
    _replace(edited);
    notifyListeners();
    try {
      _replace(await api.updateTask(edited));
    } on ApiException catch (e) {
      _replace(task);
      _error(e);
    }
    notifyListeners();
  }

  Future<void> deleteTask(Task task) async {
    tasks.removeWhere((t) => t.id == task.id);
    notifyListeners();
    try {
      await api.deleteTask(task.id);
      notify?.call('已删除「${task.title}」');
    } on ApiException catch (e) {
      tasks.add(task);
      _error(e);
      notifyListeners();
    }
  }

  Future<Project?> createProject(String title, [String? hex]) async {
    try {
      final p = await api.createProject(
        title,
        hex ?? labelPalette[projects.length % labelPalette.length],
      );
      projects = [...projects, p];
      notifyListeners();
      return p;
    } on ApiException catch (e) {
      _error(e);
      return null;
    }
  }

  Future<void> updateProject(
    Project p, {
    String? title,
    String? hexColor,
  }) async {
    try {
      final updated = await api.updateProject(
        p,
        title: title,
        hexColor: hexColor,
      );
      projects = [for (final x in projects) x.id == p.id ? updated : x];
      notifyListeners();
    } on ApiException catch (e) {
      _error(e);
    }
  }

  Future<void> deleteProject(Project p) async {
    try {
      await api.deleteProject(p.id);
      projects = projects.where((x) => x.id != p.id).toList();
      tasks.removeWhere((t) => t.projectId == p.id);
      notifyListeners();
    } on ApiException catch (e) {
      _error(e);
    }
  }
}
