import 'zone.dart';

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// 按日历加天数。不能用 add(Duration(days:))：夏令时切换那天不是 24 小时，会落到同一天或跳过一天
DateTime addDays(DateTime d, int n) =>
    DateTime(d.year, d.month, d.day + n, d.hour, d.minute, d.second);

DateTime today() => dayOf(nowWall());

DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59);

/// 按日历日算差值；用 UTC 构造避开夏令时
int daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

bool hasTime(DateTime d) =>
    !(d.hour == 23 && d.minute == 59) && !(d.hour == 0 && d.minute == 0);

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

String weekdayName(DateTime d) => '周${_weekdays[d.weekday - 1]}';

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 今天 / 明天 / 周五 / 10月25日 [+ 时间]
String friendlyDate(DateTime d, {bool withTime = true}) {
  final diff = daysBetween(today(), d);
  final String day;
  if (diff == 0) {
    day = '今天';
  } else if (diff == 1) {
    day = '明天';
  } else if (diff == 2) {
    day = '后天';
  } else if (diff == -1) {
    day = '昨天';
  } else if (diff > 2 && diff < 7) {
    day = weekdayName(d);
  } else if (d.year == nowWall().year) {
    day = '${d.month}月${d.day}日';
  } else {
    day = '${d.year}年${d.month}月${d.day}日';
  }
  return withTime && hasTime(d) ? '$day ${_hm(d)}' : day;
}

String shortDate(DateTime d) => '${d.month}/${d.day}';
