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

  Widget _shell({required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: const [
          BoxShadow(color: AppColors.black45, blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1D1D22), Color(0xFF141418)],
            ),
            border: Border.all(color: AppColors.hairlineStrong, width: 0.5),
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
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceHighlight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.music_note_rounded,
                  color: AppColors.textFaint, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('BiliBeat',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2)),
                  SizedBox(height: 2),
                  Text('选一首歌开始播放',
                      style: TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 11.5,
                          letterSpacing: 0.1)),
                ],
              ),
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
              padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedCoverImage(
                      url: track.coverUrl,
                      width: 48,
                      height: 48,
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
                          scrolling: isPlaying,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 1),
                        MarqueeText(
                          text: track.uploader,
                          scrolling: false,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _playButton(),
                  IconButton(
                    onPressed: () {
                      Haptics.selection();
                      onNext();
                    },
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.skip_next_rounded,
                        color: AppColors.textSecondary, size: 26),
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

  Widget _playButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.light();
        onPlayPause();
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceHighlight,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey<bool>(isPlaying),
            color: AppColors.textPrimary,
            size: 24,
          ),
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
          height: 2.5,
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: AppColors.hairline),
              ),
              FractionallySizedBox(
                widthFactor: progress,
                alignment: Alignment.centerLeft,
                child: const DecoratedBox(
                  decoration: BoxDecoration(gradient: AppColors.primaryGradient),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
