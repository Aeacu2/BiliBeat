import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/haptics.dart';
import '../models/track.dart';
import 'cached_cover_image.dart';
import 'marquee_text.dart';

/// A floating, frosted-glass mini player docked above the home indicator.
///
/// The total height is exactly `64 + safe-area-bottom` so it matches the space
/// reserved by the parent layout (and the playlist overlay that stops above it).
class MiniPlayer extends StatelessWidget {
  final Track? currentTrack;
  final bool isPlaying;
  final ValueNotifier<Duration> positionNotifier;
  final ValueNotifier<Duration> durationNotifier;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onTap;

  const MiniPlayer({
    super.key,
    required this.currentTrack,
    required this.isPlaying,
    required this.positionNotifier,
    required this.durationNotifier,
    required this.onPlayPause,
    required this.onNext,
    required this.onTap,
  });

  static const double _contentHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset),
      child: SizedBox(
        height: _contentHeight,
        child: currentTrack == null ? _emptyState() : _activePlayer(),
      ),
    );
  }

  Widget _emptyState() {
    return _glassShell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceHighlight,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Icon(Icons.music_note,
                  color: AppColors.textMuted, size: 20),
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
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2)),
                  SizedBox(height: 2),
                  Text('点击曲目开始播放 · 左右滑动切换页面',
                      style: TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 11,
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
      child: _glassShell(
        child: Column(
          children: [
            // Hairline progress along the top edge.
            ValueListenableBuilder<Duration>(
              valueListenable: durationNotifier,
              builder: (context, dur, _) {
                return ValueListenableBuilder<Duration>(
                  valueListenable: positionNotifier,
                  builder: (context, pos, _) {
                    final progress = dur.inMilliseconds > 0
                        ? (pos.inMilliseconds / dur.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0.0;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          height: 2,
                          decoration: const BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(2),
                              bottomLeft: Radius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
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
                            scrolling: isPlaying,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.uploader,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Haptics.light();
                        onPlayPause();
                      },
                      icon: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: AppColors.textPrimary,
                        size: 30,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Haptics.selection();
                        onNext();
                      },
                      icon: const Icon(
                        Icons.skip_next,
                        color: AppColors.textSecondary,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Frosted-glass rounded shell with a subtle top-lit sheen + hairline border.
  Widget _glassShell({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33FFFFFF), Color(0x14FFFFFF)],
            ),
            border: Border.all(color: AppColors.hairlineStrong, width: 1),
            boxShadow: const [
              BoxShadow(
                color: AppColors.black35,
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
