import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../services/database_service.dart';
import '../services/download_manager.dart';
import '../widgets/glass_card.dart';
import '../widgets/playlist_detail_sheet.dart';
import '../widgets/track_options_menu.dart';
import '../theme/app_theme.dart';
import '../widgets/cached_cover_image.dart';
import '../widgets/empty_state.dart';
import '../widgets/track_download_button.dart';

import 'dart:async';

class HomeScreen extends StatefulWidget {
  final List<Track> recentlyPlayed;
  final TrackAction onSelectTrack;
  final TrackAction? onPlayOnly;
  final Function(Playlist)? onOpenPlaylist;

  const HomeScreen({
    super.key,
    required this.recentlyPlayed,
    required this.onSelectTrack,
    this.onPlayOnly,
    this.onOpenPlaylist,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Playlist> _playlists = [];
  List<Track> _downloadedTracks = [];
  StreamSubscription<void>? _downloadSub;
  StreamSubscription<void>? _downloadManagerSub;
  List<DownloadTask> _downloadingTasks = [];
  Set<String> _downloadingIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshDownloading();
    _downloadSub = DatabaseService.downloadUpdateStream.listen((_) {
      _loadData();
    });
    _downloadManagerSub = DownloadManager.instance.updates.listen((_) {
      final ids =
          DownloadManager.instance.activeTasks.map((t) => t.track.id).toSet();
      if (!setEquals(ids, _downloadingIds)) {
        _downloadingIds = ids;
        _refreshDownloading();
      }
    });
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    _downloadManagerSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final playlists = await DatabaseService.getPlaylists();
    final downloaded = await DatabaseService.getDownloadedTracks();
    if (mounted) {
      setState(() {
        _playlists = playlists;
        _downloadedTracks = downloaded;
      });
    }
  }

  void _refreshDownloading() {
    if (!mounted) return;
    setState(() {
      _downloadingTasks = DownloadManager.instance.activeTasks;
    });
  }

  void _openCreatePlaylistDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundElevated,
        title: const Text('新建歌单', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: '请输入歌单名称',
            hintStyle: TextStyle(color: AppColors.textFaint),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          TextButton(
            child: const Text('创建', style: TextStyle(color: AppColors.accent)),
            onPressed: () => Navigator.pop(ctx, controller.text),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      await DatabaseService.createPlaylist(name);
      _loadData();
    }
  }

  void _openPlaylist(Playlist pl) {
    if (widget.onOpenPlaylist != null) {
      widget.onOpenPlaylist!(pl);
    } else {
      PlaylistDetailSheet.show(
        context,
        playlist: pl,
        onSelectTrack: widget.onSelectTrack,
        onPlayOnly: widget.onPlayOnly,
        onPlaylistUpdated: _loadData,
      );
    }
  }

  void _openDownloadedPlaylist() {
    _openPlaylist(Playlist(
      id: 'downloaded',
      name: '已下载歌曲',
      description: '无网络离线可播放的本地歌曲',
      tracks: [..._downloadingTasks.map((t) => t.track), ..._downloadedTracks],
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 120),
      children: [
        // Screen Header
        const Text('聆听', style: AppTypography.display),

        const SizedBox(height: 16),

        // Quick Access Cards: Downloaded Tracks & Favorites
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _openDownloadedPlaylist,
                child: GlassCard(
                  borderRadius: 18,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [AppColors.success, Color(0xFF059669)],
                          ),
                        ),
                        child: const Icon(Icons.download_done, color: AppColors.textPrimary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '已下载',
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _downloadingTasks.isEmpty
                                  ? '${_downloadedTracks.length} 首已下载'
                                  : '${_downloadingTasks.length} 首下载中 · ${_downloadedTracks.length} 首已下载',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        if (_downloadingTasks.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('下载中', style: AppTypography.title),
          const SizedBox(height: 12),
          ..._downloadingTasks.map(
            (task) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: CachedCoverImage(
                        url: task.track.coverUrl,
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
                            task.track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            task.track.uploader,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    TrackDownloadButton(track: task.track, size: 22),
                  ],
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),

        // Playlists Section Header
        const Text('我的歌单', style: AppTypography.title),

        const SizedBox(height: 12),

        // Playlists Horizontal List
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _playlists.length + 1,
            itemBuilder: (context, index) {
              if (index == _playlists.length) {
                // "New Playlist" button card
                return GestureDetector(
                  onTap: _openCreatePlaylistDialog,
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 14),
                    child: const GlassCard(
                      borderRadius: 16,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: AppColors.accent, size: 36),
                          SizedBox(height: 8),
                          Text('新建歌单', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final pl = _playlists[index];
              final isFav = pl.id == 'favorites';

              return GestureDetector(
                onTap: () => _openPlaylist(pl),
                child: Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 14),
                  child: GlassCard(
                    borderRadius: 16,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              colors: isFav
                                  ? [AppColors.accent, AppColors.pinkStart]
                                  : [const Color(0xFF3A3A40), const Color(0xFF232327)],
                            ),
                          ),
                          child: Icon(
                            isFav ? Icons.favorite : Icons.queue_music,
                            color: AppColors.textPrimary,
                            size: 24,
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pl.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${pl.tracks.length} 首歌曲',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 28),

        // Recently Played Section
        const Text('最近播放', style: AppTypography.title),

        const SizedBox(height: 14),

        if (widget.recentlyPlayed.isEmpty)
          const EmptyState(
            icon: Icons.history_rounded,
            title: '暂无最近播放记录',
            subtitle: '在搜索页查找 BV 号或输入歌名开始听歌吧',
          )
        else
          SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.recentlyPlayed.length,
              itemBuilder: (context, index) {
                final track = widget.recentlyPlayed[index];
                return GestureDetector(
                  onTap: () => widget.onSelectTrack(track),
                  onLongPress: () {
                    TrackOptionsMenu.show(context, track, onTrackChanged: _loadData);
                  },
                  child: Container(
                    width: 130,
                    margin: const EdgeInsets.only(right: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: CachedCoverImage(
                            url: track.coverUrl,
                            width: 130,
                            height: 130,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          track.uploader,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
