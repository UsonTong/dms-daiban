import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../state/app_state.dart';
import 'task_tile.dart';

class TaskSection {
  final String title;
  final List<Task> tasks;
  final Color? color;
  final Color? dot;

  /// 每行末尾的操作按钮（可选）
  final Widget? Function(Task task)? trailing;

  const TaskSection(
    this.title,
    this.tasks, {
    this.color,
    this.dot,
    this.trailing,
  });
}

/// "今天"页和 Mod+D 面板共用的分组：已逾期 → 今天 → 正在做 → 待办。
/// 待办行尾 ▶ 开始做；正在做里没截止的行尾 ⏸ 暂停（清掉排期，退回待办）
List<TaskSection> todaySections(BuildContext context, AppState s) {
  final scheme = Theme.of(context).colorScheme;
  return [
    TaskSection('已逾期', s.overdue, color: scheme.error),
    TaskSection('今天', s.dueToday),
    TaskSection(
      '正在做',
      s.inProgress,
      color: scheme.tertiary,
      trailing: (t) => t.dueDate == null
          ? IconButton(
              tooltip: '暂停（回到待办）',
              icon: const Icon(Icons.pause_rounded),
              color: scheme.onSurfaceVariant,
              onPressed: () => s.setStarted(t, false),
            )
          : null,
    ),
    TaskSection(
      '待办',
      s.unscheduled,
      trailing: (t) => IconButton(
        tooltip: '开始做',
        icon: const Icon(Icons.play_arrow_rounded),
        color: scheme.tertiary,
        onPressed: () => s.setStarted(t, true),
      ),
    ),
  ];
}

/// 把分组摊平成一个懒加载的 SliverList，长列表也只构建可见行
class TaskSectionsSliver extends StatelessWidget {
  final List<TaskSection> sections;
  final bool showProject;

  const TaskSectionsSliver({
    super.key,
    required this.sections,
    this.showProject = true,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Object>[];
    for (final s in sections) {
      if (s.tasks.isEmpty) continue;
      rows.add(s);
      rows.addAll(s.tasks.map((t) => (s, t)));
    }
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row is TaskSection) return _Header(section: row, first: i == 0);
        final (section, t) = row as (TaskSection, Task);
        return TaskTile(
          key: ValueKey(t.id),
          task: t,
          showProject: showProject,
          trailing: section.trailing?.call(t),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final TaskSection section;
  final bool first;
  const _Header({required this.section, required this.first});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = section.color ?? theme.colorScheme.primary;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, first ? 8 : 20, 20, 4),
      child: Row(
        children: [
          if (section.dot != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: section.dot,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            section.title,
            style: theme.textTheme.titleSmall!.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${section.tasks.length}',
            style: theme.textTheme.labelMedium!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: scheme.primary.withValues(alpha: .5)),
            const SizedBox(height: 12),
            Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge!
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
