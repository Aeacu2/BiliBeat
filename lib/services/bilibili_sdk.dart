import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/track.dart';
import 'fingerprint_service.dart';
import 'wbi_signer.dart';

class BilibiliSdk {
  static const String _baseUrl = 'https://api.bilibili.com';
  static final HttpClient _httpClient = HttpClient()
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = 10;

  static Future<String?> _httpGet(String rawUrl, {String? cookies}) async {
    try {
      final req = await _httpClient.getUrl(Uri.parse(rawUrl));
      req.headers.set('Referer', 'https://www.bilibili.com');
      req.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36');
      if (cookies != null && cookies.isNotEmpty) {
        req.headers.set('Cookie', cookies);
      }
      final res = await req.close();
      if (res.statusCode == 200) {
        return await res.transform(utf8.decoder).join();
      } else {
        final errorBody = await res.transform(utf8.decoder).join();
        debugPrint('Bilibili HTTP error ${res.statusCode}: $errorBody');
      }
    } catch (e) {
      debugPrint('Bilibili HTTP fetch error: $e');
    }
    return null;
  }

  // Extract BV or AV ID from input query
  static String? extractBvOrAvId(String input) {
    final trimmed = input.trim();
    final bvMatch = RegExp(r'(BV[a-zA-Z0-9]{10})', caseSensitive: false).firstMatch(trimmed);
    if (bvMatch != null) return bvMatch.group(1);

    final avMatch = RegExp(r'av(\d+)', caseSensitive: false).firstMatch(trimmed);
    if (avMatch != null) return avMatch.group(0);

    return null;
  }

  // Fetch Video Info by BV or AV ID
  static Future<List<Track>> fetchVideoInfo(String idInput) async {
    final id = extractBvOrAvId(idInput) ?? idInput.trim();
    final paramKey = id.toLowerCase().startsWith('bv') ? 'bvid' : 'aid';
    final url = '$_baseUrl/x/web-interface/view?$paramKey=$id';

    try {
      final body = await _httpGet(url);
      if (body != null) {
        final json = jsonDecode(body);
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'];
          final bvid = data['bvid'] as String;
          final title = data['title'] as String;
          var pic = (data['pic'] as String? ?? '').replaceAll('http:', 'https:');
          if (pic.startsWith('//')) pic = 'https:$pic';
          final owner = data['owner'] ?? {};
          final uploader = owner['name'] as String? ?? '未知UP主';
          var uploaderFace = (owner['face'] as String? ?? '').replaceAll('http:', 'https:');
          if (uploaderFace.startsWith('//')) uploaderFace = 'https:$uploaderFace';
          final totalDuration = data['duration'] as int? ?? 0;
          final pages = data['pages'] as List? ?? [];

          if (pages.isEmpty) {
            return [
              Track(
                id: '${bvid}_0',
                bvid: bvid,
                cid: data['cid'] as int? ?? 0,
                title: title,
                uploader: uploader,
                uploaderFace: uploaderFace,
                coverUrl: pic,
                duration: totalDuration,
              )
            ];
          }

          return pages.map((p) {
            final cid = p['cid'] as int;
            final pageNo = p['page'] as int;
            final partTitle = p['part'] as String? ?? title;
            final pageDuration = p['duration'] as int? ?? totalDuration;

            return Track(
              id: '${bvid}_$cid',
              bvid: bvid,
              cid: cid,
              title: pages.length > 1 ? '$title - P$pageNo: $partTitle' : title,
              uploader: uploader,
              uploaderFace: uploaderFace,
              coverUrl: pic,
              duration: pageDuration,
            );
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('Bilibili SDK error: $e');
    }

    return [];
  }

  // Fetch audio stream URL (prefers standard MP4/M4A container for native MediaPlayer compatibility)
  static Future<Map<String, String>?> fetchAudioStream(String bvid, int cid) async {
    try {
      if (cid == 0) {
        final infoList = await fetchVideoInfo(bvid);
        if (infoList.isNotEmpty) {
          cid = infoList.first.cid;
        }
      }
      if (cid == 0) return null;

      // Try fnval=0 for standard MP4/M4A stream first
      final rawParams = {
        'bvid': bvid,
        'cid': cid,
        'fnval': 16,
        'fnver': 0,
        'fourk': 1,
      };

      final signed = await WbiSigner.signParams(rawParams);
      final queryStr = signed.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}').join('&');
      final url = '$_baseUrl/x/player/wbi/playurl?$queryStr';

      final body = await _httpGet(url);
      if (body != null) {
        final json = jsonDecode(body);
        if (json['code'] == 0 && json['data'] != null) {
          // Check durl list (standard m4a/mp4 container)
          final durlList = json['data']?['durl'] as List? ?? [];
          if (durlList.isNotEmpty) {
            final streamUrl = durlList.first['url'] as String?;
            if (streamUrl != null && streamUrl.isNotEmpty) {
              debugPrint('Obtained standard MP4/M4A audio URL: $streamUrl');
              return {
                'url': streamUrl.replaceAll('http:', 'https:'),
                'quality': '高品质 AAC/M4A',
              };
            }
          }

          // Fallback to DASH audio list if durl empty
          final audioList = json['data']?['dash']?['audio'] as List? ?? [];
          if (audioList.isNotEmpty) {
            audioList.sort((a, b) => ((b['bandwidth'] as int? ?? 0) - (a['bandwidth'] as int? ?? 0)));
            final best = audioList.first;
            final streamUrl = (best['baseUrl'] ?? best['base_url'] ?? best['backupUrl']?[0]) as String?;
            if (streamUrl != null && streamUrl.isNotEmpty) {
              debugPrint('Obtained DASH audio URL: $streamUrl');
              return {
                'url': streamUrl.replaceAll('http:', 'https:'),
                'quality': '320k DASH',
              };
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch audio stream: $e');
    }

    return null;
  }

  // Search Bilibili catalog for ANY query
  static Future<List<Track>> search(String query) async {
    if (query.trim().isEmpty) return [];

    final directId = extractBvOrAvId(query);
    if (directId != null) {
      return await fetchVideoInfo(directId);
    }

    try {
      // Obtain buvid3/buvid4 device fingerprint (required by B站 anti-bot)
      final cookieStr = await FingerprintService.getCookieString();

      // Get dm_img risk-control simulation parameters
      final dmParams = FingerprintService.getDmImgParams();

      final rawParams = <String, dynamic>{
        'search_type': 'video',
        'keyword': query.trim(),
        'page': 1,
        'order': 'totalrank',
        // dm_img 风控参数 — 缺少会导致 -352 / 412
        ...dmParams,
      };

      final signed = await WbiSigner.signParams(rawParams);
      final queryStr = signed.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}').join('&');
      final searchUrl = '$_baseUrl/x/web-interface/wbi/search/type?$queryStr';

      debugPrint('Search URL: $searchUrl');
      debugPrint('Search cookies: $cookieStr');

      final body = await _httpGet(searchUrl, cookies: cookieStr);
      if (body != null) {
        final json = jsonDecode(body);
        debugPrint('Search response code: ${json['code']}, message: ${json['message']}');

        if (json['code'] == 0 && json['data']?['result'] != null) {
          final results = json['data']['result'] as List;
          final tracks = <Track>[];

          for (final item in results) {
            final bvid = item['bvid'] as String?;
            if (bvid == null || bvid.isEmpty) continue;

            final rawTitle = item['title'] as String? ?? '';
            final cleanTitle = rawTitle.replaceAll(RegExp(r'<[^>]+>'), '');
            final author = item['author'] as String? ?? 'UP主';
            final pic = (item['pic'] as String? ?? '').replaceAll('http:', 'https:');
            final upic = (item['upic'] as String? ?? '').replaceAll('http:', 'https:');

            int durationSec = 0;
            final durRaw = item['duration'];
            if (durRaw is String) {
              final parts = durRaw.split(':').map((e) => int.tryParse(e) ?? 0).toList();
              if (parts.length == 2) {
                durationSec = parts[0] * 60 + parts[1];
              } else if (parts.length == 3) {
                durationSec = parts[0] * 3600 + parts[1] * 60 + parts[2];
              }
            } else if (durRaw is int) {
              durationSec = durRaw;
            }

            tracks.add(Track(
              id: '${bvid}_${item['cid'] ?? 0}',
              bvid: bvid,
              cid: item['cid'] as int? ?? 0,
              title: cleanTitle,
              uploader: author,
              uploaderFace: upic.startsWith('//') ? 'https:$upic' : upic,
              coverUrl: pic.startsWith('//') ? 'https:$pic' : pic,
              duration: durationSec,
            ));
          }

          if (tracks.isNotEmpty) return tracks;
        }
      }
    } catch (e) {
      debugPrint('Bilibili search error: $e');
    }

    return [];
  }
}
