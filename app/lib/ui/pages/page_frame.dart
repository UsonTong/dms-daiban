import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../task_editor.dart';
import '../widgets/quick_add_field.dart';

/// 列表页通用骨架：大标题、下拉刷新、手机上用 FAB 加任务、宽屏直接内嵌输入框
class PageFrame extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> slivers;
  final int? projectId;
  final bool quickAdd;

  const PageFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.slivers,
    this.projectId,
    this.quickAdd = true,
  });

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final state = context.read<AppState>();
    return Scaffold(
      floatingActionButton: compact && quickAdd
          ? FloatingActionButton(
              onPressed: () => showQuickAddSheet(context, projectId: projectId),
              tooltip: '添加任务',
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: state.refresh,
        edgeOffset: 120,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: subtitle == null
                  ? Text(title)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.labelLarge!
                              .copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
              actions: [...actions, const SizedBox(width: 8)],
            ),
            if (!compact && quickAdd)
              MaxWidthSliver(
                sliver: SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: QuickAddField(projectId: projectId),
                  ),
                ),
              ),
            ...slivers,
            const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
          ],
        ),
      ),
    );
  }
}

/// 列表内容在宽屏上限制最大宽度，避免一行拉得太长
class MaxWidthSliver extends StatelessWidget {
  final Widget sliver;
  const MaxWidthSliver({super.key, required this.sliver});

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, c) {
        final pad = c.crossAxisExtent > 900
            ? (c.crossAxisExtent - 900) / 2
            : 0.0;
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          sliver: sliver,
        );
      },
    );
  }
}
