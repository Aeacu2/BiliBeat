import 'track.dart';

/// A named, ordered set of tracks.
///
/// `coverUrl`, `createdAt` and `updatedAt` were carried on every playlist and
/// persisted to disk, but nothing ever read them — no cover was rendered and
/// nothing sorted by date. They are gone.
class Playlist {
  final String id;
  final String name;
  final List<Track> tracks;

  const Playlist({
    required this.id,
    required this.name,
    required this.tracks,
  });

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
