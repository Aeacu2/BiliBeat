import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/bilibili_sdk.dart';
import '../services/database_service.dart';
import '../services/recommendation_engine.dart';
import '../widgets/glass_card.dart';
import '../widgets/track_options_menu.dart';
import '../theme/app_theme.dart';
import '../widgets/cached_cover_image.dart';
import '../widgets/empty_state.dart';
import '../widgets/marquee_text.dart';
import '../widgets/mini_player.dart';
import '../widgets/shimmer.dart';
import '../widgets/track_download_button.dart';
import '../widgets/track_row.dart';

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
  bool _hasSearched = false;
  String _lastQuery = '';

  List<String> _searchHistory = [];

  bool _wasFocused = false;
  bool _hadText = false;
  bool _recommendationsStale = false;

  /// Monotonic token so a slow earlier search can never overwrite the results
  /// of a later one.
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    _searchController.addListener(_onTextChange);
    _loadSearchHistory();
  }

  Future<void> _loadSearchHistory() async {
    final history = await DatabaseService.getSearchHistory();
    if (!mounted) return;
    setState(() => _searchHistory = history);
    _loadRecommendations();
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
    // The only thing the text drives in this build is the clear button, so
    // rebuilding the entire result list on every keystroke is wasted work.
    final hasText = _searchController.text.isNotEmpty;
    if (hasText != _hadText) {
      _hadText = hasText;
      setState(() {});
    }
  }

  /// Recommendations are only meaningful once there is something to learn
  /// from, and the first search is the earliest moment that is true — so the
  /// section stays hidden until then. Clearing search history hides it again,
  /// which is deliberate: it is one of the three signals feeding the profile.
  bool get _canRecommend => _searchHistory.isNotEmpty;

  Future<void> _loadRecommendations() async {
    if (!_canRecommend) {
      if (mounted) {
        setState(() {
          _recommendedTracks = const [];
          _isLoadingRecommended = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _isLoadingRecommended = true);
    try {
      final tracks = await RecommendationEngine.recommend();
      if (mounted) {
        setState(() {
          _recommendedTracks = tracks;
          _isLoadingRecommended = false;
          _recommendationsStale = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingRecommended = false);
      }
    }
  }

  /// Returning to the recommendation view after searching is the natural place
  /// to fold that new signal in — refreshing on every keystroke or every
  /// search would mean several extra requests per query.
  void _showRecommendations() {
    _searchController.clear();
    setState(() {
      _searchResults = const [];
      _hasSearched = false;
    });
    if (_recommendationsStale) _loadRecommendations();
  }

  Future<void> _clearSearchHistory() async {
    await DatabaseService.clearSearchHistory();
    if (!mounted) return;
    // Search history feeds the taste profile, so dropping it must drop its
    // influence too — not just the chips.
    setState(() {
      _searchHistory = const [];
      _recommendedTracks = const [];
      _recommendationsStale = true;
    });
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    await DatabaseService.addSearchHistory(trimmed);
    final history = await DatabaseService.getSearchHistory();
    // Leaving the tab during those awaits would otherwise unfocus a disposed
    // FocusNode and setState on a dead State.
    if (!mounted) return;

    _focusNode.unfocus();
    setState(() {
      _searchHistory = history;
      _isLoading = true;
      _hasSearched = true;
      _lastQuery = trimmed;
    });

    final token = ++_searchToken;
    final results = await BilibiliSdk.search(trimmed);
    if (mounted && token == _searchToken) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
        // This search is new evidence about taste; fold it in next time the
        // recommendation view is shown.
        _recommendationsStale = true;
      });
    }
  }

  /// Result rows that should be built lazily rather than all at once.
  List<Track> get _visibleTracks {
    if (_isLoading) return const [];
    if (_hasSearched) return _searchResults;
    if (!_canRecommend || _isLoadingRecommended) return const [];
    return _recommendedTracks;
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 20),
          sliver: SliverList(delegate: SliverChildListDelegate(_header())),
        ),
        // Rows are built on demand so a long result list costs only what is
        // actually on screen.
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.builder(
            itemCount: _visibleTracks.length,
            itemBuilder: (context, index) =>
                _buildTrackTile(_visibleTracks[index], index),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: MiniPlayer.totalHeight(context) + 24),
        ),
      ],
    );
  }

  List<Widget> _header() {
    return [
        // No "搜索" heading: the tab bar above already says which page this is,
        // and printing the same word twice, one line apart, was pure noise.
        // Search Input Bar with Focus Listener
        GlassCard(
          borderRadius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
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
                    hintText: '搜索歌曲、BV 号或链接',
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
                  onTap: _clearSearchHistory,
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
        else if (_hasSearched && _searchResults.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_searchResults.length} 个结果',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: _showRecommendations,
                child: const Text('清空搜索', style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ]
        // Search Completed but No Results Found
        else if (_hasSearched && _searchResults.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                const Icon(Icons.search_off_rounded, size: 48, color: AppColors.textMuted),
                const SizedBox(height: 12),
                Text(
                  '未找到「$_lastQuery」',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  '试试 BV 号，或更简短的关键词',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _performSearch(_lastQuery),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重试'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent30),
                  ),
                ),
              ],
            ),
          ),
        ]
        // Default view: recommendations, once there is a search to learn from.
        else if (!_canRecommend) ...[
          const EmptyState(
            icon: Icons.search_rounded,
            title: '先搜索一首歌吧',
            subtitle: '搜过之后，这里会根据你的收藏与播放推荐',
          ),
        ] else ...[
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.accent, size: 20),
              SizedBox(width: 8),
              Text(
                '推荐',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_isLoadingRecommended)
            const Column(
              children: [
                SkeletonTrackTile(),
                SkeletonTrackTile(),
                SkeletonTrackTile(),
              ],
            )
          else if (_recommendedTracks.isEmpty)
            const EmptyState(
              icon: Icons.wifi_off_rounded,
              title: '暂时没有推荐',
              subtitle: '收藏几首歌之后会更准，也可以检查网络后重试',
            ),
        ],
      ];
  }

  Widget _buildTrackTile(Track track, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TrackRow.gap),
      child: TrackRow(
          // Tapping the row: plays AND opens the full player.
          onTap: () => widget.onSelectTrack(track),
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
                      // Bilibili titles are routinely far wider than a row.
                      // The marquee is affordable here because it only
                      // animates when the text actually overflows, and the
                      // RepaintBoundary keeps each ticking title from
                      // repainting the rest of the row.
                      RepaintBoundary(
                        child: MarqueeText(
                          text: track.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                          // Desynchronise rows so a screenful of titles does
                          // not slide in lockstep.
                          phase: (index % 5) / 5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${track.uploader} • ${(track.duration / 60).floor()}:${(track.duration % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),

                // Nudged right: the gap that was missing between the title
                // and the download control comes out of the padding after the
                // last button, so the title keeps exactly the width it had.
                const SizedBox(width: 8),
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
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  onPressed: () {
                    TrackOptionsMenu.showAddToPlaylist(context, track, onTrackChanged: () {
                      if (mounted) setState(() {});
                    });
                  },
                ),
              ],
          ),
      ),
    );
  }
}
