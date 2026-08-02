import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/lyric_line.dart';
import 'bili_http.dart';

class LyricsEngine {
  static final HttpClient _client = biliHttpClient();

  static Future<String?> _httpGet(String urlStr, {Map<String, String>? headers}) async {
    try {
      final req = await _client.getUrl(Uri.parse(urlStr));
      headers?.forEach((k, v) => req.headers.set(k, v));
      final res = await req.close();
      if (res.statusCode == 200) {
        return await res.transform(utf8.decoder).join();
      }
      // Drain non-200 bodies so the connection returns to the pool; with
      // maxConnectionsPerHost = 4, a few un-drained 4xx/5xx responses would
      // exhaust it and later requests would queue behind idleTimeout.
      await res.drain<void>();
    } catch (e) {
      debugPrint('Lyrics HTTP error: $e');
    }
    return null;
  }

  // Common noise words in B站 titles
  static final RegExp noiseKeywords = RegExp(
    r'(?:4K|1080P|720P|60帧|50帧|杜比视界|杜比全景声|Hi-?Res|无损音质|无损|高音质|HQ|SQ|'
    r'官方MV|MV|纯享版|纯享|动态歌词|LRC|全场|完整版|片段|精剪|多机位|直拍|现场|Live|'
    r'首唱|单曲循环|单曲|纯音频|Audio|字幕组|字幕|重置|超清|高清|录音棚|在.*大声听|'
    r'主题曲|片尾曲|片头曲|插曲|推广曲|印象曲|角色曲|宣传曲|ED|OP|OST)',
    caseSensitive: false,
  );

  // Token-level noise: if a space-separated token contains any of these, the
  // whole token is noise (spaces are the atomic unit of titles).
  static final RegExp tokenNoise = RegExp(
    noiseKeywords.pattern + r'|(?:Cover|翻唱|原唱|词/曲|混音|演唱|UP主|版本)',
    caseSensitive: false,
  );

  static final RegExp bracketCategory = RegExp(
    r'合集|歌单|珍藏|榜|反应|点评|解析|试听',
    caseSensitive: false,
  );

  // Shared structural regexes: cleaning and candidate generation must strip
  // exactly the same brackets, or the two paths disagree on the same title.
  static final RegExp htmlTag = RegExp(r'<[^>]+>');
  static final RegExp bracketContent = RegExp(r'[【\[]([^】\]]+)[】\]]');
  static final RegExp bookBracket = RegExp(r'《([^》]+)》');
  static final RegExp bracketStripper =
      RegExp(r'【[^】]+】|\[[^\]]+\]|（[^）]+）|\([^)]+\)');
  static final RegExp parenSubtitle = RegExp(r'\s*[\(（][^\)）]+[\)）]');
  static final RegExp separator =
      RegExp(r'^(.+?)\s*[-–—/︱|丨_]\s*(\S.*)$');

  static String _preprocess(String raw) {
    return raw
        .trim()
        .replaceAll(htmlTag, '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Drops brackets, parens and whole-token noise from [s], preserving the
  /// space-separated tokens that survive.
  static String _noisyClean(String s) {
    return s
        .replaceAll(bracketStripper, ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && !tokenNoise.hasMatch(t))
        .join(' ');
  }

  // Title cleaner to extract clean song name & artist from Bilibili video titles
  //
  // Deliberately structural: brackets supply the artist, 《》 supplies the
  // song, separators split "Artist - Song", and space-separated tokens are the
  // unit of noise removal. All semantic disambiguation (which 《》 is the song,
  // who the singer is, collaboration brackets like 【A&B 歌名】) is delegated to
  // [cleanTitleWithValidation]'s lyric-DB search; this method is only the
  // offline fallback and the instant first pass.
  static Map<String, String> cleanTitle(String rawTitle, {String defaultArtist = ''}) {
    final title = _preprocess(rawTitle);
    var artist = defaultArtist.trim();
    if (artist == '未知UP主' || artist == '未知歌手' || artist == 'UP主') {
      artist = '';
    }

    String? song;

    // 2. Artist from brackets like 【周深】, [周深], or space-split
    //    【Artist1&Artist2 SongTitle】 patterns.
    final bracketMatch = bracketContent.firstMatch(title);
    if (bracketMatch != null) {
      final content = bracketMatch.group(1)!.trim();
      if (!tokenNoise.hasMatch(content) && !bracketCategory.hasMatch(content)) {
        final tokens = content.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        if (tokens.length >= 2) {
          final nonNoise = tokens.where((t) => !tokenNoise.hasMatch(t)).toList();
          if (nonNoise.length >= 2) {
            artist = nonNoise.sublist(0, nonNoise.length - 1).join(' ');
            song = nonNoise.last;
          } else if (nonNoise.isNotEmpty) {
            artist = nonNoise.join(' ');
          }
        } else {
          artist = content;
        }
      }
    }

    // 3. Song from the first book bracket 《...》. Artist, if still unknown,
    //    comes from the text immediately before or after it.
    final bookMatch = bookBracket.firstMatch(title);
    if (bookMatch != null) {
      song = bookMatch.group(1)!.trim();
      if (artist.isEmpty || artist == defaultArtist) {
        final beforeTokens = _noisyClean(title.substring(0, bookMatch.start))
            .split(RegExp(r'\s+'))
            .where((t) => t.isNotEmpty)
            .toList();
        // The token nearest the 《》 is most likely the artist's name; when
        // several precede it ("周深 古风《大鱼》") the leading one wins.
        if (beforeTokens.isNotEmpty) {
          artist = beforeTokens.first;
        }
      }
      if (artist.isEmpty || artist == defaultArtist) {
        final after = _noisyClean(title.substring(bookMatch.end));
        final leading = RegExp(r'^([\u4e00-\u9fa5A-Za-z0-9_·•.]{2,12})').firstMatch(after);
        if (leading != null && !tokenNoise.hasMatch(leading.group(1)!)) {
          artist = leading.group(1)!;
        }
      }
    }

    // 4. No book brackets: split "Artist - SongTitle" on the cleaned title.
    if (song == null) {
      final clean = _noisyClean(title);
      final parts = clean.split(RegExp(r'\s+[-–—/︱|丨_]\s+'));
      if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        if (artist.isEmpty || artist == defaultArtist) artist = parts[0];
        song = parts[1];
      } else {
        final dash = RegExp(r'^([\u4e00-\u9fa5A-Za-z0-9·•.]{2,10})\s*[-–—]\s*(.+)$')
            .firstMatch(clean);
        if (dash != null) {
          if (artist.isEmpty || artist == defaultArtist) artist = dash.group(1)!;
          song = dash.group(2)!;
        }
      }
      song ??= clean;
    }

    final finalSong = song.trim();
    return {
      'songTitle': finalSong.isEmpty ? rawTitle : finalSong,
      'artist': artist.isNotEmpty ? artist : defaultArtist,
    };
  }

  /// Structural candidate extraction for DB-backed validation: every 《…》
  /// content, every 【…】 content (whole and space-split), the part after an
  /// "Artist - Song" separator, and every surviving space-separated token.
  static List<Map<String, String>> _generateCandidates(String rawTitle) {
    final title = _preprocess(rawTitle);
    final candidates = <Map<String, String>>[];

    void add(String song, [String artistHint = '']) {
      final s = song.trim();
      final hint = artistHint.trim();
      final norm = _normalize(s);
      if (s.isEmpty || norm.isEmpty || norm.length > 24) return;
      if (tokenNoise.hasMatch(s)) return;
      if (candidates.any((c) => _normalize(c['song']!) == norm)) return;
      candidates.add({'song': s, 'artistHint': hint});
    }

    for (final m in bookBracket.allMatches(title)) {
      add(m.group(1)!);
    }
    for (final m in bracketContent.allMatches(title)) {
      final content = m.group(1)!.trim();
      if (content.isEmpty) continue;
      add(content);
      final tokens = content.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      if (tokens.length >= 2) {
        add(tokens.last, tokens.sublist(0, tokens.length - 1).join(' '));
      }
    }
    final sep = separator.firstMatch(title);
    if (sep != null) {
      add(sep.group(2)!, sep.group(1)!);
    }
    final bare = title.replaceAll(bracketStripper, ' ');
    for (final t in bare.split(RegExp(r'\s+'))) {
      add(t);
    }
    return candidates.length > 8 ? candidates.sublist(0, 8) : candidates;
  }

  /// Advanced title & artist extractor using lyric database cross-validation.
  ///
  /// Generates every plausible song candidate structurally (see
  /// [_generateCandidates]), searches each against NetEase / LRCLIB, and picks
  /// the candidate whose official metadata best matches the raw video title:
  /// an official song name or artist that appears verbatim in the raw title is
  /// the strongest signal. [cleanTitle]'s rule-based result is only the artist
  /// fallback and the offline result.
  static Future<Map<String, String>> cleanTitleWithValidation(
    String rawTitle, {
    String defaultArtist = '',
  }) async {
    final fallback = cleanTitle(rawTitle, defaultArtist: defaultArtist);
    final normRaw = _normalize(rawTitle);

    String? bestSong;
    String? bestArtist;
    var bestScore = 0;

    for (final candidate in _generateCandidates(rawTitle)) {
      final song = candidate['song']!;
      final hint = candidate['artistHint'];
      final artistQuery = (hint != null && hint.isNotEmpty) ? hint : null;

      final result = await fetchFromNetEase(song, artist: artistQuery) ??
          await fetchFromLRCLIB(song, artist: artistQuery);
      if (result == null) continue;

      final officialSong = (result.songTitle ?? '').trim();
      final officialArtist = (result.artistName ?? '').trim();
      // Strip provider parentheses subtitles like "心火 (Live)" or " (电影《...》)"
      final cleanOfficialSong = officialSong.replaceAll(parenSubtitle, '').trim();
      final offSongNorm = _normalize(cleanOfficialSong);
      final offArtistNorm = _normalize(officialArtist);
      final candNorm = _normalize(song);

      if (offSongNorm.isEmpty) continue;

      final songInRaw = normRaw.contains(offSongNorm);
      final songMatchesCandidate = offSongNorm == candNorm ||
          candNorm.contains(offSongNorm) ||
          offSongNorm.contains(candNorm);
      final artistInRaw = offArtistNorm.isNotEmpty && normRaw.contains(offArtistNorm);
      final hasLyrics = result.lines.isNotEmpty;

      var score = 0;
      if (hasLyrics) score += 1;
      if (songInRaw) score += 2;
      if (artistInRaw) score += 2;
      if (songMatchesCandidate) score += 1;

      // Without the song matching the title (or the candidate), an artist-only
      // search would happily return that artist's arbitrary song.
      if ((songInRaw || songMatchesCandidate) && score > bestScore) {
        bestScore = score;
        bestSong = cleanOfficialSong.isNotEmpty ? cleanOfficialSong : officialSong;
        bestArtist = artistInRaw ? officialArtist : fallback['artist']!;
      }
    }

    if (bestSong == null) return fallback;
    return {
      'songTitle': bestSong,
      'artist': bestArtist!,
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
    // A 2-char target like "11" would substring-match "2011"/"11月…" and pull
    // the wrong track's lyrics; exact equality is still trusted for short
    // names, but contains-matching requires a longer (specific) name.
    if (cand == target) return true;
    if (cand.length < 4 || target.length < 4) return false;
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
      // Round to whole milliseconds first: `sec.toStringAsFixed(2)` on a value
      // like 59.9996s would otherwise round up to "[mm:60.00]", which parseLrc
      // cannot read back.
      final totalMillis = (line.time * 1000).round();
      final min = totalMillis ~/ 60000;
      final secMillis = totalMillis % 60000;
      final sec = (secMillis / 1000).floor();
      final centis = (secMillis % 1000) ~/ 10;
      final tag = '[${min.toString().padLeft(2, '0')}:'
          '${sec.toString().padLeft(2, '0')}.${centis.toString().padLeft(2, '0')}]';
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
              if (songId is! int || songId <= 0) continue;
              final lyricUrl = 'https://music.163.com/api/song/lyric?id=$songId&lv=-1&tv=-1';

              final lyricBody = await _httpGet(lyricUrl, headers: {'Referer': 'https://music.163.com'});
              if (lyricBody != null) {
                final lyricJson = jsonDecode(lyricBody);
                final rawLrc = (lyricJson['lrc']?['lyric'] ?? '') as String;
                final rawTrans = (lyricJson['tlyric']?['lyric'] ?? '') as String;

                final lines = parseLrc(rawLrc);
                final transLines = parseLrc(rawTrans);

                if (transLines.isNotEmpty) {
                  // Both lists are time-sorted, so a single advancing pointer
                  // keeps the merge O(n) instead of the previous O(n²)
                  // firstWhere-scan per line.
                  var ti = 0;
                  for (var i = 0; i < lines.length; i++) {
                    final line = lines[i];
                    // Skip translations that are too early for this line.
                    while (ti < transLines.length &&
                        transLines[ti].time < line.time - 0.5) {
                      ti++;
                    }
                    // ti is now the first translation inside the window, if any.
                    if (ti < transLines.length &&
                        (transLines[ti].time - line.time).abs() < 0.5) {
                      lines[i] = LyricLine(
                        time: line.time,
                        text: line.text,
                        translation: transLines[ti].text,
                      );
                    }
                  }
                }

                if (lines.isNotEmpty) {
                  final artists = (song['artists'] as List? ?? [])
                      .where((a) => a is Map && a['name'] is String)
                      .map((a) => a['name'] as String)
                      .join(', ');
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
