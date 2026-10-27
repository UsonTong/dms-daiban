import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vikunja_md/api/models.dart';
import 'package:vikunja_md/state/app_state.dart';
import 'package:vikunja_md/ui/gantt/gantt_page.dart';
import 'package:vikunja_md/ui/task_editor.dart';
import 'package:vikunja_md/utils/dates.dart';

/// 不连服务器，只记录甘特图提交的日期
class _FakeState extends AppState {
  final saved = <(int, DateTime, DateTime)>[];

  @override
  Future<void> updateRange(Task task, DateTime start, DateTime end) async {
    saved.add((task.id, start, end));
  }

  final starts = <(int, DateTime)>[];

  @override
  Future<void> updateStart(Task task, DateTime start) async {
    starts.add((task.id, start));
  }
}

Task _task(int id, DateTime start, DateTime end) => Task.fromJson({
  'id': id,
  'title': '任务$id',
  'project_id': 1,
  'start_date': formatDate(start),
  'end_date': formatDate(end),
});

const _dayW = 36.0; // 默认"日"视图
const _rowH = 44.0;

Future<(_FakeState, Offset)> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final t0 = today();
  final state = _FakeState()
    ..tasks = [_task(1, t0, t0.add(const Duration(days: 3)))];
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: GanttPage()),
    ),
  );
  await tester.pumpAndSettle();

  // 画布的屏幕矩形已包含横向滚动；起始日按页面规则推算：今天-14 天所在周的前一周周一
  final canvas = tester.getRect(
    find.byWidgetPredicate((w) => w is CustomPaint && w.key is GlobalKey),
  );
  final first = t0.subtract(const Duration(days: 14));
  final rangeStart = first.subtract(Duration(days: first.weekday - 1 + 7));
  final barLeft = canvas.left + daysBetween(rangeStart, t0) * _dayW;
  final rowY = canvas.top + 22;
  return (state, Offset(barLeft, rowY));
}

/// 分 10 步拖动，模拟真实的指针移动
Future<void> _drag(
  WidgetTester tester,
  Offset from,
  Offset by,
  PointerDeviceKind kind,
) async {
  final g = await tester.startGesture(from, kind: kind);
  for (var i = 0; i < 10; i++) {
    await g.moveBy(by / 10);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
}

void main() {
  testWidgets('鼠标拖动横条整体平移两天', (tester) async {
    final (state, barLeft) = await _pump(tester);
    await _drag(
      tester,
      barLeft + const Offset(2 * _dayW, 0),
      const Offset(2 * _dayW, 0),
      PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    final t0 = today();
    expect(state.saved, hasLength(1));
    expect(state.saved.single.$2, t0.add(const Duration(days: 2)));
    expect(state.saved.single.$3, t0.add(const Duration(days: 5)));
  });

  testWidgets('触屏拖右边缘延长一天', (tester) async {
    final (state, barLeft) = await _pump(tester);
    await _drag(
      tester,
      barLeft + const Offset(4 * _dayW - 4, 0),
      const Offset(_dayW, 0),
      PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();

    final t0 = today();
    expect(state.saved, hasLength(1));
    expect(state.saved.single.$2, t0);
    expect(state.saved.single.$3, t0.add(const Duration(days: 4)));
  });

  testWidgets('鼠标拖空白处平移时间轴，不改任务', (tester) async {
    final (state, barLeft) = await _pump(tester);
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(GanttPage),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    final before = scroll.position.pixels;
    // 横条下面一行是空白
    await _drag(
      tester,
      barLeft + const Offset(0, _rowH * 2),
      const Offset(-200, 0),
      PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    // 第一步位移用于识别拖动，不计入滚动
    expect(scroll.position.pixels - before, inInclusiveRange(170, 200));
    expect(state.saved, isEmpty);
  });

  testWidgets('鼠标单击横条打开编辑器，不改日期', (tester) async {
    final (state, barLeft) = await _pump(tester);
    await tester.tapAt(
      barLeft + const Offset(2 * _dayW, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditor), findsOneWidget);
    expect(state.saved, isEmpty);
  });

  testWidgets('长期任务拖中间只改开始日期，不变成排期', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t0 = today();
    final state = _FakeState()
      ..tasks = [
        Task.fromJson({
          'id': 9,
          'title': '长期',
          'project_id': 1,
          'start_date': formatDate(addDays(t0, -3)),
        }),
      ];
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: GanttPage()),
      ),
    );
    await tester.pumpAndSettle();
    final canvas = tester.getRect(
      find.byWidgetPredicate((w) => w is CustomPaint && w.key is GlobalKey),
    );
    final first = addDays(t0, -14);
    final rangeStart = addDays(first, -(first.weekday - 1 + 7));
    final barLeft =
        canvas.left + daysBetween(rangeStart, addDays(t0, -3)) * _dayW;
    await _drag(
      tester,
      Offset(barLeft + 2 * _dayW, canvas.top + 22),
      const Offset(-_dayW, 0),
      PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(state.saved, isEmpty);
    expect(state.starts.single.$2, addDays(t0, -4));
  });
}
