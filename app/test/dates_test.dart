import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_md/utils/dates.dart';

void main() {
  // 美国 2026-11-01 结束夏令时、2026-03-08 开始；在 America/Los_Angeles 下跑最能暴露问题
  test('跨夏令时加天数不重复也不跳过', () {
    final days = [
      for (var i = 0; i < 5; i++) addDays(DateTime(2026, 10, 30), i).day,
    ];
    expect(days, [30, 31, 1, 2, 3]);
    final spring = [
      for (var i = 0; i < 4; i++) addDays(DateTime(2026, 3, 7), i).day,
    ];
    expect(spring, [7, 8, 9, 10]);
  });

  test('daysBetween 跨夏令时', () {
    expect(daysBetween(DateTime(2026, 10, 31), DateTime(2026, 11, 2)), 2);
    expect(daysBetween(DateTime(2026, 11, 2), DateTime(2026, 10, 31)), -2);
  });

  test('addDays 保留时分', () {
    expect(
      addDays(DateTime(2026, 10, 31, 23, 59), 1),
      DateTime(2026, 11, 1, 23, 59),
    );
  });
}
