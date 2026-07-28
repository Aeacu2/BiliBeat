class LyricLine {
  final double time; // in seconds
  final String text;
  final String? translation;

  LyricLine({
    required this.time,
    required this.text,
    this.translation,
  });

  Map<String, dynamic> toMap() {
    return {
      'time': time,
      'text': text,
      'translation': translation,
    };
  }

  factory LyricLine.fromMap(Map<String, dynamic> map) {
    return LyricLine(
      time: (map['time'] as num).toDouble(),
      text: map['text'] ?? '',
      translation: map['translation'],
    );
  }
}

class LyricsResult {
  final String source; // 'lrclib' | 'netease' | 'user' | 'none'
  final String? songTitle;
  final String? artistName;
  final List<LyricLine> lines;
  final String? rawLrc;

  LyricsResult({
    required this.source,
    this.songTitle,
    this.artistName,
    required this.lines,
    this.rawLrc,
  });

  Map<String, dynamic> toMap() {
    return {
      'source': source,
      'songTitle': songTitle,
      'artistName': artistName,
      'lines': lines.map((l) => l.toMap()).toList(),
      'rawLrc': rawLrc,
    };
  }

  factory LyricsResult.fromMap(Map<String, dynamic> map) {
    final rawLines = map['lines'] as List? ?? const [];
    return LyricsResult(
      source: map['source'] as String? ?? 'none',
      songTitle: map['songTitle'] as String?,
      artistName: map['artistName'] as String?,
      lines: rawLines
          .map((l) => LyricLine.fromMap(Map<String, dynamic>.from(l as Map)))
          .toList(),
      rawLrc: map['rawLrc'] as String?,
    );
  }
}
