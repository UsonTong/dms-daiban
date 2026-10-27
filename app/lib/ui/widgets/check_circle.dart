import 'package:flutter/material.dart';

Color? priorityColor(int p) => switch (p) {
  3 => const Color(0xFFF08C00),
  4 => const Color(0xFFE8590C),
  5 => const Color(0xFFE03131),
  _ => null,
};

const priorityNames = ['无', '低', '中', '高', '紧急', '立即'];

/// 圆形勾选框，边框颜色表示优先级
class CheckCircle extends StatelessWidget {
  final bool checked;
  final int priority;
  final VoidCallback? onTap;
  final double size;

  const CheckCircle({
    super.key,
    required this.checked,
    this.priority = 0,
    this.onTap,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ring = priorityColor(priority) ?? scheme.outline;
    return Semantics(
      checked: checked,
      button: true,
      child: InkResponse(
        onTap: onTap,
        radius: size,
        child: SizedBox.square(
          dimension: size + 22,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked
                    ? scheme.primary
                    : (priority >= 3
                          ? ring.withValues(alpha: .10)
                          : Colors.transparent),
                border: Border.all(
                  color: checked ? scheme.primary : ring,
                  width: 2,
                ),
              ),
              child: AnimatedScale(
                scale: checked ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: Icon(
                  Icons.check_rounded,
                  size: size - 6,
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
