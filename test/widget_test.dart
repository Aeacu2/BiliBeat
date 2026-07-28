import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilibeats/models/lyric_line.dart';
import 'package:bilibeats/models/track.dart';
import 'package:bilibeats/widgets/marquee_text.dart';
import 'package:bilibeats/widgets/mini_player.dart';
import 'package:bilibeats/widgets/synced_lyrics_view.dart';

const _style = TextStyle(fontSize: 14, height: 1.25);

/// Mirrors how the mini player and the now-playing panel use the marquee: a
/// width-constrained Column whose siblings must not be pushed around.
Widget _host(String text, {double width = 160, bool scrolling = true}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarqueeText(text: text, style: _style, scrolling: scrolling),
              const Text('sibling'),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('MarqueeText', () {
    testWidgets('overflowing text keeps a single-line height', (tester) async {
      await tester.pumpWidget(_host('short'));
      final shortHeight = tester.getSize(find.byType(MarqueeText)).height;

      await tester.pumpWidget(_host('a title far too long to ever fit here'));
      final longHeight = tester.getSize(find.byType(MarqueeText)).height;

      expect(longHeight, shortHeight,
          reason: 'a long title must not grow the row');
    });

    testWidgets('height is stable once the scroll animation runs',
        (tester) async {
      await tester.pumpWidget(_host('a title far too long to ever fit here'));
      final firstFrame = tester.getSize(find.byType(MarqueeText));
      final siblingBefore = tester.getTopLeft(find.text('sibling'));

      // The original bug measured text in a post-frame callback and re-laid
      // out afterwards, shifting everything below it.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));

      expect(tester.getSize(find.byType(MarqueeText)), firstFrame);
      expect(tester.getTopLeft(find.text('sibling')), siblingBefore);
      expect(tester.takeException(), isNull);
    });

    testWidgets('never exceeds the width it was given', (tester) async {
      await tester.pumpWidget(_host('a title far too long to ever fit here'));
      await tester.pump(const Duration(seconds: 2));

      expect(tester.getSize(find.byType(MarqueeText)).width, 160);
      expect(tester.takeException(), isNull);
    });

    testWidgets('short text is not scrolled', (tester) async {
      await tester.pumpWidget(_host('short'));
      await tester.pump(const Duration(seconds: 2));

      // A non-scrolling marquee renders exactly one Text child.
      expect(
        find.descendant(
            of: find.byType(MarqueeText), matching: find.text('short')),
        findsOneWidget,
      );
    });
  });

  group('SyncedLyricsView', () {
    List<LyricLine> lines() => List.generate(
        30, (i) => LyricLine(time: i * 4.0, text: '第 $i 行歌词内容'));

    Widget host({
      required List<LyricLine> data,
      ValueNotifier<Duration>? position,
      void Function(double)? onSeek,
      VoidCallback? onOpenEditor,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: SyncedLyricsView(
              lines: data,
              positionNotifier: position ?? ValueNotifier(Duration.zero),
              onSeek: onSeek,
              onOpenEditor: onOpenEditor,
            ),
          ),
        ),
      );
    }

    testWidgets('empty state offers the editor action', (tester) async {
      var opened = false;
      await tester
          .pumpWidget(host(data: const [], onOpenEditor: () => opened = true));

      expect(find.text('暂无同步歌词'), findsOneWidget);
      await tester.tap(find.text('搜索或粘贴歌词'));
      expect(opened, isTrue);
    });

    testWidgets('tapping a line seeks to its timestamp', (tester) async {
      double? sought;
      await tester
          .pumpWidget(host(data: lines(), onSeek: (s) => sought = s));
      await tester.pump();

      await tester.tap(find.text('第 2 行歌词内容'));
      expect(sought, 8.0);
    });

    testWidgets('user scrolling suspends auto-follow and offers to resume',
        (tester) async {
      final position = ValueNotifier(Duration.zero);
      await tester.pumpWidget(host(data: lines(), position: position));
      await tester.pump();

      expect(find.text('回到当前'), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
      expect(find.text('回到当前'), findsOneWidget,
          reason: 'auto-scroll must yield while the user is reading ahead');

      // Playback continuing must not yank the list back mid-browse.
      position.value = const Duration(seconds: 40);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('回到当前'), findsOneWidget);

      await tester.tap(find.text('回到当前'));
      await tester.pumpAndSettle();
      expect(find.text('回到当前'), findsNothing);
    });
  });

  group('MiniPlayer', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('renders an empty state with no track', (tester) async {
      await tester.pumpWidget(wrap(MiniPlayer(
        currentTrack: null,
        isPlaying: false,
        positionNotifier: ValueNotifier(Duration.zero),
        durationNotifier: ValueNotifier(Duration.zero),
        onPlayPause: () {},
        onNext: () {},
        onTap: () {},
      )));

      expect(find.text('BiliBeat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the track and toggles play', (tester) async {
      var toggled = false;
      await tester.pumpWidget(wrap(MiniPlayer(
        currentTrack: Track(
          id: 'BV1_1',
          bvid: 'BV1',
          cid: 1,
          title: '一首标题非常非常长的歌曲用来触发滚动效果',
          uploader: '某位 UP 主',
          coverUrl: '',
          duration: 200,
        ),
        isPlaying: true,
        positionNotifier: ValueNotifier(const Duration(seconds: 50)),
        durationNotifier: ValueNotifier(const Duration(seconds: 200)),
        onPlayPause: () => toggled = true,
        onNext: () {},
        onTap: () {},
      )));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.pause_rounded));
      expect(toggled, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
