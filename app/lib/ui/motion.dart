import 'package:flutter/material.dart';

/// Material 动效规范里的几种过渡，自己实现以免依赖与 Material 拆包冲突的 animations 库。
/// 规范：https://m3.material.io/styles/motion/transitions/transition-patterns

const _fadeThroughDuration = Duration(milliseconds: 300);

/// 淡出淡入的两段曲线：旧页面在前 30% 淡出，新页面在后 70% 淡入并从 92% 放大到 100%
const _outCurve = Interval(0, .3, curve: Curves.easeOut);
const _inCurve = Interval(.3, 1, curve: Curves.easeOutCubic);

/// 像 IndexedStack 一样保留每页状态（滚动位置等），切换时做淡出淡入
class FadeThroughStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const FadeThroughStack({
    super.key,
    required this.index,
    required this.children,
  });

  @override
  State<FadeThroughStack> createState() => _FadeThroughStackState();
}

class _FadeThroughStackState extends State<FadeThroughStack>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: _fadeThroughDuration,
    value: 1,
  );
  late int _prev = widget.index;

  @override
  void didUpdateWidget(FadeThroughStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _prev = old.index;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final animating = _c.isAnimating;
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              // 每一页的组件结构保持不变，只改参数，切换时状态不会丢
              KeyedSubtree(
                key: ValueKey(i),
                child: _Slot(
                  visible: i == widget.index || (animating && i == _prev),
                  interactive: i == widget.index,
                  opacity: i == widget.index
                      ? _inCurve.transform(t)
                      : 1 - _outCurve.transform(t),
                  scale: i == widget.index
                      ? .92 + .08 * _inCurve.transform(t)
                      : 1,
                  child: widget.children[i],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Slot extends StatelessWidget {
  final bool visible;
  final bool interactive;
  final double opacity;
  final double scale;
  final Widget child;

  const _Slot({
    required this.visible,
    required this.interactive,
    required this.opacity,
    required this.scale,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: IgnorePointer(
          ignoring: !interactive,
          child: Opacity(
            opacity: opacity.clamp(0, 1),
            child: Transform.scale(scale: scale, child: child),
          ),
        ),
      ),
    );
  }
}

/// 换掉整个子组件（按 key 区分）时做淡出淡入，不保留旧组件状态
class FadeThroughSwitcher extends StatelessWidget {
  final Widget child;
  const FadeThroughSwitcher({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _fadeThroughDuration,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (c, animation) {
        // AnimatedSwitcher 给新组件正放、旧组件倒放同一段动画
        final incoming = c.key == child.key;
        return AnimatedBuilder(
          animation: animation,
          child: c,
          builder: (context, c) {
            final t = animation.value;
            final opacity = incoming
                ? _inCurve.transform(t)
                : const Interval(.7, 1, curve: Curves.easeIn).transform(t);
            final scale = incoming ? .92 + .08 * _inCurve.transform(t) : 1.0;
            return IgnorePointer(
              ignoring: !incoming,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(scale: scale, child: c),
              ),
            );
          },
        );
      },
      child: child,
    );
  }
}

/// 进入下一级页面：新页面从右侧 30dp 滑入并淡入，旧页面向左滑出并淡出
class SharedAxisPageTransitionsBuilder extends PageTransitionsBuilder {
  const SharedAxisPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        final inT = Curves.easeInOutCubic.transform(animation.value);
        final outT = Curves.easeInOutCubic.transform(secondaryAnimation.value);
        final dx = 30 * (1 - inT) - 30 * outT;
        final opacity =
            const Interval(.3, 1).transform(animation.value) *
            (1 - const Interval(0, .3).transform(secondaryAnimation.value));
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Opacity(opacity: opacity, child: child),
        );
      },
    );
  }
}

/// 对话框：淡入 + 从 80% 放大，出场只淡出（规范里的 fade 模式）
Future<T?> showFadeScaleDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, _, _) => builder(context),
    transitionBuilder: (context, animation, _, child) => AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final reversing = animation.status == AnimationStatus.reverse;
        final scale = reversing
            ? 1.0
            : .8 + .2 * Curves.easeOutCubic.transform(animation.value);
        return Opacity(
          opacity: animation.value,
          child: Transform.scale(scale: scale, child: child),
        );
      },
    ),
  );
}
