import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/zone.dart';

void openSettings(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const SettingsPage()),
);

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final zoneSub = s.followSystemZone
        ? s.zoneLabel
        : '${s.zoneLabel}  ${utcOffsetLabel(s.zoneLabel)} · 与 Vikunja 账号同步';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('设置')),
          SliverList.list(
            children: [
              _header(context, '时间'),
              ListTile(
                leading: const Icon(Icons.public_rounded),
                title: const Text('时区'),
                subtitle: Text(zoneSub),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final picked = await Navigator.push<_ZoneChoice>(
                    context,
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => const _ZonePicker(),
                    ),
                  );
                  if (picked != null) await s.setTimezone(picked.name);
                },
              ),
              _header(context, '任务'),
              ListTile(
                leading: const Icon(Icons.play_circle_outline_rounded),
                title: const Text('点"开始做"时自动排期'),
                subtitle: Text(
                  s.planDays == 0
                      ? '不限：只记开始日期，一直在"正在做"'
                      : '从今天起排 ${s.planDays} 天，到期没做完标"超出计划"',
                ),
                trailing: DropdownButton<int>(
                  value: s.planDays,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(12),
                  onChanged: (v) => v == null ? null : s.setPlanDays(v),
                  items: [
                    for (final d in const [0, 1, 3, 5, 7, 14])
                      DropdownMenuItem(
                        value: d,
                        child: Text(d == 0 ? '不限' : '$d 天'),
                      ),
                  ],
                ),
              ),
              _header(context, '账号'),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(s.user?.username ?? ''),
                subtitle: Text(s.server),
              ),
              ListTile(
                leading: Icon(Icons.logout_rounded, color: scheme.error),
                title: Text('退出登录', style: TextStyle(color: scheme.error)),
                onTap: () {
                  Navigator.popUntil(context, (r) => r.isFirst);
                  s.logout();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall!
          .copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// name 为 null 表示跟随系统
class _ZoneChoice {
  final String? name;
  const _ZoneChoice(this.name);
}

const _common = [
  ('Asia/Shanghai', '北京 / 上海'),
  ('Asia/Hong_Kong', '香港'),
  ('Asia/Taipei', '台北'),
  ('Asia/Tokyo', '东京'),
  ('Asia/Singapore', '新加坡'),
  ('Europe/London', '伦敦'),
  ('Europe/Berlin', '柏林'),
  ('America/New_York', '纽约'),
  ('America/Los_Angeles', '洛杉矶'),
  ('UTC', '协调世界时'),
];

class _ZonePicker extends StatefulWidget {
  const _ZonePicker();

  @override
  State<_ZonePicker> createState() => _ZonePickerState();
}

class _ZonePickerState extends State<_ZonePicker> {
  List<String>? _all;
  String _q = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().listTimezones().then(
      (v) => mounted ? setState(() => _all = v) : null,
      onError: (e) => mounted ? setState(() => _error = '$e') : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final current = s.followSystemZone ? null : zoneName;
    final q = _q.trim().toLowerCase();
    final cn = {for (final (n, l) in _common) n: l};
    bool match(String n) =>
        q.isEmpty ||
        n.toLowerCase().contains(q) ||
        (cn[n]?.contains(q) ?? false);

    Widget tile(String? name, String title, {String? subtitle}) {
      final selected = name == current;
      return ListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: selected
            ? Icon(
                Icons.check_rounded,
                color: Theme.of(context).colorScheme.primary,
              )
            : null,
        selected: selected,
        onTap: () => Navigator.pop(context, _ZoneChoice(name)),
      );
    }

    final common = _common.where((e) => match(e.$1)).toList();
    final rest = (_all ?? const <String>[])
        .where((n) => !cn.containsKey(n) && match(n))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索时区，如 Shanghai、东京',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      // 时区有近 600 个，按需构建保证滚动流畅
      body: Builder(
        builder: (context) {
          final rows = <Widget Function()>[
            if (q.isEmpty)
              () => tile(
                null,
                '跟随系统',
                subtitle: '本机当前：${DateTime.now().timeZoneName}',
              ),
            if (common.isNotEmpty) () => _label(context, '常用'),
            for (final (n, l) in common)
              () => tile(n, l, subtitle: '$n  ${utcOffsetLabel(n)}'),
            if (_error != null)
              () => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            if (_all == null && _error == null)
              () => const LinearProgressIndicator(),
            if (rest.isNotEmpty) () => _label(context, '全部'),
            for (final n in rest) () => tile(n, n, subtitle: utcOffsetLabel(n)),
          ];
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) => rows[i](),
          );
        },
      ),
    );
  }

  Widget _label(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      t,
      style: Theme.of(context).textTheme.titleSmall!
          .copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
