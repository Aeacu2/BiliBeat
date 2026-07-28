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
}
