import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../settings_page.dart';
import 'project_page.dart';

/// 手机/平板上的"项目"标签页；宽屏的项目列表在侧栏里
class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showProjectDialog(context),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('新建项目'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('项目'),
            actions: [
              IconButton(
                tooltip: '设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => openSettings(context),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverList.builder(
            itemCount: s.projects.length,
            itemBuilder: (context, i) {
              final p = s.projects[i];
              final n = s.tasksOfProject(p.id).length;
              return ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: (p.color ?? scheme.primary).withValues(
                    alpha: .18,
                  ),
                  child: Icon(
                    Icons.folder_rounded,
                    color: p.color ?? scheme.primary,
                    size: 20,
                  ),
                ),
                title: Text(p.title),
                trailing: n > 0
                    ? Text(
                        '$n',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      )
                    : null,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProjectPage(
                      projectId: p.id,
                      onDeleted: () => Navigator.pop(context),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
