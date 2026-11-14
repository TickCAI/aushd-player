import '../../core/emby/models/emby_item.dart';
import '../../data/catalog_api.dart';
import '../../data/tmdb_api.dart';
import '../../l10n/content_zh.dart';
import '../widgets/net_image.dart' show ArtworkFallback;

/// Artwork resolution.
///
/// The server stores the user's own scraped images and is always reachable, so
/// it remains the backup for every TMDB image (see [ArtworkFallback]). On a
/// Chinese UI, however, localized TMDB artwork wins: server scrapers commonly
/// keep the original English poster/backdrop, which is exactly what domestic
/// users do not want to see. A failed CDN request falls back to the server
/// image transparently, so this never produces empty cards.
extension Artwork on CatalogApi {
  Uri? poster(EmbyItem item, {double width = 220}) {
    final w = (width * 1.5).round();
    final tmdb = _tmdb(item.localizedPosterPath, w);
    final server = _serverPoster(item, w);
    if (ContentZh.enabled && tmdb != null) return _prefer(tmdb, server);
    return server ?? tmdb;
  }

  Uri? _serverPoster(EmbyItem item, int w) {
    if (item.primaryImageTag != null && !item.isEpisode) {
      return image(item.id, ImageKind.primary, tag: item.primaryImageTag, width: w);
    }
    if (item.isEpisode && item.seriesId != null && item.seriesPrimaryImageTag != null) {
      return image(item.seriesId!, ImageKind.primary, tag: item.seriesPrimaryImageTag, width: w);
    }
    if (item.primaryImageTag != null) return image(item.id, ImageKind.primary, tag: item.primaryImageTag, width: w);
    return null;
  }

  Uri? landscape(EmbyItem item, {double width = 400, bool preferEpisodeStill = true}) {
    final w = (width * 1.5).round();
    final tmdb = _tmdb(item.localizedBackdropPath, w, backdrop: true) ??
        (item.isEpisode && preferEpisodeStill ? _tmdb(item.localizedStillPath, w, backdrop: true) : null);
    final server = _serverLandscape(item, w, preferEpisodeStill);
    if (ContentZh.enabled && tmdb != null) return _prefer(tmdb, server);
    return server ?? tmdb;
  }

  Uri? _serverLandscape(EmbyItem item, int w, bool preferEpisodeStill) {
    if (item.isEpisode && preferEpisodeStill && item.primaryImageTag != null) {
      return image(item.id, ImageKind.primary, tag: item.primaryImageTag, width: w);
    }
    if (item.thumbImageTag != null) return image(item.id, ImageKind.thumb, tag: item.thumbImageTag, width: w);
    if (item.backdropImageTags.isNotEmpty) {
      return image(item.id, ImageKind.backdrop, tag: item.backdropImageTags.first, width: w);
    }
    if (item.parentThumbItemId != null && item.parentThumbImageTag != null) {
      return image(item.parentThumbItemId!, ImageKind.thumb, tag: item.parentThumbImageTag, width: w);
    }
    if (item.parentBackdropItemId != null && item.parentBackdropImageTags.isNotEmpty) {
      return image(item.parentBackdropItemId!, ImageKind.backdrop, tag: item.parentBackdropImageTags.first, width: w);
    }
    if (item.primaryImageTag != null && (item.primaryImageAspectRatio ?? 0) > 1.2) {
      return image(item.id, ImageKind.primary, tag: item.primaryImageTag, width: w);
    }
    return null;
  }

  Uri? backdrop(EmbyItem item, {int width = 1920, int index = 0}) {
    // The hero usually wants a text-free server backdrop; localized art is only
    // a backup here. Cards go through [landscape] for the Chinese-first path.
    final server = _serverBackdrop(item, width, index);
    final tmdb = index == 0 ? _tmdb(item.localizedBackdropPath, width, backdrop: true) : null;
    if (server != null && tmdb != null) ArtworkFallback.register(server, tmdb);
    return server ?? tmdb;
  }

  Uri? _serverBackdrop(EmbyItem item, int width, int index) {
    if (item.backdropImageTags.isNotEmpty) {
      final i = index.clamp(0, item.backdropImageTags.length - 1);
      return image(item.id, ImageKind.backdrop, tag: item.backdropImageTags[i], width: width, index: i);
    }
    if (item.parentBackdropItemId != null && item.parentBackdropImageTags.isNotEmpty) {
      return image(item.parentBackdropItemId!, ImageKind.backdrop, tag: item.parentBackdropImageTags.first, width: width);
    }
    return null;
  }

  Uri? logo(EmbyItem item, {int width = 640}) {
    final tmdb = _tmdb(item.localizedLogoPath, width, logo: true);
    final server = _serverLogo(item, width);
    if (ContentZh.enabled && tmdb != null) return _prefer(tmdb, server);
    return server ?? tmdb;
  }

  Uri? _serverLogo(EmbyItem item, int width) {
    if (item.logoImageTag != null) return image(item.id, ImageKind.logo, tag: item.logoImageTag, width: width);
    if (item.parentLogoItemId != null && item.parentLogoImageTag != null) {
      return image(item.parentLogoItemId!, ImageKind.logo, tag: item.parentLogoImageTag, width: width);
    }
    return null;
  }

  Uri? personPhoto(Person p, {int width = 240}) {
    if (p.imageTag != null) return personImage(p, width: width);
    final localized = p.localizedImagePath;
    return localized == null ? null : TmdbApi.imageUrl(localized, width: width);
  }

  Uri? _tmdb(String? path, int width, {bool logo = false, bool backdrop = false}) =>
      path == null ? null : TmdbApi.imageUrl(path, width: width, logo: logo, backdrop: backdrop);

  Uri _prefer(Uri primary, Uri? backup) {
    ArtworkFallback.register(primary, backup);
    return primary;
  }
}
