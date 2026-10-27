import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'motion.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../utils/dates.dart';
import '../utils/zone.dart';
import 'widgets/check_circle.dart';

bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

/// 手机上从底部弹出，宽屏上用对话框
Future<void> showTaskEditor(BuildContext context, Task task) {
  if (isCompact(context)) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => TaskEditor(task: task),
    );
  }
  return showFadeScaleDialog(
    context: context,
    builder: (_) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: TaskEditor(task: task),
      ),
    ),
  );
}

class TaskEditor extends StatefulWidget {
  final Task task;
  const TaskEditor({super.key, required this.task});

  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late Task _t = widget.task;
  late final _title = TextEditingController(text: widget.task.title);
  late final _desc = TextEditingController(text: widget.task.description);
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final edited = _t.copyWith(
      title: _title.text.trim(),
      description: _desc.text,
    );
    final ok = await context.read<AppState>().saveTask(widget.task, edited);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  Future<void> _pickDue() async {
    final now = nowWall();
    final cur = _t.dueDate;
    final day = await showDatePicker(
      context: context,
      initialDate: cur ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: cur != null && hasTime(cur)
          ? TimeOfDay.fromDateTime(cur)
          : const TimeOfDay(hour: 18, minute: 0),
      helpText: '截止时间（取消则为全天）',
    );
    setState(() {
      _t = _t.copyWith(
        dueDate: time == null
            ? endOfDay(day)
            : DateTime(day.year, day.month, day.day, time.hour, time.minute),
      );
    });
  }

  Future<void> _pickRange() async {
    final now = nowWall();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
      initialDateRange: _t.hasRange
          ? DateTimeRange(start: dayOf(_t.startDate!), end: dayOf(_t.endDate!))
          : null,
    );
    if (r == null) return;
    setState(
      () => _t = _t.copyWith(startDate: r.start, endDate: endOfDay(r.end)),
    );
  }

  Future<void> _newLabel() async {
    final ctrl = TextEditingController();
    final name = await showFadeScaleDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新标签'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final l = await context.read<AppState>().ensureLabel(name.trim());
    setState(() => _t = _t.copyWith(labels: [..._t.labels, l]));
  }

  Future<void> _delete() async {
    final ok = await showFadeScaleDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除任务？'),
        content: Text('「${widget.task.title}」将被永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.pop(context);
    context.read<AppState>().deleteTask(widget.task);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final project = state.projectById(_t.projectId);
    final selected = _t.labels.map((l) => l.id).toSet();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, isCompact(context) ? 0 : 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckCircle(
                  checked: _t.done,
                  priority: _t.priority,
                  onTap: () => setState(() => _t = _t.copyWith(done: !_t.done)),
                ),
                Expanded(
                  child: TextField(
                    controller: _title,
                    style: theme.textTheme.titleLarge,
                    maxLines: null,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '任务标题',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _desc,
              minLines: 3,
              maxLines: 10,
              decoration: InputDecoration(
                hintText: '备注：做到哪了、下一步是什么…',
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Row(
              icon: Icons.folder_rounded,
              label: '项目',
              child: PopupMenuButton<int>(
                initialValue: _t.projectId,
                onSelected: (id) =>
                    setState(() => _t = _t.copyWith(projectId: id)),
                itemBuilder: (_) => [
                  for (final p in state.projects)
                    PopupMenuItem(value: p.id, child: _ProjectLabel(p)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: project == null
                      ? const Text('选择项目')
                      : _ProjectLabel(project),
                ),
              ),
            ),
            _Row(
              icon: Icons.event_rounded,
              label: '截止',
              child: _DateChip(
                text: _t.dueDate == null ? null : friendlyDate(_t.dueDate!),
                onTap: _pickDue,
                onClear: () => setState(() => _t = _t.copyWith(dueDate: null)),
              ),
            ),
            _Row(
              icon: Icons.date_range_rounded,
              label: '排期',
              child: _DateChip(
                text: _t.hasRange
                    ? '${friendlyDate(_t.startDate!, withTime: false)} → ${friendlyDate(_t.endDate!, withTime: false)}'
                    : null,
                onTap: _pickRange,
                onClear: () => setState(
                  () => _t = _t.copyWith(startDate: null, endDate: null),
                ),
              ),
            ),
            // 没截止的事：点"开始做"记下开始日期，之后每天出现在"正在做"
            if (!_t.hasRange && _t.dueDate == null)
              _Row(
                icon: Icons.play_circle_outline_rounded,
                label: '状态',
                child: _t.startDate == null
                    ? ActionChip(
                        avatar: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('开始做'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(
                          () => _t = _t.copyWith(startDate: today()),
                        ),
                      )
                    : InputChip(
                        avatar: const Icon(Icons.timelapse_rounded, size: 18),
                        label: Text(_ongoingLabel(_t.startDate!)),
                        deleteIcon: const Icon(Icons.pause_rounded, size: 18),
                        deleteButtonTooltipMessage: '暂停',
                        onDeleted: () =>
                            setState(() => _t = _t.copyWith(startDate: null)),
                        visualDensity: VisualDensity.compact,
                      ),
              ),
            _Row(
              icon: Icons.flag_rounded,
              label: '优先级',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < priorityNames.length; i++)
                    ChoiceChip(
                      label: Text(priorityNames[i]),
                      selected: _t.priority == i,
                      selectedColor: priorityColor(i)?.withValues(alpha: .2),
                      onSelected: (_) =>
                          setState(() => _t = _t.copyWith(priority: i)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
            _Row(
              icon: Icons.sell_rounded,
              label: '标签',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final l in state.labels)
                    FilterChip(
                      label: Text(l.title),
                      selected: selected.contains(l.id),
                      selectedColor: (l.color ?? scheme.secondary).withValues(
                        alpha: .22,
                      ),
                      avatar: selected.contains(l.id)
                          ? null
                          : CircleAvatar(
                              backgroundColor: l.color ?? scheme.secondary,
                              radius: 5,
                            ),
                      visualDensity: VisualDensity.compact,
                      onSelected: (on) => setState(
                        () => _t = _t.copyWith(
                          labels: on
                              ? [..._t.labels, l]
                              : _t.labels.where((x) => x.id != l.id).toList(),
                        ),
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('新标签'),
                    visualDensity: VisualDensity.compact,
                    onPressed: _newLabel,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('删除'),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  const _Row({required this.icon, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Text(
                label,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ],
      ),
    );
  }
}

class _ProjectLabel extends StatelessWidget {
  final Project p;
  const _ProjectLabel(this.p);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: p.color ?? Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 8),
      Text(p.title),
    ],
  );
}

class _DateChip extends StatelessWidget {
  final String? text;
  final VoidCallback onTap;
  final VoidCallback onClear;
  const _DateChip({
    required this.text,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (text == null) {
      return ActionChip(
        label: const Text('设置'),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      );
    }
    return InputChip(
      label: Text(text!),
      onPressed: onTap,
      onDeleted: onClear,
      visualDensity: VisualDensity.compact,
    );
  }
}

String _ongoingLabel(DateTime start) {
  final n = daysBetween(start, today()) + 1;
  if (n <= 0) return '${shortDate(start)} 开始';
  return n == 1 ? '今天开始，在做' : '已做 $n 天';
}
