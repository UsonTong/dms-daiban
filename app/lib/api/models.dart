import 'package:flutter/material.dart';

import '../utils/zone.dart';

/// Vikunja 用 0001-01-01 表示"没有日期"
DateTime? parseDate(dynamic v) {
  if (v is! String || v.isEmpty || v.startsWith('0001-')) return null;
  final d = DateTime.tryParse(v);
  return d == null ? null : toWall(d);
}

String? formatDate(DateTime? d) =>
    d == null ? null : toUtcInstant(d).toIso8601String();

Color? parseHex(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceAll('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

String toHex(Color c) =>
    (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');

class Label {
  final int id;
  final String title;
  final String hexColor;

  const Label({required this.id, required this.title, this.hexColor = ''});

  Color? get color => parseHex(hexColor);

  factory Label.fromJson(Map<String, dynamic> j) => Label(
    id: j['id'] as int,
    title: (j['title'] ?? '') as String,
    hexColor: (j['hex_color'] ?? '') as String,
  );
}

class Project {
  final int id;
  final String title;
  final String hexColor;
  final int position;
  final Map<String, dynamic> raw;

  Project({
    required this.id,
    required this.title,
    required this.hexColor,
    required this.position,
    required this.raw,
  });

  Color? get color => parseHex(hexColor);

  factory Project.fromJson(Map<String, dynamic> j) => Project(
    id: j['id'] as int,
    title: (j['title'] ?? '') as String,
    hexColor: (j['hex_color'] ?? '') as String,
    position: ((j['position'] ?? 0) as num).toInt(),
    raw: j,
  );

  bool get isArchived => raw['is_archived'] == true;

  Map<String, dynamic> toJson({String? title, String? hexColor}) => {
    ...raw,
    'title': title ?? this.title,
    'hex_color': hexColor ?? this.hexColor,
  };
}

class Task {
  final int id;
  final String title;
  final String description;
  final int projectId;
  final bool done;
  final DateTime? dueDate;
  final DateTime? startDate;
  final DateTime? endDate;
  final int priority;
  final List<Label> labels;
  final int repeatAfter;

  /// 服务端返回的完整对象；更新时必须整包提交，否则没传的字段会被清空
  final Map<String, dynamic> raw;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.projectId,
    required this.done,
    required this.dueDate,
    required this.startDate,
    required this.endDate,
    required this.priority,
    required this.labels,
    required this.repeatAfter,
    required this.raw,
  });

  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: j['id'] as int,
    title: (j['title'] ?? '') as String,
    description: (j['description'] ?? '') as String,
    projectId: j['project_id'] as int,
    done: j['done'] == true,
    dueDate: parseDate(j['due_date']),
    startDate: parseDate(j['start_date']),
    endDate: parseDate(j['end_date']),
    priority: ((j['priority'] ?? 0) as num).toInt(),
    labels: ((j['labels'] as List?) ?? const [])
        .map((e) => Label.fromJson(e as Map<String, dynamic>))
        .toList(),
    repeatAfter: ((j['repeat_after'] ?? 0) as num).toInt(),
    raw: j,
  );

  bool get hasRange => startDate != null && endDate != null;

  /// 正在做、没有截止：只有开始日期
  bool get isOngoing => startDate != null && endDate == null && dueDate == null;

  /// 还没安排：一个日期都没有
  bool get isUnscheduled =>
      startDate == null && endDate == null && dueDate == null;

  /// 用 sentinel 区分"不改"和"改成 null"
  static const _keep = Object();

  Task copyWith({
    String? title,
    String? description,
    int? projectId,
    bool? done,
    Object? dueDate = _keep,
    Object? startDate = _keep,
    Object? endDate = _keep,
    int? priority,
    List<Label>? labels,
  }) {
    final j = Map<String, dynamic>.from(raw);
    if (title != null) j['title'] = title;
    if (description != null) j['description'] = description;
    if (projectId != null) j['project_id'] = projectId;
    if (done != null) j['done'] = done;
    if (dueDate != _keep) j['due_date'] = formatDate(dueDate as DateTime?);
    if (startDate != _keep) {
      j['start_date'] = formatDate(startDate as DateTime?);
    }
    if (endDate != _keep) j['end_date'] = formatDate(endDate as DateTime?);
    if (priority != null) j['priority'] = priority;
    if (labels != null) {
      j['labels'] = labels
          .map((l) => {'id': l.id, 'title': l.title, 'hex_color': l.hexColor})
          .toList();
    }
    return Task.fromJson(j);
  }
}

class User {
  final int id;
  final String username;
  final int defaultProjectId;

  /// 账号设置里的时区，如 Asia/Shanghai；为空表示没设
  final String timezone;

  /// 完整的设置对象；改设置时必须整包提交
  final Map<String, dynamic> settings;

  User({
    required this.id,
    required this.username,
    required this.defaultProjectId,
    required this.timezone,
    required this.settings,
  });

  factory User.fromJson(Map<String, dynamic> j) {
    final settings = Map<String, dynamic>.from((j['settings'] as Map?) ?? {});
    return User(
      id: j['id'] as int,
      username: (j['username'] ?? '') as String,
      defaultProjectId: (settings['default_project_id'] ?? 0) as int,
      timezone: (settings['timezone'] ?? '') as String,
      settings: settings,
    );
  }
}
