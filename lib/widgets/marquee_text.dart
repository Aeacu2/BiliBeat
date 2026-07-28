import 'package:flutter/material.dart';

/// A single-line text that gently scrolls when — and only when — it is too wide
/// for the space it was given, with soft fade-outs at both edges.
///
/// ## Why this is written the way it is
///
/// The previous marquee measured its text in a post-frame callback and called
/// `setState`, which changed the widget's own size *after* layout had already
/// completed. Inside a `Column` (mini player / now-playing panel) that pushed
/// the siblings around and, in the worst case, collapsed the whole panel. This
/// implementation is structurally incapable of doing that:
///
///  * The height is derived synchronously from a [TextPainter] during `build`,
///    so the widget reports a stable, correct size on the very first layout
///    pass and never changes it afterwards.
///  * The overflow amount is computed in the same synchronous pass from the
///    incoming [BoxConstraints] — no measurement round-trip.
///  * The scroll itself is a [Transform.translate] driven by an
///    [AnimationController]. A transform is a paint-time effect: it can never
///    feed back into layout, so the parent `Column` is never disturbed.
///  * The controller is only ever started/stopped from a post-frame callback,
///    and starting it does not call `setState`.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  /// When false the text is parked at its start position (still ellipsized if
  /// it overflows). Typically wired to "is this track actually playing".
  final bool scrolling;

  /// Scroll speed in logical pixels per second.
  final double velocity;

  /// Blank space between the end of the text and the start of its repeat.
  final double gap;

  /// How long to dwell at the start of each cycle before scrolling.
  final Duration startPause;

  /// Alignment used when the text *fits* and no scrolling is needed.
  final TextAlign textAlign;

  /// Soft alpha fade at the leading/trailing edges while scrolling.
  final bool fade;

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.scrolling = true,
    this.velocity = 26,
    this.gap = 44,
    this.startPause = const Duration(milliseconds: 1600),
    this.textAlign = TextAlign.start,
    this.fade = true,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  // Cached measurement so we do not re-run a TextPainter on every build.
  String? _measuredText;
  TextStyle? _measuredStyle;
  double _measuredScale = 1.0;
  Size _measuredSize = Size.zero;

  // Cycle geometry, recomputed in build; read by the animation callback.
  double _travel = 0.0;
  double _pauseFraction = 0.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Size _measure(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    if (_measuredText == widget.text &&
        _measuredStyle == widget.style &&
        _measuredScale == scale) {
      return _measuredSize;
    }
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    _measuredText = widget.text;
    _measuredStyle = widget.style;
    _measuredScale = scale;
    _measuredSize = painter.size;
    painter.dispose();
    return _measuredSize;
  }

  /// Reconciles the controller with the geometry computed during build.
  /// Deferred to after the frame so we never mutate an animation mid-layout;
  /// it touches no layout-affecting state, so it cannot shift the parent.
  void _syncController({required bool shouldRun, required Duration cycle}) {
    if (!mounted) return;
    if (!shouldRun) {
      if (_controller.isAnimating) _controller.stop();
      if (_controller.value != 0) _controller.value = 0;
      return;
    }
    if (_controller.duration != cycle) {
      _controller.duration = cycle;
      _controller.stop();
      _controller.value = 0;
    }
    if (!_controller.isAnimating) _controller.repeat();
  }

  @override
  Widget build(BuildContext context) {
    final textSize = _measure(context);
    // A deterministic single-line height: the widget's size is settled before
    // the first paint and never changes.
    final lineHeight = textSize.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        // Unbounded width (e.g. inside an unconstrained Row) — a marquee has no
        // meaning here, and measuring against infinity would be wrong.
        if (!maxWidth.isFinite) {
          return Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            style: widget.style,
            textAlign: widget.textAlign,
          );
        }

        final overflows = textSize.width > maxWidth + 0.5;
        if (!overflows) {
          _scheduleSync(shouldRun: false, cycle: Duration.zero);
          return SizedBox(
            width: maxWidth,
            height: lineHeight,
            child: Text(
              widget.text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: widget.style,
              textAlign: widget.textAlign,
            ),
          );
        }

        // One cycle scrolls the text plus the gap, so the repeat slides in
        // seamlessly behind it.
        _travel = textSize.width + widget.gap;
        final travelMs = (_travel / widget.velocity * 1000).round();
        final totalMs = travelMs + widget.startPause.inMilliseconds;
        _pauseFraction = totalMs == 0 ? 0 : widget.startPause.inMilliseconds / totalMs;
        final cycle = Duration(milliseconds: totalMs.clamp(1, 600000));

        _scheduleSync(shouldRun: widget.scrolling, cycle: cycle);

        Widget marquee = ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = _controller.value;
                // Dwell at the start, then scroll one full cycle.
                final progress = t <= _pauseFraction
                    ? 0.0
                    : (t - _pauseFraction) / (1.0 - _pauseFraction);
                return Transform.translate(
                  offset: Offset(-progress * _travel, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.text,
                      maxLines: 1, softWrap: false, style: widget.style),
                  SizedBox(width: widget.gap),
                  Text(widget.text,
                      maxLines: 1, softWrap: false, style: widget.style),
                ],
              ),
            ),
          ),
        );

        if (widget.fade) {
          marquee = ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) {
              final fadeStop = (12.0 / rect.width).clamp(0.0, 0.25);
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Color(0x00FFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0x00FFFFFF),
                ],
                stops: [0.0, fadeStop, 1.0 - fadeStop, 1.0],
              ).createShader(rect);
            },
            child: marquee,
          );
        }

        return SizedBox(width: maxWidth, height: lineHeight, child: marquee);
      },
    );
  }

  void _scheduleSync({required bool shouldRun, required Duration cycle}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncController(shouldRun: shouldRun, cycle: cycle);
    });
  }
}
