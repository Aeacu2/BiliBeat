import 'dart:async';

import '../models/track.dart';
import 'audio_download_service.dart';

/// A live snapshot of an in-flight download.
///
/// There is no `status`: a task exists only while it is downloading, and is
/// removed on completion *or* failure. The old `DownloadStatus.failed` was
/// never assigned anywhere, so every `status == downloading` check in the app
/// was a tautology guarding unreachable state.
class DownloadTask {
  final Track track;

  /// 0..1, or 0 when the server sent no content length.
  final double fraction;

  const DownloadTask({required this.track, this.fraction = 0.0});

  DownloadTask copyWith({double? fraction}) =>
      DownloadTask(track: track, fraction: fraction ?? this.fraction);
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

  /// Currently in-flight tasks, newest first.
  List<DownloadTask> get activeTasks => _tasks.values.toList().reversed.toList();

  DownloadTask? taskFor(String trackId) => _tasks[trackId];

  bool isDownloading(String trackId) => _tasks.containsKey(trackId);

  /// Starts downloading [track] (idempotent). Observe progress via [updates].
  Future<void> startDownload(Track track) async {
    // Claim the slot synchronously, before any await. Checking `isDownloaded`
    // first meant two rapid taps could both clear the guard during that await
    // and start the same download twice.
    if (_tasks.containsKey(track.id)) return;
    _tasks[track.id] = DownloadTask(track: track);
    _notify();
    try {
      // ensureDownloaded is itself a no-op when the file is already on disk.
      await AudioDownloadService.ensureDownloaded(track);
    } catch (_) {
      // Surfaced by the progress stream; the task simply ends either way.
    } finally {
      _tasks.remove(track.id);
      _notify();
    }
  }

  void _onProgress(DownloadProgress p) {
    final task = _tasks[p.trackId];
    if (task == null) return;
    if (p.done || p.error != null) return; // startDownload's finally clears it
    _tasks[p.trackId] = task.copyWith(fraction: p.fraction);
    _notify();
  }

  void _notify() {
    if (!_controller.isClosed) _controller.add(null);
  }
}
