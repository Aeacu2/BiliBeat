class Track {
  final String id;
  final String bvid;
  final int cid;
  final String title;
  final String uploader;
  final String? uploaderFace;
  final String coverUrl;
  final int duration; // in seconds
  final String? audioUrl;
  final String? quality;
  final bool isDownloaded;
  final String? localFilePath;
  final int? addedAt;

  Track({
    required this.id,
    required this.bvid,
    required this.cid,
    required this.title,
    required this.uploader,
    this.uploaderFace,
    required this.coverUrl,
    required this.duration,
    this.audioUrl,
    this.quality,
    this.isDownloaded = false,
    this.localFilePath,
    this.addedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bvid': bvid,
      'cid': cid,
      'title': title,
      'uploader': uploader,
      'uploaderFace': uploaderFace,
      'coverUrl': coverUrl,
      'duration': duration,
      'audioUrl': audioUrl,
      'quality': quality,
      'isDownloaded': isDownloaded ? 1 : 0,
      'localFilePath': localFilePath,
      'addedAt': addedAt ?? DateTime.now().millisecondsSinceEpoch,
    };
  }

  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      id: map['id'] ?? '',
      bvid: map['bvid'] ?? '',
      cid: map['cid'] ?? 0,
      title: map['title'] ?? '未知曲目',
      uploader: map['uploader'] ?? '未知UP主',
      uploaderFace: map['uploaderFace'],
      coverUrl: map['coverUrl'] ?? '',
      duration: map['duration'] ?? 0,
      audioUrl: map['audioUrl'],
      quality: map['quality'],
      isDownloaded: (map['isDownloaded'] ?? 0) == 1,
      localFilePath: map['localFilePath'],
      addedAt: map['addedAt'],
    );
  }

  Track copyWith({
    String? id,
    String? bvid,
    int? cid,
    String? title,
    String? uploader,
    String? uploaderFace,
    String? coverUrl,
    int? duration,
    String? audioUrl,
    String? quality,
    bool? isDownloaded,
    String? localFilePath,
    int? addedAt,
  }) {
    return Track(
      id: id ?? this.id,
      bvid: bvid ?? this.bvid,
      cid: cid ?? this.cid,
      title: title ?? this.title,
      uploader: uploader ?? this.uploader,
      uploaderFace: uploaderFace ?? this.uploaderFace,
      coverUrl: coverUrl ?? this.coverUrl,
      duration: duration ?? this.duration,
      audioUrl: audioUrl ?? this.audioUrl,
      quality: quality ?? this.quality,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      localFilePath: localFilePath ?? this.localFilePath,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  /// Identity is the track id (`bvid_cid`), which uniquely names one playable
  /// part. Two `Track` objects for the same part — one from search, one
  /// rehydrated from disk — must compare equal so list lookups behave.
  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Track($id, $title)';
}

/// Callback for "play this track", optionally within a specific queue
/// context (e.g. a playlist/favorites). When [queue] is null, the caller's
/// default library (all downloaded tracks) is used.
typedef TrackAction = void Function(Track track, {List<Track>? queue});
