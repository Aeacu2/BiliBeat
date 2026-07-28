import 'dart:async';

import '../models/track.dart';
import 'audio_download_service.dart';

enum DownloadStatus { downloading, failed }

/// A live, observable snapshot of an in-flight download.
class DownloadTask {
  final Track track;
  final DownloadStatus status;
  final double fraction; // 0..1
  final int received;
  final int total;

  const DownloadTask({
    required this.track,
    this.status = DownloadStatus.downloading,
    this.fraction = 0.0,
    this.received = 0,
    this.total = 0,
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    double? fraction,
    int? received,
    int? total,
  }) {
    return DownloadTask(
      track: track,
      status: status ?? this.status,
      fraction: fraction ?? this.fraction,
      received: received ?? this.received,
      total: total ?? this.total,
    );
  }
}

/// Tracks user-initiated downloads with live progress so any screen can render
/// Apple Music–style rings and "X 下载中 / Y 已下载" counts.
///
/// Playback-path downloads (started inside the audio handler) are intentionally
/// NOT tracked here — only explicit user downloads are surfaced.
class DownloadManager {
  DownloadManager._() {
    AudioDownloadService.progressStream.listen(_onProgress);
  }
  static final DownloadManager instance = DownloadManager._();

  final Map<String, DownloadTask> _tasks = {};
  final StreamController<void> _controller = StreamController<void>.broadcast();

  /// Emits whenever the task set or any task's progress changes.
  Stream<void> get updates => _controller.stream;

  /// Currently in-flight tasks (downloading), newest first.
  List<DownloadTask> get activeTasks => _tasks.values
      .where((t) => t.status == DownloadStatus.downloading)
      .toList()
      .reversed
      .toList();

  int get downloadingCount => activeTasks.length;

  DownloadTask? taskFor(String trackId) => _tasks[trackId];

  bool isDownloading(String trackId) {
    final t = _tasks[trackId];
    return t != null && t.status == DownloadStatus.downloading;
  }

  /// Starts downloading [track] (idempotent). Observe progress via [updates].
  Future<void> startDownload(Track track) async {
    if (await AudioDownloadService.isDownloaded(track)) return;
    if (_tasks.containsKey(track.id)) return;
    _tasks[track.id] = DownloadTask(track: track);
    _notify();
    try {
      await AudioDownloadService.ensureDownloaded(track);
      _tasks.remove(track.id);
      _notify();
    } catch (_) {
      _tasks.remove(track.id);
      _notify();
    }
  }

  void _onProgress(DownloadProgress p) {
    final task = _tasks[p.trackId];
    if (task == null) return;
    if (p.done || p.error != null) return; // startDownload's await finalizes
    _tasks[p.trackId] = task.copyWith(
      status: DownloadStatus.downloading,
      received: p.receivedBytes,
      total: p.totalBytes ?? 0,
      fraction: p.fraction,
    );
    _notify();
  }

  void _notify() {
    if (!_controller.isClosed) _controller.add(null);
  }
}
