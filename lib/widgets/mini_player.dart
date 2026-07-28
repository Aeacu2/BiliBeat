import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/haptics.dart';
import '../models/track.dart';
import 'cached_cover_image.dart';
import 'marquee_text.dart';

/// The docked player — a compact edition of the now-playing page rather than a
/// separate control bar.
///
/// It is deliberately built from the same parts as [NowPlayingSheet], because
/// tapping it *becomes* that page: the card's rounded surface grows into the
/// page, so the two must share a visual language or the morph reads as a jump
/// cut. The artwork uses the album-art corner radius, the surface is the same
/// elevated near-black with the same soft shadow, and the primary control keeps
/// the page's shape and position — but not its fill. Continuity is about shape
/// and place; a saturated pink disc shrunk onto a 68pt bar just shouts.
///
/// Still no `BackdropFilter`: real-time blur over the whole page cost a full
/// GPU layer pass every frame and was the root of the Android foreground
/// erasure bug. A tuned opaque surface reads just as rich and costs nothing.
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
  static const double contentHeight = 68.0;

  /// The album art's radius, so the card looks like the page folded down.
  static const double radius = AppRadius.xl;

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

  /// One elevated surface, one hairline, one deep shadow — the album art's
  /// treatment at bar scale.
  Widget _shell({required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: AppColors.black55,
            blurRadius: 28,
            spreadRadius: -4,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.backgroundElevated,
            border: Border.all(color: AppColors.hairline),
            borderRadius: BorderRadius.circular(radius),
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
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(AppRadius.md),
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
              padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
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
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14.5,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.25,
                          ),
                        ),
                        const SizedBox(height: 1),
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
                  const SizedBox(width: 8),
                  // Same shape and place as the page's primary control, so the
                  // eye can track it across the morph — but quiet. A filled
                  // pink disc is right at 68pt in the middle of the player;
                  // shrunk onto a 68pt bar it was the loudest thing on the
                  // screen and fought the artwork it sits next to.
                  _playButton(),
                  _iconButton(
                    Icons.skip_next_rounded,
                    onPressed: () {
                      Haptics.selection();
                      onNext();
                    },
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
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              // The same top-lit sheen the glass surfaces use, so the control
              // belongs to the card instead of being pasted onto it.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.surfaceHighlight, AppColors.surfaceCard],
              ),
              border: Border.fromBorderSide(
                  BorderSide(color: AppColors.hairlineStrong)),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey<bool>(isPlaying),
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, {required VoidCallback onPressed}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Icon(icon, color: AppColors.textSecondary, size: 26),
        ),
      ),
    );
  }

  /// The page's seek bar, reduced to the hairline it becomes when folded: it
  /// sits on the card's bottom edge and is clipped to its radius.
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
                child: const ColoredBox(color: AppColors.accent),
              ),
            ],
          ),
        );
      },
    );
  }
}
