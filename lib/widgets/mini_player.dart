import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/haptics.dart';
import '../models/track.dart';
import 'cached_cover_image.dart';
import 'marquee_text.dart';

/// The docked player bar.
///
/// Design notes:
///  * A solid, softly-lit card rather than a `BackdropFilter`. Real-time blur
///    over the whole page cost a full GPU layer pass every frame and was the
///    root of the Android foreground-erasure bug; a tuned opaque surface with a
///    top sheen and a deep shadow reads just as "glassy" and costs nothing.
///  * Progress is a hairline seated on the bottom edge of the card and clipped
///    to its radius, so it belongs to the card instead of floating above it.
///  * The whole bar is a target: tap or swipe up to expand, swipe sideways to
///    change track.
class MiniPlayer extends StatelessWidget {
  final Track? currentTrack;
  final bool isPlaying;
  final ValueNotifier<Duration> positionNotifier;
  final ValueNotifier<Duration> durationNotifier;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback? onPrevious;
  final VoidCallback onTap;

  const MiniPlayer({
    super.key,
    required this.currentTrack,
    required this.isPlaying,
    required this.positionNotifier,
    required this.durationNotifier,
    required this.onPlayPause,
    required this.onNext,
    this.onPrevious,
    required this.onTap,
  });

  /// Card height, excluding the bottom inset the parent reserves.
  static const double contentHeight = 64.0;
  static const double _radius = 22.0;

  /// Bottom gap below the card: the home-indicator inset, or a small margin on
  /// devices that have none.
  static double bottomGap(BuildContext context) {
    final inset = MediaQuery.of(context).padding.bottom;
    return inset > 0 ? inset : 10;
  }

  /// Total space the docked player occupies — the single source of truth for
  /// every layout that has to stop above it.
  static double totalHeight(BuildContext context) =>
      contentHeight + bottomGap(context);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomGap(context)),
      child: SizedBox(
        height: contentHeight,
        child: currentTrack == null ? _emptyState() : _activePlayer(),
      ),
    );
  }

  /// One flat surface, one hairline, one soft shadow. No gradient, no sheen —
  /// stacking those on a 64pt bar is what made it read as busy.
  Widget _shell({required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: const [
          BoxShadow(color: AppColors.black45, blurRadius: 20, offset: Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF17171B),
            border: Border.all(color: AppColors.hairline),
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _emptyState() {
    return _shell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.music_note_rounded,
                  color: AppColors.textFaint, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('选一首歌开始播放',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activePlayer() {
    final track = currentTrack!;
    return GestureDetector(
      onTap: onTap,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -180) {
          Haptics.selection();
          onTap();
        }
      },
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -220) {
          Haptics.selection();
          onNext();
        } else if (v > 220 && onPrevious != null) {
          Haptics.selection();
          onPrevious!();
        }
      },
      child: _shell(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedCoverImage(
                      url: track.coverUrl,
                      width: 44,
                      height: 44,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        MarqueeText(
                          text: track.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        MarqueeText(
                          text: track.uploader,
                          phase: 0.35,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Two bare icons of equal weight. The filled circle around
                  // play was the heaviest thing on the bar and fought the
                  // artwork for attention.
                  _iconButton(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    onPressed: () {
                      Haptics.light();
                      onPlayPause();
                    },
                    color: AppColors.textPrimary,
                    animateSwap: true,
                  ),
                  _iconButton(
                    Icons.skip_next_rounded,
                    onPressed: () {
                      Haptics.selection();
                      onNext();
                    },
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: RepaintBoundary(child: _progressLine()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconButton(
    IconData icon, {
    required VoidCallback onPressed,
    required Color color,
    bool animateSwap = false,
  }) {
    final glyph = Icon(icon, key: ValueKey(icon), color: color, size: 28);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: animateSwap
              ? AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: glyph,
                )
              : glyph,
        ),
      ),
    );
  }

  Widget _progressLine() {
    return AnimatedBuilder(
      animation: Listenable.merge([positionNotifier, durationNotifier]),
      builder: (context, _) {
        final dur = durationNotifier.value.inMilliseconds;
        final progress = dur > 0
            ? (positionNotifier.value.inMilliseconds / dur).clamp(0.0, 1.0)
            : 0.0;
        return SizedBox(
          height: 2,
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: AppColors.hairline),
              ),
              FractionallySizedBox(
                widthFactor: progress,
                alignment: Alignment.centerLeft,
                child: const ColoredBox(color: AppColors.accent),
              ),
            ],
          ),
        );
      },
    );
  }
}
