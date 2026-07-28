import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/track.dart';
import 'models/playlist.dart';
import 'models/lyric_line.dart';
import 'services/lyrics_engine.dart';
import 'services/database_service.dart';
import 'services/audio_player_handler.dart';
import 'services/audio_download_service.dart';
import 'theme/app_theme.dart';
import 'theme/haptics.dart';
import 'widgets/ambient_background.dart';
import 'widgets/mini_player.dart';
import 'widgets/now_playing_sheet.dart';
import 'widgets/lyric_editor_dialog.dart';
import 'widgets/playlist_detail_sheet.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';

import 'package:audio_service/audio_service.dart';

BiliBeatAudioHandler? _audioHandlerInstance;

/// The one handler registered with `audio_service`. Reading this before
/// [main] has initialised it is a programming error — lazily constructing a
/// second handler here would silently detach playback from the OS media
/// session, so we fail loudly instead.
BiliBeatAudioHandler get audioHandlerInstance {
  final handler = _audioHandlerInstance;
  assert(handler != null, 'audioHandlerInstance read before AudioService.init');
  return handler!;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 60;
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  _audioHandlerInstance = await AudioService.init(
    builder: () => BiliBeatAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.bilibeat.channel.audio',
      androidNotificationChannelName: 'BiliBeat',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );
  runApp(const BiliBeatApp());
}

class BiliBeatApp extends StatelessWidget {
  const BiliBeatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiliBeat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _activeTabIndex = 0;
  final GlobalKey _tabRowKey = GlobalKey();
  final List<GlobalKey> _tabKeys = [GlobalKey(), GlobalKey()];
  double _indicatorLeft = 0;
  double _indicatorWidth = 0;
  late final BiliBeatAudioHandler _audioHandler = audioHandlerInstance;

  Track? _currentTrack;
  bool _isPlaying = false;
  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<List<LyricLine>> _lyricsNotifier = ValueNotifier([]);
  List<Track> _recentlyPlayed = [];
  Playlist? _activePlaylistSheet;

  late final PageController _pageController = PageController(initialPage: 0);
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _initListeners();
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateIndicator());
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _lyricsNotifier.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _initListeners() {
    _subs.add(_audioHandler.currentTrackStream.listen((track) async {
      if (track != null) {
        if (mounted) {
          setState(() {
            _currentTrack = track;
          });
        }

        // Fetch lyrics with stale cache validation
        final cleanSongTitle = LyricsEngine.cleanTitle(track.title)['songTitle']!;
        final cached = await DatabaseService.getCachedLyrics(track.id);
        if (_currentTrack?.id != track.id) return;

        bool isCacheValid = false;
        if (cached != null && cached.lines.isNotEmpty && cached.source != 'none') {
          final cachedTitle = cached.songTitle ?? '';
          if (cachedTitle.isNotEmpty && LyricsEngine.isTitleMatching(cachedTitle, cleanSongTitle)) {
            isCacheValid = true;
          }
        }

        if (isCacheValid) {
          _lyricsNotifier.value = cached!.lines;
        } else {
          _lyricsNotifier.value = const [];
          final freshLyrics = await LyricsEngine.autoFetchLyrics(track.title);
          if (_currentTrack?.id != track.id) return;
          // A "not found" result carries placeholder lines; showing an empty
          // list instead lets the lyrics view offer its search/paste action.
          _lyricsNotifier.value =
              freshLyrics.source == 'none' ? const [] : freshLyrics.lines;
          await DatabaseService.cacheLyrics(track.id, freshLyrics);
        }
      }
    }));

    _subs.add(_audioHandler.playerStateStream.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
        });
      }
    }));

    _subs.add(_audioHandler.positionStream.listen((pos) {
      _positionNotifier.value = pos;
    }));

    _subs.add(_audioHandler.durationStream.listen((dur) {
      _durationNotifier.value = dur;
    }));

    // The handler writes history itself when it auto-advances, so the rail has
    // to follow the store rather than the UI actions that happen to reach it.
    _subs.add(DatabaseService.historyUpdateStream.listen((_) => _loadHistory()));
  }

  Future<void> _loadHistory() async {
    final history = await DatabaseService.getRecentlyPlayed();
    if (mounted) {
      setState(() {
        _recentlyPlayed = history;
      });
    }
  }

  /// Resolve the loop/shuffle queue: a playlist/favorites passes its own
  /// tracks; anywhere else passes null and we default to the whole downloaded
  /// library.
  Future<List<Track>> _resolveQueue(List<Track>? queue) async {
    if (queue != null && queue.isNotEmpty) return queue;
    return DatabaseService.getDownloadedTracks();
  }

  void _onPlayTrackOnly(Track track, {List<Track>? queue}) async {
    setState(() {
      _currentTrack = track;
    });
    final q = await _resolveQueue(queue);
    _audioHandler.playTrack(track, newQueue: q.isNotEmpty ? q : null);
  }

  void _onPlayTrackAndExpand(Track track, {List<Track>? queue}) async {
    setState(() {
      _currentTrack = track;
    });
    _openNowPlaying(track: track, follow: true);
    final q = await _resolveQueue(queue);
    _audioHandler.playTrack(track, newQueue: q.isNotEmpty ? q : null);
  }

  /// Search tap: preview an undownloaded track in the player sheet without
  /// auto-downloading; play straight away (looping the downloaded library) if
  /// it's already local.
  void _onSearchSelectTrack(Track track, {List<Track>? queue}) async {
    final downloaded = await AudioDownloadService.isDownloaded(track);
    if (!mounted) return;
    if (downloaded) {
      _onPlayTrackAndExpand(track, queue: queue);
    } else {
      _openNowPlaying(track: track);
    }
  }

  bool _nowPlayingOpen = false;

  void _openNowPlaying({Track? track, bool follow = false}) {
    final focused = track ?? _currentTrack;
    if (focused == null) return;
    // A double tap used to stack two identical full-screen routes.
    if (_nowPlayingOpen) return;
    _nowPlayingOpen = true;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            )),
            child: NowPlayingSheet(
              handler: _audioHandler,
              focusedTrack: focused,
              positionNotifier: _positionNotifier,
              durationNotifier: _durationNotifier,
              lyricsNotifier: _lyricsNotifier,
              onOpenLyricEditor: _openLyricEditor,
              followHandler: follow,
            ),
          );
        },
      ),
    ).whenComplete(() => _nowPlayingOpen = false);
  }

  /// Opens the info/lyrics editor for [track] — which is whatever the player
  /// sheet is actually showing, not necessarily the playing track.
  void _openLyricEditor(Track track, {bool lyricsTab = false}) {
    final isCurrent = _currentTrack?.id == track.id;
    showDialog(
      context: context,
      builder: (context) {
        return LyricEditorDialog(
          songTitle: track.title,
          artistName: track.uploader,
          coverUrl: track.coverUrl,
          positionNotifier: _positionNotifier,
          initialTabIndex: lyricsTab ? 1 : 0,
          currentLines: isCurrent ? _lyricsNotifier.value : const [],
          onApplyLyrics: (result) async {
            if (isCurrent) _lyricsNotifier.value = result.lines;
            await DatabaseService.cacheLyrics(track.id, result);
          },
          onUpdateMetadata: (newTitle, newArtist, newCoverUrl) async {
            final updated = track.copyWith(
              title: newTitle,
              uploader: newArtist,
              coverUrl: newCoverUrl,
            );
            if (isCurrent && mounted) {
              setState(() => _currentTrack = updated);
            }
            await DatabaseService.updateTrackMetadata(updated);
            _audioHandler.updateCurrentTrackMetadata(updated);
          },
        );
      },
    );
  }

  Widget _tabItem(int index, String label) {
    final active = _activeTabIndex == index;
    return GestureDetector(
      key: _tabKeys[index],
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.selection();
        setState(() => _activeTabIndex = index);
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) => _updateIndicator());
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.textPrimary : AppColors.textMuted,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
    );
  }

  void _updateIndicator() {
    final rowBox = _tabRowKey.currentContext?.findRenderObject() as RenderBox?;
    final tabBox = _tabKeys[_activeTabIndex].currentContext?.findRenderObject()
        as RenderBox?;
    if (rowBox == null || tabBox == null || !mounted) return;
    final offset = tabBox.localToGlobal(Offset.zero, ancestor: rowBox);
    setState(() {
      _indicatorLeft = offset.dx;
      _indicatorWidth = tabBox.size.width;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dockedHeight = MiniPlayer.totalHeight(context);

    return Scaffold(
      body: AmbientBackground(
        coverUrl: _currentTrack?.coverUrl,
        child: Stack(
          children: [
            // Layer 1: Content Pages
            Column(
              children: [
                // Top Tab Header Selector ("聆听" | "搜索") — sliding pill
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Stack(
                      key: _tabRowKey,
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          left: _indicatorLeft,
                          width: _indicatorWidth,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.accent14,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                              border: Border.all(
                                  color: AppColors.accent30),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            _tabItem(0, '聆听'),
                            const SizedBox(width: 12),
                            _tabItem(1, '搜索'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Swipeable PageView (聆听 & 搜索)
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      Haptics.selection();
                      setState(() {
                        _activeTabIndex = index;
                      });
                      WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _updateIndicator());
                    },
                    children: [
                      RepaintBoundary(
                        child: HomeScreen(
                          recentlyPlayed: _recentlyPlayed,
                          onSelectTrack: _onPlayTrackAndExpand,
                          onPlayOnly: _onPlayTrackOnly,
                          onOpenPlaylist: (pl) {
                            setState(() => _activePlaylistSheet = pl);
                          },
                        ),
                      ),
                      RepaintBoundary(
                        child: SearchScreen(
                          onSelectTrack: _onSearchSelectTrack,
                          onPlayOnly: _onPlayTrackOnly,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: dockedHeight),
              ],
            ),

            // Layer 2: Active Playlist Overlay (Stops strictly above MiniPlayer)
            if (_activePlaylistSheet != null)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: dockedHeight,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(_activePlaylistSheet!.id),
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * 40),
                      child: child,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _activePlaylistSheet = null),
                          child: const ColoredBox(color: AppColors.black45),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: PlaylistDetailSheet(
                          playlist: _activePlaylistSheet!,
                          onSelectTrack: _onPlayTrackAndExpand,
                          onPlayOnly: _onPlayTrackOnly,
                          onPlaylistUpdated: _loadHistory,
                          onClose: () =>
                              setState(() => _activePlaylistSheet = null),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Layer 3: Permanent Docked MiniPlayer (Top of Z-index, ALWAYS interactive!)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MiniPlayer(
                currentTrack: _currentTrack,
                isPlaying: _isPlaying,
                positionNotifier: _positionNotifier,
                durationNotifier: _durationNotifier,
                onPlayPause: () {
                  if (_isPlaying) {
                    _audioHandler.pause();
                  } else {
                    _audioHandler.play();
                  }
                },
                onNext: () => _audioHandler.skipToNext(),
                onPrevious: () => _audioHandler.skipToPrevious(),
                onTap: () => _openNowPlaying(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
