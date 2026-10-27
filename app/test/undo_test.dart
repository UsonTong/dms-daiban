import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_md/api/models.dart';
import 'package:vikunja_md/api/vikunja_api.dart';
import 'package:vikunja_md/state/app_state.dart';
import 'package:vikunja_md/utils/dates.dart';

/// 不连服务器：更新任务原样返回
class _FakeApi extends VikunjaApi {
  @override
  Future<Task> updateTask(Task t) async => Task.fromJson({
    ...t.raw,
    'done_at': t.done ? DateTime.now().toUtc().toIso8601String() : null,
  });
}

Task _task(int id) =>
    Task.fromJson({'id': id, 'title': '任务$id', 'project_id': 1});

void main() {
  late AppState s;
  VoidCallback? lastUndo;
  final messages = <String>[];

  setUp(() {
    s = AppState(api: _FakeApi())..tasks = [_task(1), _task(2)];
    lastUndo = null;
    messages.clear();
    s.notify = (msg, {undo}) {
      messages.add(msg);
      if (undo != null) lastUndo = undo;
    };
  });

  test('勾掉后进"今天已完成"，动画结束从列表移除', () async {
    await s.toggleDone(s.tasks.first);
    expect(s.tasks.map((t) => t.id), [2]);
    expect(s.doneToday.map((t) => t.id), [1]);
  });

  test('勾掉动画期间点撤销，任务留在列表里', () async {
    final pending = s.toggleDone(s.tasks.first);
    await Future.delayed(const Duration(milliseconds: 100));
    lastUndo!();
    await pending;
    await Future.delayed(const Duration(milliseconds: 50));
    expect(s.tasks.map((t) => t.id), containsAll([1, 2]));
    expect(s.tasks.firstWhere((t) => t.id == 1).done, isFalse);
    expect(s.doneToday, isEmpty);
  });

  test('过后从"今天已完成"里点勾恢复', () async {
    await s.toggleDone(s.tasks.first);
    await s.toggleDone(s.doneToday.first);
    expect(s.tasks.map((t) => t.id), containsAll([1, 2]));
    expect(s.doneToday, isEmpty);
    expect(messages.last, '已恢复「任务1」');
  });

  test('待办点开始做进"正在做"，暂停退回"待办"', () async {
    final t = s.tasks.first;
    expect(s.unscheduled.map((x) => x.id), contains(t.id));
    await s.setStarted(t, true);
    expect(s.inProgress.map((x) => x.id), [t.id]);
    // 默认计划 3 天：今天开始，后天结束
    final started = s.inProgress.single;
    expect(dayOf(started.startDate!), today());
    expect(dayOf(started.endDate!), addDays(today(), 2));
    expect(s.unscheduled.map((x) => x.id), isNot(contains(t.id)));
    await s.setStarted(s.inProgress.first, false);
    expect(s.inProgress, isEmpty);
    expect(s.unscheduled.map((x) => x.id), contains(t.id));
    expect(s.unscheduled.firstWhere((x) => x.id == t.id).endDate, isNull);
    expect(messages.last, '已暂停「任务1」，放回待办');
  });

  test('计划天数设为不限：只记开始日期', () async {
    s.planDays = 0;
    await s.setStarted(s.tasks.first, true);
    expect(s.inProgress.single.isOngoing, isTrue);
  });
}
