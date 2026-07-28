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
  static final StreamController<void> _downloadUpdateController = StreamController<void>.broadcast();
  static Future<void>? _loadFuture;

  static Stream<void> get downloadUpdateStream => _downloadUpdateController.stream;

  static final List<Playlist> _playlists = [
    Playlist(
      id: 'favorites',
      name: '收藏',
      description: '你的个人精选收藏',
      tracks: [],
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    )
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
                if (!_downloadedTracks.any((t) => t.id == track.id || (t.bvid.isNotEmpty && t.bvid == track.bvid))) {
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
          _playlists.insert(0, Playlist(
            id: 'favorites',
            name: '收藏',
            description: '你的个人精选收藏',
            tracks: [],
            createdAt: DateTime.now().millisecondsSinceEpoch,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ));
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
    final dlIdx = _downloadedTracks.indexWhere((t) => t.bvid == updated.bvid || t.id == updated.id);
    if (dlIdx != -1) {
      _downloadedTracks[dlIdx] = updated;
      await _persistDownloaded();
    }

    await AudioDownloadService.saveTrackMetadata(updated);

    for (final pl in _playlists) {
      final idx = pl.tracks.indexWhere((t) => t.bvid == updated.bvid || t.id == updated.id);
      if (idx != -1) {
        pl.tracks[idx] = updated;
      }
    }
    await _persistPlaylists();

    final recIdx = _recentlyPlayed.indexWhere((t) => t.bvid == updated.bvid || t.id == updated.id);
    if (recIdx != -1) {
      _recentlyPlayed[recIdx] = updated;
      await _persistRecentlyPlayed();
    }

    _downloadUpdateController.add(null);
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

  static Future<Playlist> createPlaylist(String name, {String? description}) async {
    await _ensureLoaded();
    final newPlaylist = Playlist(
      id: 'pl_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? '新建歌单' : name.trim(),
      description: description,
      tracks: [],
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _playlists.add(newPlaylist);
    await _persistPlaylists();
    return newPlaylist;
  }

  static Future<void> deletePlaylist(String playlistId) async {
    await _ensureLoaded();
    if (playlistId == 'favorites') return;
    _playlists.removeWhere((p) => p.id == playlistId);
    await _persistPlaylists();
  }

  static Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    await _ensureLoaded();
    final playlist = _playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => _playlists.first,
    );
    if (!playlist.tracks.any((t) => t.id == track.id || (t.bvid.isNotEmpty && t.bvid == track.bvid))) {
      playlist.tracks.insert(0, track);
      await _persistPlaylists();
    }
  }

  static Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    await _ensureLoaded();
    final playlist = _playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => _playlists.first,
    );
    playlist.tracks.removeWhere((t) => t.id == trackId);
    await _persistPlaylists();
  }

  static Future<bool> isFavorite(String trackId) async {
    await _ensureLoaded();
    final favorites = await getFavoritesPlaylist();
    return favorites.tracks.any((t) => t.id == trackId || (t.bvid.isNotEmpty && t.bvid == trackId));
  }

  static Future<bool> toggleFavorite(Track track) async {
    await _ensureLoaded();
    final favorites = await getFavoritesPlaylist();
    final exists = favorites.tracks.any((t) => t.id == track.id || (t.bvid.isNotEmpty && t.bvid == track.bvid));

    if (exists) {
      favorites.tracks.removeWhere((t) => t.id == track.id || (t.bvid.isNotEmpty && t.bvid == track.bvid));
      await _persistPlaylists();
      return false;
    } else {
      favorites.tracks.insert(0, track);
      await _persistPlaylists();
      return true;
    }
  }

  static Future<void> addRecentlyPlayed(Track track) async {
    await _ensureLoaded();
    final bvid = track.bvid.isNotEmpty ? track.bvid : track.id;
    _recentlyPlayed.removeWhere((t) => t.id == track.id || (t.bvid.isNotEmpty && t.bvid == bvid));
    _recentlyPlayed.insert(0, track);
    if (_recentlyPlayed.length > 50) _recentlyPlayed.removeLast();
    await _persistRecentlyPlayed();
  }

  static Future<List<Track>> getRecentlyPlayed() async {
    await _ensureLoaded();
    return _recentlyPlayed;
  }

  static Future<void> saveDownloadedTrack(Track track, String filePath) async {
    await _ensureLoaded();
    final bvid = track.bvid.isNotEmpty ? track.bvid : track.id;
    _downloadedTracks.removeWhere((t) => t.id == track.id || (t.bvid.isNotEmpty && t.bvid == bvid));
    _downloadedTracks.insert(0, track);
    await _persistDownloaded();
    _downloadUpdateController.add(null);
  }

  static Future<List<Track>> getDownloadedTracks() async {
    await _ensureLoaded();
    return List<Track>.from(_downloadedTracks);
  }

  static Future<void> cacheLyrics(String trackId, LyricsResult lyrics) async {
    _lyricsCache[trackId] = lyrics;
  }

  static Future<LyricsResult?> getCachedLyrics(String trackId) async {
    return _lyricsCache[trackId];
  }
}
