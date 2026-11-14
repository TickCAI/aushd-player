import 'dart:ui' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/core/emby/models/emby_item.dart' show EmbyItem, Person;
import 'package:zerk_play/data/catalog_api.dart' show CatalogApi, ImageKind, LibraryArtworkRef, LibraryView;
import 'package:zerk_play/data/metadata_localizer.dart' show MetadataLocalizer;
import 'package:zerk_play/l10n/app_localizations.dart' show lookupL10n;
import 'package:zerk_play/l10n/content_zh.dart' show ContentZh;
import 'package:zerk_play/playback/mpv/mpv_options.dart' show buildMpvOptions;
import 'package:zerk_play/playback/player_settings.dart' show PlayerSettings;
import 'package:zerk_play/ui/widgets/library_card.dart' show LibraryCard, libraryCardWidth;
import 'package:zerk_play/ui/widgets/mixed_cards.dart' show spotlightWidth;
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

  test('library tiles use the wide spotlight size, not the 380 landscape card', () {
    expect(libraryCardWidth, spotlightWidth);
    expect(libraryCardWidth, greaterThan(380.0));
  });

  test('a Limit-capped TotalRecordCount can never shrink a real library count', () {
    // v1.0.5 overwrote RecursiveItemCount with a query limited to 1 item,
    // which made every library on the home shelf read "1 部".
    expect(CatalogApi.bestLibraryCount(500, 1), 500);
    expect(CatalogApi.bestLibraryCount(500, 900), 900);
    expect(CatalogApi.bestLibraryCount(null, 12), 12);
    expect(CatalogApi.bestLibraryCount(7, null), 7);
    expect(CatalogApi.bestLibraryCount(null, null), isNull);
  });

  test('enriching a library keeps its landscape artwork ref and overview', () {
    const ref = LibraryArtworkRef('item-7', ImageKind.backdrop, 'backdrop-tag');
    const view = LibraryView(id: 'lib-1', name: '电影', featuredArtwork: ref, overview: '每日更新');
    final enriched = view.copyWith(itemCount: 128);
    expect(enriched.featuredArtwork?.itemId, 'item-7');
    expect(enriched.featuredArtwork?.kind, ImageKind.backdrop);
    expect(enriched.overview, '每日更新');
    expect(enriched.itemCount, 128);
  });

  test('TMDB is only consulted when the server left a real gap', () {
    EmbyItem scraped({
      String? imageTag = 'poster-tag',
      String? overview = '服务器刮削的简介',
      List<String> genres = const ['剧情'],
      List<Person> people = const [Person(id: 'p1', name: '演员')],
      Map<String, String> providerIds = const {'Tmdb': '123'},
    }) =>
        EmbyItem(
          id: 'm1',
          name: '电影',
          type: 'Movie',
          primaryImageTag: imageTag,
          overview: overview,
          genres: genres,
          people: people,
          providerIds: providerIds,
        );

    // A fully scraped library item costs zero TMDB requests.
    expect(MetadataLocalizer.needsFill(scraped()), isFalse);
    expect(MetadataLocalizer.needsFill(scraped(imageTag: null)), isTrue);
    expect(MetadataLocalizer.needsFill(scraped(overview: null)), isTrue);
    expect(MetadataLocalizer.needsFill(scraped(people: const [])), isTrue);
    // Without a Tmdb provider id there is nothing to look up, so no request.
    expect(MetadataLocalizer.needsFill(scraped(providerIds: const {})), isFalse);
  });
}
