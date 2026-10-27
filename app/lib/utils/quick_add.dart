import 'dates.dart';
import 'zone.dart';

class QuickAddResult {
  final String title;
  final DateTime? due;
  final int? priority;
  final String? project;
  final List<String> labels;

  const QuickAddResult({
    required this.title,
    this.due,
    this.priority,
    this.project,
    this.labels = const [],
  });

  bool get hasExtras =>
      due != null || priority != null || project != null || labels.isNotEmpty;
}

const _wd = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7};

final _dateRe = RegExp(
  r'(大后天|后天|明天|今天|今晚|下周[一二三四五六日天]|(?:周|星期)[一二三四五六日天]|(\d{1,2})月(\d{1,2})[日号]?|(?<![\d])(\d{1,2})[/\-](\d{1,2})(?![\d]))',
);
final _timeRe = RegExp(
  r'(上午|早上|中午|下午|晚上)?\s*(\d{1,2})(?:[:：](\d{2})|点(半|(\d{1,2})分?)?)',
);
final _priorityRe = RegExp(r'[!！]([1-5])');
final _projectRe = RegExp(r'(?:^|\s)\+(\S+)');
final _labelRe = RegExp(r'(?:^|\s)[*#](\S+)');

/// 解析 "明天下午3点 改报价 !3 +商城 *客户"
QuickAddResult parseQuickAdd(String input, {DateTime? now}) {
  var text = input;
  final base = now ?? nowWall();
  final t0 = dayOf(base);

  int? priority;
  text = text.replaceFirstMapped(_priorityRe, (m) {
    priority = int.parse(m[1]!);
    return ' ';
  });

  String? project;
  text = text.replaceFirstMapped(_projectRe, (m) {
    project = m[1];
    return ' ';
  });

  final labels = <String>[];
  text = text.replaceAllMapped(_labelRe, (m) {
    labels.add(m[1]!);
    return ' ';
  });

  DateTime? day;
  var evening = false;
  text = text.replaceFirstMapped(_dateRe, (m) {
    final s = m[0]!;
    if (s == '今天') {
      day = t0;
    } else if (s == '今晚') {
      day = t0;
      evening = true;
    } else if (s == '明天') {
      day = addDays(t0, 1);
    } else if (s == '后天') {
      day = addDays(t0, 2);
    } else if (s == '大后天') {
      day = addDays(t0, 3);
    } else if (s.startsWith('下周')) {
      final target = _wd[s.substring(2)]!;
      final nextMonday = addDays(t0, 8 - t0.weekday);
      day = addDays(nextMonday, target - 1);
    } else if (s.startsWith('周') || s.startsWith('星期')) {
      final target = _wd[s.substring(s.length - 1)]!;
      day = addDays(t0, (target - t0.weekday + 7) % 7);
    } else {
      final month = int.parse(m[2] ?? m[4]!);
      final d = int.parse(m[3] ?? m[5]!);
      var candidate = DateTime(t0.year, month, d);
      if (candidate.isBefore(t0)) candidate = DateTime(t0.year + 1, month, d);
      day = candidate;
    }
    return ' ';
  });

  int? hour;
  var minute = 0;
  if (day != null) {
    text = text.replaceFirstMapped(_timeRe, (m) {
      var h = int.parse(m[2]!);
      final period = m[1];
      if ((period == '下午' || period == '晚上' || evening) && h < 12) h += 12;
      if (period == '中午' && h < 6) h += 12;
      if (h > 23) return m[0]!;
      hour = h;
      if (m[3] != null) {
        minute = int.parse(m[3]!);
      } else if (m[4] == '半') {
        minute = 30;
      } else if (m[5] != null) {
        minute = int.parse(m[5]!);
      }
      return ' ';
    });
  }

  DateTime? due;
  if (day != null) {
    final d = day!;
    due = hour != null
        ? DateTime(d.year, d.month, d.day, hour!, minute)
        : evening
        ? DateTime(d.year, d.month, d.day, 20)
        : endOfDay(d);
  }

  return QuickAddResult(
    title: text.replaceAll(RegExp(r'\s+'), ' ').trim(),
    due: due,
    priority: priority,
    project: project,
    labels: labels,
  );
}
