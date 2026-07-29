import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import '../theme/haptics.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/database_service.dart';
import '../services/download_manager.dart';
import 'empty_state.dart';
import 'track_row.dart';
import 'marquee_text.dart';
import 'mini_player.dart';
import 'track_options_menu.dart';
import 'cached_cover_image.dart';
import 'track_download_button.dart';

class PlaylistDetailSheet extends StatefulWidget {
  final Playlist playlist;
  final TrackAction onSelectTrack;
  final TrackAction? onPlayOnly;
  final void Function(List<Track> tracks, {bool shuffle})? onPlayCollection;
  final VoidCallback? onPlaylistUpdated;
  final VoidCallback? onClose;

  const PlaylistDetailSheet({
    super.key,
    required this.playlist,
    required this.onSelectTrack,
    this.onPlayOnly,
    this.onPlayCollection,
    this.onPlaylistUpdated,
    this.onClose,
  });

  static Future<void> show(
    BuildContext context, {
    required Playlist playlist,
    required TrackAction onSelectTrack,
    TrackAction? onPlayOnly,
    void Function(List<Track> tracks, {bool shuffle})? onPlayCollection,
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
        onPlayCollection: onPlayCollection,
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
  StreamSubscription<void>? _libSub;

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
    // Metadata can be edited from the now-playing page stacked on top of this
    // sheet; without this the sheet kept rendering the pre-edit title.
    _libSub = DatabaseService.libraryUpdateStream.listen((_) => _refresh());
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
    _libSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    // 本地 is a virtual playlist with no database row, so it is rebuilt from
    // the download library rather than looked up by id.
    final Playlist updated;
    if (_isVirtualDownloads) {
      updated = Playlist(
        id: _currentPlaylist.id,
        name: _currentPlaylist.name,
        tracks: await DatabaseService.getDownloadedTracks(),
      );
    } else {
      final playlists = await DatabaseService.getPlaylists();
      updated = playlists.firstWhere(
        (p) => p.id == _currentPlaylist.id,
        orElse: () => _currentPlaylist,
      );
    }
    if (mounted) setState(() => _currentPlaylist = updated);
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
                _headerArtwork(isFav),
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
                // dropped from the queue immediately — the queue is the
                // playable subset.
                onPressed: _playableQueue.isEmpty
                    ? null
                    : () {
                        Haptics.medium();
                        widget.onPlayCollection?.call(_playableQueue,
                            shuffle: true);
                      },
                icon: const Icon(Icons.shuffle_rounded, size: 22),
                label: const Text('随机播放', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: _currentPlaylist.tracks.length,
                    // No grab handles: the row is the handle, after a hold.
                    // A dedicated handle would be a third control on a row
                    // that already has two.
                    buildDefaultDragHandles: false,
                    onReorderItem: _onReorder,
                    proxyDecorator: (child, index, animation) => Material(
                      color: Colors.transparent,
                      child: Opacity(opacity: 0.9, child: child),
                    ),
                    itemBuilder: (context, index) {
                      final track = _currentPlaylist.tracks[index];
                      final isDownloading =
                          DownloadManager.instance.isDownloading(track.id);
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(track.id),
                        index: index,
                        child: Dismissible(
                        key: ValueKey('d_${track.id}'),
                        direction: DismissDirection.endToStart,
                        background: _removeBackground(),
                        confirmDismiss: (_) => _confirmRemove(track),
                        onDismissed: (_) => _removeTrack(track),
                        child: Padding(
                        padding: const EdgeInsets.only(bottom: TrackRow.gap),
                        child: TrackRow(
                            // No onLongPress here: holding a row now picks it
                            // up to reorder. The options menu is still on the
                            // same track's row in 聆听 / 搜索.
                            onTap: isDownloading ? null : () => widget.onSelectTrack(track, queue: _playableQueue),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedCoverImage(
                                      url: track.coverUrl,
                                      width: 48,
                                      height: 48,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        RepaintBoundary(
                                          child: MarqueeText(
                                            text: track.title,
                                            phase: (index % 5) / 5,
                                            style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                height: 1.3),
                                          ),
                                        ),
                                        Text(
                                          track.uploader,
                                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Nudged right, with the gap taken from the
                                  // padding after the last button rather than
                                  // from the title's width.
                                  const SizedBox(width: 8),
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
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 40, minHeight: 40),
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

  /// The red "remove" affordance revealed by swiping a row left.
  Widget _removeBackground() {
    return Container(
      margin: const EdgeInsets.only(bottom: TrackRow.gap),
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

  /// The playlist's artwork, and the way to change it. 本地 is rebuilt from
  /// the download library on every refresh and has no row to store a cover on,
  /// so it keeps the default badge.
  Widget _headerArtwork(bool isFav) {
    final cover = _currentPlaylist.coverUrl;
    final editable = !_isVirtualDownloads;
    return GestureDetector(
      onTap: editable ? _pickCover : null,
      child: SizedBox(
        width: 72,
        height: 72,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: cover != null && cover.isNotEmpty
                    ? CachedCoverImage(url: cover, width: 72, height: 72)
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isFav
                                ? [AppColors.accent, const Color(0xFFFF5252)]
                                : [
                                    const Color(0xFF3A3A40),
                                    const Color(0xFF232327)
                                  ],
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
              ),
            ),
            if (editable)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.backgroundElevated,
                    border: Border.fromBorderSide(
                        BorderSide(color: AppColors.hairlineStrong)),
                  ),
                  child: const Icon(Icons.photo_camera_rounded,
                      color: AppColors.textSecondary, size: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCover() async {
    Haptics.light();
    try {
      final image =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null) return;
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/bilibeat_covers');
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = image.path.split('.').last;
      final saved = File(
          '${dir.path}/playlist_${_currentPlaylist.id}_'
          '${DateTime.now().millisecondsSinceEpoch}.$ext');
      await File(image.path).copy(saved.path);
      await DatabaseService.setPlaylistCover(_currentPlaylist.id, saved.path);
      await _refresh();
    } catch (e) {
      debugPrint('Playlist cover pick failed: $e');
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    Haptics.selection();
    // Reorder locally first so the list does not flash back to the old order
    // while the store round-trips.
    setState(() {
      final tracks = _currentPlaylist.tracks;
      final track = tracks.removeAt(oldIndex);
      tracks.insert(newIndex.clamp(0, tracks.length), track);
    });
    if (_isVirtualDownloads) {
      await DatabaseService.reorderDownloaded(oldIndex, newIndex);
    } else {
      await DatabaseService.reorderPlaylist(
          _currentPlaylist.id, oldIndex, newIndex);
    }
    widget.onPlaylistUpdated?.call();
  }

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
        content: const Text('将删除本地音频，可重新下载。',
            style: TextStyle(color: AppColors.textSecondary)),
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
