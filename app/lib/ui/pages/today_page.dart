import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/dates.dart';
import '../../utils/zone.dart';
import '../widgets/task_sections.dart';
import '../widgets/folded_tasks.dart';
import 'page_frame.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final now = nowWall();
    // App 时区和本机不同时标出来，免得看错
    final sys = DateTime.now();
    final zoneHint =
        zoneName != null && (sys.hour != now.hour || sys.minute != now.minute)
        ? ' · $zoneName'
        : '';
    final sections = todaySections(context, s);
    final empty = sections.every((x) => x.tasks.isEmpty);
    return PageFrame(
      title: '今天',
      subtitle: '${now.month}月${now.day}日 ${weekdayName(now)}$zoneHint',
      slivers: [
        if (s.loading && s.tasks.isEmpty)
          const SliverToBoxAdapter(child: LinearProgressIndicator())
        else if (empty) ...[
          // 铺满剩余空间的空状态要放最后
          const MaxWidthSliver(sliver: DoneTodaySliver()),
          const EmptyState(icon: Icons.wb_sunny_outlined, text: '今天没有待办，轻松一下'),
        ] else ...[
          MaxWidthSliver(sliver: TaskSectionsSliver(sections: sections)),
          const SliverPadding(padding: EdgeInsets.only(top: 8)),
          const MaxWidthSliver(sliver: DoneTodaySliver()),
        ],
      ],
    );
  }
}
