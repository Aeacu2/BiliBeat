import 'dart:async';

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/audio_download_service.dart';
import '../services/download_manager.dart';
import '../theme/app_theme.dart';
import '../theme/haptics.dart';
import 'progress_ring.dart';

/// A context-aware download/play button with an Apple Music–style progress
/// ring while downloading. Morphs: download → ring → play.
class TrackDownloadButton extends StatefulWidget {
  final Track track;
  final double size;

  /// Called when the track is already downloaded and the user taps play.
  final VoidCallback? onPlay;

  const TrackDownloadButton({
    super.key,
    required this.track,
    this.size = 26,
    this.onPlay,
  });

  @override
  State<TrackDownloadButton> createState() => _TrackDownloadButtonState();
}

class _TrackDownloadButtonState extends State<TrackDownloadButton> {
  StreamSubscription<void>? _sub;
  StreamSubscription<DownloadProgress>? _finishedSub;
  bool _isDownloaded = false;
  bool _wasDownloading = false;
  double _fraction = 0.0;

  @override
  void initState() {
    super.initState();
    _refresh();
    _sub = DownloadManager.instance.updates.listen((_) {
      if (!mounted) return;
      final task = DownloadManager.instance.taskFor(widget.track.id);
      final downloading = task != null;
      final fraction = task?.fraction ?? 0.0;
      // The manager broadcasts for *every* download in flight; a row that is
      // not involved must not rebuild.
      if (downloading == _wasDownloading && fraction == _fraction) return;
      if (_wasDownloading && !downloading) _refresh();
      _wasDownloading = downloading;
      _fraction = fraction;
      setState(() {});
    });
    // The playback path downloads outside DownloadManager (starting a track
    // fetches it), so a row whose track was never *explicitly* downloaded kept
    // offering a download button for a file that was already on disk.
    _finishedSub = AudioDownloadService.progressStream.listen((p) {
      if (!mounted || !p.done || p.trackId != widget.track.id) return;
      if (!_isDownloaded) setState(() => _isDownloaded = true);
    });
  }

  @override
  void didUpdateWidget(covariant TrackDownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _wasDownloading = false;
      _fraction = 0.0;
      _refresh();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _finishedSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final downloaded = await AudioDownloadService.isDownloaded(widget.track);
    if (mounted) setState(() => _isDownloaded = downloaded);
  }

  @override
  Widget build(BuildContext context) {
    final task = DownloadManager.instance.taskFor(widget.track.id);
    if (task != null) {
      return SizedBox(
        width: widget.size + 14,
        height: widget.size + 14,
        child: Center(
          child: ProgressRing(
            fraction: task.fraction,
            size: widget.size + 4,
            child: Icon(
              Icons.arrow_downward,
              color: AppColors.textSecondary,
              size: widget.size * 0.55,
            ),
          ),
        ),
      );
    }
    if (_isDownloaded) {
      return IconButton(
        icon: Icon(Icons.play_circle_fill,
            color: AppColors.accent, size: widget.size + 4),
        tooltip: '播放',
        onPressed: () {
          Haptics.light();
          widget.onPlay?.call();
        },
      );
    }
    return IconButton(
      icon: Icon(Icons.download_rounded,
          color: AppColors.textSecondary, size: widget.size),
      tooltip: '下载',
      onPressed: () {
        Haptics.light();
        DownloadManager.instance.startDownload(widget.track);
      },
    );
  }
}
