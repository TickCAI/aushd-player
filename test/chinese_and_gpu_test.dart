import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/l10n/content_zh.dart';
import 'package:zerk_play/playback/mpv/mpv_options.dart';
import 'package:zerk_play/playback/player_settings.dart';
import 'package:zerk_play/ui/widgets/net_image.dart';

void main() {
  setUp(() => ContentZh.uiLanguage = 'zh');

  test('graphics API defaults to d3d11 and survives a settings round trip', () {
    const defaults = PlayerSettings();
    expect(defaults.gpuApi, 'd3d11');
    final saved = defaults.copyWith(gpuApi: 'vulkan').toJson();
    expect(saved['gpuApi'], 'vulkan');
    expect(PlayerSettings.fromJson(saved).gpuApi, 'vulkan');
    // An older settings blob without the new key must keep the safe default.
    expect(PlayerSettings.fromJson(const <String, dynamic>{'vo': 'gpu-next'}).gpuApi, 'd3d11');
  });

  test('mpv uses the selected graphics API and drops d3d11 hardware decode on it', () {
    final d3d = buildMpvOptions(settings: const PlayerSettings(hwdec: 'd3d11va'));
    final vulkan = buildMpvOptions(settings: const PlayerSettings(gpuApi: 'vulkan', hwdec: 'd3d11va'));
    final opengl = buildMpvOptions(settings: const PlayerSettings(gpuApi: 'opengl'));
    expect(d3d['gpu-api'], 'd3d11');
    expect(d3d['hwdec'], 'd3d11va');
    expect(vulkan['gpu-api'], 'vulkan');
    expect(vulkan['hwdec'], 'auto-safe');
    expect(opengl['gpu-api'], 'opengl');
  });

  test('Chinese content adaptation covers genres, languages, roles and collections', () {
    expect(ContentZh.genre('Crime'), '犯罪');
    expect(ContentZh.genre('Science Fiction'), '科幻');
    expect(ContentZh.genre('Action & Adventure'), '动作冒险');
    expect(ContentZh.genres(const ['Crime', 'Drama']), '犯罪, 剧情');
    expect(ContentZh.genre('Some custom tag'), 'Some custom tag');
    expect(ContentZh.language('English'), '英语');
    expect(ContentZh.language('Chinese (Simplified)'), '简体中文');
    expect(ContentZh.language('eng'), '英语');
    expect(ContentZh.language('zh-TW'), '繁體中文');
    expect(ContentZh.personRole('Director'), '导演');
    expect(ContentZh.collectionName('Johnny Keep Walking Collection'), 'Johnny Keep Walking 系列');
    expect(ContentZh.collectionName('年会不能停！（系列）'), '年会不能停！（系列）');

    ContentZh.uiLanguage = 'en';
    expect(ContentZh.genre('Crime'), 'Crime');
    expect(ContentZh.language('English'), 'English');
  });

  test('artwork fallback registry is scoped to the preferred URL', () {
    final primary = Uri.parse('https://image.tmdb.org/t/p/w780/zh.jpg');
    final backup = Uri.parse('http://localhost:8096/Items/1/Images/Primary');
    final other = Uri.parse('https://image.tmdb.org/t/p/w780/other.jpg');
    ArtworkFallback.register(primary, backup);
    expect(ArtworkFallback.of(primary), backup);
    expect(ArtworkFallback.of(other), isNull);
    ArtworkFallback.register(other, null);
    expect(ArtworkFallback.of(other), isNull);
  });
}
