import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_md/utils/quick_add.dart';

void main() {
  // 2026-10-23 是周五
  final now = DateTime(2026, 10, 23, 10);

  test('明天下午3点 + 优先级 + 项目 + 标签', () {
    final r = parseQuickAdd('明天下午3点 改报价 !3 +商城 *客户', now: now);
    expect(r.title, '改报价');
    expect(r.due, DateTime(2026, 10, 24, 15));
    expect(r.priority, 3);
    expect(r.project, '商城');
    expect(r.labels, ['客户']);
  });

  test('无空格的中文日期', () {
    final r = parseQuickAdd('后天交周报', now: now);
    expect(r.title, '交周报');
    expect(r.due, DateTime(2026, 10, 25, 23, 59));
  });

  test('周几与下周几', () {
    expect(parseQuickAdd('周五 复盘', now: now).due!.day, 23);
    expect(parseQuickAdd('周一 开会', now: now).due!.day, 26);
    expect(parseQuickAdd('下周三 续服务器', now: now).due!.day, 28);
  });

  test('具体日期与时间', () {
    expect(
      parseQuickAdd('11月2日 9:30 面试', now: now).due,
      DateTime(2026, 11, 2, 9, 30),
    );
    expect(parseQuickAdd('1/5 年检', now: now).due, DateTime(2027, 1, 5, 23, 59));
    expect(parseQuickAdd('今晚 打电话', now: now).due, DateTime(2026, 10, 23, 20));
  });

  test('没有日期时数字不被当成时间', () {
    final r = parseQuickAdd('买 3 箱水', now: now);
    expect(r.title, '买 3 箱水');
    expect(r.due, isNull);
  });
}
