import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/dates.dart';
import '../../utils/quick_add.dart';
import 'check_circle.dart';

/// 一行输入加任务，实时预览识别出的日期/项目/标签/优先级
class QuickAddField extends StatefulWidget {
  final int? projectId;
  final bool autofocus;
  final VoidCallback? onSubmitted;

  /// 外部要主动把光标放进来时传入（如 Mod+D 面板每次弹出）；不传就自己管
  final FocusNode? focusNode;

  const QuickAddField({
    super.key,
    this.projectId,
    this.autofocus = false,
    this.onSubmitted,
    this.focusNode,
  });

  @override
  State<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends State<QuickAddField> {
  final _ctrl = TextEditingController();
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  QuickAddResult? _preview;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _ctrl.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final t = await context.read<AppState>().quickAdd(
      _ctrl.text,
      projectId: widget.projectId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (t != null) {
      _ctrl.clear();
      setState(() => _preview = null);
      widget.onSubmitted?.call();
    }
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = _preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          autofocus: widget.autofocus,
          textInputAction: TextInputAction.done,
          onChanged: (v) => setState(
            () => _preview = v.trim().isEmpty ? null : parseQuickAdd(v),
          ),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: '添加任务',
            prefixIcon: const Icon(Icons.add_rounded),
            suffixIcon: _busy
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded),
                    onPressed: _submit,
                    tooltip: '添加',
                  ),
            filled: true,
            fillColor: scheme.surfaceContainerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: p == null || !p.hasExtras
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (p.due != null)
                        _chip(
                          context,
                          Icons.event_rounded,
                          friendlyDate(p.due!),
                        ),
                      if (p.priority != null)
                        _chip(
                          context,
                          Icons.flag_rounded,
                          '优先级 ${priorityNames[p.priority!]}',
                          color: priorityColor(p.priority!),
                        ),
                      if (p.project != null)
                        _chip(context, Icons.folder_rounded, p.project!),
                      for (final l in p.labels)
                        _chip(context, Icons.sell_rounded, l),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _chip(
    BuildContext context,
    IconData icon,
    String text, {
    Color? color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 16, color: color ?? scheme.primary),
      label: Text(text),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

Future<void> showQuickAddSheet(BuildContext context, {int? projectId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(ctx).bottom,
      ),
      child: QuickAddField(projectId: projectId, autofocus: true),
    ),
  );
}
