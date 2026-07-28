import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Apple Music–style circular download progress ring with an optional center
/// child (e.g. a download / stop icon).
class ProgressRing extends StatelessWidget {
  final double fraction; // 0..1
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color trackColor;
  final Widget? child;

  const ProgressRing({
    super.key,
    required this.fraction,
    this.size = 24,
    this.strokeWidth = 2.5,
    this.color,
    this.trackColor = const Color(0x33FFFFFF),
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accent;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              strokeWidth: strokeWidth,
              backgroundColor: trackColor,
              valueColor: AlwaysStoppedAnimation<Color>(c),
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}
