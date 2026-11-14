import 'dart:ui' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/data/catalog_api.dart' show LibraryView;
import 'package:zerk_play/l10n/app_localizations.dart' show lookupL10n;
import 'package:zerk_play/l10n/content_zh.dart' show ContentZh;
import 'package:zerk_play/playback/mpv/mpv_options.dart' show buildMpvOptions;
import 'package:zerk_play/playback/player_settings.dart' show PlayerSettings;
import 'package:zerk_play/ui/widgets/library_card.dart' show LibraryCard;
import 'package:zerk_play/ui/widgets/net_image.dart' show ArtworkFallback;

void main() {
  setUp(() {
    ContentZh.uiLanguage = 'zh';
    ArtworkFallback.clear();
  });

  test('a corrupt gpuApi preference can never reach mpv_initialize', () {
    expect(PlayerSettings.fromJson(const {'gpuApi': 'made-up'}).gpuApi, 'd3d11');
    expect(PlayerSettings.fromJson(const {'gpuApi': 42}).gpuApi, 'd3d11');
    expect(const PlayerSettings(gpuApi: 'made-up').safeGpuApi, 'd3d11');
    expect(const PlayerSettings(gpuApi: 'vulkan').safeGpuApi, 'vulkan');
  });

  test('OpenGL is paired with the legacy gpu VO instead of failing gpu-next', () {
    final opengl = buildMpvOptions(settings: const PlayerSettings(gpuApi: 'opengl', videoOutput: 'gpu-next'));
    expect(opengl['gpu-api'], 'opengl');
    expect(opengl['vo'], 'gpu');

    final vulkan = buildMpvOptions(settings: const PlayerSettings(gpuApi: 'vulkan', hwdec: 'dxva2-copy'));
    expect(vulkan['gpu-api'], 'vulkan');
    expect(vulkan['vo'], 'gpu-next');
    expect(vulkan['hwdec'], 'auto-safe');
  });

  test('a null backup clears a stale fallback mapping', () {
    final primary = Uri.parse('https://image.tmdb.org/t/p/w780/a.jpg');
    final backup = Uri.parse('http://localhost:8096/Items/1/Images/Primary');
    ArtworkFallback.register(primary, backup);
    expect(ArtworkFallback.of(primary), backup);
    ArtworkFallback.register(primary, null);
    expect(ArtworkFallback.of(primary), isNull);
  });

  test('library tiles keep all server artwork fields when a count arrives later', () {
    const view = LibraryView(
      id: 'lib-1',
      name: '电影',
      collectionType: 'movies',
      imageTag: 'primary-tag',
      thumbImageTag: 'thumb-tag',
      logoImageTag: 'logo-tag',
      backdropImageTags: ['backdrop-tag'],
    );
    final enriched = view.copyWith(itemCount: 128);
    expect(enriched.id, view.id);
    expect(enriched.thumbImageTag, 'thumb-tag');
    expect(enriched.logoImageTag, 'logo-tag');
    expect(enriched.backdropImageTags, const ['backdrop-tag']);
    expect(enriched.itemCount, 128);
    expect(LibraryCard.typeLabel('tvshows', lookupL10n(const Locale('zh'))), '剧集');
  });

  test('library type labels are not hardcoded Chinese on an English UI', () {
    ContentZh.uiLanguage = 'en';
    expect(LibraryCard.typeLabel('music', lookupL10n(const Locale('en'))), 'Music');
  });
}
