import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../state/app_state.dart';
import '../../utils/dates.dart';
import '../task_editor.dart';

const _rowH = 44.0;
const _headerH = 52.0;

enum _DragMode { move, start, end }

/// 甘特图里一行要画的东西；只有截止日的任务按一天显示
class _Row {
  final Task task;
  final DateTime? start;
  final DateTime? end;
  final bool dueOnly;

  /// 长期在做（只有开始日期）：横条画到今天，末端渐隐
  final bool openEnded;
  final bool dim;
  final Color color;

  _Row(
    this.task,
    this.start,
    this.end, {
    required this.dueOnly,
    required this.dim,
    required this.color,
    this.openEnded = false,
  });

  int get days => start == null ? 0 : daysBetween(start!, end!) + 1;
}

class _Preview {
  final int taskId;
  final DateTime start;
  final DateTime end;
  const _Preview(this.taskId, this.start, this.end);
}

class GanttPage extends StatefulWidget {
  /// 嵌在别的容器里（Mod+D 面板）：不带 Scaffold 和顶栏
  final bool embedded;

  const GanttPage({super.key, this.embedded = false});

  @override
  State<GanttPage> createState() => _GanttPageState();
}

class _GanttPageState extends State<GanttPage> {
  double _dayW = 36;
  final Set<int> _labelFilter = {};
  bool _showUndated = false;

  final _h = ScrollController();
  final _bodyKey = GlobalKey();

  /// 拖动中的预览只驱动画布重绘，不重建整个页面
  final _preview = ValueNotifier<_Preview?>(null);
  _DragMode? _mode;
  _Row? _dragRow;
  double _dragDx = 0;
  MouseCursor _cursor = MouseCursor.defer;

  late DateTime _rangeStart;
  bool _hasRange = false;
  int _dayCount = 0;
  List<_Row> _rows = [];
  bool _scrolledToToday = false;

  @override
  void dispose() {
    _h.dispose();
    _preview.dispose();
    super.dispose();
  }

  void _build(AppState s) {
    final primary = Theme.of(context).colorScheme.primary;
    final dated = <_Row>[];
    final undated = <_Row>[];
    for (final t in s.tasks) {
      final dim =
          _labelFilter.isNotEmpty &&
          !t.labels.any((l) => _labelFilter.contains(l.id));
      final color = s.taskColor(t) ?? primary;
      if (t.isOngoing) {
        final st = dayOf(t.startDate!);
        final t0 = today();
        dated.add(
          _Row(
            t,
            st,
            st.isAfter(t0) ? st : t0,
            dueOnly: false,
            openEnded: true,
            dim: dim,
            color: color,
          ),
        );
      } else if (t.startDate != null || t.endDate != null) {
        final st = dayOf(t.startDate ?? t.endDate!);
        final en = dayOf(t.endDate ?? t.startDate!);
        dated.add(
          _Row(
            t,
            st,
            en.isBefore(st) ? st : en,
            dueOnly: false,
            dim: dim,
            color: color,
          ),
        );
      } else if (t.dueDate != null) {
        final d = dayOf(t.dueDate!);
        dated.add(_Row(t, d, d, dueOnly: true, dim: dim, color: color));
      } else if (_showUndated) {
        undated.add(
          _Row(t, null, null, dueOnly: false, dim: dim, color: color),
        );
      }
    }
    dated.sort((a, b) {
      final c = a.start!.compareTo(b.start!);
      return c != 0 ? c : a.end!.compareTo(b.end!);
    });
    undated.sort((a, b) => AppState.compareTasks(a.task, b.task));
    _rows = [...dated, ...undated];

    final t0 = today();
    var first = addDays(t0, -14);
    var last = addDays(t0, 60);
    for (final r in dated) {
      if (r.start!.isBefore(first)) first = r.start!;
      if (r.end!.isAfter(last)) last = r.end!;
    }
    // 从周一开始，前后多留一周
    _rangeStart = addDays(first, -(first.weekday - 1 + 7));
    _dayCount = daysBetween(_rangeStart, last) + 21;
  }

  void _scrollToToday() {
    if (!_h.hasClients) return;
    final x = (daysBetween(_rangeStart, today()) - 3) * _dayW;
    _h.jumpTo(x.clamp(0, _h.position.maxScrollExtent));
  }

  // ---------- 命中测试 ----------

  Offset? _local(Offset global) {
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  (_Row, _DragMode)? _hit(Offset local) {
    final i = local.dy ~/ _rowH;
    if (i < 0 || i >= _rows.length) return null;
    final r = _rows[i];
    if (r.start == null) return null;
    final x0 = daysBetween(_rangeStart, r.start!) * _dayW;
    final x1 = x0 + r.days * _dayW;
    if (local.dx < x0 - 4 || local.dx > x1 + 4) return null;
    final edge = math.min(12.0, (x1 - x0) / 3);
    if (local.dx >= x1 - edge) return (r, _DragMode.end);
    if (local.dx <= x0 + edge) return (r, _DragMode.start);
    return (r, _DragMode.move);
  }

  /// 按下时就记住命中了哪根横条的哪个部位；之后手指移出横条也不影响
  (_Row, _DragMode)? _pressHit;

  bool _canDrag(Offset global) {
    final l = _local(global);
    _pressHit = l == null ? null : _hit(l);
    return _pressHit != null;
  }

  void _onDragStart(DragStartDetails d) {
    final hit = _pressHit ?? _hit(d.localPosition);
    _pressHit = null;
    if (hit == null) return;
    _dragRow = hit.$1;
    // 长期任务的右端是"今天"，整体拖动没有意义，按住中间也只改开始日期
    _mode = hit.$1.openEnded && hit.$2 == _DragMode.move
        ? _DragMode.start
        : hit.$2;
    _dragDx = 0;
    _preview.value = _Preview(hit.$1.task.id, hit.$1.start!, hit.$1.end!);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final r = _dragRow;
    if (r == null) return;
    _dragDx += d.delta.dx;
    final n = (_dragDx / _dayW).round();
    var st = r.start!, en = r.end!;
    switch (_mode!) {
      case _DragMode.move:
        st = addDays(st, n);
        en = addDays(en, n);
      case _DragMode.start:
        st = addDays(st, n);
        if (st.isAfter(en)) st = en;
      case _DragMode.end:
        en = addDays(en, n);
        if (en.isBefore(st)) en = st;
    }
    final p = _preview.value;
    if (p == null || p.start != st || p.end != en) {
      _preview.value = _Preview(r.task.id, st, en);
    }
  }

  void _onDragEnd([DragEndDetails? _]) {
    final r = _dragRow, p = _preview.value;
    _dragRow = null;
    // 鼠标按下即认领手势，所以几乎没动就松开 = 点击，打开编辑
    if (r != null && _dragDx.abs() < 4) {
      _preview.value = null;
      showTaskEditor(context, r.task);
      return;
    }
    if (r != null && p != null && (p.start != r.start || p.end != r.end)) {
      final s = context.read<AppState>();
      // 长期任务拖开始端只改开始日期；拖右端等于给它定了结束日，变成普通排期
      final save = r.openEnded && _mode == _DragMode.start
          ? s.updateStart(r.task, p.start)
          : s.updateRange(r.task, p.start, p.end);
      save.whenComplete(() => _preview.value = null);
    } else {
      _preview.value = null;
    }
  }

  void _onTapUp(TapUpDetails d) {
    final hit = _hit(d.localPosition);
    if (hit != null) {
      showTaskEditor(context, hit.$1.task);
      return;
    }
    // 点无日期任务那一行的某一天 = 把它排到这一天
    final i = d.localPosition.dy ~/ _rowH;
    if (i >= 0 && i < _rows.length && _rows[i].start == null) {
      final day = addDays(_rangeStart, d.localPosition.dx ~/ _dayW);
      context.read<AppState>().updateRange(_rows[i].task, day, day);
    }
  }

  void _onHover(PointerHoverEvent e) {
    final hit = _hit(e.localPosition);
    final c = hit == null
        ? MouseCursor.defer
        : hit.$2 == _DragMode.move
        ? SystemMouseCursors.grab
        : SystemMouseCursors.resizeLeftRight;
    if (c != _cursor) setState(() => _cursor = c);
  }

  // ---------- 界面 ----------

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = isCompact(context);
    final prevStart = _hasRange ? _rangeStart : null;
    _build(s);
    _hasRange = true;
    // 数据变化让时间轴起点前移/后移时，滚动位置跟着平移，保持看的还是同一天
    if (prevStart != null && prevStart != _rangeStart && _h.hasClients) {
      final shift = daysBetween(_rangeStart, prevStart) * _dayW;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_h.hasClients) return;
        _h.jumpTo((_h.offset + shift).clamp(0, _h.position.maxScrollExtent));
      });
    }
    final leftW = compact ? 132.0 : 300.0;
    final totalW = _dayCount * _dayW;

    // 任务加载完、横向滚动视图挂上之后才定位到今天
    if (!_scrolledToToday) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrolledToToday || !_h.hasClients) return;
        _scrolledToToday = true;
        _scrollToToday();
      });
    }

    final actions = <Widget>[
      IconButton(
        tooltip: '回到今天',
        icon: const Icon(Icons.today_rounded),
        onPressed: _scrollToToday,
      ),
      IconButton(
        tooltip: _showUndated ? '隐藏无日期任务' : '显示无日期任务（点某天即可排期）',
        isSelected: _showUndated,
        icon: const Icon(Icons.event_busy_outlined),
        selectedIcon: const Icon(Icons.event_available_rounded),
        onPressed: () => setState(() => _showUndated = !_showUndated),
      ),
      const SizedBox(width: 4),
      SegmentedButton<double>(
        segments: const [
          ButtonSegment(value: 36, label: Text('日')),
          ButtonSegment(value: 18, label: Text('周')),
          ButtonSegment(value: 8, label: Text('月')),
        ],
        selected: {_dayW},
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        onSelectionChanged: (v) {
          setState(() => _dayW = v.first);
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
        },
      ),
    ];
    final body = Column(
      children: [
        if (s.labels.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final l in s.labels)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(l.title),
                      selected: _labelFilter.contains(l.id),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(
                        color: (l.color ?? scheme.secondary).withValues(
                          alpha: .6,
                        ),
                      ),
                      backgroundColor: (l.color ?? scheme.secondary).withValues(
                        alpha: .08,
                      ),
                      selectedColor: l.color ?? scheme.secondary,
                      labelStyle: TextStyle(
                        color: _labelFilter.contains(l.id)
                            ? _onColor(l.color ?? scheme.secondary)
                            : null,
                      ),
                      onSelected: (on) => setState(
                        () => on
                            ? _labelFilter.add(l.id)
                            : _labelFilter.remove(l.id),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Divider(height: 1, color: scheme.outlineVariant),
        // 表头：左侧列名 + 右侧日期（跟随横向滚动）
        SizedBox(
          height: _headerH,
          child: Row(
            children: [
              _LeftHeader(width: leftW, compact: compact),
              Expanded(
                child: ClipRect(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _HeaderPainter(
                      start: _rangeStart,
                      days: _dayCount,
                      dayW: _dayW,
                      scheme: scheme,
                      text: theme.textTheme,
                      scroll: _h,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          // 画布至少铺满可视高度，任务少或没有时网格和今天竖线也是完整的
          child: LayoutBuilder(
            builder: (context, c) {
              final bodyH = math.max(_rows.length * _rowH, c.maxHeight);
              return Stack(
                children: [
                  SingleChildScrollView(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: leftW,
                          height: bodyH,
                          child: ValueListenableBuilder(
                            valueListenable: _preview,
                            builder: (context, p, _) => Column(
                              children: [
                                for (final r in _rows)
                                  _LeftRow(
                                    row: r,
                                    compact: compact,
                                    preview: p,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          height: bodyH,
                          child: VerticalDivider(
                            width: 1,
                            color: scheme.outlineVariant,
                          ),
                        ),
                        Expanded(
                          // 桌面上用鼠标按住空白处左右拖动来平移时间轴
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context).copyWith(
                              dragDevices: PointerDeviceKind.values.toSet(),
                            ),
                            child: SingleChildScrollView(
                              controller: _h,
                              scrollDirection: Axis.horizontal,
                              child: MouseRegion(
                                cursor: _cursor,
                                onHover: _onHover,
                                child: RawGestureDetector(
                                  gestures: {
                                    _BarDragRecognizer:
                                        GestureRecognizerFactoryWithHandlers<
                                          _BarDragRecognizer
                                        >(
                                          () => _BarDragRecognizer(_canDrag),
                                          // 触摸阈值取系统值的一半：在横条上横滑时先于滚动视图认领手势
                                          (r) => r
                                            ..gestureSettings =
                                                DeviceGestureSettings(
                                                  touchSlop:
                                                      (MediaQuery.gestureSettingsOf(
                                                            context,
                                                          ).touchSlop ??
                                                          kTouchSlop) /
                                                      2,
                                                )
                                            // 从按下点开始算位移，横条全程跟手
                                            ..dragStartBehavior =
                                                DragStartBehavior.down
                                            ..onStart = _onDragStart
                                            ..onUpdate = _onDragUpdate
                                            ..onEnd = _onDragEnd
                                            ..onCancel = _onDragEnd,
                                        ),
                                    TapGestureRecognizer:
                                        GestureRecognizerFactoryWithHandlers<
                                          TapGestureRecognizer
                                        >(
                                          TapGestureRecognizer.new,
                                          (r) => r.onTapUp = _onTapUp,
                                        ),
                                  },
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      key: _bodyKey,
                                      size: Size(totalW, bodyH),
                                      painter: _BodyPainter(
                                        rows: _rows,
                                        start: _rangeStart,
                                        days: _dayCount,
                                        dayW: _dayW,
                                        scheme: scheme,
                                        text: theme.textTheme,
                                        preview: _preview,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_rows.isEmpty)
                    IgnorePointer(
                      child: Center(
                        child: Card(
                          elevation: 0,
                          color: scheme.surfaceContainerHigh,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            child: Text(
                              '还没有带日期的任务\n在任务里设置「排期」或「截止」就会出现在这里',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
    // 嵌在 Mod+D 面板里时没有顶栏，按钮放在卡片里的一行
    if (widget.embedded) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Row(children: [const Spacer(), ...actions]),
          ),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('甘特图'),
        actions: [...actions, const SizedBox(width: 12)],
      ),
      body: body,
    );
  }
}

/// 只在按下点落在横条上时才参与手势竞争，空白处照常滚动
class _BarDragRecognizer extends HorizontalDragGestureRecognizer {
  final bool Function(Offset global) allow;
  _BarDragRecognizer(this.allow);

  @override
  bool isPointerAllowed(PointerEvent event) =>
      allow(event.position) && super.isPointerAllowed(event);

  /// 鼠标的拖动阈值只有 1px，和滚动视图永远打平；按在横条上就直接认领，
  /// 没移动就松开按"点击"处理
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (event.kind == PointerDeviceKind.mouse) {
      resolve(GestureDisposition.accepted);
    }
  }
}

Color _onColor(Color c) =>
    c.computeLuminance() > .5 ? Colors.black87 : Colors.white;

class _LeftHeader extends StatelessWidget {
  final double width;
  final bool compact;
  const _LeftHeader({required this.width, required this.compact});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge!
        .copyWith(fontWeight: FontWeight.w600);
    return SizedBox(
      width: width + 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(child: Text('任务', style: style)),
            if (!compact) ...[
              SizedBox(width: 64, child: Text('开始', style: style)),
              SizedBox(
                width: 40,
                child: Text('天数', style: style, textAlign: TextAlign.right),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LeftRow extends StatelessWidget {
  final _Row row;
  final bool compact;
  final _Preview? preview;
  const _LeftRow({
    required this.row,
    required this.compact,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = preview?.taskId == row.task.id ? preview : null;
    final start = p?.start ?? row.start;
    final days = p != null ? daysBetween(p.start, p.end) + 1 : row.days;
    final color = row.dim
        ? scheme.onSurface.withValues(alpha: .35)
        : scheme.onSurface;
    final sub = theme.textTheme.bodySmall!.copyWith(
      color: row.dim ? color : scheme.onSurfaceVariant,
    );
    return InkWell(
      onTap: () => showTaskEditor(context, row.task),
      child: Container(
        height: _rowH,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                row.task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium!.copyWith(color: color),
              ),
            ),
            if (!compact) ...[
              SizedBox(
                width: 64,
                child: Text(start == null ? '—' : shortDate(start), style: sub),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  start == null ? '' : '$days',
                  style: sub,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 表头跟着主体的横向滚动画；只画可见的日期，月份标签吸附在左边缘
class _HeaderPainter extends CustomPainter {
  final DateTime start;
  final int days;
  final double dayW;
  final ColorScheme scheme;
  final TextTheme text;
  final ScrollController scroll;

  _HeaderPainter({
    required this.start,
    required this.days,
    required this.dayW,
    required this.scheme,
    required this.text,
    required this.scroll,
  }) : super(repaint: scroll);

  @override
  void paint(Canvas canvas, Size size) {
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    final t0 = today();
    final line = Paint()..color = scheme.outlineVariant.withValues(alpha: .6);
    final weekend = Paint()
      ..color = scheme.surfaceContainerHighest.withValues(alpha: .7);
    final monthStyle = text.labelLarge!.copyWith(fontWeight: FontWeight.w600);
    const monthH = 22.0;

    final first = math.max(0, (offset / dayW).floor());
    final last = math.min(days, ((offset + size.width) / dayW).ceil() + 1);

    canvas.save();
    canvas.translate(-offset, 0);
    for (var i = first; i < last; i++) {
      final d = addDays(start, i);
      final x = i * dayW;
      if (d.weekday >= 6 && dayW >= 9) {
        canvas.drawRect(
          Rect.fromLTWH(x, monthH, dayW, size.height - monthH),
          weekend,
        );
      }
      if (d.day == 1) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      }
      final isToday = d == t0;
      if (!(dayW >= 20 || d.weekday == 1 || isToday)) continue;
      final center = Offset(x + dayW / 2, monthH + (size.height - monthH) / 2);
      if (isToday) {
        canvas.drawCircle(center, 12, Paint()..color = scheme.primary);
      }
      _text(
        canvas,
        '${d.day}',
        center,
        text.labelMedium!.copyWith(
          color: isToday ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
        centered: true,
      );
    }

    // 月份标签：贴住可见区域左边，被下个月顶出去
    var m = DateTime(addDays(start, first).year, addDays(start, first).month);
    while (true) {
      final segStart = math.max(0, daysBetween(start, m)) * dayW;
      final next = DateTime(m.year, m.month + 1);
      final segEnd = daysBetween(start, next) * dayW;
      if (segStart > offset + size.width) break;
      final label = TextPainter(
        text: TextSpan(text: '${m.year}年${m.month}月', style: monthStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = math.min(
        math.max(segStart, offset) + 8,
        segEnd - label.width - 8,
      );
      label.paint(canvas, Offset(x, 3));
      label.dispose();
      m = next;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeaderPainter old) =>
      old.start != start ||
      old.days != days ||
      old.dayW != dayW ||
      old.scheme != scheme ||
      old.scroll != scroll;
}

class _BodyPainter extends CustomPainter {
  final List<_Row> rows;
  final DateTime start;
  final int days;
  final double dayW;
  final ColorScheme scheme;
  final TextTheme text;
  final ValueNotifier<_Preview?> preview;

  _BodyPainter({
    required this.rows,
    required this.start,
    required this.days,
    required this.dayW,
    required this.scheme,
    required this.text,
    required this.preview,
  }) : super(repaint: preview);

  @override
  void paint(Canvas canvas, Size size) {
    final t0 = today();
    final grid = Paint()..color = scheme.outlineVariant.withValues(alpha: .35);
    final weekend = Paint()
      ..color = scheme.surfaceContainerHighest.withValues(alpha: .55);

    // 背景：周末、网格、今天
    for (var i = 0; i < days; i++) {
      final d = addDays(start, i);
      final x = i * dayW;
      if (d.weekday >= 6 && dayW >= 9) {
        canvas.drawRect(Rect.fromLTWH(x, 0, dayW, size.height), weekend);
      }
      if (dayW >= 20 || d.weekday == 1) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      }
    }
    for (var r = 1; r <= rows.length; r++) {
      canvas.drawLine(
        Offset(0, r * _rowH),
        Offset(size.width, r * _rowH),
        grid,
      );
    }
    final tx = daysBetween(start, t0) * dayW;
    canvas.drawRect(
      Rect.fromLTWH(tx, 0, dayW, size.height),
      Paint()..color = scheme.primary.withValues(alpha: .07),
    );
    canvas.drawLine(
      Offset(tx + dayW / 2, 0),
      Offset(tx + dayW / 2, size.height),
      Paint()
        ..color = scheme.primary.withValues(alpha: .6)
        ..strokeWidth = 1.5,
    );

    final p = preview.value;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (r.start == null) continue;
      final dragging = p?.taskId == r.task.id;
      final st = dragging ? p!.start : r.start!;
      final en = dragging ? p!.end : r.end!;
      final x = daysBetween(start, st) * dayW;
      final w = (daysBetween(st, en) + 1) * dayW;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 1, i * _rowH + 8, w - 2, _rowH - 16),
        const Radius.circular(6),
      );
      final base = r.color.withValues(alpha: r.dim ? .25 : 1);

      if (dragging) {
        canvas.drawShadow(Path()..addRRect(rect), Colors.black, 4, false);
      }
      if (r.dueOnly) {
        // 只有截止日：描边样式
        canvas.drawRRect(
          rect,
          Paint()..color = base.withValues(alpha: base.a * .18),
        );
        canvas.drawRRect(
          rect,
          Paint()
            ..color = base
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      } else if (r.openEnded) {
        // 长期在做：最后一天半渐隐，表示还没结束
        final fade = math.min(dayW * 1.5, rect.width * .6);
        canvas.drawRRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              colors: [base, base, base.withValues(alpha: 0)],
              stops: [0, (rect.width - fade) / rect.width, 1],
            ).createShader(rect.outerRect),
        );
      } else {
        canvas.drawRRect(rect, Paint()..color = base);
      }

      final fg = r.dueOnly || r.dim
          ? scheme.onSurface.withValues(alpha: r.dim ? .4 : .9)
          : _onColor(r.color);
      final style = text.labelMedium!.copyWith(
        color: fg,
        fontWeight: FontWeight.w600,
      );
      final inner = w - 16;
      if (inner >= 40) {
        canvas.save();
        canvas.clipRRect(rect);
        _text(
          canvas,
          r.task.title,
          Offset(x + 9, i * _rowH + _rowH / 2),
          style,
          maxWidth: inner,
          vCenter: true,
        );
        canvas.restore();
      } else {
        _text(
          canvas,
          r.task.title,
          Offset(x + w + 6, i * _rowH + _rowH / 2),
          style.copyWith(
            color: scheme.onSurfaceVariant.withValues(alpha: r.dim ? .4 : 1),
          ),
          maxWidth: 220,
          vCenter: true,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.rows != rows ||
      old.start != start ||
      old.days != days ||
      old.dayW != dayW ||
      old.scheme != scheme;
}

void _text(
  Canvas canvas,
  String s,
  Offset at,
  TextStyle style, {
  bool centered = false,
  bool vCenter = false,
  double maxWidth = double.infinity,
}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  var o = at;
  if (centered) o = at - Offset(tp.width / 2, tp.height / 2);
  if (vCenter) o = Offset(at.dx, at.dy - tp.height / 2);
  tp.paint(canvas, o);
  tp.dispose();
}
