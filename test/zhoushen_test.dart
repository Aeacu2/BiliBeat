import 'package:flutter_test/flutter_test.dart';
import 'package:bilibeat/services/lyrics_engine.dart';

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
    final res = LyricsEngine.cleanTitle('《大鱼》周深');
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

  test('cleanTitleWithValidation: 【姚贝娜&amp;单依纯 心火】collab bracket (DB disambiguation)', () async {
    final res = await LyricsEngine.cleanTitleWithValidation(
      '【姚贝娜&amp;单依纯 心火】音乐是我们最珍贵的琥珀，致敬。',
      defaultArtist: '某UP主',
    );
    expect(res['songTitle'], '心火');
    expect(res['artist'], contains('姚贝娜'));
    expect(res['artist'], contains('单依纯'));
  });

  test('cleanTitle: 【姚贝娜&amp;单依纯 心火】with HTML entity & collab', () {
    final res = LyricsEngine.cleanTitle(
      '【姚贝娜&amp;单依纯 心火】音乐是我们最珍贵的琥珀，致敬。',
      defaultArtist: '某UP主',
    );
    expect(res['songTitle'], '心火');
    expect(res['artist'], '姚贝娜&单依纯');
  });

  test('cleanTitle: 【Artist&Artist Song】without HTML entity', () {
    final res = LyricsEngine.cleanTitle(
      '【张杰&张碧晨 只要平凡】我不是药神',
      defaultArtist: '某UP主',
    );
    expect(res['songTitle'], '只要平凡');
    expect(res['artist'], '张杰&张碧晨');
  });

  test('cleanTitle: show《音乐缘计划》+ song《全世界下雨》multi-bracket', () {
    final res = LyricsEngine.cleanTitle(
      '【周深｜舞台】《音乐缘计划》第二季EP09带来《全世界下雨》舞台',
      defaultArtist: '某UP主',
    );
    expect(res['songTitle'], '全世界下雨');
    expect(res['artist'], '周深');
  });

  test('cleanTitleWithValidation: show-vs-song book brackets', () async {
    final res = await LyricsEngine.cleanTitleWithValidation(
      '【周深｜舞台】《音乐缘计划》第二季EP09带来《全世界下雨》舞台',
      defaultArtist: '某UP主',
    );
    expect(res['songTitle'], '全世界下雨');
    expect(res['artist'], '周深');
  });

  test('cleanTitleWithValidation: repeated taps are idempotent (memoized)', () async {
    const raw = '【周深｜舞台】《音乐缘计划》第二季EP09带来《全世界下雨》舞台';
    final a =
        await LyricsEngine.cleanTitleWithValidation(raw, defaultArtist: '某UP主');
    final b =
        await LyricsEngine.cleanTitleWithValidation(raw, defaultArtist: '某UP主');
    expect(a, b);
    expect(a['songTitle'], isNotEmpty);
  });

  test('cleanTitle: show metadata after | separator is ignored', () {
    final res = LyricsEngine.cleanTitle(
      '【纯享】刘端端姚晓棠《霸王别姬》 舞台携手再现传世经典 | 音乐缘计划 | Melody Journey | iQIYI奇艺音悦台',
      defaultArtist: '某UP主',
    );
    expect(res['songTitle'], '霸王别姬');
    expect(res['artist'], '刘端端姚晓棠');
  });

  test('cleanTitleWithValidation: show metadata after | separator', () async {
    final res = await LyricsEngine.cleanTitleWithValidation(
      '【纯享】刘端端姚晓棠《霸王别姬》 舞台携手再现传世经典 | 音乐缘计划 | Melody Journey | iQIYI奇艺音悦台',
      defaultArtist: '某UP主',
    );
    expect(res['songTitle'], '霸王别姬');
    expect(res['artist'], '刘端端姚晓棠');
  });

  // Regression: 【show】 plain-artist 《song》. The leading bracket is the
  // show tag (声生不息3), not the artist — the plain text between the bracket
  // and the song bracket is. Used to return 声生不息3 as the artist, which
  // also poisoned the auto lyric search.
  test('cleanTitle: 【show】 plain artist 《song》 — plain artist wins', () {
    final res = LyricsEngine.cleanTitle(
      '【声生不息3】 黄绮珊&周深 《岁月》',
      defaultArtist: '某UP主',
    );
    expect(res['songTitle'], '岁月');
    expect(res['artist'], '黄绮珊&周深');
  });

  // The bracket artist must still win when nothing sits between bracket and
  // song, even with noise tokens in between (dropped by _noisyClean).
  test('cleanTitle: 【artist】 noise 《song》 keeps bracket artist', () {
    final res = LyricsEngine.cleanTitle(
      '【周深】 4K高清 《大鱼》',
      defaultArtist: '某UP主',
    );
    expect(res['songTitle'], '大鱼');
    expect(res['artist'], '周深');
  });

  // Regression (3.11.0 report): space-separated collab after a show bracket
  // with NO season digit. The & marker rule and the season-digit rule both
  // missed it, so the bracket show name survived as the artist and
  // validation laundered it (孙燕姿's 逆光 isn't by anyone in the title).
  test('cleanTitle: 【show】 space-separated collab 《song》', () {
    final res = LyricsEngine.cleanTitle(
      '【声生不息】陈楚生 周深 合作舞台《逆光》 爱在“逆光”中前行',
      defaultArtist: '某UP主',
    );
    expect(res['songTitle'], '逆光');
    expect(res['artist'], '陈楚生 周深');
  });
}
