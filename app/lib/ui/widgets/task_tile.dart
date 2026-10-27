import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../state/app_state.dart';
import '../../utils/dates.dart';
import '../../utils/zone.dart';
import '../task_editor.dart';
import 'check_circle.dart';

class TaskTile extends StatefulWidget {
  final Task task;
  final bool showProject;

  /// 行尾的操作按钮（如"没安排"里的"开始做"）
  final Widget? trailing;

  const TaskTile({
    super.key,
    required this.task,
    this.showProject = true,
    this.trailing,
  });

  @override
  State<TaskTile> createState() => _TaskTileState();
}

/// 勾选后：先打勾划线，再折叠高度；时长与 AppState 的移除延迟对齐
class _TaskTileState extends State<TaskTile> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final Animation<double> _size = CurvedAnimation(
    parent: _c,
    curve: const Interval(.45, 1, curve: Curves.easeInOutCubic),
  );

  /// 新加的任务从 0 高度展开并淡入
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    value: context.read<AppState>().justAdded.contains(widget.task.id) ? 0 : 1,
  )..forward();
  late final Animation<double> _enterCurve = CurvedAnimation(
    parent: _enter,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _c.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final completing = context.select<AppState, bool>(
      (s) => s.completing.contains(widget.task.id),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (completing && !_c.isAnimating && _c.value == 0) _c.forward();
      if (!completing && _c.value != 0) _c.value = 0;
    });

    final t = widget.task;
    final checked = completing || t.done;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizeTransition(
      sizeFactor: _enterCurve,
      alignment: Alignment.topLeft,
      child: FadeTransition(
        opacity: _enterCurve,
        child: SizeTransition(
          sizeFactor: ReverseAnimation(_size),
          alignment: Alignment.topLeft,
          child: InkWell(
            onTap: () => showTaskEditor(context, t),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 16, 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckCircle(
                    checked: checked,
                    priority: t.priority,
                    onTap: () => state.toggleDone(t),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: theme.textTheme.bodyLarge!.copyWith(
                              color: checked
                                  ? scheme.onSurfaceVariant
                                  : scheme.onSurface,
                              decoration: checked
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: scheme.onSurfaceVariant,
                            ),
                            child: Text(
                              t.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _Meta(task: t, showProject: showProject),
                          _Note(task: t),
                        ],
                      ),
                    ),
                  ),
                  if (widget.trailing != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: widget.trailing,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get showProject => widget.showProject;
}

class _Meta extends StatelessWidget {
  final Task task;
  final bool showProject;
  const _Meta({required this.task, required this.showProject});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.labelMedium!.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final items = <Widget>[];

    final due = task.dueDate;
    if (due != null) {
      final overdue = !task.done && due.isBefore(nowWall());
      final c = overdue ? scheme.error : small.color;
      items.add(
        _iconText(
          Icons.event_rounded,
          friendlyDate(due),
          small.copyWith(color: c),
        ),
      );
    }
    if (task.isOngoing) {
      final n = daysBetween(task.startDate!, today()) + 1;
      items.add(
        _iconText(
          Icons.play_circle_outline_rounded,
          n <= 0
              ? '${shortDate(task.startDate!)} 开始'
              : (n == 1 ? '今天开始' : '已做 $n 天'),
          small.copyWith(color: scheme.tertiary),
        ),
      );
    } else if (task.hasRange) {
      final range = '${shortDate(task.startDate!)}–${shortDate(task.endDate!)}';
      final t0 = today();
      final total = daysBetween(task.startDate!, task.endDate!) + 1;
      final day = daysBetween(task.startDate!, t0) + 1;
      final over = daysBetween(task.endDate!, t0);
      if (!task.done && over > 0) {
        // 计划的天数用完了还没做完
        items.add(
          _iconText(
            Icons.timer_off_outlined,
            '超出计划 $over 天',
            small.copyWith(color: scheme.error),
          ),
        );
      } else if (!task.done && day >= 1) {
        items.add(
          _iconText(
            Icons.date_range_rounded,
            '第 $day/$total 天 · $range',
            small.copyWith(color: scheme.tertiary),
          ),
        );
      } else {
        items.add(_iconText(Icons.date_range_rounded, range, small));
      }
    }
    if (task.repeatAfter > 0) {
      items.add(Icon(Icons.repeat_rounded, size: 14, color: small.color));
    }
    if (showProject) {
      final p = context.select<AppState, Project?>(
        (s) => s.projectById(task.projectId),
      );
      if (p != null) {
        items.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: p.color ?? scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(p.title, style: small),
            ],
          ),
        );
      }
    }
    for (final l in task.labels) {
      final c = l.color ?? scheme.secondary;
      items.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: c.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            l.title,
            style: small.copyWith(color: Color.lerp(c, scheme.onSurface, .25)),
          ),
        ),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: items,
      ),
    );
  }

  Widget _iconText(IconData icon, String text, TextStyle style) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: style.color),
      const SizedBox(width: 3),
      Text(text, style: style),
    ],
  );
}

/// 备注的第一行直接显示在任务下面：切回来时一眼看到"做到哪了"
class _Note extends StatelessWidget {
  final Task task;
  const _Note({required this.task});

  @override
  Widget build(BuildContext context) {
    final line = task.description
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (line.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall!.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
