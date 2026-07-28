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

BiliBeatAudioHandler get audioHandlerInstance =>
    _audioHandlerInstance ??= BiliBeatAudioHandler();

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

        // Fetch lyrics
        final cached = await DatabaseService.getCachedLyrics(track.id);
        if (_currentTrack?.id != track.id) return;
        if (cached != null && cached.lines.isNotEmpty) {
          _lyricsNotifier.value = cached.lines;
        } else {
          final freshLyrics = await LyricsEngine.autoFetchLyrics(track.title);
          if (_currentTrack?.id != track.id) return;
          _lyricsNotifier.value = freshLyrics.lines;
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
    _loadHistory();
  }

  void _onPlayTrackAndExpand(Track track, {List<Track>? queue}) async {
    setState(() {
      _currentTrack = track;
    });
    _openNowPlaying(track: track);
    final q = await _resolveQueue(queue);
    _audioHandler.playTrack(track, newQueue: q.isNotEmpty ? q : null);
    _loadHistory();
  }

  /// Search tap: preview an undownloaded track in the player sheet without
  /// auto-downloading; play straight away (looping the downloaded library) if
  /// it's already local.
  void _onSearchSelectTrack(Track track, {List<Track>? queue}) async {
    final downloaded = await AudioDownloadService.isDownloaded(track);
    if (downloaded) {
      _onPlayTrackAndExpand(track); // search always loops the downloaded library
    } else {
      _openNowPlaying(track: track);
    }
  }

  void _openNowPlaying({Track? track}) {
    final focused = track ?? _currentTrack;
    if (focused == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return NowPlayingSheet(
          handler: _audioHandler,
          focusedTrack: focused,
          positionNotifier: _positionNotifier,
          durationNotifier: _durationNotifier,
          lyricsNotifier: _lyricsNotifier,
          onOpenLyricEditor: _openLyricEditor,
        );
      },
    );
  }

  void _openLyricEditor() {
    if (_currentTrack == null) return;
    showDialog(
      context: context,
      builder: (context) {
        return LyricEditorDialog(
          songTitle: _currentTrack!.title,
          artistName: _currentTrack!.uploader,
          coverUrl: _currentTrack!.coverUrl,
          positionNotifier: _positionNotifier,
          currentLines: _lyricsNotifier.value,
          onApplyLyrics: (result) async {
            _lyricsNotifier.value = result.lines;
            await DatabaseService.cacheLyrics(_currentTrack!.id, result);
          },
          onUpdateMetadata: (newTitle, newArtist, newCoverUrl) async {
            final updated = _currentTrack!.copyWith(
              title: newTitle,
              uploader: newArtist,
              coverUrl: newCoverUrl,
            );
            setState(() {
              _currentTrack = updated;
            });
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
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final dockedHeight = 64.0 + bottomInset;

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
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => setState(() => _activePlaylistSheet = null),
                        child: Container(color: Colors.black45),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: PlaylistDetailSheet(
                        playlist: _activePlaylistSheet!,
                        onSelectTrack: _onPlayTrackAndExpand,
                        onPlayOnly: _onPlayTrackOnly,
                        onPlaylistUpdated: () {},
                        onClose: () => setState(() => _activePlaylistSheet = null),
                      ),
                    ),
                  ],
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
                onTap: () => _openNowPlaying(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
