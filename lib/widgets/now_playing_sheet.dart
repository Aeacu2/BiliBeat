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
import 'cached_cover_image.dart';
import 'marquee_text.dart';
import 'progress_ring.dart';
import 'synced_lyrics_view.dart';

/// Full-screen "now playing" surface.
class NowPlayingSheet extends StatefulWidget {
  final BiliBeatAudioHandler handler;
  final Track focusedTrack;
  final ValueNotifier<Duration> positionNotifier;
  final ValueNotifier<Duration> durationNotifier;
  final ValueNotifier<List<LyricLine>> lyricsNotifier;

  /// Receives the track actually on screen — which is not always the one the
  /// handler is playing (a search result can be previewed here).
  final void Function(Track track, {bool lyricsTab}) onOpenLyricEditor;

  /// Set when the sheet is opened as part of "play this now". The handler has
  /// not switched track yet at that instant, so it cannot be inferred — and
  /// getting it wrong leaves the sheet stuck on one track for the whole
  /// session, never following the queue.
  final bool followHandler;

  const NowPlayingSheet({
    super.key,
    required this.handler,
    required this.focusedTrack,
    required this.positionNotifier,
    required this.durationNotifier,
    required this.lyricsNotifier,
    required this.onOpenLyricEditor,
    this.followHandler = false,
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
  double? _dragValue;

  bool get _isActive => widget.handler.currentTrack?.id == _displayTrack.id;

  @override
  void initState() {
    super.initState();
    final h = widget.handler;
    _displayTrack = widget.focusedTrack;
    _followHandler =
        widget.followHandler || (h.currentTrack?.id == _displayTrack.id);
    _isPlaying = h.isPlaying;
    _isShuffle = h.isShuffle;
    _loopMode = h.loopMode;
    _volume = h.volume;
    _downloadTask = _liveTaskFor(_displayTrack.id);
    _refreshTrackState();

    _subs.add(h.currentTrackStream.listen((t) {
      if (t == null || !mounted) return;
      if (_followHandler && t.id != _displayTrack.id) {
        setState(() => _displayTrack = t);
        _refreshTrackState();
      } else if (t.id == _displayTrack.id) {
        setState(() => _displayTrack = t); // metadata edit
      }
    }));
    _subs.add(h.playerStateStream.listen((p) {
      if (!mounted) return;
      setState(() => _isPlaying = p);
      // Playback implies the file reached disk, and the handler downloads
      // outside DownloadManager — so re-check rather than leaving the control
      // stuck on "download" while the track plays.
      if (p && _isActive && !_isDownloaded) _refreshDownloaded();
    }));
    _subs.add(h.shuffleStream.listen((s) {
      if (mounted) setState(() => _isShuffle = s);
    }));
    _subs.add(h.loopModeStream.listen((m) {
      if (mounted) setState(() => _loopMode = m);
    }));
    _subs.add(h.volumeStream.listen((v) {
      if (mounted) setState(() => _volume = v);
    }));
    _subs.add(DownloadManager.instance.updates.listen((_) {
      if (!mounted) return;
      final task = _liveTaskFor(_displayTrack.id);
      final finished = _downloadTask != null && task == null;
      setState(() => _downloadTask = task);
      // Only stat the filesystem when a download actually finished, not on
      // every progress tick (they arrive every 64 KiB).
      if (finished) _refreshDownloaded();
    }));
  }

  DownloadTask? _liveTaskFor(String id) {
    final task = DownloadManager.instance.taskFor(id);
    return (task != null && task.status == DownloadStatus.downloading)
        ? task
        : null;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  /// One combined refresh so switching tracks costs a single rebuild.
  Future<void> _refreshTrackState() async {
    final track = _displayTrack;
    final results = await Future.wait([
      AudioDownloadService.isDownloaded(track),
      DatabaseService.isFavorite(track.id),
    ]);
    if (!mounted || _displayTrack.id != track.id) return;
    setState(() {
      _isDownloaded = results[0] && !DownloadManager.instance.isDownloading(track.id);
      _isFavorite = results[1];
    });
  }

  Future<void> _refreshDownloaded() async {
    final track = _displayTrack;
    final downloaded = await AudioDownloadService.isDownloaded(track);
    if (!mounted || _displayTrack.id != track.id) return;
    setState(() => _isDownloaded = downloaded);
  }

  void _startDownload() {
    Haptics.light();
    DownloadManager.instance.startDownload(_displayTrack);
    if (mounted) {
      setState(() => _downloadTask = _liveTaskFor(_displayTrack.id));
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
    if (nowFav && !_isDownloaded) _startDownload();
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        // Swipe down anywhere on the chrome to dismiss, like the system sheets.
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 320) {
            Haptics.selection();
            Navigator.of(context).maybePop();
          }
        },
        child: SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: _showLyrics && _isActive
                        ? ValueListenableBuilder<List<LyricLine>>(
                            key: const ValueKey('lyrics'),
                            valueListenable: widget.lyricsNotifier,
                            builder: (context, lines, _) {
                              return SyncedLyricsView(
                                lines: lines,
                                positionNotifier: widget.positionNotifier,
                                onSeek: (sec) => widget.handler.seek(
                                  Duration(milliseconds: (sec * 1000).toInt()),
                                ),
                                onOpenEditor: () => widget
                                    .onOpenLyricEditor(_displayTrack,
                                        lyricsTab: true),
                              );
                            },
                          )
                        : _albumArt(),
                  ),
                ),
              ),
              _bottomPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.textSecondary, size: 30),
            tooltip: '收起',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              _isActive ? '正在播放' : '预览',
              textAlign: TextAlign.center,
              style: AppTypography.overline.copyWith(
                color: _isActive ? AppColors.accent : AppColors.textFaint,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _showLyrics ? Icons.lyrics_rounded : Icons.lyrics_outlined,
              color: _showLyrics && _isActive
                  ? AppColors.accent
                  : (_isActive ? AppColors.textSecondary : AppColors.textFaint),
              size: 22,
            ),
            tooltip: '歌词',
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
      key: const ValueKey('art'),
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final size = maxHeight > 0
            ? (maxHeight * 0.82).clamp(160.0, constraints.maxWidth)
            : 240.0;
        return Center(
          child: AnimatedScale(
            scale: (_isActive && _isPlaying) ? 1.0 : 0.9,
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
                    blurRadius: 44,
                    spreadRadius: -6,
                    offset: Offset(0, 20),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MarqueeText(
                      text: _displayTrack.title,
                      scrolling: _isActive && _isPlaying,
                      style: AppTypography.title,
                    ),
                    const SizedBox(height: 4),
                    MarqueeText(
                      text: _displayTrack.uploader,
                      scrolling: false,
                      style: AppTypography.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.edit_note_rounded,
                    color: AppColors.textSecondary, size: 24),
                tooltip: '编辑',
                onPressed: () => widget.onOpenLyricEditor(_displayTrack),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _seekBar(),
          const SizedBox(height: 4),
          _transportControls(),
          const SizedBox(height: 8),
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
    return AnimatedBuilder(
      animation:
          Listenable.merge([widget.durationNotifier, widget.positionNotifier]),
      builder: (context, _) {
        final fallback =
            _displayTrack.duration > 0 ? _displayTrack.duration.toDouble() : 1.0;
        final streamed = widget.durationNotifier.value.inSeconds.toDouble();
        final double maxSec =
            _isActive && streamed > 0 ? streamed : fallback;
        final double posSec = _isActive
            ? (_dragValue ??
                    widget.positionNotifier.value.inSeconds.toDouble())
                .clamp(0.0, maxSec)
            : 0.0;
        var remaining = Duration(seconds: (maxSec - posSec).round());
        if (remaining < Duration.zero) remaining = Duration.zero;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
                disabledActiveTrackColor: AppColors.hairlineStrong,
                disabledInactiveTrackColor: AppColors.hairline,
                disabledThumbColor: AppColors.textFaint,
              ),
              child: Slider(
                value: posSec,
                max: maxSec,
                label: _formatDuration(Duration(seconds: posSec.round())),
                // Seeking a track that is not the one playing is meaningless.
                onChanged: _isActive
                    ? (v) => setState(() => _dragValue = v)
                    : null,
                onChangeStart: (v) => setState(() => _dragValue = v),
                onChangeEnd: (v) {
                  Haptics.light();
                  widget.handler.seek(Duration(seconds: v.toInt()));
                  setState(() => _dragValue = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
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
  }

  Widget _transportControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _favoriteButton(),
        _skipButton(Icons.skip_previous_rounded, _isActive ? _prev : null),
        _playButton(),
        _skipButton(Icons.skip_next_rounded, _isActive ? _next : null),
        _modeButton(),
      ],
    );
  }

  Widget _skipButton(IconData icon, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(icon,
          color: onPressed == null
              ? AppColors.textFaint
              : AppColors.textPrimary,
          size: 40),
      onPressed: onPressed,
    );
  }

  Widget _favoriteButton() {
    return SizedBox(
      width: 48,
      child: IconButton(
        icon: Icon(
          _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: _isFavorite ? AppColors.accent : AppColors.textMuted,
          size: 26,
        ),
        tooltip: _isFavorite ? '取消收藏' : '收藏',
        onPressed: _handleFavorite,
      ),
    );
  }

  /// The primary control mirrors the track's real state, because playback is
  /// download-then-play: a track that is not on disk cannot be played, so it
  /// offers a download (with the same progress ring used in the lists) and
  /// only becomes play/pause once the file is there.
  Widget _playButton() {
    final task = _downloadTask;

    // Download and downloading are the *same button*, not two designs: the
    // circle, its fill, its border and its glyph are identical, and starting a
    // download only adds a progress arc around the outside. Previously the
    // filled circle was replaced by a bare thin ring, so the control appeared
    // to vanish the instant you tapped it.
    if (task != null || !_isDownloaded) {
      return _circleButton(
        tooltip: task != null ? '下载中' : '下载',
        onPressed: task != null ? null : _startDownload,
        filled: false,
        progress: task?.fraction,
        icon: const Icon(Icons.download_rounded,
            color: AppColors.textPrimary, size: 34),
      );
    }

    final playing = _isActive && _isPlaying;
    return _circleButton(
      tooltip: playing ? '暂停' : '播放',
      onPressed: _playOrPause,
      filled: true,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          key: ValueKey<bool>(playing),
          color: Colors.white,
          size: 40,
        ),
      ),
    );
  }

  /// The one primary-control shape. [progress], when set, draws a determinate
  /// arc just outside the circle without altering the circle itself.
  Widget _circleButton({
    required Widget icon,
    required VoidCallback? onPressed,
    required String tooltip,
    required bool filled,
    double? progress,
  }) {
    final button = Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: filled ? AppColors.primaryGradient : null,
        color: filled ? null : AppColors.surfaceHighlight,
        border: filled
            ? null
            : Border.all(color: AppColors.hairlineStrong, width: 1),
        boxShadow: filled
            ? const [
                BoxShadow(
                  color: AppColors.accent30,
                  blurRadius: 22,
                  offset: Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: icon,
      ),
    );

    if (progress == null) return button;

    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ProgressRing(
            fraction: progress,
            size: 76,
            strokeWidth: 3,
            trackColor: AppColors.hairline,
          ),
          button,
        ],
      ),
    );
  }

  Widget _modeButton() {
    final IconData icon = _isShuffle
        ? Icons.shuffle_rounded
        : (_loopMode == LoopMode.one
            ? Icons.repeat_one_rounded
            : Icons.repeat_rounded);
    final label = _isShuffle
        ? '随机播放'
        : (_loopMode == LoopMode.one ? '单曲循环' : '列表循环');
    // Shuffle and repeat-one are both "not the default", so both light up.
    final active = _isShuffle || _loopMode == LoopMode.one;
    return SizedBox(
      width: 48,
      child: IconButton(
        icon: Icon(icon,
            color: active ? AppColors.accent : AppColors.textMuted, size: 24),
        tooltip: label,
        onPressed: () {
          Haptics.medium();
          widget.handler.cyclePlayMode();
        },
      ),
    );
  }

  Widget _volumeBar() {
    final IconData icon;
    if (_volume <= 0.01) {
      icon = Icons.volume_off_rounded;
    } else if (_volume < 0.5) {
      icon = Icons.volume_down_rounded;
    } else {
      icon = Icons.volume_up_rounded;
    }
    return Row(
      children: [
        IconButton(
          icon: Icon(icon, color: AppColors.textFaint, size: 18),
          visualDensity: VisualDensity.compact,
          tooltip: _volume <= 0.01 ? '取消静音' : '静音',
          onPressed: () {
            Haptics.selection();
            final next = _volume <= 0.01 ? 1.0 : 0.0;
            setState(() => _volume = next);
            widget.handler.setVolume(next);
          },
        ),
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
        const SizedBox(width: 8),
      ],
    );
  }
}
