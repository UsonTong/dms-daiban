import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// App 内的日期一律是"所选时区的墙上时间"（用不带时区的 DateTime 承载），
/// 只在和服务器交换数据时换算成真实时刻。为空表示跟随系统时区。
tz.Location? _zone;
bool _loaded = false;

void _ensureLoaded() {
  if (_loaded) return;
  tzdata.initializeTimeZones();
  _loaded = true;
}

/// 当前生效的时区名；null 表示跟随系统
String? get zoneName => _zone?.name;

/// 切换时区；名字无效时退回跟随系统，返回是否真的变了
bool setZone(String? name) {
  _ensureLoaded();
  final next = (name == null || name.isEmpty)
      ? null
      : tz.timeZoneDatabase.locations[name];
  final changed = next?.name != _zone?.name;
  _zone = next;
  return changed;
}

/// 真实时刻 → 所选时区的墙上时间
DateTime toWall(DateTime instant) {
  final z = _zone;
  if (z == null) return instant.toLocal();
  final t = tz.TZDateTime.from(instant, z);
  return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
}

/// 所选时区的墙上时间 → UTC 时刻
DateTime toUtcInstant(DateTime wall) {
  final z = _zone;
  if (z == null) return wall.toUtc();
  final t = tz.TZDateTime(
    z,
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  );
  return DateTime.fromMillisecondsSinceEpoch(
    t.millisecondsSinceEpoch,
    isUtc: true,
  );
}

DateTime nowWall() => toWall(DateTime.now());

/// 某时区此刻的 UTC 偏移，如 "UTC+08:00"
String utcOffsetLabel(String name) {
  _ensureLoaded();
  final loc = tz.timeZoneDatabase.locations[name];
  if (loc == null) return '';
  final offset = tz.TZDateTime.now(loc).timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final m = offset.inMinutes.abs();
  return 'UTC$sign${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// 所选时区此刻相对 UTC 的偏移（分钟），给不认识时区库的外部组件（DMS 面板）用
int zoneOffsetMinutes() {
  final now = DateTime.now().toUtc();
  final w = toWall(now);
  return DateTime.utc(w.year, w.month, w.day, w.hour, w.minute)
      .difference(
        DateTime.utc(now.year, now.month, now.day, now.hour, now.minute),
      )
      .inMinutes;
}
