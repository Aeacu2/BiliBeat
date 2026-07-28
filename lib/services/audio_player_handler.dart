import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../models/track.dart';
import 'audio_download_service.dart';
import 'database_service.dart';

enum LoopMode { off, all, one }

/// Playback engine built on a native just_audio queue.
///
/// Architecture (download-then-play):
///  * Every track is fully downloaded to disk before it plays; the native
///    player (ExoPlayer on Android, AVPlayer on iOS) reads the local file
///    directly. No loopback proxy, no Dart byte-forwarding, no ATS issues.
///  * A [ja.Playlist] holds a small window of downloaded files
///    so the OS can transition to the next track gaplessly. The next track is
///    pre-downloaded in the background as soon as the current one starts.
///  * Loop/shuffle/advance logic lives in Dart; the native queue is only a
///    sliding window that mirrors the logical playlist around [_currentIndex].
class BiliBeatAudioHandler extends BaseAudioHandler with SeekHandler {
  final ja.AudioPlayer _player = ja.AudioPlayer();
  // ignore: deprecated_member_use
  final ja.ConcatenatingAudioSource _queueSource =
      // ignore: deprecated_member_use
      ja.ConcatenatingAudioSource(children: []);

  final List<Track> _playlist = [];
  int _currentIndex = -1;

  /// Logical playlist index of `_queueSource` child 0. Player index `i`
  /// therefore maps to logical index `_queueBaseIndex + i`.
  int _queueBaseIndex = 0;

  bool _isPlaying = false;
  LoopMode _loopMode = LoopMode.all;
  bool _isShuffle = false;
  bool _isRebuilding = false;
  String? _prefetchingId;

  final StreamController<Track?> _currentTrackController =
      StreamController<Track?>.broadcast();
  final StreamController<List<Track>> _queueController =
      StreamController<List<Track>>.broadcast();
  final StreamController<bool> _playerStateController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _shuffleController =
      StreamController<bool>.broadcast();
  final StreamController<LoopMode> _loopModeController =
      StreamController<LoopMode>.broadcast();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  Stream<Track?> get currentTrackStream => _currentTrackController.stream;
  Stream<List<Track>> get queueStream => _queueController.stream;
  Stream<bool> get playerStateStream => _playerStateController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<bool> get shuffleStream => _shuffleController.stream;
  Stream<LoopMode> get loopModeStream => _loopModeController.stream;

  Track? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _playlist.length)
          ? _playlist[_currentIndex]
          : null;
  bool get isPlaying => _isPlaying;
  LoopMode get loopMode => _loopMode;
  bool get isShuffle => _isShuffle;

  BiliBeatAudioHandler() {
    _initAudioPlayerListeners();
  }

  void updateCurrentTrackMetadata(Track updatedTrack) {
    if (_currentIndex >= 0 && _currentIndex < _playlist.length) {
      _playlist[_currentIndex] = updatedTrack;
      _currentTrackController.add(updatedTrack);
      mediaItem.add(MediaItem(
        id: updatedTrack.id,
        album: 'bilibeats',
        title: updatedTrack.title,
        artist: updatedTrack.uploader,
        artUri: Uri.tryParse(updatedTrack.coverUrl),
        duration: Duration(seconds: updatedTrack.duration),
      ));
    }
  }

  /// Current playback volume (0.0 – 1.0).
  double get volume => _player.volume;

  /// Sets playback volume (0.0 – 1.0).
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));

  void _initAudioPlayerListeners() {
    // Position is forwarded to the UI only. We deliberately do NOT broadcast
    // playback state here: pushing a PlaybackState to audio_service on every
    // tick causes notification/MediaSession churn. The system UI interpolates
    // the notification position from the last state + speed.
    _player.positionStream.listen((pos) {
      _position = pos;
      _positionController.add(pos);
    });

    _player.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        _durationController.add(dur);
        _broadcastState();
      }
    });

    _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      _playerStateController.add(_isPlaying);
      _broadcastState();

      if (state.processingState == ja.ProcessingState.completed) {
        _handleQueueCompleted();
      }
    });

    // Fires when the native player advances to the next queued file (gapless
    // auto-advance). Reconcile our logical index and prepare the following one.
    _player.currentIndexStream.listen((playerIndex) {
      if (playerIndex == null) return;
      final logical = _queueBaseIndex + playerIndex;
      // Guard against echoes from rebuilds / no-op changes.
      if (logical == _currentIndex) return;
      if (logical < 0 || logical >= _playlist.length) return;
      _currentIndex = logical;
      _onActiveTrackChanged(_playlist[logical]);
    });
  }

  /// Called whenever the actively-playing track changes (manual or auto).
  void _onActiveTrackChanged(Track track) {
    _currentTrackController.add(track);
    _updateMediaItem(track);
    DatabaseService.addRecentlyPlayed(track);
    _duration = Duration(seconds: track.duration > 0 ? track.duration : 180);
    _durationController.add(_duration);
    _broadcastState();
    _prefetchNext();
  }

  // ---------------------------------------------------------------------------
  // Public playback API
  // ---------------------------------------------------------------------------

  Future<void> playTrack(Track track, {List<Track>? newQueue}) async {
    if (newQueue != null && newQueue.isNotEmpty) {
      _playlist
        ..clear()
        ..addAll(newQueue);
      _queueController.add(_playlist);
    }
    if (!_playlist.any((t) => t.id == track.id)) {
      _playlist.insert(0, track);
      _queueController.add(_playlist);
    }

    var index = _playlist.indexWhere((t) => t.id == track.id);
    if (index == -1) index = 0;
    _currentIndex = index;

    // Announce immediately so the UI updates while the file downloads.
    final active = _playlist[index];
    _currentTrackController.add(active);
    _updateMediaItem(active);
    await DatabaseService.addRecentlyPlayed(active);
    _duration = Duration(seconds: active.duration > 0 ? active.duration : 180);
    _durationController.add(_duration);

    await _startCurrent(autoplay: true);
  }

  @override
  Future<void> play() async {
    // Cold restore: we have a logical track but an empty native queue.
    if (_queueSource.length == 0 && currentTrack != null) {
      await _startCurrent(autoplay: true);
      return;
    }
    await _player.play();
    _isPlaying = true;
    _playerStateController.add(true);
    _broadcastState();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _isPlaying = false;
    _playerStateController.add(false);
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    await _player.seek(position);
    _positionController.add(_position);
  }

  @override
  Future<void> skipToNext() async {
    if (_playlist.isEmpty) return;

    if (_loopMode == LoopMode.one && currentTrack != null) {
      await seek(Duration.zero);
      await play();
      return;
    }

    // Gapless: the next file is already queued in the native player.
    if (_player.hasNext) {
      await _player.seekToNext();
      return;
    }

    final next = _currentIndex + 1;
    if (next < _playlist.length) {
      await playTrack(_playlist[next]);
    } else if (_loopMode == LoopMode.all) {
      await playTrack(_playlist[0]);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_playlist.isEmpty) return;

    // Standard music UX: restart the current track once we're >3s in.
    if (_player.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }

    if (_player.hasPrevious) {
      await _player.seekToPrevious();
      return;
    }

    final prev = _currentIndex - 1;
    if (prev >= 0) {
      await playTrack(_playlist[prev]);
    } else if (_loopMode == LoopMode.all) {
      await playTrack(_playlist[_playlist.length - 1]);
    } else {
      await seek(Duration.zero);
    }
  }

  /// Cycle the single play-mode control: 随机 -> 列表循环 -> 单曲循环 -> 随机.
  void cyclePlayMode() {
    if (_isShuffle) {
      // 随机 -> 列表循环
      _isShuffle = false;
      _loopMode = LoopMode.all;
    } else if (_loopMode != LoopMode.one) {
      // 列表循环 -> 单曲循环
      _loopMode = LoopMode.one;
    } else {
      // 单曲循环 -> 随机
      _isShuffle = true;
      _loopMode = LoopMode.all;
      if (_playlist.isNotEmpty) {
        final current = currentTrack;
        _playlist.shuffle();
        if (current != null) {
          _playlist.removeWhere((t) => t.id == current.id);
          _playlist.insert(0, current);
        }
        _currentIndex = 0;
        _queueController.add(_playlist);
        _startCurrent(autoplay: _isPlaying);
      }
    }
    _shuffleController.add(_isShuffle);
    _loopModeController.add(_loopMode);
    _applyLoopMode();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _applyLoopMode() async {
    await _player.setLoopMode(
      _loopMode == LoopMode.one ? ja.LoopMode.one : ja.LoopMode.off,
    );
    if (_loopMode == LoopMode.one) {
      // Reduce the window to the lone current track so it loops by itself.
      await _startCurrent(autoplay: _isPlaying);
    } else {
      _prefetchNext();
    }
  }

  /// Download (if needed) the current track and load it as a single-item native
  /// queue, then optionally start playback and prefetch the following track.
  Future<void> _startCurrent({required bool autoplay}) async {
    final active = currentTrack;
    if (active == null) return;

    _broadcastState(processingOverride: AudioProcessingState.loading);

    final String path;
    try {
      path = await AudioDownloadService.ensureDownloaded(active);
    } catch (e) {
      debugPrint('playTrack download failed: $e');
      _broadcastState();
      return;
    }

    _isRebuilding = true;
    try {
      await _queueSource.clear();
      await _queueSource.add(ja.AudioSource.file(path, tag: active));
      _queueBaseIndex = _currentIndex;
      _prefetchingId = null;

      await _player.setLoopMode(
        _loopMode == LoopMode.one ? ja.LoopMode.one : ja.LoopMode.off,
      );
      await _player.setAudioSource(
        _queueSource,
        initialIndex: 0,
        initialPosition: Duration.zero,
      );

      if (autoplay) {
        await _player.play();
        _isPlaying = true;
        _playerStateController.add(true);
      }
    } catch (e) {
      debugPrint('startCurrent error: $e');
    } finally {
      _isRebuilding = false;
    }

    _broadcastState();
    if (_loopMode != LoopMode.one) _prefetchNext();
  }

  /// Background-download the next logical track and append it to the native
  /// queue, but only when it is the immediate contiguous successor of the
  /// queue's last child. This keeps the window gapless-ready without ever
  /// streaming bytes through Dart.
  Future<void> _prefetchNext() async {
    if (_loopMode == LoopMode.one) return;
    if (_playlist.isEmpty || _currentIndex < 0) return;

    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _playlist.length) return;

    final next = _playlist[nextIndex];
    if (_prefetchingId == next.id) return;

    final lastLogicalInQueue = _queueBaseIndex + (_queueSource.length - 1);
    if (nextIndex != lastLogicalInQueue + 1) return;

    _prefetchingId = next.id;
    try {
      final path = await AudioDownloadService.ensureDownloaded(next);
      // Re-validate the slot: the user may have navigated while downloading.
      final expectedSlot = _queueBaseIndex + _queueSource.length;
      if (expectedSlot == nextIndex && _currentIndex == nextIndex - 1) {
        await _queueSource.add(ja.AudioSource.file(path, tag: next));
      }
    } catch (e) {
      debugPrint('Prefetch next track error: $e');
    } finally {
      if (_prefetchingId == next.id) _prefetchingId = null;
    }
  }

  /// The native queue ran out. Handle loop-all wrap-around and end-of-playlist.
  void _handleQueueCompleted() {
    if (_isRebuilding || _playlist.isEmpty) return;

    if (_loopMode == LoopMode.all) {
      playTrack(_playlist[0]);
      return;
    }

    if (_currentIndex < _playlist.length - 1) {
      // Safety net (e.g. an earlier prefetch failed): keep going.
      playTrack(_playlist[_currentIndex + 1]);
    } else {
      _isPlaying = false;
      _playerStateController.add(false);
      _broadcastState();
    }
  }

  void _broadcastState({AudioProcessingState? processingOverride}) {
    final playing = _player.playing;
    final mapped = const {
      ja.ProcessingState.idle: AudioProcessingState.idle,
      ja.ProcessingState.loading: AudioProcessingState.loading,
      ja.ProcessingState.buffering: AudioProcessingState.buffering,
      ja.ProcessingState.ready: AudioProcessingState.ready,
      ja.ProcessingState.completed: AudioProcessingState.completed,
    }[_player.processingState];

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingOverride ?? mapped ?? AudioProcessingState.idle,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentIndex,
    ));
  }

  void _updateMediaItem(Track track) {
    final item = MediaItem(
      id: track.id,
      album: 'Bilibili Music',
      title: track.title,
      artist: track.uploader,
      duration: Duration(seconds: track.duration > 0 ? track.duration : 180),
      artUri: Uri.tryParse(track.coverUrl),
    );
    mediaItem.add(item);
  }
}
