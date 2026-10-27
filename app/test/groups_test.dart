import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_md/api/models.dart';
import 'package:vikunja_md/state/app_state.dart';
import 'package:vikunja_md/utils/dates.dart';

Task _t(int id, {DateTime? start, DateTime? end, DateTime? due}) =>
    Task.fromJson({
      'id': id,
      'title': '任务$id',
      'project_id': 1,
      'start_date': formatDate(start),
      'end_date': formatDate(end),
      'due_date': formatDate(due),
    });

void main() {
  final t0 = today();
  DateTime d(int n) => addDays(t0, n);

  final state = AppState()
    ..tasks = [
      _t(1, start: d(-30)), // 长期在做，一个月前开始
      _t(2), // 没安排
      _t(3, start: d(2)), // 后天才开始
      _t(4, start: d(-2), end: d(3)), // 排期覆盖今天
      _t(5, start: d(-5), end: d(-1)), // 计划已过还没做完
      _t(6, start: d(-3), due: endOfDay(d(4))), // 开始了，截止在以后
      _t(7, due: endOfDay(t0)), // 今天截止
      _t(8, start: d(-3), due: endOfDay(d(-1))), // 已逾期
    ];

  test('正在做：按计划结束/截止日近远排，超出计划的不消失，长期在做的在最后', () {
    expect(state.inProgress.map((t) => t.id), [5, 4, 6, 1]);
  });

  test('长期在做的永远不算逾期', () {
    expect(state.overdue.map((t) => t.id), [8]);
    expect(state.dueToday.map((t) => t.id), [7]);
  });

  test('没安排的只有一个日期都没有的', () {
    expect(state.unscheduled.map((t) => t.id), [2]);
  });
}
