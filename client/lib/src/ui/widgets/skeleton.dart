import 'package:flutter/material.dart';

/// Placeholder rows with the shape of a real row, shown while a list loads
/// (never a spinner for a whole list), at least three. The shimmer takes
/// 1.2 s, linear; under reduced motion it is static.
class SkeletonRows extends StatefulWidget {
  const SkeletonRows({super.key, this.count = 4, this.circleLeading = true});

  final int count;

  /// Whether each row starts with a 40 dp circle, as a producer or person
  /// row does.
  final bool circleLeading;

  @override
  State<SkeletonRows> createState() => _SkeletonRowsState();
}

class _SkeletonRowsState extends State<SkeletonRows>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shimmer.stop();
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Loading',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (context, _) {
          final tone = Color.lerp(
            colors.surfaceContainerHigh,
            colors.surfaceContainerHighest,
            _shimmer.isAnimating ? (1 - (2 * _shimmer.value - 1).abs()) : 0.5,
          )!;
          Widget bar(double width, double height) => Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(height / 2),
            ),
          );
          return Column(
            children: [
              for (var i = 0; i < widget.count; i++)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
                  child: Row(
                    children: [
                      if (widget.circleLeading) ...[
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: tone,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            bar(140 + 20.0 * (i % 3), 14),
                            const SizedBox(height: 8),
                            bar(200 - 20.0 * (i % 2), 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
