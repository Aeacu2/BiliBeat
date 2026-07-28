import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// An elegant translucent surface.
///
/// Instead of an expensive [BackdropFilter] on every card (which looks muddy
/// when many are on screen and costs GPU), this uses a subtle top-lit sheen
/// (a faint vertical white gradient) plus a hairline border — the quiet,
/// refined look of premium apps. Set [blur] to opt into real frosted glass for
/// hero surfaces (mini player, dialogs).
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;
  final bool blur;
  final double elevation;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16.0,
    this.onTap,
    this.blur = false,
    this.elevation = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    Widget content = Container(
      padding: padding ?? const EdgeInsets.all(12),
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.surfaceHighlight, AppColors.surfaceCard],
        ),
        border: Border.all(color: AppColors.hairline, width: 1),
        boxShadow: elevation > 0
            ? [
                BoxShadow(
                  color: AppColors.black35,
                  blurRadius: elevation,
                  offset: Offset(0, elevation * 0.4),
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (blur) {
      content = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: content,
        ),
      );
    }

    if (onTap != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }
}
