import 'package:flutter/material.dart';

/// A single-line text that scrolls horizontally when it overflows, but only
/// while [scrolling] is true (e.g. while playing). When not scrolling it shows
/// a normal ellipsized line.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool scrolling;
  final double speed; // pixels per second
  final double blankSpace;

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.scrolling = true,
    this.speed = 40,
    this.blankSpace = 48,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  final GlobalKey _textKey = GlobalKey();
  late final AnimationController _controller;
  double _textWidth = 0;
  bool _measured = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.scrolling != widget.scrolling) {
      _measured = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measure() {
    final box = _textKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    final w = box.size.width;
    if ((w - _textWidth).abs() > 1 || !_measured) {
      _textWidth = w;
      _measured = true;
      final cycle = w + widget.blankSpace;
      final secs = (cycle / widget.speed).clamp(5.0, 30.0);
      _controller
        ..stop()
        ..duration = Duration(milliseconds: (secs * 1000).round())
        ..repeat();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // When not scrolling, behave like a normal ellipsized label.
    if (!widget.scrolling) {
      return Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        final needsScroll = _measured && _textWidth > viewport;
        final cycleWidth = _textWidth + widget.blankSpace;
        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final offset =
                  needsScroll ? -_controller.value * cycleWidth : 0.0;
              return Transform.translate(
                offset: Offset(offset, 0),
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.text,
                        key: _textKey,
                        maxLines: 1,
                        softWrap: false,
                        style: widget.style,
                      ),
                      if (needsScroll) ...[
                        SizedBox(width: widget.blankSpace),
                        Text(
                          widget.text,
                          maxLines: 1,
                          softWrap: false,
                          style: widget.style,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
