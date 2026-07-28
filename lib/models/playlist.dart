import 'track.dart';

class Playlist {
  final String id;
  final String name;
  final String? description;
  final String? coverUrl;
  final List<Track> tracks;
  final int createdAt;
  final int updatedAt;

  Playlist({
    required this.id,
    required this.name,
    this.description,
    this.coverUrl,
    required this.tracks,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'coverUrl': coverUrl,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map, {List<Track>? tracks}) {
    return Playlist(
      id: map['id'] ?? '',
      name: map['name'] ?? '未命名歌单',
      description: map['description'],
      coverUrl: map['coverUrl'],
      tracks: tracks ?? [],
      createdAt: map['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: map['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
