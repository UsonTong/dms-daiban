import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../motion.dart';

import '../../api/models.dart';
import '../../state/app_state.dart';
import '../widgets/task_sections.dart';
import 'page_frame.dart';

class ProjectPage extends StatefulWidget {
  final int projectId;
  final VoidCallback? onDeleted;
  const ProjectPage({super.key, required this.projectId, this.onDeleted});

  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage> {
  bool _showDone = false;
  List<Task>? _done;

  Future<void> _toggleDone() async {
    setState(() => _showDone = !_showDone);
    if (_showDone) {
      final list = await context.read<AppState>().doneTasksOfProject(
        widget.projectId,
      );
      if (mounted) setState(() => _done = list);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.projectById(widget.projectId);
    if (p == null) return const Scaffold(body: Center(child: Text('项目不存在')));
    final open = s.tasksOfProject(p.id);
    return PageFrame(
      title: p.title,
      subtitle: '${open.length} 项未完成',
      projectId: p.id,
      actions: [
        IconButton(
          tooltip: _showDone ? '隐藏已完成' : '显示已完成',
          isSelected: _showDone,
          icon: const Icon(Icons.task_alt_rounded),
          onPressed: _toggleDone,
        ),
        PopupMenuButton<String>(
          onSelected: (v) => switch (v) {
            'edit' => showProjectDialog(context, project: p),
            'delete' => _delete(p),
            _ => null,
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('编辑项目'),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('删除项目'),
              ),
            ),
          ],
        ),
      ],
      slivers: [
        if (open.isEmpty && !_showDone)
          const EmptyState(icon: Icons.check_circle_outline, text: '这个项目没有待办')
        else
          MaxWidthSliver(
            sliver: TaskSectionsSliver(
              showProject: false,
              sections: [
                TaskSection('未完成', open),
                if (_showDone) TaskSection('已完成', _done ?? const []),
              ],
            ),
          ),
        if (_showDone && _done == null)
          const SliverToBoxAdapter(child: LinearProgressIndicator()),
      ],
    );
  }

  Future<void> _delete(Project p) async {
    final ok = await showFadeScaleDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除项目？'),
        content: Text('「${p.title}」和其中所有任务都会被删除。'),
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
    await context.read<AppState>().deleteProject(p);
    widget.onDeleted?.call();
  }
}

/// 新建或编辑项目：名称 + 颜色
Future<void> showProjectDialog(BuildContext context, {Project? project}) async {
  final ctrl = TextEditingController(text: project?.title ?? '');
  var hex = project?.hexColor.isNotEmpty == true
      ? project!.hexColor
      : labelPalette.first;
  final state = context.read<AppState>();
  final ok = await showFadeScaleDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(project == null ? '新建项目' : '编辑项目'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in labelPalette)
                  InkResponse(
                    onTap: () => setS(() => hex = c),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: parseHex(c),
                      child: hex == c
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || ctrl.text.trim().isEmpty) return;
  if (project == null) {
    await state.createProject(ctrl.text.trim(), hex);
  } else {
    await state.updateProject(project, title: ctrl.text.trim(), hexColor: hex);
  }
}
