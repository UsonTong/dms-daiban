import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// 帧率浮层：Ctrl+Shift+F 开关；环境变量 VMD_FPS=1 时默认打开并每秒往 stdout 打一行统计。
/// 打开期间用 Ticker 持续出帧，测的是引擎实际能跑到的帧率上限。
class FpsOverlay extends StatefulWidget {
  final Widget child;
  const FpsOverlay({super.key, required this.child});

  @override
  State<FpsOverlay> createState() => _FpsOverlayState();
}

class _FpsOverlayState extends State<FpsOverlay>
    with SingleTickerProviderStateMixin {
  static final _envOn = !kIsWeb && Platform.environment['VMD_FPS'] == '1';

  late final Ticker _ticker = createTicker((_) {});
  bool _on = _envOn;
  final _timings = <FrameTiming>[];
  String _label = '';
  DateTime _windowStart = DateTime.now();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    if (_on) _start();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _stop();
    _ticker.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    final k = HardwareKeyboard.instance;
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.keyF &&
        k.isControlPressed &&
        k.isShiftPressed) {
      setState(() => _on ? _stop() : _start());
      return true;
    }
    return false;
  }

  void _start() {
    _on = true;
    _timings.clear();
    _windowStart = DateTime.now();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _ticker.start();
  }

  void _stop() {
    _on = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    if (_ticker.isActive) _ticker.stop();
  }

  void _onTimings(List<FrameTiming> list) {
    _timings.addAll(list);
    final elapsed = DateTime.now().difference(_windowStart);
    if (elapsed < const Duration(seconds: 1) || _timings.isEmpty) return;

    final fps = _timings.length * 1000 / elapsed.inMilliseconds;
    double avg(Duration Function(FrameTiming) f) =>
        _timings.map((t) => f(t).inMicroseconds).reduce((a, b) => a + b) /
        _timings.length /
        1000;
    double worst(Duration Function(FrameTiming) f) =>
        _timings
            .map((t) => f(t).inMicroseconds)
            .reduce((a, b) => a > b ? a : b) /
        1000;
    final build = avg((t) => t.buildDuration),
        raster = avg((t) => t.rasterDuration);
    final worstTotal = worst((t) => t.totalSpan);
    final hz = PlatformDispatcher.instance.views.first.display.refreshRate;

    final line =
        '${fps.toStringAsFixed(0)} fps / ${hz.toStringAsFixed(0)} Hz  '
        'build ${build.toStringAsFixed(2)}ms  raster ${raster.toStringAsFixed(2)}ms  '
        'worst ${worstTotal.toStringAsFixed(1)}ms';
    if (_envOn) stdout.writeln('[fps] $line');
    _timings.clear();
    _windowStart = DateTime.now();
    if (mounted) setState(() => _label = line);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (_on)
          Positioned(
            top: 8,
            right: 8,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    _label.isEmpty ? '测量中…' : _label,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
