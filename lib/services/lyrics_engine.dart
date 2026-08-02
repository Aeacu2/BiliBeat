import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/lyric_line.dart';

class LyricsEngine {
  static final HttpClient _client = HttpClient()
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = 4;

  static Future<String?> _httpGet(String urlStr, {Map<String, String>? headers}) async {
    try {
      final req = await _client.getUrl(Uri.parse(urlStr));
      headers?.forEach((k, v) => req.headers.set(k, v));
      final res = await req.close();
      if (res.statusCode == 200) {
        return await res.transform(utf8.decoder).join();
      }
    } catch (e) {
      debugPrint('Lyrics HTTP error: $e');
    }
    return null;
  }

  // Title cleaner to extract clean song name & artist from Bilibili video titles
  static Map<String, String> cleanTitle(String rawTitle, {String defaultArtist = ''}) {
    var title = rawTitle.trim();
    var artist = defaultArtist.trim();
    if (artist == '未知UP主' || artist == '未知歌手' || artist == 'UP主') {
      artist = '';
    }

    // 1. Remove HTML tags like <em class="keyword">...</em>
    title = title.replaceAll(RegExp(r'<[^>]+>'), '');

    // Common noise words in B站 titles
    final noiseKeywords = RegExp(
      r'(?:4K|1080P|720P|60帧|50帧|杜比视界|杜比全景声|Hi-?Res|无损音质|无损|高音质|HQ|SQ|'
      r'官方MV|MV|纯享版|纯享|动态歌词|LRC|全场|完整版|片段|精剪|多机位|直拍|现场|Live|'
      r'首唱|单曲循环|单曲|纯音频|Audio|字幕组|字幕|重置|超清|高清|录音棚|在.*大声听|'
      r'主题曲|片尾曲|片头曲|插曲|推广曲|印象曲|角色曲|宣传曲|ED|OP|OST)',
      caseSensitive: false,
    );

    // 2. Extract artist from brackets like 【周深】, [周深], 【歌手：周深】
    final bracketMatch = RegExp(r'[【\[]([^】\]]+)[】\]]').firstMatch(title);
    if (bracketMatch != null) {
      final content = bracketMatch.group(1)!.trim();
      if (!noiseKeywords.hasMatch(content) &&
          !RegExp(r'合集|歌单|珍藏|榜|反应|点评|解析|试听', caseSensitive: false).hasMatch(content)) {
        final cleanBracket = content
            .replaceAll(RegExp(r'^(歌手|演唱|UP主|原唱|Singer|Vocal)[：:]\s*', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s*([|︱丨/]\s*).*$'), '')
            .trim();
        if (cleanBracket.isNotEmpty && cleanBracket.length <= 15) {
          artist = cleanBracket;
        }
      }
    }

    // 3. Extract song from book brackets 《...》
    final bookTitleMatches = RegExp(r'《([^》]+)》').allMatches(title).toList();
    if (bookTitleMatches.isNotEmpty) {
      final showPrefixes = RegExp(r'(电视剧|电影|纪录片|综艺|游戏|动漫|动画|央视|节目)');
      final showSuffixes = RegExp(r'(?:[\u4e00-\u9fa5]{1,4}曲|ED|OP|OST|原声带|原声|项目|节目|特辑)');

      Match? mainBookMatch;
      for (final m in bookTitleMatches) {
        final beforeText = title.substring((m.start - 10).clamp(0, m.start), m.start);
        final afterText = title.substring(m.end, (m.end + 15).clamp(m.end, title.length));

        final isPrecededByShow = showPrefixes.hasMatch(beforeText);
        final isFollowedByThemeTag = RegExp(r'^\s*[\(（]?[^《\)）]*' + showSuffixes.pattern).hasMatch(afterText);

        if (!isPrecededByShow && !isFollowedByThemeTag) {
          mainBookMatch = m;
          break;
        }
      }

      mainBookMatch ??= bookTitleMatches.last;
      final extractedSong = mainBookMatch.group(1)!.trim();

      if (artist.isEmpty) {
        // Look for artist immediately preceding 《...》: e.g. "邓紫棋《11》" or "在百万豪装录音棚大声听 毛不易《一程山路》"
        final beforeBook = title.substring(0, mainBookMatch.start).trim();
        final cleanBefore = beforeBook
            .replaceAll(RegExp(r'【[^】]*】|\[[^\]]*\]'), '')
            .replaceAll(noiseKeywords, ' ')
            .trim();
        final trailingArtistMatch = RegExp(r'([\u4e00-\u9fa5A-Za-z0-9_·•.]{2,10})\s*$').firstMatch(cleanBefore);
        if (trailingArtistMatch != null) {
          final cand = trailingArtistMatch.group(1)!.trim();
          if (!noiseKeywords.hasMatch(cand) && cand.length <= 12) {
            artist = cand;
          }
        }

        // Look for artist immediately following 《...》: e.g. "《欧若拉》邓紫棋纯享完整版" or "《起风了》- 买辣椒也用券"
        if (artist.isEmpty) {
          final afterBook = title.substring(mainBookMatch.end).trim();
          final leadingArtistMatch = RegExp(r'^\s*[-–—/︱|丨_]?\s*([\u4e00-\u9fa5A-Za-z0-9_·•.]{2,10})').firstMatch(afterBook);
          if (leadingArtistMatch != null) {
            final cand = leadingArtistMatch.group(1)!.trim();
            if (!noiseKeywords.hasMatch(cand) && cand.length <= 12) {
              artist = cand;
            }
          }
        }
      }

      if (extractedSong.isNotEmpty) {
        return {
          'songTitle': extractedSong,
          'artist': artist.isNotEmpty ? artist : defaultArtist,
        };
      }
    }

    // 4. No book brackets 《...》: clean noise and split Artist - SongTitle
    var clean = title
        .replaceAll(RegExp(r'^[A-Za-z0-9_\-\.\s]*[\u4e00-\u9fa5A-Za-z0-9]+(站|图文站|字幕组|工作室|应援会|后援会|FanClub|粉丝团)[_︱|丨\s_-]*', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'【[^】]+】|\[[^\]]+\]|（[^）]+）|\([^)]+\)'), ' ')
        .replaceAll(RegExp(r'\b\d{4}[.\-_]?\d{2}[.\-_]?\d{2}\b|\b\d{8}\b'), ' ')
        .replaceAll(RegExp(r'(巡演|演唱会|呼和浩特站|北京站|上海站|广州站|深圳站|天津站|沈阳站|南京站|武汉站|重庆站|杭州站)\b'), ' ')
        .replaceAll(noiseKeywords, ' ')
        .replaceAll(RegExp(r'(Cover|翻唱|原唱|词/曲|混音|演唱|UP主)', caseSensitive: false), ' ');

    if (artist.isEmpty) {
      final parts = clean.split(RegExp(r'\s+[-–—/︱|丨_]\s+'));
      if (parts.length >= 2) {
        final p0 = parts[0].trim();
        final p1 = parts[1].trim();
        if (p0.isNotEmpty && p1.isNotEmpty) {
          artist = p0;
          clean = p1;
        }
      }
    }

    clean = clean.replaceAll(RegExp(r'[︱|丨~_─—\-]\s*'), ' ').trim();
    clean = clean.replaceAll(RegExp(r'\s+'), ' ');

    return {
      'songTitle': clean.isEmpty ? rawTitle : clean,
      'artist': artist.isNotEmpty ? artist : defaultArtist,
    };
  }

  /// Advanced title & artist extractor using lyric database cross-validation.
  ///
  /// 1. Extracts initial candidate song & artist using rule-based parsing.
  /// 2. Searches NetEase / LRCLIB lyric databases for official track metadata.
  /// 3. Cross-validates official metadata against the raw video title:
  ///    - If both official song & artist appear in raw video title -> applies both.
  ///    - If only official song matches (e.g. cover song) -> applies song title, preserving cover artist.
  static Future<Map<String, String>> cleanTitleWithValidation(
    String rawTitle, {
    String defaultArtist = '',
  }) async {
    final initial = cleanTitle(rawTitle, defaultArtist: defaultArtist);
    final ruleSong = initial['songTitle'] ?? rawTitle;
    final ruleArtist = initial['artist'] ?? defaultArtist;

    final query = (ruleArtist.isNotEmpty && ruleArtist != defaultArtist)
        ? '$ruleArtist $ruleSong'
        : ruleSong;

    try {
      final lyricsRes = await fetchFromNetEase(query) ??
          await fetchFromLRCLIB(query, artist: ruleArtist);

      if (lyricsRes != null) {
        final officialSong = (lyricsRes.songTitle ?? '').trim();
        final officialArtist = (lyricsRes.artistName ?? '').trim();

        // Strip NetEase parentheses subtitles like " (Live)" or " (电影《...》)"
        final cleanOfficialSong = officialSong.replaceAll(RegExp(r'\s*[\(（][^\)）]+[\)）]'), '').trim();

        final rawNorm = _normalize(rawTitle);
        final ruleSongNorm = _normalize(ruleSong);
        final offSongNorm = _normalize(officialSong);
        final cleanOffSongNorm = _normalize(cleanOfficialSong);
        final offArtistNorm = _normalize(officialArtist);

        final songMatches = (offSongNorm.isNotEmpty &&
                (rawNorm.contains(offSongNorm) ||
                    ruleSongNorm.contains(offSongNorm) ||
                    offSongNorm.contains(ruleSongNorm))) ||
            (cleanOffSongNorm.isNotEmpty &&
                (rawNorm.contains(cleanOffSongNorm) ||
                    ruleSongNorm.contains(cleanOffSongNorm) ||
                    cleanOffSongNorm.contains(ruleSongNorm)));

        final artistMatches = offArtistNorm.isNotEmpty &&
            (rawNorm.contains(offArtistNorm) ||
                _normalize(ruleArtist).contains(offArtistNorm));

        if (songMatches) {
          final appliedSong = (cleanOffSongNorm == ruleSongNorm || ruleSongNorm.contains(cleanOffSongNorm))
              ? ruleSong
              : (cleanOfficialSong.isNotEmpty ? cleanOfficialSong : officialSong);
          return {
            'songTitle': appliedSong,
            'artist': artistMatches
                ? officialArtist
                : (ruleArtist.isNotEmpty ? ruleArtist : defaultArtist),
          };
        }
      }
    } catch (e) {
      debugPrint('Cross validation error: $e');
    }

    return {
      'songTitle': ruleSong,
      'artist': ruleArtist,
    };
  }

  // Normalize string for candidate matching verification
  static String _normalize(String input) {
    return input.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), '').toLowerCase();
  }

  static bool isTitleMatching(String candidateName, String targetTitle) {
    final cand = _normalize(candidateName);
    final target = _normalize(targetTitle);
    if (cand.isEmpty || target.isEmpty) return false;
    return cand.contains(target) || target.contains(cand);
  }

  /// Parses LRC text into time-sorted lines.
  ///
  /// Handles the two forms the old parser silently dropped, both of which are
  /// everywhere in real .lrc files:
  ///  * `[mm:ss]` with no fractional part — previously skipped entirely, so
  ///    whole files could import as zero lines.
  ///  * Several timestamps sharing one line (`[00:12.00][01:30.00]副歌`) for a
  ///    repeated chorus — previously only the first was kept, so the chorus
  ///    never highlighted on later passes.
  static final RegExp _lrcTag = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');

  static List<LyricLine> parseLrc(String lrcText) {
    if (lrcText.isEmpty) return [];

    final result = <LyricLine>[];

    for (final line in lrcText.split('\n')) {
      final matches = _lrcTag.allMatches(line).toList();
      if (matches.isEmpty) continue;

      final text = line.replaceAll(_lrcTag, '').trim();
      if (text.isEmpty) continue;

      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fraction = match.group(3);
        // "5" means .5s, "05" means .05s, "050" means .050s.
        final millis = fraction == null
            ? 0
            : int.parse(fraction.padRight(3, '0').substring(0, 3));
        result.add(LyricLine(
          time: minutes * 60 + seconds + millis / 1000.0,
          text: text,
        ));
      }
    }

    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  /// Serialises lines back to LRC text (inverse of [parseLrc]).
  static String toLrc(List<LyricLine> lines) {
    final sb = StringBuffer();
    for (final line in lines) {
      final min = (line.time / 60).floor();
      final sec = line.time - min * 60;
      final tag =
          '[${min.toString().padLeft(2, '0')}:${sec.toStringAsFixed(2).padLeft(5, '0')}]';
      sb.writeln('$tag${line.text}');
      if (line.translation != null && line.translation!.isNotEmpty) {
        sb.writeln('$tag${line.translation}');
      }
    }
    return sb.toString();
  }

  // 1. LRCLIB Provider
  static Future<LyricsResult?> fetchFromLRCLIB(String title, {String? artist}) async {
    final queries = [
      if (artist != null && artist.isNotEmpty) '$artist $title',
      title,
    ];

    for (final query in queries) {
      final url = 'https://lrclib.net/api/search?q=${Uri.encodeComponent(query)}';
      try {
        final body = await _httpGet(url, headers: {'User-Agent': 'bilibeats/1.0.0'});
        if (body != null) {
          final items = jsonDecode(body) as List? ?? [];
          for (final item in items) {
            final trackName = (item['trackName'] ?? '') as String;
            if (isTitleMatching(trackName, title)) {
              final rawLrc = (item['syncedLyrics'] ?? item['plainLyrics'] ?? '') as String;
              final lines = parseLrc(rawLrc);

              if (lines.isNotEmpty || rawLrc.isNotEmpty) {
                return LyricsResult(
                  source: 'lrclib',
                  songTitle: trackName.isNotEmpty ? trackName : title,
                  artistName: item['artistName'] ?? artist,
                  lines: lines.isNotEmpty ? lines : [LyricLine(time: 0, text: rawLrc)],
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('LRCLIB fetch error: $e');
      }
    }

    return null;
  }

  // 2. NetEase Cloud Music Provider (Best Chinese coverage)
  static Future<LyricsResult?> fetchFromNetEase(String title, {String? artist}) async {
    final queries = [
      if (artist != null && artist.isNotEmpty) '$artist $title',
      title,
    ];

    for (final query in queries) {
      final searchUrl = 'https://music.163.com/api/search/get?s=${Uri.encodeComponent(query)}&type=1&limit=5';
      try {
        final searchBody = await _httpGet(searchUrl, headers: {'Referer': 'https://music.163.com'});
        if (searchBody != null) {
          final json = jsonDecode(searchBody);
          final songs = json['result']?['songs'] as List? ?? [];
          for (final song in songs) {
            final songName = (song['name'] ?? '') as String;
            if (isTitleMatching(songName, title)) {
              final songId = song['id'];
              final lyricUrl = 'https://music.163.com/api/song/lyric?id=$songId&lv=-1&tv=-1';

              final lyricBody = await _httpGet(lyricUrl, headers: {'Referer': 'https://music.163.com'});
              if (lyricBody != null) {
                final lyricJson = jsonDecode(lyricBody);
                final rawLrc = (lyricJson['lrc']?['lyric'] ?? '') as String;
                final rawTrans = (lyricJson['tlyric']?['lyric'] ?? '') as String;

                final lines = parseLrc(rawLrc);
                final transLines = parseLrc(rawTrans);

                if (transLines.isNotEmpty) {
                  // Index loop, not `lines.indexOf(line)`: indexOf is O(n) per
                  // line (and relied on instance identity), making the merge
                  // O(n^2) over the lyric count.
                  for (var i = 0; i < lines.length; i++) {
                    final line = lines[i];
                    final matchTrans = transLines.firstWhere(
                      (t) => (t.time - line.time).abs() < 0.5,
                      orElse: () => LyricLine(time: -1, text: ''),
                    );
                    if (matchTrans.time >= 0) {
                      lines[i] = LyricLine(
                        time: line.time,
                        text: line.text,
                        translation: matchTrans.text,
                      );
                    }
                  }
                }

                if (lines.isNotEmpty) {
                  final artists = (song['artists'] as List? ?? []).map((a) => a['name']).join(', ');
                  return LyricsResult(
                    source: 'netease',
                    songTitle: songName,
                    artistName: artists.isNotEmpty ? artists : artist,
                    lines: lines,
                  );
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('NetEase lyrics fetch error: $e');
      }
    }

    return null;
  }

  // Multi-source Waterfall Lyrics Orchestrator
  static Future<LyricsResult> autoFetchLyrics(String rawTitle) async {
    final cleaned = cleanTitle(rawTitle);
    final title = cleaned['songTitle']!;
    final artist = cleaned['artist'];

    // Step 1: NetEase (best Chinese coverage)
    final neteaseResult = await fetchFromNetEase(title, artist: artist);
    if (neteaseResult != null && neteaseResult.lines.isNotEmpty) {
      return neteaseResult;
    }

    // Step 2: LRCLIB
    final lrclibResult = await fetchFromLRCLIB(title, artist: artist);
    if (lrclibResult != null && lrclibResult.lines.isNotEmpty) {
      return lrclibResult;
    }

    // No placeholder lines: the UI renders its own empty state with a real
    // action, and fake "lyrics" would otherwise scroll past as if they were
    // the song's words.
    return LyricsResult(
      source: 'none',
      songTitle: title,
      artistName: artist,
      lines: const [],
    );
  }
}
