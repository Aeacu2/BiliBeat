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
import 'widgets/expand_from_card.dart';
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
  // Edge to edge, with a transparent navigation bar and — the part that
  // matters — no divider. Android draws a hairline above the gesture area by
  // default, which is the line that kept showing under the docked player no
  // matter how flush the card itself was.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  ));
  _audioHandlerInstance = await AudioService.init(
    builder: BiliBeatAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.bilibeat.channel.audio',
      androidNotificationChannelName: 'BiliBeat',
      androidNotificationOngoing: true,
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

  /// Player state is held in notifiers, not State fields. It changes on every
  /// play/pause and every track advance, and as plain `setState` state it
  /// rebuilt the whole tree — both page subtrees included — for a change that
  /// only the ambient backdrop and the docked bar care about.
  /// Not a `ValueNotifier<Track?>`: [Track] equality is id-only, so a
  /// ValueNotifier would drop the metadata-edit assignment (same id, new
  /// title/cover) and leave the docked player showing stale text.
  final TrackNotifier _currentTrack = TrackNotifier();
  final ValueNotifier<bool> _isPlaying = ValueNotifier(false);
  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<List<LyricLine>> _lyricsNotifier = ValueNotifier([]);
  /// Also a notifier, and for the same reason as the player state above: the
  /// handler writes a history entry on *every* track change, and holding this
  /// in `setState` state rebuilt both page subtrees each time a song started —
  /// for a change only the 最近播放 rail cares about.
  final ValueNotifier<List<Track>> _recentlyPlayed = ValueNotifier(const []);
  Playlist? _activePlaylistSheet;

  late final PageController _pageController = PageController();
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
    _currentTrack.dispose();
    _recentlyPlayed.dispose();
    _isPlaying.dispose();
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _lyricsNotifier.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _initListeners() {
    _subs.add(_audioHandler.currentTrackStream.listen((track) async {
      if (track != null) {
        _currentTrack.value = track;

        // Fetch lyrics with stale cache validation.
        //
        // Every await below needs a `mounted` guard: cancelling the
        // subscription in dispose() stops *new* events, but an event already
        // being handled resumes after its await regardless — and writing to a
        // disposed ValueNotifier throws.
        final cleanSongTitle = LyricsEngine.cleanTitle(track.title)['songTitle']!;
        final cached = await DatabaseService.getCachedLyrics(track.id);
        if (!mounted || _currentTrack.value?.id != track.id) return;

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
          if (!mounted || _currentTrack.value?.id != track.id) return;
          // A "not found" result carries placeholder lines; showing an empty
          // list instead lets the lyrics view offer its search/paste action.
          _lyricsNotifier.value =
              freshLyrics.source == 'none' ? const [] : freshLyrics.lines;
          await DatabaseService.cacheLyrics(track.id, freshLyrics);
        }
      }
    }));

    _subs.add(_audioHandler.playerStateStream.listen((playing) {
      _isPlaying.value = playing;
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
    if (mounted) _recentlyPlayed.value = history;
  }

  /// Resolve the loop/shuffle queue: a playlist/favorites passes its own
  /// tracks; anywhere else passes null and we default to the whole downloaded
  /// library.
  Future<List<Track>> _resolveQueue(List<Track>? queue) async {
    if (queue != null && queue.isNotEmpty) return queue;
    return DatabaseService.getDownloadedTracks();
  }

  void _onPlayTrackOnly(Track track, {List<Track>? queue}) async {
    _currentTrack.value = track;
    final q = await _resolveQueue(queue);
    _audioHandler.playTrack(track, newQueue: q.isNotEmpty ? q : null);
  }

  void _onPlayTrackAndExpand(Track track, {List<Track>? queue}) async {
    _currentTrack.value = track;
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
  final GlobalKey _miniPlayerKey = GlobalKey();

  /// Where the docked card is on screen right now, or null if it is not laid
  /// out (nothing playing yet, first frame).
  Rect? _miniPlayerRect() {
    final box = _miniPlayerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    // The card is flush to the bottom and the sides, so its slot *is* the card
    // — no margins to subtract.
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _openNowPlaying({Track? track, bool follow = false}) {
    final focused = track ?? _currentTrack.value;
    if (focused == null) return;
    // A double tap used to stack two identical full-screen routes.
    if (_nowPlayingOpen) return;
    _nowPlayingOpen = true;

    final from = _miniPlayerRect();

    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 340),
        pageBuilder: (context, animation, secondaryAnimation) {
          return NowPlayingSheet(
            handler: _audioHandler,
            focusedTrack: focused,
            positionNotifier: _positionNotifier,
            durationNotifier: _durationNotifier,
            lyricsNotifier: _lyricsNotifier,
            onOpenLyricEditor: _openLyricEditor,
            followHandler: follow,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // The docked card *becomes* the page: its rectangle grows to fill
          // the screen and its corner radius unrolls, and on the way back it
          // folds down onto the card again. Falling back to a slide-up keeps
          // the entry sane when there is no card to grow from (opened straight
          // from a search result before anything is docked).
          if (from == null) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              )),
              child: child,
            );
          }
          return ExpandFromCard(animation: animation, from: from, child: child);
        },
      ),
    ).whenComplete(() => _nowPlayingOpen = false);
  }

  /// Opens the info/lyrics editor for [track] — which is whatever the player
  /// sheet is actually showing, not necessarily the playing track.
  void _openLyricEditor(Track track, {bool lyricsTab = false}) {
    final isCurrent = _currentTrack.value?.id == track.id;
    // Finishing the track while the user is editing its info or lyrics would
    // swap the whole editor's subject out. Stay put until the sheet closes.
    final release = _audioHandler.holdAutoAdvance();
    showDialog(
      context: context,
      builder: (context) {
        return LyricEditorDialog(
          songTitle: track.title,
          artistName: track.uploader,
          coverUrl: track.coverUrl,
          // Only the playing track has a live position; handing the
          // editor another track's clock would drive the preview
          // against a timeline that has nothing to do with it.
          positionNotifier: isCurrent ? _positionNotifier : null,
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
            if (isCurrent) _currentTrack.value = updated;
            await DatabaseService.updateTrackMetadata(updated);
            _audioHandler.updateCurrentTrackMetadata(updated);
          },
        );
      },
    ).whenComplete(release);
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.textPrimary : AppColors.textMuted,
            fontSize: 23,
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
      body: Stack(
        children: [
          // Layer 0: ambient backdrop. A sibling behind the content rather
          // than its parent, so a cover change repaints only this layer
          // instead of rebuilding both pages.
          Positioned.fill(
            child: ValueListenableBuilder<Track?>(
              valueListenable: _currentTrack,
              builder: (context, track, _) =>
                  AmbientBackground(coverUrl: track?.coverUrl),
            ),
          ),
          Stack(
          children: [
            // Layer 1: Content Pages
            Column(
              children: [
                // Top Tab Header Selector ("聆听" | "搜索") — sliding pill
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
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
                                    border:
                                        Border.all(color: AppColors.accent30),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  _tabItem(0, '聆听'),
                                  const SizedBox(width: 8),
                                  _tabItem(1, '搜索'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // The right-hand end of this row was dead space. The
                        // mark closes it off and gives the header a shape,
                        // which is what a header is for.
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Image.asset('assets/logo.png', height: 38),
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
                        child: ValueListenableBuilder<List<Track>>(
                          valueListenable: _recentlyPlayed,
                          builder: (context, recent, _) => HomeScreen(
                            recentlyPlayed: recent,
                            onSelectTrack: _onPlayTrackAndExpand,
                            onPlayOnly: _onPlayTrackOnly,
                            onOpenPlaylist: (pl) {
                              setState(() => _activePlaylistSheet = pl);
                            },
                          ),
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
              child: ListenableBuilder(
                key: _miniPlayerKey,
                listenable: Listenable.merge([_currentTrack, _isPlaying]),
                builder: (context, _) => MiniPlayer(
                currentTrack: _currentTrack.value,
                isPlaying: _isPlaying.value,
                positionNotifier: _positionNotifier,
                durationNotifier: _durationNotifier,
                onPlayPause: () {
                  if (_isPlaying.value) {
                    _audioHandler.pause();
                  } else {
                    _audioHandler.play();
                  }
                },
                onNext: _audioHandler.skipToNext,
                onPrevious: _audioHandler.skipToPrevious,
                onTap: _openNowPlaying,
              ),
              ),
            ),
          ],
          ),
        ],
      ),
    );
  }
}
