import 'track.dart';

/// A named, ordered set of tracks.
///
/// `coverUrl`, `createdAt` and `updatedAt` were carried on every playlist and
/// persisted to disk, but nothing ever read them — no cover was rendered and
/// nothing sorted by date. They are gone.
class Playlist {
  final String id;
  final String name;

  /// Mutated in place by the database layer (add/remove/metadata edits), so it
  /// must always be growable.
  final List<Track> tracks;

  /// Deliberately NOT const. A const constructor lets `Playlist(tracks: [])` be
  /// promoted to a const literal, and a const `[]` is unmodifiable — which
  /// turned "add to 收藏" into `Cannot add to an unmodifiable list`. Keeping the
  /// constructor non-const makes that promotion impossible, and stops
  /// `prefer_const_constructors` from suggesting it back.
  Playlist({
    required this.id,
    required this.name,
    required List<Track> tracks,
  }) : tracks = List<Track>.of(tracks);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map, {List<Track>? tracks}) {
    return Playlist(
      id: map['id'] ?? '',
      name: map['name'] ?? '未命名歌单',
      tracks: tracks ?? [],
    );
  }
}
