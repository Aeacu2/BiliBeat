import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import '../models/playlist.dart';
import '../models/lyric_line.dart';
import 'audio_download_service.dart';

class DatabaseService {
  static final List<Track> _recentlyPlayed = [];
  static final List<Track> _downloadedTracks = [];
  static final Map<String, LyricsResult> _lyricsCache = {};
  static final List<String> _searchHistory = [];
  static final StreamController<void> _libraryUpdateController = StreamController<void>.broadcast();
  static final StreamController<void> _historyUpdateController = StreamController<void>.broadcast();
  static Future<void>? _loadFuture;

  /// Emitted when the library changes: downloads, playlists or favourites.
  /// Screens subscribe to this instead of relying on whichever call site
  /// happened to make the change to also remember to refresh them.
  static Stream<void> get libraryUpdateStream => _libraryUpdateController.stream;

  /// Emitted when the recently-played list changes — including when the audio
  /// handler auto-advances, which no UI action would otherwise notice.
  static Stream<void> get historyUpdateStream => _historyUpdateController.stream;

  /// Cap on the in-memory + on-disk lyrics cache.
  static const int _maxLyricsCacheEntries = 200;

  static final List<Playlist> _playlists = [
    Playlist(id: 'favorites', name: '收藏', tracks: [])
  ];

  static Future<void> _ensureLoaded() => _loadFuture ??= _load();

  static Future<void> _load() async {
    try {
      final docs = await getApplicationDocumentsDirectory();

      // Load Downloaded Tracks
      final downloadedFile = File('${docs.path}/bilibeat_downloaded.json');
      if (await downloadedFile.exists()) {
        final content = await downloadedFile.readAsString();
        final List<dynamic> list = jsonDecode(content);
        _downloadedTracks.clear();
        for (final item in list) {
          final t = Track.fromMap(Map<String, dynamic>.from(item));
          _downloadedTracks.add(t);
        }
      }

      // Auto-discover any downloaded audio files on disk
      final audioDir = Directory('${docs.path}/bilibeat_audio');
      if (await audioDir.exists()) {
        final List<FileSystemEntity> entities = await audioDir.list().toList();
        for (final entity in entities) {
          if (entity is File && entity.path.endsWith('.ready')) {
            final readyPath = entity.path;
            final audioPath = readyPath.replaceAll('.ready', '.m4a');
            final metaPath = readyPath.replaceAll('.ready', '.json');
            final audioFile = File(audioPath);
            final metaFile = File(metaPath);

            if (await audioFile.exists() && (await audioFile.length()) > 0 && await metaFile.exists()) {
              try {
                final metaContent = await metaFile.readAsString();
                final trackMap = Map<String, dynamic>.from(jsonDecode(metaContent));
                final track = Track.fromMap(trackMap);
                if (!_downloadedTracks.any((t) => t.id == track.id)) {
                  _downloadedTracks.add(track);
                }
              } catch (e) {
                debugPrint('Auto-discover track error: $e');
              }
            }
          }
        }
      }

      // Load Recently Played
      final recentFile = File('${docs.path}/bilibeat_recently_played.json');
      if (await recentFile.exists()) {
        final content = await recentFile.readAsString();
        final List<dynamic> list = jsonDecode(content);
        _recentlyPlayed.clear();
        for (final item in list) {
          final t = Track.fromMap(Map<String, dynamic>.from(item));
          _recentlyPlayed.add(t);
        }
      }

      // Load Playlists
      final playlistFile = File('${docs.path}/bilibeat_playlists.json');
      if (await playlistFile.exists()) {
        final content = await playlistFile.readAsString();
        final List<dynamic> list = jsonDecode(content);
        _playlists.clear();
        for (final item in list) {
          final map = Map<String, dynamic>.from(item);
          final List<dynamic> trackList = map['tracks'] ?? [];
          final tracks = trackList.map((t) => Track.fromMap(Map<String, dynamic>.from(t))).toList();
          _playlists.add(Playlist.fromMap(map, tracks: tracks));
        }
        if (!_playlists.any((p) => p.id == 'favorites')) {
          _playlists.insert(0, Playlist(id: 'favorites', name: '收藏', tracks: []));
        }
      }
      // Load Search History
      final historyFile = File('${docs.path}/bilibeat_search_history.json');
      if (await historyFile.exists()) {
        final content = await historyFile.readAsString();
        final List<dynamic> list = jsonDecode(content);
        _searchHistory
          ..clear()
          ..addAll(list.map((e) => e.toString()));
      }

      // Load the lyrics cache so a restart does not re-hit the network for
      // every track the user already has lyrics for.
      final lyricsFile = File('${docs.path}/bilibeat_lyrics.json');
      if (await lyricsFile.exists()) {
        final content = await lyricsFile.readAsString();
        final Map<String, dynamic> map = jsonDecode(content);
        map.forEach((key, value) {
          try {
            _lyricsCache[key] =
                LyricsResult.fromMap(Map<String, dynamic>.from(value as Map));
          } catch (e) {
            debugPrint('Lyrics cache entry $key skipped: $e');
          }
        });
      }
    } catch (e) {
      debugPrint('DatabaseService _ensureLoaded error: $e');
    }
  }

  static Future<void> _persistDownloaded() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final downloadedFile = File('${docs.path}/bilibeat_downloaded.json');
      final list = _downloadedTracks.map((t) => t.toMap()).toList();
      await downloadedFile.writeAsString(jsonEncode(list));
    } catch (e) {
      debugPrint('DatabaseService _persistDownloaded error: $e');
    }
  }

  static Future<void> _persistRecentlyPlayed() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final recentFile = File('${docs.path}/bilibeat_recently_played.json');
      final list = _recentlyPlayed.map((t) => t.toMap()).toList();
      await recentFile.writeAsString(jsonEncode(list));
    } catch (e) {
      debugPrint('DatabaseService _persistRecentlyPlayed error: $e');
    }
  }

  static Future<void> _persistPlaylists() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final playlistFile = File('${docs.path}/bilibeat_playlists.json');
      final list = _playlists.map((p) {
        final map = p.toMap();
        map['tracks'] = p.tracks.map((t) => t.toMap()).toList();
        return map;
      }).toList();
      await playlistFile.writeAsString(jsonEncode(list));
    } catch (e) {
      debugPrint('DatabaseService _persistPlaylists error: $e');
    }
    _libraryUpdateController.add(null);
  }

  static Future<void> _persistSearchHistory() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final historyFile = File('${docs.path}/bilibeat_search_history.json');
      await historyFile.writeAsString(jsonEncode(_searchHistory));
    } catch (e) {
      debugPrint('DatabaseService _persistSearchHistory error: $e');
    }
  }

  static Future<List<String>> getSearchHistory() async {
    await _ensureLoaded();
    return List<String>.from(_searchHistory);
  }

  static Future<void> addSearchHistory(String query) async {
    await _ensureLoaded();
    final q = query.trim();
    if (q.isEmpty) return;
    _searchHistory.remove(q);
    _searchHistory.insert(0, q);
    if (_searchHistory.length > 12) _searchHistory.removeLast();
    await _persistSearchHistory();
  }

  static Future<void> clearSearchHistory() async {
    await _ensureLoaded();
    _searchHistory.clear();
    await _persistSearchHistory();
  }

  static Future<void> updateTrackMetadata(Track updated) async {
    await _ensureLoaded();
    final dlIdx = _downloadedTracks.indexWhere((t) => t.id == updated.id);
    if (dlIdx != -1) {
      _downloadedTracks[dlIdx] = updated;
      await _persistDownloaded();
    }

    // Deliberate edit: this one does overwrite the on-disk copy.
    await AudioDownloadService.saveTrackMetadata(updated, force: true);

    for (final pl in _playlists) {
      final idx = pl.tracks.indexWhere((t) => t.id == updated.id);
      if (idx != -1) {
        pl.tracks[idx] = updated;
      }
    }
    await _persistPlaylists();

    final recIdx = _recentlyPlayed.indexWhere((t) => t.id == updated.id);
    if (recIdx != -1) {
      _recentlyPlayed[recIdx] = updated;
      await _persistRecentlyPlayed();
    }

    _libraryUpdateController.add(null);
    _historyUpdateController.add(null);
  }

  static Future<List<Playlist>> getPlaylists() async {
    await _ensureLoaded();
    return List<Playlist>.from(_playlists);
  }

  static Future<Playlist> getFavoritesPlaylist() async {
    await _ensureLoaded();
    return _playlists.firstWhere(
      (p) => p.id == 'favorites',
      orElse: () => _playlists.first,
    );
  }

  static Future<Playlist> createPlaylist(String name) async {
    await _ensureLoaded();
    final newPlaylist = Playlist(
      id: 'pl_\${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? '新建歌单' : name.trim(),
      tracks: [],
    );
    _playlists.add(newPlaylist);
    await _persistPlaylists();
    return newPlaylist;
  }

  /// Renames a playlist.
  static Future<void> renamePlaylist(String playlistId, String newName) async {
    await _ensureLoaded();
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return;
    final old = _playlists[idx];
    _playlists[idx] = Playlist(
      id: old.id,
      name: newName.trim().isEmpty ? old.name : newName.trim(),
      coverUrl: old.coverUrl,
      tracks: old.tracks,
    );
    await _persistPlaylists();
  }

  /// Sets (or clears, with null) a playlist's cover image.
  static Future<void> setPlaylistCover(String playlistId, String? path) async {
    await _ensureLoaded();
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return;
    final old = _playlists[idx];
    _playlists[idx] = Playlist(
      id: old.id,
      name: old.name,
      coverUrl: path,
      tracks: old.tracks,
    );
    await _persistPlaylists();
  }

  /// Moves a track within a playlist. Both indices are final positions —
  /// `onReorderItem` already accounts for the removal, unlike the deprecated
  /// `onReorder`, whose newIndex needed adjusting by hand.
  static Future<void> reorderPlaylist(
      String playlistId, int oldIndex, int newIndex) async {
    await _ensureLoaded();
    final pl = _playlists.firstWhere((p) => p.id == playlistId,
        orElse: () => Playlist(id: '', name: '', tracks: []));
    if (pl.id.isEmpty) return;
    _moveWithin(pl.tracks, oldIndex, newIndex);
    await _persistPlaylists();
  }

  /// The same, for the 本地 library, which is a list rather than a playlist.
  static Future<void> reorderDownloaded(int oldIndex, int newIndex) async {
    await _ensureLoaded();
    _moveWithin(_downloadedTracks, oldIndex, newIndex);
    await _persistDownloaded();
    _libraryUpdateController.add(null);
  }

  static void _moveWithin(List<Track> list, int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final track = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), track);
  }

  static Future<void> deletePlaylist(String playlistId) async {
    await _ensureLoaded();
    if (playlistId == 'favorites') return;
    _playlists.removeWhere((p) => p.id == playlistId);
    await _persistPlaylists();
  }

  static Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    await _ensureLoaded();
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return;
    final playlist = _playlists[idx];
    if (!playlist.tracks.any((t) => t.id == track.id)) {
      playlist.tracks.insert(0, track);
      await _persistPlaylists();
    }
  }

  static Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    await _ensureLoaded();
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return;
    final playlist = _playlists[idx];
    playlist.tracks.removeWhere((t) => t.id == trackId);
    await _persistPlaylists();
  }

  static Future<bool> isFavorite(String trackId) async {
    await _ensureLoaded();
    final favorites = await getFavoritesPlaylist();
    return favorites.tracks.any((t) => t.id == trackId);
  }

  static Future<bool> toggleFavorite(Track track) async {
    await _ensureLoaded();
    final favorites = await getFavoritesPlaylist();
    final exists = favorites.tracks.any((t) => t.id == track.id);

    if (exists) {
      favorites.tracks.removeWhere((t) => t.id == track.id);
      await _persistPlaylists();
      return false;
    } else {
      favorites.tracks.insert(0, track);
      await _persistPlaylists();
      return true;
    }
  }

  /// Records a play. De-duplication is by track **id** (`bvid_cid`) only:
  /// keying by `bvid` used to collapse the separate parts (P1/P2/…) of one
  /// video into a single entry, silently dropping tracks from the list.
  static Future<void> addRecentlyPlayed(Track track) async {
    await _ensureLoaded();
    final alreadyFirst =
        _recentlyPlayed.isNotEmpty && _recentlyPlayed.first.id == track.id;
    _recentlyPlayed.removeWhere((t) => t.id == track.id);
    _recentlyPlayed.insert(0, track);
    if (_recentlyPlayed.length > 50) _recentlyPlayed.removeLast();
    await _persistRecentlyPlayed();
    if (!alreadyFirst) _historyUpdateController.add(null);
  }

  static Future<List<Track>> getRecentlyPlayed() async {
    await _ensureLoaded();
    return List<Track>.from(_recentlyPlayed);
  }

  /// Registers [track] as available offline.
  ///
  /// If the library already knows this track, it is left exactly as it is.
  /// Playback calls this on every start with a possibly stale copy, and
  /// overwriting here reverted any title/artist/cover the user had edited —
  /// [updateTrackMetadata] is the only thing allowed to change that.
  static Future<void> saveDownloadedTrack(Track track) async {
    await _ensureLoaded();
    if (_downloadedTracks.any((t) => t.id == track.id)) return;
    _downloadedTracks.insert(0, track);
    await _persistDownloaded();
    _libraryUpdateController.add(null);
  }

  /// Deletes the local audio for [track] and forgets it from the library & playlists.
  static Future<void> removeDownloadedTrack(Track track) async {
    await _ensureLoaded();
    await AudioDownloadService.delete(track);
    _downloadedTracks.removeWhere((t) => t.id == track.id);
    await _persistDownloaded();
    for (final pl in _playlists) {
      pl.tracks.removeWhere((t) => t.id == track.id);
    }
    await _persistPlaylists();
    _libraryUpdateController.add(null);
  }

  static Future<List<Track>> getDownloadedTracks() async {
    await _ensureLoaded();
    return List<Track>.from(_downloadedTracks);
  }

  static Future<void> cacheLyrics(String trackId, LyricsResult lyrics) async {
    await _ensureLoaded();
    // Do not persist "not found" placeholders: they would stick forever and
    // stop the app from ever retrying a lookup that might succeed later.
    if (lyrics.source == 'none') {
      _lyricsCache.remove(trackId);
      return;
    }
    _lyricsCache[trackId] = lyrics;
    while (_lyricsCache.length > _maxLyricsCacheEntries) {
      _lyricsCache.remove(_lyricsCache.keys.first);
    }
    await _persistLyrics();
  }

  static Future<LyricsResult?> getCachedLyrics(String trackId) async {
    await _ensureLoaded();
    return _lyricsCache[trackId];
  }

  static Future<void> _persistLyrics() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File('${docs.path}/bilibeat_lyrics.json');
      final map = _lyricsCache.map((k, v) => MapEntry(k, v.toMap()));
      await file.writeAsString(jsonEncode(map));
    } catch (e) {
      debugPrint('DatabaseService _persistLyrics error: $e');
    }
  }
}
