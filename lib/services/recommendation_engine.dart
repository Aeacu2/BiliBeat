import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'bilibili_sdk.dart';
import 'database_service.dart';
import 'lyrics_engine.dart';

/// What the user seems to like, derived entirely from local data: favourites,
/// play history and search history. Nothing is uploaded and nothing is
/// persisted separately — clearing any of those sources immediately changes
/// what comes back, because the profile is rebuilt from scratch each time.
@immutable
class TasteProfile {
  /// UP主 name -> weight.
  final Map<String, double> uploaders;

  /// Title/query token -> weight.
  final Map<String, double> terms;

  /// Tracks the user already has; never recommend these back.
  final Set<String> knownIds;

  const TasteProfile({
    required this.uploaders,
    required this.terms,
    required this.knownIds,
  });

  static const TasteProfile empty =
      TasteProfile(uploaders: {}, terms: {}, knownIds: {});

  bool get isEmpty => uploaders.isEmpty && terms.isEmpty;

  /// Weights. Favourites are the strongest signal (an explicit "I like this"),
  /// a typed search is a deliberate intent, and a play is the weakest — it can
  /// just be something that came up in a queue.
  static const double _favouriteWeight = 3.0;
  static const double _searchWeight = 2.0;
  static const double _playWeight = 1.0;

  /// Titles get noisy fast on Bilibili ("【4K】…完整版"), so tokens come from
  /// the cleaned song title rather than the raw one.
  ///
  /// Chinese has no word boundaries, so CJK runs are indexed as character
  /// bigrams — "大鱼海棠" contributes 大鱼/鱼海/海棠, which is enough for
  /// "more like this" without shipping a segmenter.
  static Set<String> tokenize(String text) {
    if (text.isEmpty) return const {};
    final cleaned = LyricsEngine.cleanTitle(text)['songTitle'] ?? text;
    final tokens = <String>{};

    for (final m in RegExp(r'[a-zA-Z0-9]{2,}').allMatches(cleaned)) {
      tokens.add(m.group(0)!.toLowerCase());
    }
    for (final run in RegExp(r'[一-龥]{2,}').allMatches(cleaned)) {
      final han = run.group(0)!;
      for (var i = 0; i + 1 < han.length; i++) {
        tokens.add(han.substring(i, i + 2));
      }
    }
    return tokens;
  }

  static TasteProfile build({
    required List<Track> favourites,
    required List<Track> history,
    required List<String> searches,
  }) {
    final uploaders = <String, double>{};
    final terms = <String, double>{};
    final known = <String>{};

    void absorb(Track t, double weight) {
      known.add(t.id);
      if (t.uploader.isNotEmpty) {
        uploaders[t.uploader] = (uploaders[t.uploader] ?? 0) + weight;
      }
      for (final token in tokenize(t.title)) {
        terms[token] = (terms[token] ?? 0) + weight;
      }
    }

    for (final t in favourites) {
      absorb(t, _favouriteWeight);
    }
    // Recent plays only: taste drifts, and old history should not dominate.
    for (final t in history.take(30)) {
      absorb(t, _playWeight);
    }
    for (final q in searches) {
      for (final token in tokenize(q)) {
        terms[token] = (terms[token] ?? 0) + _searchWeight;
      }
    }

    return TasteProfile(uploaders: uploaders, terms: terms, knownIds: known);
  }

  /// How well [track] matches this profile. 0 means no overlap at all.
  double score(Track track) {
    var score = (uploaders[track.uploader] ?? 0) * 2.0;
    for (final token in tokenize(track.title)) {
      score += terms[token] ?? 0;
    }
    return score;
  }

  /// Queries to actually send to Bilibili, strongest signal first: the UP主s
  /// the user returns to, then their most distinctive title terms, then what
  /// they searched for.
  List<String> seedQueries({int max = 4}) {
    final byWeight = uploaders.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final termsByWeight = terms.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final seeds = <String>[];
    for (final e in byWeight.take(2)) {
      seeds.add(e.key);
    }
    for (final e in termsByWeight) {
      if (seeds.length >= max) break;
      // Single bigrams are too generic to search on their own; pair the
      // strongest ones into one query instead.
      if (e.key.length >= 2 && !seeds.contains(e.key)) seeds.add(e.key);
    }
    return seeds.take(max).toList();
  }
}

/// Builds 为您推荐 from the user's own library.
class RecommendationEngine {
  RecommendationEngine._();

  /// Recommendations are for picking something to listen to, so long-form
  /// uploads — concerts, compilations, radio rips — are excluded. Explicit
  /// searches are never filtered this way.
  static const int maxDurationSeconds = 6 * 60;

  static bool isSongLength(Track t) =>
      t.duration > 0 && t.duration <= maxDurationSeconds;

  /// Returns tracks similar to what the user favourites, plays and searches
  /// for, best match first. Empty when there is nothing to learn from.
  static Future<List<Track>> recommend({int limit = 20}) async {
    final favourites = (await DatabaseService.getFavoritesPlaylist()).tracks;
    final history = await DatabaseService.getRecentlyPlayed();
    final searches = await DatabaseService.getSearchHistory();

    final profile = TasteProfile.build(
      favourites: favourites,
      history: history,
      searches: searches,
    );
    if (profile.isEmpty) return const [];

    final seeds = profile.seedQueries();
    if (seeds.isEmpty) return const [];

    final candidates = <String, Track>{};
    for (final seed in seeds) {
      try {
        for (final track in await BilibiliSdk.search(seed)) {
          if (!isSongLength(track)) continue;
          if (profile.knownIds.contains(track.id)) continue; // already theirs
          candidates.putIfAbsent(track.id, () => track);
        }
      } catch (e) {
        debugPrint('Recommendation seed "$seed" failed: $e');
      }
      if (candidates.length >= limit * 3) break;
    }

    // Score once per candidate, not twice per comparison: `score` tokenises
    // the title, and sorting called it O(n log n) times on the same tracks.
    final ranked = candidates.values
        .map((t) => (track: t, score: profile.score(t)))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return ranked.take(limit).map((e) => e.track).toList();
  }
}
