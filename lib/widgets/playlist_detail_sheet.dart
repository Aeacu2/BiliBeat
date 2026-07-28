import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/database_service.dart';
import '../services/download_manager.dart';
import 'glass_card.dart';
import 'track_options_menu.dart';
import 'cached_cover_image.dart';
import 'track_download_button.dart';

class PlaylistDetailSheet extends StatefulWidget {
  final Playlist playlist;
  final TrackAction onSelectTrack;
  final TrackAction? onPlayOnly;
  final VoidCallback? onPlaylistUpdated;
  final VoidCallback? onClose;

  const PlaylistDetailSheet({
    super.key,
    required this.playlist,
    required this.onSelectTrack,
    this.onPlayOnly,
    this.onPlaylistUpdated,
    this.onClose,
  });

  static Future<void> show(
    BuildContext context, {
    required Playlist playlist,
    required TrackAction onSelectTrack,
    TrackAction? onPlayOnly,
    VoidCallback? onPlaylistUpdated,
    VoidCallback? onClose,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black38,
      isScrollControlled: true,
      builder: (context) => PlaylistDetailSheet(
        playlist: playlist,
        onSelectTrack: onSelectTrack,
        onPlayOnly: onPlayOnly,
        onPlaylistUpdated: onPlaylistUpdated,
        onClose: onClose ?? () => Navigator.pop(context),
      ),
    );
  }

  @override
  State<PlaylistDetailSheet> createState() => _PlaylistDetailSheetState();
}

class _PlaylistDetailSheetState extends State<PlaylistDetailSheet> {
  late Playlist _currentPlaylist;
  StreamSubscription<void>? _dlSub;

  /// Playback queue for this view: the playlist's tracks minus any still
  /// downloading (not yet playable).
  List<Track> get _playableQueue => _currentPlaylist.tracks
      .where((t) => !DownloadManager.instance.isDownloading(t.id))
      .toList();
  Set<String> _dlIds = {};

  @override
  void initState() {
    super.initState();
    _currentPlaylist = widget.playlist;
    _dlIds =
        DownloadManager.instance.activeTasks.map((t) => t.track.id).toSet();
    _dlSub = DownloadManager.instance.updates.listen((_) {
      final ids =
          DownloadManager.instance.activeTasks.map((t) => t.track.id).toSet();
      if (!setEquals(ids, _dlIds)) {
        _dlIds = ids;
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _dlSub?.cancel();
    super.dispose();
  }

  void _refresh() async {
    final playlists = await DatabaseService.getPlaylists();
    final updated = playlists.firstWhere(
      (p) => p.id == _currentPlaylist.id,
      orElse: () => _currentPlaylist,
    );
    if (mounted) {
      setState(() {
        _currentPlaylist = updated;
      });
    }
    widget.onPlaylistUpdated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isFav = _currentPlaylist.id == 'favorites';
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final dockedPlayerHeight = 64.0 + bottomInset;

    return Container(
      margin: widget.onClose != null ? EdgeInsets.zero : EdgeInsets.only(bottom: dockedPlayerHeight),
      height: MediaQuery.of(context).size.height * 0.76,
      decoration: const BoxDecoration(
        color: Color(0xFF141416),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.black50,
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle & Top Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 48),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textFaint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: widget.onClose ?? () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: isFav
                          ? [AppColors.accent, const Color(0xFFFF5252)]
                          : [const Color(0xFF3A3A40), const Color(0xFF232327)],
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      isFav ? Icons.favorite : Icons.queue_music,
                      color: AppColors.textPrimary,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentPlaylist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_currentPlaylist.tracks.length} 首曲目 • ${_currentPlaylist.description ?? "歌单音源已归档"}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          if (_currentPlaylist.tracks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: () {
                  widget.onSelectTrack(_currentPlaylist.tracks.first,
                      queue: _playableQueue);
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: const Text('播放全部并展开', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.textPrimary,
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),

          const SizedBox(height: 8),

          // Track List
          Expanded(
            child: _currentPlaylist.tracks.isEmpty
                ? const Center(
                    child: Text(
                      '歌单暂无曲目\n在搜索或推荐页面点击歌曲旁边的加号(+)按钮添加吧！',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textFaint, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: _currentPlaylist.tracks.length,
                    itemBuilder: (context, index) {
                      final track = _currentPlaylist.tracks[index];
                      final isDownloading =
                          DownloadManager.instance.isDownloading(track.id);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          borderRadius: 12,
                          padding: EdgeInsets.zero,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: isDownloading ? null : () => widget.onSelectTrack(track, queue: _playableQueue),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedCoverImage(
                                      url: track.coverUrl,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          track.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                                        ),
                                        Text(
                                          track.uploader,
                                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Play / download-with-ring button.
                                  TrackDownloadButton(
                                    track: track,
                                    size: 24,
                                    onPlay: () {
                                      if (widget.onPlayOnly != null) {
                                        widget.onPlayOnly!(track,
                                            queue: _playableQueue);
                                      } else {
                                        widget.onSelectTrack(track,
                                            queue: _playableQueue);
                                      }
                                    },
                                  ),
                                  // Plus sign button (+) to Add to Playlist
                                  IconButton(
                                    icon: const Icon(Icons.add, color: AppColors.textSecondary, size: 22),
                                    tooltip: '添加至歌单',
                                    onPressed: () {
                                      TrackOptionsMenu.showAddToPlaylist(context, track, onTrackChanged: _refresh);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
