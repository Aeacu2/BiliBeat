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
  bool _isDownloaded = false;
  bool _wasDownloading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _sub = DownloadManager.instance.updates.listen((_) {
      if (!mounted) return;
      final downloading =
          DownloadManager.instance.isDownloading(widget.track.id);
      if (_wasDownloading && !downloading) _refresh();
      _wasDownloading = downloading;
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant TrackDownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) _refresh();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final downloaded = await AudioDownloadService.isDownloaded(widget.track);
    if (mounted) setState(() => _isDownloaded = downloaded);
  }

  @override
  Widget build(BuildContext context) {
    final task = DownloadManager.instance.taskFor(widget.track.id);
    if (task != null && task.status == DownloadStatus.downloading) {
      return SizedBox(
        width: widget.size + 14,
        height: widget.size + 14,
        child: Center(
          child: ProgressRing(
            fraction: task.fraction,
            size: widget.size + 4,
            strokeWidth: 2.5,
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
