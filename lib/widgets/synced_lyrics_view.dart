import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/lyric_line.dart';

/// Synced lyrics view that highlights & auto-scrolls to the active line.
class SyncedLyricsView extends StatefulWidget {
  final List<LyricLine> lines;
  final ValueNotifier<Duration> positionNotifier;
  final Function(double position)? onSeek;
  final VoidCallback? onOpenEditor;
  final double offset;

  const SyncedLyricsView({
    super.key,
    required this.lines,
    required this.positionNotifier,
    this.onSeek,
    this.onOpenEditor,
    this.offset = 0.0,
  });

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _activeIndex = 0;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

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
    if (oldWidget.lines != widget.lines || oldWidget.offset != widget.offset) {
      _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
      _onPosition(force: true);
    }
  }

  @override
  void dispose() {
    widget.positionNotifier.removeListener(_onPosition);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPosition({bool force = false}) {
    if (widget.lines.isEmpty) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastUpdate).inMilliseconds < 150) return;
    _lastUpdate = now;

    final posSec = (widget.positionNotifier.value.inMilliseconds / 1000.0) - widget.offset;
    final newIndex = _findActiveIndex(posSec);
    if (newIndex != _activeIndex || force) {
      setState(() => _activeIndex = newIndex);
      _scrollToActive();
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

  void _scrollToActive() {
    if (!_scrollController.hasClients || widget.lines.isEmpty) return;

    double accumulatedOffset = 0.0;
    for (int i = 0; i < _activeIndex && i < widget.lines.length; i++) {
      accumulatedOffset += _estimateItemHeight(widget.lines[i], false);
    }

    final activeItemHeight = _estimateItemHeight(widget.lines[_activeIndex], true);
    final viewportDimension = _scrollController.position.viewportDimension;
    final targetOffset = accumulatedOffset - (viewportDimension / 2) + (activeItemHeight / 2);

    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  double _estimateItemHeight(LyricLine line, bool isActive) {
    double height = 24.0; // vertical padding: 12 + 12
    final mainFontSize = isActive ? 23.0 : 18.0;
    final textLen = line.text.length;
    final lineCount = (textLen / 14.0).ceil().clamp(1, 5);
    height += lineCount * (mainFontSize * 1.35);

    if (line.translation != null && line.translation!.isNotEmpty) {
      height += 4.0;
      final transFontSize = isActive ? 16.0 : 14.0;
      final transLen = line.translation!.length;
      final transLineCount = (transLen / 18.0).ceil().clamp(1, 5);
      height += transLineCount * (transFontSize * 1.35);
    }

    return height;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) {
      return const Center(
        child: Text(
          '暂无同步歌词',
          style: TextStyle(color: AppColors.textMuted, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 40, bottom: 200, left: 24, right: 24),
      itemCount: widget.lines.length,
      itemBuilder: (context, index) {
        final line = widget.lines[index];
        final isActive = index == _activeIndex;

        return GestureDetector(
          onTap: () {
            if (widget.onSeek != null) {
              widget.onSeek!(line.time + widget.offset);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    color: isActive
                        ? AppColors.textPrimary
                        : AppColors.textPrimary35,
                    fontSize: isActive ? 23 : 18,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                    letterSpacing: isActive ? -0.3 : 0.0,
                    shadows: isActive
                        ? [
                            const Shadow(
                              color: AppColors.accent55,
                              blurRadius: 22,
                            ),
                            const Shadow(
                              color: AppColors.white35,
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: Text(line.text),
                ),
                if (line.translation != null &&
                    line.translation!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    line.translation!,
                    style: TextStyle(
                      color: isActive
                          ? AppColors.accent
                          : AppColors.textFaint,
                      fontSize: isActive ? 16 : 14,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
