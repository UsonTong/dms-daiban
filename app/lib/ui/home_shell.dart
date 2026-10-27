import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'gantt/gantt_page.dart';
import 'pages/all_page.dart';
import 'pages/project_page.dart';
import 'pages/projects_page.dart';
import 'pages/today_page.dart';
import 'motion.dart';
import 'settings_page.dart';

/// 自适应导航：手机底栏、平板侧轨、桌面侧栏（含项目列表）
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  int? _project;
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _life = AppLifecycleListener(
      onResume: () => s.setForeground(true),
      onPause: () => s.setForeground(false),
    );
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  static const _pages = [TodayPage(), AllPage(), GanttPage(), ProjectsPage()];

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final todayCount = context.select<AppState, int>((s) => s.todayCount);

    Widget badge(IconData icon) => Badge(
      isLabelVisible: todayCount > 0,
      label: Text('$todayCount'),
      child: Icon(icon),
    );

    if (w < 600) {
      return Scaffold(
        body: FadeThroughStack(index: _tab, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            NavigationDestination(
              icon: badge(Icons.wb_sunny_outlined),
              selectedIcon: badge(Icons.wb_sunny),
              label: '今天',
            ),
            const NavigationDestination(
              icon: Icon(Icons.inbox_outlined),
              selectedIcon: Icon(Icons.inbox),
              label: '全部',
            ),
            const NavigationDestination(
              icon: Icon(Icons.view_timeline_outlined),
              selectedIcon: Icon(Icons.view_timeline),
              label: '甘特图',
            ),
            const NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label: '项目',
            ),
          ],
        ),
      );
    }

    if (w < 1000) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _tab,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -.9,
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IconButton(
                      tooltip: '设置',
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => openSettings(context),
                    ),
                  ),
                ),
              ),
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                NavigationRailDestination(
                  icon: badge(Icons.wb_sunny_outlined),
                  selectedIcon: badge(Icons.wb_sunny),
                  label: const Text('今天'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.inbox_outlined),
                  selectedIcon: Icon(Icons.inbox),
                  label: Text('全部'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.view_timeline_outlined),
                  selectedIcon: Icon(Icons.view_timeline),
                  label: Text('甘特图'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: Text('项目'),
                ),
              ],
            ),
            Expanded(
              child: FadeThroughStack(index: _tab, children: _pages),
            ),
          ],
        ),
      );
    }

    // 桌面：侧栏里直接列出项目
    final tab = _tab == 3 ? 0 : _tab;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 280,
            child: _SideBar(
              tab: _project == null ? tab : null,
              project: _project,
              todayCount: todayCount,
              onTab: (i) => setState(() {
                _tab = i;
                _project = null;
              }),
              onProject: (id) => setState(() => _project = id),
            ),
          ),
          Expanded(
            // 前三格是常驻页面（保留状态），第四格放当前项目；项目之间切换也做淡出淡入
            child: FadeThroughStack(
              index: _project != null ? 3 : tab,
              children: [
                ..._pages.sublist(0, 3),
                FadeThroughSwitcher(
                  child: _project == null
                      ? const SizedBox.shrink(key: ValueKey('none'))
                      : ProjectPage(
                          key: ValueKey(_project),
                          projectId: _project!,
                          onDeleted: () => setState(() => _project = null),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideBar extends StatelessWidget {
  final int? tab;
  final int? project;
  final int todayCount;
  final ValueChanged<int> onTab;
  final ValueChanged<int> onProject;

  const _SideBar({
    required this.tab,
    required this.project,
    required this.todayCount,
    required this.onTab,
    required this.onProject,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget item({
      required IconData icon,
      required String label,
      required bool selected,
      required VoidCallback onTap,
      Widget? leading,
      String? trailing,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        child: ListTile(
          selected: selected,
          selectedTileColor: scheme.secondaryContainer,
          selectedColor: scheme.onSecondaryContainer,
          shape: const StadiumBorder(),
          leading: leading ?? Icon(icon),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: trailing == null
              ? null
              : Text(trailing, style: theme.textTheme.labelLarge),
          onTap: onTap,
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 16, 16),
              child: Row(
                children: [
                  Icon(Icons.task_alt_rounded, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text('待办', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (v) {
                      if (v == 'logout') s.logout();
                      if (v == 'refresh') s.refresh();
                      if (v == 'settings') openSettings(context);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'refresh', child: Text('刷新')),
                      const PopupMenuItem(value: 'settings', child: Text('设置')),
                      PopupMenuItem(
                        value: 'logout',
                        child: Text('退出登录（${s.user?.username ?? ''}）'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            item(
              icon: Icons.wb_sunny_outlined,
              label: '今天',
              selected: tab == 0,
              onTap: () => onTab(0),
              trailing: todayCount > 0 ? '$todayCount' : null,
            ),
            item(
              icon: Icons.inbox_outlined,
              label: '全部',
              selected: tab == 1,
              onTap: () => onTab(1),
              trailing: '${s.tasks.length}',
            ),
            item(
              icon: Icons.view_timeline_outlined,
              label: '甘特图',
              selected: tab == 2,
              onTap: () => onTab(2),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8),
              child: Divider(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 16, 4),
              child: Row(
                children: [
                  Text(
                    '项目',
                    style: theme.textTheme.titleSmall!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '新建项目',
                    icon: const Icon(Icons.add_rounded, size: 20),
                    onPressed: () => showProjectDialog(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            for (final p in s.projects)
              item(
                icon: Icons.folder_outlined,
                leading: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: p.color ?? scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                label: p.title,
                selected: project == p.id,
                onTap: () => onProject(p.id),
                trailing: () {
                  final n = s.tasksOfProject(p.id).length;
                  return n > 0 ? '$n' : null;
                }(),
              ),
          ],
        ),
      ),
    );
  }
}
