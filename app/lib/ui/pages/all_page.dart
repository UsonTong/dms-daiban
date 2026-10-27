import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../widgets/task_sections.dart';
import 'page_frame.dart';

class AllPage extends StatelessWidget {
  const AllPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final sections = [
      for (final p in s.projects)
        TaskSection(
          p.title,
          s.tasksOfProject(p.id),
          color: scheme.onSurface,
          dot: p.color ?? scheme.primary,
        ),
    ];
    return PageFrame(
      title: '全部',
      subtitle: '${s.tasks.length} 项未完成',
      slivers: [
        if (s.tasks.isEmpty)
          const EmptyState(icon: Icons.inbox_outlined, text: '没有未完成的任务')
        else
          MaxWidthSliver(
            sliver: TaskSectionsSliver(sections: sections, showProject: false),
          ),
      ],
    );
  }
}
