import 'package:flutter/material.dart';

/// A clean, robust single-line text widget with smooth ellipsizing overflow
/// that never breaks parent Column flex constraints or causes post-frame layout collapse.
class MarqueeText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final bool scrolling;

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.scrolling = true,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}
