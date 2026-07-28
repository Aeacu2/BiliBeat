import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/bilibili_sdk.dart';
import '../services/database_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/track_options_menu.dart';
import '../theme/app_theme.dart';
import '../widgets/cached_cover_image.dart';
import '../widgets/shimmer.dart';
import '../widgets/track_download_button.dart';

class SearchScreen extends StatefulWidget {
  final TrackAction onSelectTrack;
  final TrackAction? onPlayOnly;

  const SearchScreen({
    super.key,
    required this.onSelectTrack,
    this.onPlayOnly,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<Track> _searchResults = [];
  List<Track> _recommendedTracks = [];
  bool _isLoading = false;
  bool _isLoadingRecommended = true;

  List<String> _searchHistory = [];

  bool _wasFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    _searchController.addListener(_onTextChange);
    _loadSearchHistory();
    _loadRecommendations();
  }

  Future<void> _loadSearchHistory() async {
    final history = await DatabaseService.getSearchHistory();
    if (mounted) setState(() => _searchHistory = history);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _searchController.removeListener(_onTextChange);
    _focusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final focused = _focusNode.hasFocus;
    if (focused != _wasFocused) {
      _wasFocused = focused;
      setState(() {});
    }
  }

  void _onTextChange() {
    setState(() {});
  }

  Future<void> _loadRecommendations() async {
    try {
      final tracks = await BilibiliSdk.search('动漫原声OST');
      if (mounted) {
        setState(() {
          _recommendedTracks = tracks;
          _isLoadingRecommended = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingRecommended = false);
      }
    }
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    await DatabaseService.addSearchHistory(trimmed);
    final history = await DatabaseService.getSearchHistory();

    _focusNode.unfocus();
    setState(() {
      _searchHistory = history;
      _isLoading = true;
    });

    final results = await BilibiliSdk.search(trimmed);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 120),
      children: [
        const Text('搜索', style: AppTypography.display),

        const SizedBox(height: 16),

        // Search Input Bar with Focus Listener
        GlassCard(
          borderRadius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.search, color: AppColors.textMuted, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  onSubmitted: _performSearch,
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    hintText: '输入 BV 号 / B 站链接 / 歌曲关键词',
                    hintStyle: TextStyle(color: AppColors.textFaint, fontSize: 14),
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (_searchController.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchResults = []);
                  },
                  child: const Icon(Icons.clear, color: AppColors.textMuted, size: 18),
                ),
            ],
          ),
        ),

        // Show Search History ONLY when Search Bar is Focused / Tapped!
        if (_focusNode.hasFocus) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '历史搜索',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              if (_searchHistory.isNotEmpty)
                GestureDetector(
                  onTap: () async {
                    await DatabaseService.clearSearchHistory();
                    if (mounted) setState(() => _searchHistory = []);
                  },
                  child: const Text('清空历史', style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _searchHistory.map((tag) {
              return ActionChip(
                label: Text(tag, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                backgroundColor: const Color(0x1AFFFFFF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                onPressed: () {
                  _searchController.text = tag;
                  _performSearch(tag);
                },
              );
            }).toList(),
          ),
        ],

        const SizedBox(height: 24),

        // Loading Indicator
        if (_isLoading)
          const Column(
            children: [
              SkeletonTrackTile(),
              SkeletonTrackTile(),
              SkeletonTrackTile(),
              SkeletonTrackTile(),
              SkeletonTrackTile(),
            ],
          )
        // Active Search Results List
        else if (_searchResults.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '搜索结果 (${_searchResults.length})',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchResults = []);
                },
                child: const Text('清空搜索', style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._searchResults.map((track) => _buildTrackTile(track)),
        ]
        // Default Auto Recommendations View
        else ...[
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.accent, size: 20),
              SizedBox(width: 8),
              Text(
                '为您推荐',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_isLoadingRecommended)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
              ),
            )
          else
            ..._recommendedTracks.map((track) => _buildTrackTile(track)),
        ],
      ],
    );
  }

  Widget _buildTrackTile(Track track) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        borderRadius: 14,
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          // Tapping card body: Plays AND Directly Opens Full Player Sheet!
          onTap: () => widget.onSelectTrack(track),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedCoverImage(
                    url: track.coverUrl,
                    width: 54,
                    height: 54,
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
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${track.uploader} • ${(track.duration / 60).floor()}:${(track.duration % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),

                // Download / play button with live progress ring.
                TrackDownloadButton(
                  track: track,
                  size: 24,
                  onPlay: () {
                    if (widget.onPlayOnly != null) {
                      widget.onPlayOnly!(track);
                    } else {
                      widget.onSelectTrack(track);
                    }
                  },
                ),

                // Plus Sign Button (+) to Add to Playlist
                IconButton(
                  icon: const Icon(Icons.add, color: AppColors.textSecondary, size: 22),
                  tooltip: '添加至歌单',
                  onPressed: () {
                    TrackOptionsMenu.showAddToPlaylist(context, track, onTrackChanged: () {
                      if (mounted) setState(() {});
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
