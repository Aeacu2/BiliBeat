import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bilibeats/services/lyrics_engine.dart';

void main() {
  test('Test LyricsEngine.cleanTitle on 540 real Bilibili titles', () async {
    final file = File('/Users/aeacu2/.gemini/antigravity/brain/f2850352-2ae9-4c2e-a7e3-fc6a95ce80a0/scratch/real_bilibili_titles.json');
    if (!file.existsSync()) return;

    final List<dynamic> rawList = jsonDecode(await file.readAsString());

    for (int i = 0; i < rawList.length && i < 50; i++) {
      final title = rawList[i]['title'] as String;
      final uploader = rawList[i]['uploader'] as String;
      final parsed = LyricsEngine.cleanTitle(title, defaultArtist: uploader);
      expect(parsed['songTitle'], isNotNull);
    }
  });
}
