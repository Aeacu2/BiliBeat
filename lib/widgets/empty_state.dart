import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A polished empty-state placeholder: an icon medallion over a soft accent
/// glow, plus a title and optional subtitle. Used wherever a list can be empty.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final double medallionSize;
  final EdgeInsetsGeometry padding;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.medallionSize = 84,
    this.padding = const EdgeInsets.symmetric(vertical: 32),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: medallionSize,
            height: medallionSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [
                  AppColors.accent22,
                  AppColors.accent04,
                ],
              ),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Icon(
              icon,
              size: medallionSize * 0.42,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.headline,
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
          ],
        ],
      ),
    );
  }
}
