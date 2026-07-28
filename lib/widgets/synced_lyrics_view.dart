import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/haptics.dart';
import '../models/lyric_line.dart';

/// Synced lyrics that highlight and auto-scroll to the active line.
///
/// Two things make this feel right rather than merely functional:
///  * Browsing wins. While the user is scrolling, auto-scroll yields and a
///    "回到当前" pill appears; it resumes on its own a few seconds later.
///    Previously every position tick yanked the list back, so reading ahead
///    was impossible.
///  * Lines are centred against *measured* heights and viewport-proportional
///    padding, so the first and last lines can reach the middle too.
class SyncedLyricsView extends StatefulWidget {
  final List<LyricLine> lines;
  final ValueNotifier<Duration> positionNotifier;
  final Function(double position)? onSeek;
  final VoidCallback? onOpenEditor;
  final double offset;

  /// Calibration mode, armed by the parent. While it is on, a vertical drag
  /// moves the *timeline* instead of scrolling, and a guide marks the line the
  /// drag is measured against.
  ///
  /// It is a mode rather than a long-press because the two gestures cannot
  /// share a pointer: a long-press recogniser wins the arena whenever a finger
  /// rests before it moves, which is exactly how people scroll — so browsing
  /// the lyrics kept turning into an accidental calibration.
  final bool calibrating;

  /// Called once per drag with how many seconds the timeline should move
  /// (positive = the lyrics were early and need delaying).
  final void Function(double deltaSeconds)? onCalibrate;

  /// Whether the view should follow playback. False for a preview driven by a
  /// clock that never advances, where auto-scrolling back to 0:00 five seconds
  /// after every scroll makes the lyrics impossible to read.
  final bool autoFollow;

  const SyncedLyricsView({
    super.key,
    required this.lines,
    required this.positionNotifier,
    this.onSeek,
    this.onOpenEditor,
    this.offset = 0.0,
    this.calibrating = false,
    this.onCalibrate,
    this.autoFollow = true,
  });

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, double> _heightCache = {};

  int _activeIndex = 0;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  /// While true the user is in control and auto-scroll stands down.
  bool _userBrowsing = false;
  Timer? _resumeTimer;

  /// Live finger travel during a calibration drag. The list is translated by
  /// it, and the amount of lyric-time that travel corresponds to is the
  /// correction.
  double _dragDy = 0.0;


  double _viewportHeight = 400;
  double _topPadding = 160;
  double _lineWidth = 320;

  static const Duration _browseGrace = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    widget.positionNotifier.addListener(_onPosition);
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionNotifier != widget.positionNotifier) {
      oldWidget.positionNotifier.removeListener(_onPosition);
      widget.positionNotifier.addListener(_onPosition);
    }
    if (oldWidget.calibrating != widget.calibrating) _dragDy = 0.0;
    if (oldWidget.lines != widget.lines || oldWidget.offset != widget.offset) {
      _heightCache.clear();
      _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
      // Re-centring here would undo the drag the user just made: the offset
      // changing *is* the result of that drag.
      _onPosition(force: true, keepPosition: widget.calibrating);
    }
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    widget.positionNotifier.removeListener(_onPosition);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPosition({bool force = false, bool keepPosition = false}) {
    if (widget.lines.isEmpty) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastUpdate).inMilliseconds < 150) return;
    _lastUpdate = now;

    final posSec =
        (widget.positionNotifier.value.inMilliseconds / 1000.0) - widget.offset;
    final newIndex = _findActiveIndex(posSec);
    if (newIndex != _activeIndex || force) {
      setState(() => _activeIndex = newIndex);
      if (widget.autoFollow && !_userBrowsing && !keepPosition) {
        _scrollToActive();
      }
    }
  }

  int _findActiveIndex(double posSec) {
    final lines = widget.lines;
    int lo = 0;
    int hi = lines.length - 1;
    int ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time <= posSec) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  void _beginBrowsing() {
    _resumeTimer?.cancel();
    if (!_userBrowsing && mounted) setState(() => _userBrowsing = true);
  }

  void _scheduleResume() {
    if (!widget.autoFollow) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_browseGrace, _resumeFollowing);
  }

  void _resumeFollowing() {
    _resumeTimer?.cancel();
    if (!mounted) return;
    setState(() => _userBrowsing = false);
    _scrollToActive();
  }

  void _scrollToActive({bool animate = true}) {
    if (!_scrollController.hasClients || widget.lines.isEmpty) return;

    double accumulated = 0.0;
    for (int i = 0; i < _activeIndex && i < widget.lines.length; i++) {
      accumulated += _itemHeight(widget.lines[i], false);
    }

    final activeHeight = _itemHeight(widget.lines[_activeIndex], true);
    // Content offset includes the leading padding, which the old version
    // forgot — every line settled a padding's worth above centre.
    final target = _topPadding +
        accumulated -
        (_viewportHeight / 2) +
        (activeHeight / 2);
    final clamped =
        target.clamp(0.0, _scrollController.position.maxScrollExtent);

    if (!animate) {
      _scrollController.jumpTo(clamped);
      return;
    }
    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  // ---------------------------------------------------------------------------
  // Timeline calibration by dragging
  // ---------------------------------------------------------------------------

  bool get _canCalibrate =>
      widget.calibrating && widget.onCalibrate != null && widget.lines.isNotEmpty;

  /// The scroll offset of the middle of the viewport — the line the guide sits
  /// on, and therefore what the drag is measured against.
  double get _anchorContentY =>
      (_scrollController.hasClients ? _scrollController.offset : 0.0) +
      _viewportHeight / 2;

  /// Inverse of the list layout: which lyric time is drawn at content offset
  /// [y]. Interpolated inside a line so the drag is smooth rather than
  /// snapping between lines.
  ///
  /// Measures the active line at its *active* height. It is drawn larger than
  /// the rest, so assuming a uniform height put everything below it out by that
  /// difference — and since the active line moves with every correction, the
  /// error changed after each drag and accumulated across a session.
  double _timeAtContentY(double y) {
    final lines = widget.lines;
    double top = _topPadding;
    for (int i = 0; i < lines.length; i++) {
      final h = _itemHeight(lines[i], i == _activeIndex);
      if (y < top + h) {
        final start = lines[i].time;
        final end = i + 1 < lines.length ? lines[i + 1].time : start + 4.0;
        final fraction = ((y - top) / h).clamp(0.0, 1.0);
        return start + (end - start) * fraction;
      }
      top += h;
    }
    return lines.last.time;
  }

  /// How much lyric-time a drag of [dy] pixels is worth: the difference between
  /// what sits under the guide now and what would sit under it after the drag.
  ///
  /// Deliberately *relative*. Measuring against the playhead instead — "the
  /// line you dragged onto the guide should be singing now" — is only defined
  /// while the track is actually playing; in a preview, whose clock sits at
  /// 0:00, it turned every drag into an offset of minus-however-far-into-the-
  /// song-you-had-scrolled. A displacement is the same correction in both
  /// cases, because the guide already sits on the line the timeline currently
  /// claims is playing.
  double _deltaForDrag(double dy) {
    if (widget.lines.isEmpty) return 0.0;
    final anchor = _anchorContentY;
    return _timeAtContentY(anchor) - _timeAtContentY(anchor - dy);
  }

  /// The total correction as it stands, including the drag in progress — the
  /// same number the editor shows, rather than a per-session tally that reset
  /// every time calibration was re-armed.
  double get _pendingDelta => widget.offset + _deltaForDrag(_dragDy);

  void _onCalibrationDrag(DragUpdateDetails details) {
    setState(() => _dragDy += details.delta.dy);
  }

  /// Commits the drag. The list is scrolled to where the finger left the
  /// content and the transform is reset, so the line the user dragged onto the
  /// guide stays there instead of springing back the moment they let go.
  void _endCalibrationDrag() {
    final dy = _dragDy;
    if (dy == 0) return;

    // The correction is what the finger asked for. Scrolling by the same
    // amount keeps the line the user dragged onto the guide sitting there,
    // but only as far as the list can travel — at either end it simply cannot,
    // and the correction must not be silently swallowed with it.
    final delta = _deltaForDrag(dy);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo((_scrollController.offset - dy)
          .clamp(0.0, _scrollController.position.maxScrollExtent));
    }
    setState(() => _dragDy = 0.0);
    if (delta.abs() >= 0.01) {
      Haptics.selection();
      widget.onCalibrate!(double.parse(delta.toStringAsFixed(2)));
    }
  }

  /// Measured row height, memoised per (text, state, width).
  double _itemHeight(LyricLine line, bool isActive) {
    final key = '${line.text} ${line.translation ?? ''} $isActive'
        ' ${_lineWidth.round()}';
    final cached = _heightCache[key];
    if (cached != null) return cached;

    double height = 28.0; // vertical padding: 14 + 14
    height += _measureText(line.text, isActive ? 24.0 : 20.0,
        isActive ? FontWeight.w700 : FontWeight.w600);
    if (line.translation != null && line.translation!.isNotEmpty) {
      height += 4.0;
      height += _measureText(line.translation!, isActive ? 16.0 : 14.0,
          FontWeight.w500);
    }

    if (_heightCache.length > 400) _heightCache.clear();
    _heightCache[key] = height;
    return height;
  }

  double _measureText(String text, double fontSize, FontWeight weight) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, fontWeight: weight, height: 1.35),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _lineWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) return _emptyState();

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportHeight = constraints.maxHeight;
        _lineWidth = constraints.maxWidth;
        // Enough padding that the very first and very last lines can still
        // reach the middle of the viewport.
        _topPadding = _viewportHeight * 0.42;

        return Stack(
          children: [
            // Armed: the drag moves the timeline and the list is frozen.
            // Otherwise the list scrolls exactly as it always did.
            GestureDetector(
              onVerticalDragUpdate: _canCalibrate ? _onCalibrationDrag : null,
              onVerticalDragEnd:
                  _canCalibrate ? (_) => _endCalibrationDrag() : null,
              onVerticalDragCancel:
                  _canCalibrate ? _endCalibrationDrag : null,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification &&
                      notification.dragDetails != null) {
                    _beginBrowsing();
                  } else if (notification is ScrollEndNotification &&
                      _userBrowsing) {
                    _scheduleResume();
                  }
                  return false;
                },
                child: Transform.translate(
                  offset: Offset(0, _dragDy),
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: _canCalibrate
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    padding: EdgeInsets.only(
                      top: _topPadding,
                      bottom: _viewportHeight * 0.5,
                    ),
                    itemCount: widget.lines.length,
                    itemBuilder: (context, index) => _lineTile(index),
                  ),
                ),
              ),
            ),
            if (_canCalibrate) _anchorGuide(),
            if (_canCalibrate)
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: IgnorePointer(child: Center(child: _calibrationHud())),
              )
            else if (_userBrowsing && widget.autoFollow)
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Center(child: _resumePill()),
              ),
          ],
        );
      },
    );
  }

  Widget _lineTile(int index) {
    final line = widget.lines[index];
    final isActive = index == _activeIndex;
    final distance = (index - _activeIndex).abs();
    // Fade lines out with distance so the eye lands on the current one.
    final opacity = isActive
        ? 1.0
        : (distance == 1 ? 0.5 : (distance == 2 ? 0.34 : 0.24));

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: widget.onSeek == null
          ? null
          : () {
              Haptics.selection();
              widget.onSeek!(line.time + widget.offset);
              _resumeFollowing();
            },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 280),
        opacity: opacity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: isActive ? 24 : 20,
                  height: 1.35,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: isActive ? -0.4 : -0.2,
                  // A single soft accent bloom. The old double shadow (22px
                  // accent + 8px white) muddied the glyphs instead of lifting
                  // them.
                  shadows: isActive
                      ? const [Shadow(color: AppColors.accent50, blurRadius: 18)]
                      : null,
                ),
                child: Text(line.text),
              ),
              if (line.translation != null && line.translation!.isNotEmpty) ...[
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 280),
                  style: TextStyle(
                    color: isActive ? AppColors.accent : AppColors.textMuted,
                    fontSize: isActive ? 16 : 14,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                  child: Text(line.translation!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The line the drag is aligning against — without it the gesture has no
  /// visible target and the numbers mean nothing.
  Widget _anchorGuide() {
    return Positioned(
      left: 0,
      right: 0,
      top: _viewportHeight / 2 - 1,
      // Ignores pointers: the guide sits exactly where the finger wants to
      // start its drag, and an opaque overlay there swallows the gesture.
      child: IgnorePointer(
        child: Row(
          children: [
            Container(width: 14, height: 2, color: AppColors.accent),
            Expanded(child: Container(height: 1, color: AppColors.accent30)),
            Container(width: 14, height: 2, color: AppColors.accent),
          ],
        ),
      ),
    );
  }

  Widget _calibrationHud() {
    final delta = _pendingDelta;
    // Say what moved: the *lyrics* are early or late relative to the audio.
    final label = delta >= 0 ? '歌词延迟' : '歌词提前';
    final seconds = delta.abs().toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.backgroundElevated,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.accent30),
        boxShadow: const [
          BoxShadow(color: AppColors.black45, blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: AppColors.accent, size: 15),
          const SizedBox(width: 7),
          Text(
            '$label $seconds 秒',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          const Text('上下拖动歌词对齐',
              style: TextStyle(color: AppColors.textFaint, fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _resumePill() {
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        _resumeFollowing();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.backgroundElevated,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.accent30),
          boxShadow: const [
            BoxShadow(color: AppColors.black45, blurRadius: 16, offset: Offset(0, 4)),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.my_location_rounded, color: AppColors.accent, size: 15),
            SizedBox(width: 6),
            Text('回到当前',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lyrics_outlined, color: AppColors.textFaint, size: 40),
          const SizedBox(height: 12),
          const Text(
            '暂无同步歌词',
            style: TextStyle(color: AppColors.textMuted, fontSize: 16),
          ),
          if (widget.onOpenEditor != null) ...[
            const SizedBox(height: 6),
            const Text(
              '可以搜索、或直接粘贴 .lrc 文本',
              style: TextStyle(color: AppColors.textFaint, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.onOpenEditor,
              icon: const Icon(Icons.search, size: 16),
              label: const Text('搜索或粘贴歌词'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent30),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
