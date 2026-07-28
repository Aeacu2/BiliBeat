import 'dart:async';

import 'package:flutter/material.dart';

import '../models/lyric_line.dart';
import '../models/track.dart';
import '../services/audio_player_handler.dart';
import '../services/database_service.dart';
import '../services/audio_download_service.dart';
import '../services/download_manager.dart';
import '../theme/app_theme.dart';
import '../theme/haptics.dart';
import 'ambient_background.dart';
import 'cached_cover_image.dart';
import 'marquee_text.dart';
import 'progress_ring.dart';
import 'synced_lyrics_view.dart';

/// Full-screen "now playing" surface.
///
/// It can display a [focusedTrack] that is not yet downloaded (e.g. tapped from
/// search). In that case the center control is a download button (Apple
/// Music–style ring while downloading); favoriting also starts the download.
/// Once the track is playable it behaves like a normal player and follows the
/// handler through prev/next/auto-advance.
class NowPlayingSheet extends StatefulWidget {
  final BiliBeatAudioHandler handler;
  final Track focusedTrack;
  final ValueNotifier<Duration> positionNotifier;
  final ValueNotifier<Duration> durationNotifier;
  final ValueNotifier<List<LyricLine>> lyricsNotifier;
  final VoidCallback onOpenLyricEditor;

  const NowPlayingSheet({
    super.key,
    required this.handler,
    required this.focusedTrack,
    required this.positionNotifier,
    required this.durationNotifier,
    required this.lyricsNotifier,
    required this.onOpenLyricEditor,
  });

  @override
  State<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<NowPlayingSheet> {
  final List<StreamSubscription> _subs = [];

  late Track _displayTrack;
  bool _followHandler = false;
  bool _isPlaying = false;
  bool _isShuffle = false;
  LoopMode _loopMode = LoopMode.all;
  bool _showLyrics = false;
  double _volume = 1.0;
  bool _isFavorite = false;
  bool _isDownloaded = false;
  DownloadTask? _downloadTask;
  bool _modePressed = false;
  double? _dragValue;

  bool get _isActive => widget.handler.currentTrack?.id == _displayTrack.id;

  @override
  void initState() {
    super.initState();
    final h = widget.handler;
    _displayTrack = widget.focusedTrack;
    _followHandler = (h.currentTrack?.id == _displayTrack.id);
    _isPlaying = h.isPlaying;
    _isShuffle = h.isShuffle;
    _loopMode = h.loopMode;
    _volume = h.volume;
    final initialTask = DownloadManager.instance.taskFor(_displayTrack.id);
    _downloadTask = (initialTask != null && initialTask.status == DownloadStatus.downloading)
        ? initialTask
        : null;
    _refreshDownloaded();
    _refreshFavorite();

    _subs.add(h.currentTrackStream.listen((t) {
      if (t == null || !mounted) return;
      if (_followHandler) {
        setState(() => _displayTrack = t);
        _refreshDownloaded();
        _refreshFavorite();
      }
    }));
    _subs.add(h.playerStateStream.listen((p) {
      if (mounted) setState(() => _isPlaying = p);
    }));
    _subs.add(h.shuffleStream.listen((s) {
      if (mounted) setState(() => _isShuffle = s);
    }));
    _subs.add(h.loopModeStream.listen((m) {
      if (mounted) setState(() => _loopMode = m);
    }));
    _subs.add(DownloadManager.instance.updates.listen((_) {
      if (!mounted) return;
      final task = DownloadManager.instance.taskFor(_displayTrack.id);
      setState(() {
        _downloadTask =
            (task != null && task.status == DownloadStatus.downloading)
                ? task
                : null;
      });
      _refreshDownloaded();
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _refreshDownloaded() async {
    if (DownloadManager.instance.isDownloading(_displayTrack.id)) {
      if (mounted) setState(() => _isDownloaded = false);
      return;
    }
    final downloaded = await AudioDownloadService.isDownloaded(_displayTrack);
    if (mounted) setState(() => _isDownloaded = downloaded);
  }

  Future<void> _refreshFavorite() async {
    final fav = await DatabaseService.isFavorite(_displayTrack.id);
    if (mounted) setState(() => _isFavorite = fav);
  }

  void _startDownload() {
    Haptics.light();
    DownloadManager.instance.startDownload(_displayTrack);
    final task = DownloadManager.instance.taskFor(_displayTrack.id);
    if (mounted) {
      setState(() {
        _downloadTask =
            (task != null && task.status == DownloadStatus.downloading)
                ? task
                : null;
      });
    }
  }

  void _playOrPause() {
    Haptics.light();
    if (_isActive) {
      _isPlaying ? widget.handler.pause() : widget.handler.play();
    } else {
      _followHandler = true;
      widget.handler.playTrack(_displayTrack);
    }
  }

  void _prev() {
    Haptics.selection();
    _followHandler = true;
    widget.handler.skipToPrevious();
  }

  void _next() {
    Haptics.selection();
    _followHandler = true;
    widget.handler.skipToNext();
  }

  Future<void> _handleFavorite() async {
    Haptics.light();
    final nowFav = await DatabaseService.toggleFavorite(_displayTrack);
    if (mounted) setState(() => _isFavorite = nowFav);
    // Favoriting a track that isn't local yet kicks off its download too.
    if (nowFav && !_isDownloaded) {
      _startDownload();
    }
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: AmbientBackground(
          coverUrl: _displayTrack.coverUrl,
          child: SafeArea(
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: Center(
                    child: _showLyrics && _isActive
                        ? ValueListenableBuilder<List<LyricLine>>(
                            valueListenable: widget.lyricsNotifier,
                            builder: (context, lines, _) {
                              return SyncedLyricsView(
                                lines: lines,
                                positionNotifier: widget.positionNotifier,
                                onSeek: (sec) => widget.handler.seek(
                                  Duration(milliseconds: (sec * 1000).toInt()),
                                ),
                                onOpenEditor: widget.onOpenLyricEditor,
                              );
                            },
                          )
                        : _albumArt(),
                  ),
                ),
                _bottomPanel(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down,
                color: AppColors.textSecondary, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.hairlineStrong,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              _showLyrics ? Icons.lyrics : Icons.lyrics_outlined,
              color: _showLyrics && _isActive
                  ? AppColors.accent
                  : AppColors.textSecondary,
              size: 22,
            ),
            onPressed: _isActive
                ? () {
                    Haptics.selection();
                    setState(() => _showLyrics = !_showLyrics);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _albumArt() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final size = maxHeight > 0 ? (maxHeight * 0.75).clamp(150.0, 320.0) : 240.0;
        return Center(
          child: AnimatedScale(
            scale: (_isActive && _isPlaying) ? 1.0 : 0.92,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.black55,
                    blurRadius: 40,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: CachedCoverImage(
                  url: _displayTrack.coverUrl,
                  width: size,
                  height: size,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bottomPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MarqueeText(
                      text: _displayTrack.title,
                      scrolling: _isActive && _isPlaying,
                      style: AppTypography.title,
                    ),
                    const SizedBox(height: 3),
                    MarqueeText(
                      text: _displayTrack.uploader,
                      scrolling: _isActive && _isPlaying,
                      style: AppTypography.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_note,
                    color: AppColors.textSecondary, size: 24),
                tooltip: '信息与歌词',
                onPressed: widget.onOpenLyricEditor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _seekBar(),
          const SizedBox(height: 8),
          _transportControls(),
          const SizedBox(height: 12),
          _volumeBar(),
        ],
      ),
    );
  }

  Widget _seekBar() {
    const timeStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 12,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.durationNotifier,
      builder: (context, duration, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: widget.positionNotifier,
          builder: (context, position, _) {
            final double maxSec = _isActive
                ? (duration.inSeconds.toDouble() > 0
                    ? duration.inSeconds.toDouble()
                    : (_displayTrack.duration > 0
                        ? _displayTrack.duration.toDouble()
                        : 1.0))
                : (_displayTrack.duration > 0
                    ? _displayTrack.duration.toDouble()
                    : 1.0);
            final double posSec = _isActive
                ? (_dragValue ??
                        position.inSeconds.toDouble().clamp(0.0, maxSec))
                    .clamp(0.0, maxSec)
                : 0.0;
            final remaining = (Duration(seconds: maxSec.round()) -
                        Duration(seconds: posSec.round())) <
                    Duration.zero
                ? Duration.zero
                : (Duration(seconds: maxSec.round()) -
                    Duration(seconds: posSec.round()));
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                const pad = 24.0;
                final fraction = maxSec > 0 ? posSec / maxSec : 0.0;
                final thumbX = pad / 2 + fraction * (width - pad);
                return Column(
                  children: [
                    SizedBox(
                      height: 40,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (_dragValue != null)
                            Positioned(
                              left: (thumbX - 26).clamp(0.0, width - 52),
                              top: -22,
                              child: _timeBubble(
                                  _formatDuration(Duration(seconds: posSec.round()))),
                            ),
                          Center(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14),
                              ),
                              child: Slider(
                                value: posSec,
                                max: maxSec,
                                onChanged: (v) {
                                  setState(() => _dragValue = v);
                                  if (_isActive) {
                                    widget.handler
                                        .seek(Duration(seconds: v.toInt()));
                                  }
                                },
                                onChangeStart: (v) =>
                                    setState(() => _dragValue = v),
                                onChangeEnd: (v) {
                                  Haptics.light();
                                  setState(() => _dragValue = null);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(Duration(seconds: posSec.round())),
                              style: timeStyle),
                          Text('-${_formatDuration(remaining)}', style: timeStyle),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _timeBubble(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: const [
          BoxShadow(
            color: AppColors.black30,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.background,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _transportControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _favoriteButton(),
        IconButton(
          icon: const Icon(Icons.skip_previous,
              color: AppColors.textPrimary, size: 38),
          onPressed: _isActive ? _prev : null,
        ),
        _centerButton(),
        IconButton(
          icon: const Icon(Icons.skip_next,
              color: AppColors.textPrimary, size: 38),
          onPressed: _isActive ? _next : null,
        ),
        _modeButton(),
      ],
    );
  }

  Widget _favoriteButton() {
    return SizedBox(
      width: 44,
      child: IconButton(
        icon: Icon(
          _isFavorite ? Icons.favorite : Icons.favorite_border,
          color: _isFavorite ? AppColors.accent : AppColors.textMuted,
          size: 26,
        ),
        onPressed: _handleFavorite,
      ),
    );
  }

  /// Center control: download → ring → play/pause, depending on download state.
  Widget _centerButton() {
    final task = _downloadTask;
    if (task != null) {
      return SizedBox(
        width: 76,
        height: 76,
        child: Center(
          child: ProgressRing(
            fraction: task.fraction,
            size: 56,
            strokeWidth: 3.5,
            child: const Icon(Icons.arrow_downward,
                color: AppColors.textPrimary, size: 22),
          ),
        ),
      );
    }
    if (!_isDownloaded) {
      return _circleButton(
        child: const Icon(Icons.download_rounded,
            color: AppColors.textPrimary, size: 34),
        onTap: _startDownload,
      );
    }
    final playing = _isActive && _isPlaying;
    return _circleButton(
      child: Icon(
        playing ? Icons.pause : Icons.play_arrow,
        color: AppColors.textPrimary,
        size: 42,
      ),
      onTap: _playOrPause,
    );
  }

  Widget _circleButton({required Widget child, required VoidCallback onTap}) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceHighlight,
        border: Border.all(color: AppColors.hairlineStrong),
      ),
      child: IconButton(
        icon: child,
        onPressed: onTap,
      ),
    );
  }

  Widget _modeButton() {
    final IconData icon = _isShuffle
        ? Icons.shuffle
        : (_loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat);
    return SizedBox(
      width: 44,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (mounted) setState(() => _modePressed = true);
        },
        onTapUp: (_) {
          if (!mounted) return;
          setState(() => _modePressed = false);
          Haptics.medium();
          widget.handler.cyclePlayMode();
        },
        onTapCancel: () {
          if (mounted) setState(() => _modePressed = false);
        },
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  _modePressed ? AppColors.surfaceHighlight : Colors.transparent,
            ),
            child: Icon(
              icon,
              color: _modePressed ? AppColors.accent : AppColors.textMuted,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _volumeBar() {
    return Row(
      children: [
        const Icon(Icons.volume_mute, color: AppColors.textFaint, size: 18),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: _volume,
              onChanged: (v) {
                setState(() => _volume = v);
                widget.handler.setVolume(v);
              },
            ),
          ),
        ),
        const Icon(Icons.volume_up, color: AppColors.textFaint, size: 18),
      ],
    );
  }
}

