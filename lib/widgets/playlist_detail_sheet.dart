import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/database_service.dart';
import '../services/download_manager.dart';
import 'empty_state.dart';
import 'glass_card.dart';
import 'mini_player.dart';
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
    final dockedPlayerHeight = MiniPlayer.totalHeight(context);

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
                        '${_currentPlaylist.tracks.length} 首',
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
                // Starting on a track that is still downloading would be
                // dropped from the queue immediately — start on the first
                // playable one instead.
                onPressed: _playableQueue.isEmpty
                    ? null
                    : () {
                        final queue = _playableQueue;
                        widget.onSelectTrack(queue.first, queue: queue);
                      },
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: const Text('播放全部', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                    child: EmptyState(
                      icon: Icons.library_music_rounded,
                      title: '歌单暂无曲目',
                      subtitle: '在搜索页点 + 添加',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: _currentPlaylist.tracks.length,
                    itemBuilder: (context, index) {
                      final track = _currentPlaylist.tracks[index];
                      final isDownloading =
                          DownloadManager.instance.isDownloading(track.id);
                      return Dismissible(
                        key: ValueKey(track.id),
                        direction: DismissDirection.endToStart,
                        background: _removeBackground(),
                        confirmDismiss: (_) => _confirmRemove(track),
                        onDismissed: (_) => _removeTrack(track),
                        child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          borderRadius: 12,
                          padding: EdgeInsets.zero,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: isDownloading ? null : () => widget.onSelectTrack(track, queue: _playableQueue),
                            onLongPress: () => TrackOptionsMenu.show(
                                context, track,
                                onTrackChanged: _refresh),
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
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// The red "remove" affordance revealed by swiping a row left.
  Widget _removeBackground() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        _isVirtualDownloads
            ? Icons.delete_outline_rounded
            : Icons.playlist_remove_rounded,
        color: AppColors.danger,
      ),
    );
  }

  bool get _isVirtualDownloads => _currentPlaylist.id == 'downloaded';

  Future<bool> _confirmRemove(Track track) async {
    // Removing from a playlist is trivially reversible; deleting the audio
    // itself is not, so only that path asks.
    if (!_isVirtualDownloads) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundElevated,
        title: const Text('删除本地音频',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text('将删除本地音频，可重新下载。',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _removeTrack(Track track) async {
    setState(() => _currentPlaylist.tracks.removeWhere((t) => t.id == track.id));
    if (_isVirtualDownloads) {
      await DatabaseService.removeDownloadedTrack(track);
    } else {
      await DatabaseService.removeTrackFromPlaylist(
          _currentPlaylist.id, track.id);
    }
    widget.onPlaylistUpdated?.call();
  }
}
