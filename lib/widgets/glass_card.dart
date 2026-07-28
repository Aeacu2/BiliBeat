import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// An elegant translucent surface.
///
/// Instead of an expensive [BackdropFilter] on every card (which looks muddy
/// when many are on screen, costs a full GPU layer pass, and on Android was the
/// cause of the foreground-erasure bug), this uses a subtle top-lit sheen — a
/// faint vertical white gradient — plus a hairline border. That is the quiet,
/// refined look premium apps actually ship.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.surfaceHighlight, AppColors.surfaceCard],
        ),
        border: Border.all(color: AppColors.hairline, width: 1),
      ),
      child: child,
    );
  }
}
