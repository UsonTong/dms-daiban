import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_md/ui/motion.dart';

class _Counter extends StatefulWidget {
  final String name;
  const _Counter(this.name);
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => n++),
      child: Text('${widget.name}:$n'),
    ),
  );
}

Widget _app(int index) => MaterialApp(
  home: FadeThroughStack(
    index: index,
    children: const [_Counter('A'), _Counter('B')],
  ),
);

double _opacityOf(WidgetTester tester, String text) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.textContaining(text),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

void main() {
  testWidgets('切换后保留各页状态', (tester) async {
    await tester.pumpWidget(_app(0));
    await tester.tap(find.text('A:0'));
    await tester.pump();
    await tester.pumpWidget(_app(1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(0));
    await tester.pumpAndSettle();
    expect(find.text('A:1'), findsOneWidget);
  });

  testWidgets('过渡中途新页半透明，旧页不可点', (tester) async {
    await tester.pumpWidget(_app(0));
    await tester.pumpWidget(_app(1));
    await tester.pump(const Duration(milliseconds: 150));
    final b = _opacityOf(tester, 'B:');
    expect(b, greaterThan(0));
    expect(b, lessThan(1));
    expect(_opacityOf(tester, 'A:'), 0); // 前 30% 已淡出完
    await tester.tap(find.text('A:0'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('A:0', skipOffstage: false), findsOneWidget);
    expect(_opacityOf(tester, 'B:'), 1);
  });
}
