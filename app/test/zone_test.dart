import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_md/api/models.dart';
import 'package:vikunja_md/utils/zone.dart';

void main() {
  tearDown(() => setZone(null));

  test('选北京时间：服务器时刻显示成北京墙上时间，并能原样写回', () {
    setZone('Asia/Shanghai');
    final d = parseDate('2026-10-23T23:59:00+08:00')!;
    expect(d, DateTime(2026, 10, 23, 23, 59));
    expect(formatDate(d), '2026-10-23T15:59:00.000Z');
  });

  test('同一时刻换到洛杉矶时区', () {
    setZone('America/Los_Angeles');
    expect(
      parseDate('2026-10-23T23:59:00+08:00'),
      DateTime(2026, 10, 23, 8, 59),
    );
    // 冬令时
    expect(parseDate('2026-12-01T12:00:00Z'), DateTime(2026, 12, 1, 4));
  });

  test('无效时区名退回跟随系统', () {
    expect(setZone('Mars/Base'), isFalse);
    expect(zoneName, isNull);
  });

  test('UTC 偏移标签', () {
    expect(utcOffsetLabel('Asia/Shanghai'), 'UTC+08:00');
    expect(utcOffsetLabel('Asia/Kolkata'), 'UTC+05:30');
  });
}
