import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../state/app_state.dart';
import 'task_tile.dart';

/// "今天已完成 N 件"：不小心勾掉的，点一下勾就能恢复
class DoneTodaySliver extends StatelessWidget {
  const DoneTodaySliver({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return FoldedTasksSliver(
      icon: Icons.task_alt_rounded,
      title: (n) => '今天已完成 $n 件',
      hint: '点勾可恢复',
      tasks: s.doneToday,
    );
  }
}

/// 折叠的一组任务：一行标题，点开展开
class FoldedTasksSliver extends StatefulWidget {
  final IconData icon;
  final String Function(int count) title;
  final String? hint;
  final List<Task> tasks;
  final Widget Function(Task task)? trailing;

  const FoldedTasksSliver({
    super.key,
    required this.icon,
    required this.title,
    required this.tasks,
    this.hint,
    this.trailing,
  });

  @override
  State<FoldedTasksSliver> createState() => _FoldedTasksSliverState();
}

class _FoldedTasksSliverState extends State<FoldedTasksSliver> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final list = widget.tasks;
    if (list.isEmpty) return const SliverToBoxAdapter();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 18, color: muted),
                    const SizedBox(width: 10),
                    Text(
                      widget.title(list.length),
                      style: theme.textTheme.labelLarge!.copyWith(color: muted),
                    ),
                    if (_open && widget.hint != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        widget.hint!,
                        style: theme.textTheme.labelMedium!.copyWith(
                          color: muted.withValues(alpha: .7),
                        ),
                      ),
                    ],
                    const Spacer(),
                    AnimatedRotation(
                      turns: _open ? .5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more_rounded, color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_open)
          SliverList.builder(
            itemCount: list.length,
            itemBuilder: (context, i) => TaskTile(
              key: ValueKey(list[i].id),
              task: list[i],
              trailing: widget.trailing?.call(list[i]),
            ),
          ),
      ],
    );
  }
}
