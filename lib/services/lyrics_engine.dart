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

  // Title cleaner to extract clean song name & artist from Bilibili titles
  static Map<String, String> cleanTitle(String rawTitle) {
    var title = rawTitle;
    var artist = '';

    // 1. Extract artist from brackets like 【周深】, [周深], 【歌手：周深】
    final bracketMatch = RegExp(r'[【\[]([^】\]]+)[】\]]').firstMatch(title);
    if (bracketMatch != null) {
      final content = bracketMatch.group(1)!;
      if (!RegExp(r'MV|4K|1080P|Live|官方|高音质|原纯|完整版|字幕|重置|翻唱|Cover|纯享|60帧|超清', caseSensitive: false).hasMatch(content)) {
        artist = content.replaceAll(RegExp(r'^(歌手|演唱|UP主)[：:]\s*'), '').trim();
      }
    }

    // 2. If title contains book-title brackets 《...》, that inside is the exact song title!
    final bookTitleMatch = RegExp(r'《([^》]+)》').firstMatch(title);
    if (bookTitleMatch != null) {
      final extractedSong = bookTitleMatch.group(1)!.trim();
      if (extractedSong.isNotEmpty) {
        return {
          'songTitle': extractedSong,
          'artist': artist,
        };
      }
    }

    // 3. Remove uploader / fan-station prefixes (e.g. ForCharlie_周深图文站, XX_字幕组, YY工作室)
    title = title.replaceAll(RegExp(r'^[A-Za-z0-9_\-\.\s]*[\u4e00-\u9fa5A-Za-z0-9]+(站|图文站|字幕组|工作室|应援会|后援会|FanClub|粉丝团)[_︱|丨\s_-]*', caseSensitive: false), ' ');

    // 4. Remove all bracket blocks
    title = title.replaceAll(RegExp(r'【[^】]+】'), ' ');
    title = title.replaceAll(RegExp(r'\[[^\]]+\]'), ' ');
    title = title.replaceAll(RegExp(r'（[^）]+）'), ' ');
    title = title.replaceAll(RegExp(r'\([^)]+\)'), ' ');

    // 5. Remove dates (e.g., 20260712, 2024.05.01, 2026-07-12)
    title = title.replaceAll(RegExp(r'\b\d{4}[.\-_]?\d{2}[.\-_]?\d{2}\b'), ' ');
    title = title.replaceAll(RegExp(r'\b\d{8}\b'), ' ');

    // 6. Remove concert/venue/tour descriptors & noise keywords
    title = title.replaceAll(RegExp(r'(深深的|巡演|演唱会|呼和浩特站|北京站|上海站|广州站|深圳站|成都站|南京站|武汉站|重庆站|杭州站)\b'), ' ');
    title = title.replaceAll(RegExp(r'(4K|1080P|720P|60帧|高音质|无损|纯享|单曲循环|完整版|官方MV|动态歌词|LRC|P\d+|多机位|精剪|直拍|现场|Live|全场|片段|高清|超清|重置|首唱)', caseSensitive: false), ' ');
    title = title.replaceAll(RegExp(r'(Cover|翻唱|原唱|词/曲|混音|演唱|UP主)', caseSensitive: false), ' ');

    // 7. Remove common noise punctuation
    title = title.replaceAll(RegExp(r'[︱|丨~_─—\-]'), ' ');
    title = title.trim().replaceAll(RegExp(r'\s+'), ' ');

    // 8. Handle "Artist - Title" splitting if artist wasn't extracted from brackets
    if (artist.isEmpty && title.contains('-')) {
      final parts = title.split('-');
      if (parts.length >= 2) {
        artist = parts[0].trim();
        title = parts[1].trim();
      }
    }

    return {
      'songTitle': title.isEmpty ? rawTitle : title,
      'artist': artist,
    };
  }

  // Normalize string for candidate matching verification
  static String _normalize(String input) {
    return input.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), '').toLowerCase();
  }

  static bool _isTitleMatching(String candidateName, String targetTitle) {
    final cand = _normalize(candidateName);
    final target = _normalize(targetTitle);
    if (cand.isEmpty || target.isEmpty) return false;
    return cand.contains(target) || target.contains(cand);
  }

  // Parse raw LRC text into sorted List<LyricLine>
  static List<LyricLine> parseLrc(String lrcText) {
    if (lrcText.isEmpty) return [];

    final lines = lrcText.split('\n');
    final result = <LyricLine>[];
    final timeRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');

    for (final line in lines) {
      final match = timeRegex.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final millisStr = match.group(3)!.padRight(3, '0').substring(0, 3);
        final millis = int.parse(millisStr);
        final timeSec = minutes * 60 + seconds + millis / 1000.0;

        final text = line.replaceAll(RegExp(r'\[\d{2}:\d{2}\.\d{2,3}\]'), '').trim();
        if (text.isNotEmpty) {
          result.add(LyricLine(time: timeSec, text: text));
        }
      }
    }

    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
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
            if (_isTitleMatching(trackName, title)) {
              final rawLrc = (item['syncedLyrics'] ?? item['plainLyrics'] ?? '') as String;
              final lines = parseLrc(rawLrc);

              if (lines.isNotEmpty || rawLrc.isNotEmpty) {
                return LyricsResult(
                  source: 'lrclib',
                  songTitle: trackName.isNotEmpty ? trackName : title,
                  artistName: item['artistName'] ?? artist,
                  lines: lines.isNotEmpty ? lines : [LyricLine(time: 0, text: rawLrc)],
                  rawLrc: rawLrc,
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
            if (_isTitleMatching(songName, title)) {
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
                  for (final line in lines) {
                    final matchTrans = transLines.firstWhere(
                      (t) => (t.time - line.time).abs() < 0.5,
                      orElse: () => LyricLine(time: -1, text: ''),
                    );
                    if (matchTrans.time >= 0) {
                      lines[lines.indexOf(line)] = LyricLine(
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
                    rawLrc: rawLrc,
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

    return LyricsResult(
      source: 'none',
      songTitle: title,
      artistName: artist,
      lines: [
        LyricLine(time: 0, text: '未找到同步歌词'),
        LyricLine(time: 5, text: '点击右上角 🔍 手动搜索或导入 LRC 歌词'),
      ],
    );
  }
}
