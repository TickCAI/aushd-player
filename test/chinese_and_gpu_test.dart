import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/l10n/content_zh.dart';
import 'package:zerk_play/playback/mpv/mpv_options.dart';
import 'package:zerk_play/playback/player_settings.dart';
import 'package:zerk_play/playback/render_guard.dart';
import 'package:zerk_play/ui/widgets/net_image.dart';

void main() {
  setUp(() => ContentZh.uiLanguage = 'zh');

  test('graphics API defaults to Vulkan and survives a settings round trip', () {
    const defaults = PlayerSettings();
    expect(defaults.gpuApi, 'vulkan');
    expect(defaults.gpuApiAuto, isTrue);
    final saved = defaults.copyWith(gpuApi: 'd3d11', gpuApiAuto: false).toJson();
    expect(saved['gpuApi'], 'd3d11');
    expect(saved['gpuApiAuto'], isFalse);
    expect(PlayerSettings.fromJson(saved).gpuApi, 'd3d11');
    expect(PlayerSettings.fromJson(saved).gpuApiAuto, isFalse);
    // An older settings blob without the new keys keeps the safe default and
    // is still eligible for the automatic migration away from D3D11.
    final old = PlayerSettings.fromJson(const <String, dynamic>{'vo': 'gpu-next'});
    expect(old.gpuApi, 'vulkan');
    expect(old.gpuApiAuto, isTrue);
  });

  test('mpv pins a matching GPU context and avoids flip-model D3D11 swapchains', () {
    final d3d = buildMpvOptions(settings: const PlayerSettings(gpuApi: 'd3d11', hwdec: 'd3d11va'));
    final vulkan = buildMpvOptions(settings: const PlayerSettings(hwdec: 'd3d11va'));
    final opengl = buildMpvOptions(settings: const PlayerSettings(gpuApi: 'opengl'));
    expect(d3d['gpu-api'], 'd3d11');
    expect(d3d['gpu-context'], 'd3d11');
    expect(d3d['d3d11-flip'], 'no');
    expect(d3d['hwdec'], 'd3d11va');
    expect(vulkan['gpu-api'], 'vulkan');
    expect(vulkan['gpu-context'], 'winvk');
    expect(vulkan['hwdec'], 'auto-safe');
    expect(vulkan['d3d11-flip'], isNull);
    expect(opengl['gpu-api'], 'opengl');
    expect(opengl['gpu-context'], 'win');
    expect(opengl['vo'], 'gpu');
  });

  test('render guard migrates old defaults and steps down after a native crash', () {
    final old = PlayerSettings.fromJson(const <String, dynamic>{'gpuApi': 'd3d11'});
    expect(RenderGuard.migrateDefault(old).gpuApi, 'vulkan');
    const manual = PlayerSettings(gpuApi: 'd3d11', gpuApiAuto: false);
    expect(identical(RenderGuard.migrateDefault(manual), manual), isTrue);

    final first = RenderGuard.fallback(manual, 1);
    expect(first.gpuApi, 'vulkan');
    expect(first.hwdec, 'auto-safe');
    expect(first.gpuApiAuto, isFalse);

    final second = RenderGuard.fallback(first, 2);
    expect(second.gpuApi, 'opengl');
    expect(second.videoOutput, 'gpu');
    expect(second.hwdec, 'no');

    // A crash that already happened on Vulkan must not "step down" to it.
    const vulkan = PlayerSettings(gpuApi: 'vulkan');
    expect(RenderGuard.fallback(vulkan, 1).gpuApi, 'opengl');
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
