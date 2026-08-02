import 'package:flutter_test/flutter_test.dart';
import 'package:bilibeats/services/lyrics_engine.dart';

void main() {
  test('cleanTitle: 周深-世界赠予我的 (with noise)', () {
    final res = LyricsEngine.cleanTitle(
      '周深-世界赠予我的 4k最高音质无损纯享 重混音修音版本【Hi-Res无损】',
      defaultArtist: '琉云星',
    );
    expect(res['songTitle'], '世界赠予我的');
    expect(res['artist'], '周深');
  });

  test('cleanTitle: 画绢 + 衣裳中国 (show tag disambiguation)', () {
    final res = LyricsEngine.cleanTitle(
      '【周深】《画绢》央视《衣裳中国》主题曲 完整版 4K',
      defaultArtist: '周深图文站',
    );
    expect(res['songTitle'], '画绢');
    expect(res['artist'], '周深');
  });

  test('cleanTitle: simple Artist - Song with spaces', () {
    final res = LyricsEngine.cleanTitle(
      '毛不易 - 一程山路',
      defaultArtist: '某UP主',
    );
    expect(res['songTitle'], '一程山路');
    expect(res['artist'], '毛不易');
  });

  test('cleanTitle: 邓紫棋《11》with book brackets', () {
    final res = LyricsEngine.cleanTitle(
      '邓紫棋《11》官方MV',
      defaultArtist: 'UP主',
    );
    expect(res['songTitle'], '11');
    expect(res['artist'], '邓紫棋');
  });

  test('cleanTitle: book bracket with artist after', () {
    final res = LyricsEngine.cleanTitle(
      '《大鱼》周深',
      defaultArtist: '',
    );
    expect(res['songTitle'], '大鱼');
    expect(res['artist'], '周深');
  });

  test('cleanTitle: preserves normal tokens without noise keywords', () {
    final res = LyricsEngine.cleanTitle(
      '陈奕迅 - 十年',
      defaultArtist: '某UP主',
    );
    expect(res['songTitle'], '十年');
    expect(res['artist'], '陈奕迅');
  });

  test('cleanTitleWithValidation: 周深-世界赠予我的', () async {
    final res = await LyricsEngine.cleanTitleWithValidation(
      '周深-世界赠予我的 4k最高音质无损纯享 重混音修音版本【Hi-Res无损】',
      defaultArtist: '琉云星',
    );
    expect(res['songTitle'], '世界赠予我的');
    // Artist should be 周深 from either rule-based or cross-validation
    expect(res['artist'], '周深');
  });
}
