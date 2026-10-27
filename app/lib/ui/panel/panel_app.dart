import 'dart:async';
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/dates.dart';
import '../../utils/zone.dart';
import '../app_theme.dart';
import '../gantt/gantt_page.dart';
import '../motion.dart';
import '../widgets/quick_add_field.dart';
import '../widgets/task_sections.dart';
import '../widgets/folded_tasks.dart';

/// 和 linux/runner/panel_mode.cc 通信：setInteractive 切换鼠标穿透/键盘独占，toggle 由快捷键触发
const _channel = MethodChannel('vikunja_md/panel');

// 卡片大小；卡片所在的窗口四周再留出阴影的边距
const _listCard = Size(560, 680);
const _ganttCard = Size(1280, 800);
const _shadowMargin = 24.0;

/// Mod+D 弹出的"今天"面板：常驻后台的独立进程，界面组件和完整应用完全相同
void runPanel({required bool showOnStart}) {
  final state = AppState(panel: true);
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: PanelApp(showOnStart: showOnStart),
    ),
  );
  state.init();
}

class PanelApp extends StatelessWidget {
  final bool showOnStart;
  const PanelApp({super.key, required this.showOnStart});

  @override
  Widget build(BuildContext context) {
    return themedApp(
      (light, dark, mode) => MaterialApp(
        title: '待办',
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        color: Colors.transparent,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: _PanelOverlay(showOnStart: showOnStart),
      ),
    );
  }
}

class _PanelOverlay extends StatefulWidget {
  final bool showOnStart;
  const _PanelOverlay({required this.showOnStart});

  @override
  State<_PanelOverlay> createState() => _PanelOverlayState();
}

class _PanelOverlayState extends State<_PanelOverlay>
    with SingleTickerProviderStateMixin {
  // 进场 240ms 减速，退场 160ms，节奏与 DMS 自带弹出层一致
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 160),
  );
  late final _curve = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  bool _open = false;

  /// 列表 / 甘特图；关掉再开保持上次的选择
  bool _gantt = false;

  /// 外层快捷键（Esc）用的焦点和输入框焦点。
  /// 不能靠 autofocus：外层先拿到焦点后，之后每次弹出时输入框的 autofocus 都会被忽略
  final _rootFocus = FocusNode(debugLabel: 'panel');
  final _inputFocus = FocusNode(debugLabel: 'quick-add');

  /// 每次弹出换一个 key，内容重建：输入框自动聚焦、列表回到顶部
  int _session = 0;

  String? _toast;
  VoidCallback? _toastUndo;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'toggle') _open ? _close() : _show();
      // 点了背景层（卡片外面）
      if (call.method == 'dismiss') _close();
    });
    context.read<AppState>().notify = (msg, {undo}) {
      _toastTimer?.cancel();
      setState(() {
        _toast = msg;
        _toastUndo = undo;
      });
      _toastTimer = Timer(Duration(seconds: undo == null ? 4 : 6), () {
        if (mounted) setState(() => _toast = null);
      });
    };
    if (widget.showOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _show());
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _toastTimer?.cancel();
    _rootFocus.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _show() async {
    final s = context.read<AppState>();
    setState(() {
      _open = true;
      _session++;
      _toast = null;
    });
    await _channel.invokeMethod('setInteractive', true);
    _traceFrames();
    _c.forward();
    // 等新的卡片建好再把光标放进输入框；没有输入框（未配置）时至少让 Esc 能用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_open) return;
      if (_inputFocus.context != null) {
        _inputFocus.requestFocus();
      } else {
        _rootFocus.requestFocus();
      }
    });
    s.loadPanelConfig();
    s.refresh(silent: s.tasks.isNotEmpty);
  }

  Future<void> _close() async {
    if (!_open) return;
    // 有编辑器等对话框开着时一起关掉
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _open = false);
    await _c.reverse();
    if (!_open) await _channel.invokeMethod('setInteractive', false);
  }

  /// VMD_FPS=1 时打印弹出动画期间每一帧的耗时，排查卡顿用
  void _traceFrames() {
    if (Platform.environment['VMD_FPS'] != '1') return;
    final frames = <FrameTiming>[];
    void cb(List<FrameTiming> list) => frames.addAll(list);
    SchedulerBinding.instance.addTimingsCallback(cb);
    // release 模式下帧数据每秒才批量回报一次，多等一会儿；只看首帧之后 300ms（动画本身）
    Future.delayed(const Duration(milliseconds: 2500), () {
      SchedulerBinding.instance.removeTimingsCallback(cb);
      if (frames.isEmpty) return stdout.writeln('[open] 无帧');
      int ts(FrameTiming f) => f.timestampInMicroseconds(FramePhase.vsyncStart);
      final t0 = ts(frames.first);
      final anim = frames.where((f) => ts(f) - t0 <= 300000).toList();
      final gaps = [
        for (var i = 1; i < anim.length; i++)
          (ts(anim[i]) - ts(anim[i - 1])) / 1000,
      ];
      final worst = anim
          .map((f) => f.totalSpan.inMicroseconds / 1000)
          .reduce((a, b) => a > b ? a : b);
      String avg(Duration Function(FrameTiming) f) =>
          (anim.map((x) => f(x).inMicroseconds).reduce((a, b) => a + b) /
                  anim.length /
                  1000)
              .toStringAsFixed(1);
      stdout.writeln(
        '[open] 平均 build ${avg((f) => f.buildDuration)}ms  raster ${avg((f) => f.rasterDuration)}ms  '
        '${anim.length} 帧/300ms  最慢一帧 ${worst.toStringAsFixed(1)}ms  '
        '间隔 ${gaps.map((g) => g.toStringAsFixed(1)).join(' ')}',
      );
    });
  }

  /// 卡片窗口只有卡片那么大（大表面每帧开销高，帧率上不去），切甘特图要先改窗口：
  /// 变大时先放大窗口再让卡片动画长大；变小时先让卡片缩回去再缩窗口
  Future<void> _setGantt(bool on) async {
    if (on == _gantt) return;
    Size window(Size card) =>
        Size(card.width + _shadowMargin * 2, card.height + _shadowMargin * 2);
    if (on) {
      final w = window(_ganttCard);
      await _channel.invokeMethod('setCardSize', [
        w.width.round(),
        w.height.round(),
      ]);
      if (mounted) setState(() => _gantt = true);
    } else {
      setState(() => _gantt = false);
      await Future.delayed(const Duration(milliseconds: 300));
      if (!_gantt) {
        final w = window(_listCard);
        await _channel.invokeMethod('setCardSize', [
          w.width.round(),
          w.height.round(),
        ]);
      }
    }
  }

  Future<void> _openFullApp() async {
    await _close();
    final home = Platform.environment['HOME'];
    await Process.start(
      '$home/.local/bin/daiban',
      [],
      mode: ProcessStartMode.detached,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 窗口就是卡片加阴影边距；屏幕不够大时原生端会把窗口夹小，这里跟着夹
    final size = MediaQuery.sizeOf(context);
    final target = _gantt ? _ganttCard : _listCard;
    final width = target.width.clamp(200.0, size.width - _shadowMargin * 2);
    final height = target.height.clamp(200.0, size.height - _shadowMargin * 2);

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        focusNode: _rootFocus,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, card) {
            // 完全收起时留一个看不见的像素：画面空了 Flutter 会跳过提交，
            // 屏幕上就会残留淡出前最后一帧的影子
            if (_c.isDismissed) {
              return const Align(
                alignment: Alignment.topLeft,
                child: SizedBox.square(
                  dimension: 1,
                  child: ColoredBox(color: Color(0x01000000)),
                ),
              );
            }
            final t = _curve.value;
            return Stack(
              children: [
                // 卡片四周阴影边距是透明的，点到也算"外面"（更外面由原生背景层接住）
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                  ),
                ),
                // 像对话框那样淡入并轻微放大；窗口本身由合成器居中
                Align(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    width: width,
                    height: height,
                    child: Opacity(
                      opacity: t,
                      child: Transform.scale(scale: .94 + .06 * t, child: card),
                    ),
                  ),
                ),
              ],
            );
          },
          // 收起时立刻藏掉悬停提示，免得卡片淡出后提示还留在屏幕上
          child: TooltipVisibility(
            visible: _open,
            child: _PanelCard(
              key: ValueKey(_session),
              inputFocus: _inputFocus,
              onClose: _close,
              onOpenFullApp: _openFullApp,
              gantt: _gantt,
              onGantt: _setGantt,
              toast: _toast,
              toastUndo: _toastUndo,
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  final FocusNode inputFocus;
  final VoidCallback onClose;
  final VoidCallback onOpenFullApp;
  final bool gantt;
  final ValueChanged<bool> onGantt;
  final String? toast;
  final VoidCallback? toastUndo;

  const _PanelCard({
    super.key,
    required this.inputFocus,
    required this.onClose,
    required this.onOpenFullApp,
    required this.gantt,
    required this.onGantt,
    required this.toast,
    required this.toastUndo,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = nowWall();
    final overdue = s.overdue, today = s.dueToday;
    final summary =
        s.panelError ??
        (overdue.isEmpty && today.isEmpty
            ? '${now.month}月${now.day}日 ${weekdayName(now)}'
            : '${now.month}月${now.day}日 ${weekdayName(now)} · '
                  '${today.length + overdue.length} 项${overdue.isNotEmpty ? '，逾期 ${overdue.length}' : ''}');
    final sections = todaySections(context, s);
    final empty = sections.every((x) => x.tasks.isEmpty);

    return Material(
      color: scheme.surfaceContainerLow,
      elevation: 12,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('今天', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        style: theme.textTheme.labelLarge!.copyWith(
                          color: s.panelError != null
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.checklist_rounded),
                      tooltip: '列表',
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.view_timeline_outlined),
                      tooltip: '甘特图',
                    ),
                  ],
                  selected: {gantt},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (v) => onGantt(v.first),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '打开完整应用',
                  icon: const Icon(Icons.open_in_new_rounded),
                  onPressed: onOpenFullApp,
                ),
                IconButton(
                  tooltip: '收起（Esc）',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          if (s.panelError == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: QuickAddField(focusNode: inputFocus),
            ),
          Expanded(
            child: FadeThroughSwitcher(
              child: gantt
                  ? const GanttPage(key: ValueKey('gantt'), embedded: true)
                  : KeyedSubtree(
                      key: const ValueKey('list'),
                      child: CustomScrollView(
                        slivers: [
                          if (s.loading && s.tasks.isEmpty)
                            const SliverToBoxAdapter(
                              child: LinearProgressIndicator(),
                            )
                          else if (empty && s.panelError == null) ...[
                            // 铺满剩余空间的空状态要放最后
                            const DoneTodaySliver(),
                            const EmptyState(
                              icon: Icons.wb_sunny_outlined,
                              text: '今天没有待办，轻松一下',
                            ),
                          ] else ...[
                            TaskSectionsSliver(sections: sections),
                            const SliverPadding(
                              padding: EdgeInsets.only(top: 8),
                            ),
                            const DoneTodaySliver(),
                          ],
                          const SliverPadding(
                            padding: EdgeInsets.only(bottom: 12),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: toast == null
                ? const SizedBox(width: double.infinity)
                : Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                    decoration: BoxDecoration(
                      color: scheme.inverseSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            toast!,
                            style: TextStyle(color: scheme.onInverseSurface),
                          ),
                        ),
                        if (toastUndo != null)
                          TextButton(
                            onPressed: toastUndo,
                            child: Text(
                              '撤销',
                              style: TextStyle(color: scheme.inversePrimary),
                            ),
                          )
                        else
                          const SizedBox(height: 40),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
