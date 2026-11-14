import 'package:flutter/foundation.dart';

import '../core/emby/models/emby_item.dart';
import '../services/janus/janus_service.dart';
import 'collection_index.dart';
import 'metadata_localizer.dart';

/// Points at a real landscape image that belongs to an item inside a library.
/// Emby's auto-generated library `Primary`/`Thumb` is a tall poster collage;
/// cropping that into a 16:9 tile cuts off every title, so we pick a genuine
/// backdrop from the library's own content instead.
final class LibraryArtworkRef {
  const LibraryArtworkRef(this.itemId, this.kind, this.tag);

  final String itemId;
  final ImageKind kind;
  final String? tag;
}

final class LibraryView {
  const LibraryView({
    required this.id,
    required this.name,
    this.collectionType,
    this.imageTag,
    this.thumbImageTag,
    this.logoImageTag,
    this.backdropImageTags = const [],
    this.itemCount,
    this.featuredArtwork,
    this.overview,
  });

  final String id;
  final String name;

  final String? collectionType;

  /// Primary image. Emby auto-generates a collage of movie posters when no
  /// custom library artwork was uploaded, so this is only a last resort.
  final String? imageTag;

  final String? thumbImageTag;
  final String? logoImageTag;
  final List<String> backdropImageTags;
  final int? itemCount;

  /// A landscape still taken from one of the items in this library.
  final LibraryArtworkRef? featuredArtwork;
  final String? overview;

  LibraryView copyWith({
    int? itemCount,
    LibraryArtworkRef? featuredArtwork,
  }) =>
      LibraryView(
        id: id,
        name: name,
        collectionType: collectionType,
        imageTag: imageTag,
        thumbImageTag: thumbImageTag,
        logoImageTag: logoImageTag,
        backdropImageTags: backdropImageTags,
        itemCount: itemCount ?? this.itemCount,
        featuredArtwork: featuredArtwork ?? this.featuredArtwork,
        overview: overview,
      );
}

final class ItemPage {
  const ItemPage(this.items, this.total);

  final List<EmbyItem> items;
  final int total;
}

enum ImageKind { primary, backdrop, thumb, logo }

final class CatalogApi {
  CatalogApi({required this._janus});

  final JanusService _janus;

  MetadataLocalizer? localizer;

  CollectionIndex? collections;

  String get _userId => _janus.session.userId;

  static const cardFields = 'PrimaryImageAspectRatio,ProductionYear,CommunityRating,OfficialRating,'
      'RunTimeTicks,Overview,Genres,ParentId,SeriesId,SeasonId,ProviderIds,ChildCount,'
      'RecursiveItemCount,Status,EndDate,PremiereDate';

  static const detailFields = '$cardFields,Taglines,Studios,People,MediaSources,MediaStreams,Chapters,'
      'OriginalTitle,PartCount,LocationType';

  static const _imageArgs = {
    'EnableImageTypes': 'Primary,Backdrop,Thumb,Logo',
    'ImageTypeLimit': '1',
    'EnableUserData': 'true',
  };

  /// Home page tiles are rebuilt on every navigation; keep the enriched view
  /// list for a few minutes instead of issuing one query per library each time.
  ({DateTime at, List<LibraryView> data})? _enrichedViews;

  Future<List<LibraryView>> views() async {
    final json = await _janus.client.getJson('/Users/$_userId/Views', queryParameters: {
      'Fields': 'ChildCount,RecursiveItemCount,PrimaryImageAspectRatio,Overview',
      ..._imageArgs,
    });
    return [
      for (final raw in (json['Items'] as List? ?? const []))
        if (raw is Map && raw['Id'] is String)
          LibraryView(
            id: raw['Id'] as String,
            name: (raw['Name'] as String?) ?? '',
            collectionType: raw['CollectionType'] as String?,
            imageTag: _tag(raw, 'Primary'),
            thumbImageTag: _tag(raw, 'Thumb'),
            logoImageTag: _tag(raw, 'Logo'),
            backdropImageTags: [
              for (final t in (raw['BackdropImageTags'] as List? ?? const [])) if (t is String) t,
            ],
            itemCount: (raw['RecursiveItemCount'] as num?)?.toInt() ?? (raw['ChildCount'] as num?)?.toInt(),
            overview: raw['Overview'] as String?,
          ),
    ];
  }

  /// One pass per library returns both the authoritative item count and a
  /// real landscape still to use as the tile artwork.
  Future<List<LibraryView>> viewsWithCounts() async {
    final cached = _enrichedViews;
    if (cached != null && DateTime.now().difference(cached.at) < const Duration(minutes: 5)) {
      return cached.data;
    }
    final views = await this.views();
    if (views.isEmpty) return views;
    final enriched = await Future.wait([
      for (final v in views.take(12)) _enrichView(v),
    ]);
    _enrichedViews = (at: DateTime.now(), data: enriched);
    return enriched;
  }

  Future<LibraryView> _enrichView(LibraryView v) async {
    ItemPage page;
    try {
      page = await query(parentId: v.id, limit: 12, sortBy: 'DateCreated', descending: true, localize: false)
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Some servers reject DateCreated as a sort field. A plain name-ordered
      // query still gives us artwork, and /Views already has the real count.
      try {
        page = await query(parentId: v.id, limit: 12, localize: false).timeout(const Duration(seconds: 4));
      } catch (_) {
        return v;
      }
    }
    // `TotalRecordCount` is capped by Limit on a few Emby/Jellyfin builds (it
    // used to make every library read "1 部"), while RecursiveItemCount from
    // /Views is the authoritative number. Never let the smaller value win.
    final count = bestLibraryCount(v.itemCount, page.total > 0 ? page.total : null);
    return v.copyWith(itemCount: count, featuredArtwork: _featuredArtwork(page.items) ?? v.featuredArtwork);
  }

  /// Kept pure so the "every library shows 1 film" regression stays covered by
  /// a unit test without a live server.
  static int? bestLibraryCount(int? fromViews, int? fromQuery) {
    if (fromViews == null) return fromQuery;
    if (fromQuery == null) return fromViews;
    return fromViews > fromQuery ? fromViews : fromQuery;
  }

  static LibraryArtworkRef? _featuredArtwork(List<EmbyItem> items) {
    for (final item in items) {
      if (item.backdropImageTags.isNotEmpty) {
        return LibraryArtworkRef(item.id, ImageKind.backdrop, item.backdropImageTags.first);
      }
    }
    for (final item in items) {
      if (item.thumbImageTag != null) return LibraryArtworkRef(item.id, ImageKind.thumb, item.thumbImageTag);
    }
    return null;
  }

  /// Shared by the home shelf and the rail so both show the same artwork.
  Uri? libraryArtwork(LibraryView v, {int width = 960}) {
    if (v.backdropImageTags.isNotEmpty) {
      return image(v.id, ImageKind.backdrop, tag: v.backdropImageTags.first, width: width);
    }
    final featured = v.featuredArtwork;
    if (featured != null) return image(featured.itemId, featured.kind, tag: featured.tag, width: width);
    if (v.thumbImageTag != null) return image(v.id, ImageKind.thumb, tag: v.thumbImageTag, width: width);
    if (v.imageTag != null) return image(v.id, ImageKind.primary, tag: v.imageTag, width: width);
    return null;
  }

  static String? _tag(Map raw, String kind) {
    final tags = raw['ImageTags'];
    final value = tags is Map ? tags[kind] : null;
    return value is String && value.isNotEmpty ? value : null;
  }

  Future<List<EmbyItem>> resume({int limit = 24}) => _list('/Users/$_userId/Items/Resume', {
        'Limit': '$limit',
        'MediaTypes': 'Video',
        'Fields': '$cardFields,Chapters',
      });

  Future<List<EmbyItem>> nextUp({int limit = 24, String? seriesId}) => _list('/Shows/NextUp', {
        'UserId': _userId,
        'Limit': '$limit',
        'SeriesId': seriesId,
        'Fields': '$cardFields,Chapters',
        'LegacyNextUp': 'true',
      });

  Future<List<EmbyItem>> continueWatching({int limit = 24}) async {
    final (inProgress, next) = await (resume(limit: limit), nextUp(limit: limit)).wait;
    return mergeContinueWatching(inProgress, next);
  }

  static List<EmbyItem> mergeContinueWatching(List<EmbyItem> resume, List<EmbyItem> nextUp) {
    final ids = {for (final i in resume) i.id};
    final shows = {for (final i in resume) ?i.seriesId};
    return [
      ...resume,
      for (final i in nextUp)
        if (!ids.contains(i.id) && !shows.contains(i.seriesId)) i,
    ];
  }

  Future<List<EmbyItem>> watchingSeries({Duration within = const Duration(days: 120)}) async {
    Future<Map<String, dynamic>> episodes(String path, Map<String, String> args) =>
        _janus.client.getJson(path, queryParameters: {
          ...args,
          'Fields': 'SeriesId',
          'EnableImages': 'false',
          'EnableTotalRecordCount': 'false',
        });
    final since = DateTime.now().subtract(within);
    final (played, resume, next) = await (
      episodes('/Users/$_userId/Items', {
        'IncludeItemTypes': 'Episode',
        'Recursive': 'true',
        'Filters': 'IsPlayed',
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
        'Limit': '300',
      }),
      episodes('/Users/$_userId/Items/Resume', {'IncludeItemTypes': 'Episode', 'Limit': '50'}),
      episodes('/Shows/NextUp', {'UserId': _userId, 'Limit': '50'}),
    ).wait;
    final ids = <String>{
      for (final e in _parse(played))
        if (e.seriesId != null && (e.lastPlayedDate?.isAfter(since) ?? false)) e.seriesId!,
      for (final e in [..._parse(resume), ..._parse(next)]) ?e.seriesId,
    };
    if (ids.isEmpty) return const [];
    final page = await query(ids: ids.toList(), types: ['Series'], limit: ids.length, localize: false);
    final ended = DateTime.now().subtract(const Duration(days: 45));
    return [
      for (final s in page.items)
        if (s.status != 'Ended' || (s.endDate?.isAfter(ended) ?? false)) s,
    ];
  }

  Future<List<EmbyItem>> latest({String? parentId, List<String>? types, int limit = 24}) async {
    final json = await _janus.client.getJsonList('/Users/$_userId/Items/Latest', queryParameters: {
      'Limit': '$limit',
      'ParentId': parentId,
      'IncludeItemTypes': types?.join(','),
      'GroupItems': 'true',
      'Fields': cardFields,
      ..._imageArgs,
    });
    return _localize([for (final raw in json) if (raw is Map) EmbyItem.fromJson(raw.cast<String, dynamic>())]);
  }

  Future<ItemPage> query({
    String? parentId,
    List<String>? types,
    String sortBy = 'SortName',
    bool descending = false,
    int start = 0,
    int limit = 60,
    bool recursive = true,
    List<String>? genres,
    List<int>? years,
    String? filters,
    double? minCommunityRating,
    String? searchTerm,
    String? anyProviderIdEquals,
    String? personIds,
    List<String>? ids,
    String? listItemIds,
    String fields = cardFields,
    bool localize = true,
    bool collapseBoxSets = false,
  }) async {
    if (anyProviderIdEquals != null && _janus.client.isJellyfin) {
      final index = await _providerIndex();
      final matched = {
        for (final key in anyProviderIdEquals.toLowerCase().split(',')) ...?index[key.trim()],
      };
      if (ids != null) matched.retainAll(ids);
      if (matched.isEmpty) return const ItemPage([], 0);
      ids = matched.toList();
      anyProviderIdEquals = null;
    }
    final json = await _janus.client.getJson('/Users/$_userId/Items', queryParameters: {
      'ParentId': parentId,
      'IncludeItemTypes': types?.join(','),
      'Recursive': '$recursive',
      'SortBy': sortBy,
      'SortOrder': descending ? 'Descending' : 'Ascending',
      'StartIndex': '$start',
      'Limit': '$limit',
      'Genres': genres?.join('|'),
      'Years': years?.join(','),
      'Filters': filters,
      'MinCommunityRating': minCommunityRating?.toString(),
      'SearchTerm': searchTerm,
      'AnyProviderIdEquals': anyProviderIdEquals,
      'PersonIds': personIds,
      'Ids': ids?.join(','),
      'ListItemIds': listItemIds,
      'GroupItemsIntoCollections': collapseBoxSets ? 'true' : null,
      'CollapseBoxSetItems': collapseBoxSets ? 'true' : null,
      'Fields': fields,
      'EnableTotalRecordCount': 'true',
      ..._imageArgs,
    });
    final items = _parse(json);
    return ItemPage(localize ? await _localize(items) : items, (json['TotalRecordCount'] as num?)?.toInt() ?? 0);
  }

  Future<Map<String, List<String>>> _providerIndex() {
    final key = '${_janus.session.serverUrl}|$_userId';
    final cached = _providerIds;
    if (cached != null && cached.key == key && DateTime.now().difference(cached.at) < const Duration(minutes: 10)) {
      return cached.index;
    }
    final index = _loadProviderIndex();
    _providerIds = (key: key, at: DateTime.now(), index: index);
    index.catchError((Object _) {
      _providerIds = null;
      return const <String, List<String>>{};
    });
    return index;
  }

  ({String key, DateTime at, Future<Map<String, List<String>>> index})? _providerIds;

  Future<Map<String, List<String>>> _loadProviderIndex() async {
    final json = await _janus.client.getJson('/Users/$_userId/Items', queryParameters: {
      'IncludeItemTypes': 'Movie,Series,BoxSet',
      'Recursive': 'true',
      'Fields': 'ProviderIds',
      'EnableImages': 'false',
      'EnableUserData': 'false',
      'EnableTotalRecordCount': 'false',
    });
    final out = <String, List<String>>{};
    for (final raw in (json['Items'] as List? ?? const [])) {
      if (raw is! Map || raw['Id'] is! String || raw['ProviderIds'] is! Map) continue;
      for (final e in (raw['ProviderIds'] as Map).entries) {
        final value = '${e.value ?? ''}'.trim().toLowerCase();
        if (value.isEmpty) continue;
        (out['${'${e.key}'.toLowerCase()}.$value'] ??= []).add(raw['Id'] as String);
      }
    }
    return out;
  }

  /// The server already holds the user's own scrape. TMDB is never consulted
  /// for a plain item lookup; a detail page opts into gap filling via [localize].
  Future<EmbyItem> item(String id, {bool localizeMetadata = false}) async {
    final json = await _janus.client.getJson('/Users/$_userId/Items/$id', queryParameters: {
      'Fields': detailFields,
      ..._imageArgs,
    });
    final parsed = EmbyItem.fromJson(json);
    if (!localizeMetadata) return parsed;
    return localize(parsed);
  }

  Future<Map<String, int>> seriesTmdbIds(Set<String> seriesIds) async {
    final json = await _janus.client.getJson('/Users/$_userId/Items', queryParameters: {
      'Ids': seriesIds.join(','),
      'Fields': 'ProviderIds',
      'EnableImages': 'false',
      'EnableUserData': 'false',
    });
    return {
      for (final i in _parse(json))
        if (i.tmdbId != null) i.id: i.tmdbId!,
    };
  }

  Future<List<EmbyItem>> seasons(String seriesId) => _list('/Shows/$seriesId/Seasons', {
        'UserId': _userId,
        'Fields': '$cardFields,LocationType',
        'IsMissing': null,
      });

  Future<EmbyItem?> episodeToPlay(EmbyItem show) async {
    final seriesId = show.isSeries ? show.id : show.seriesId;
    if (seriesId == null) return null;
    final next = (await nextUp(seriesId: seriesId, limit: 1)).firstOrNull;
    if (next != null && (!show.isSeason || next.seasonId == show.id)) return next;
    final all = (await episodes(seriesId, seasonId: show.isSeason ? show.id : null)).where((e) => e.isPlayable);
    return all.where((e) => (e.parentIndexNumber ?? 1) > 0).firstOrNull ?? all.firstOrNull;
  }

  Future<List<EmbyItem>> episodes(String seriesId, {String? seasonId}) =>
      _list('/Shows/$seriesId/Episodes', {
        'UserId': _userId,
        'SeasonId': seasonId,
        'Fields': '$cardFields,Chapters,LocationType,MediaSources',
      });

  Future<List<EmbyItem>> similar(String id, {int limit = 16}) => _list('/Items/$id/Similar', {
        'UserId': _userId,
        'Limit': '$limit',
        'Fields': cardFields,
      });

  Future<List<EmbyItem>> boxSets() async =>
      (await query(types: ['BoxSet'], sortBy: 'SortName', limit: 500, localize: false)).items;

  Future<List<EmbyItem>> collectionItems(EmbyItem collection) async {
    if (collection.id.isNotEmpty) {
      final page = await query(
        parentId: collection.id,
        recursive: false,
        sortBy: 'PremiereDate,ProductionYear,SortName',
        limit: 300,
        fields: '$cardFields,Taglines',
      );
      return page.items;
    }
    final tmdbId = collection.tmdbId;
    final info = tmdbId == null
        ? null
        : await (collections?.collection(tmdbId) ?? localizer?.collection(tmdbId) ?? Future.value());
    final parts = info?.parts;
    if (parts == null || parts.isEmpty) return const [];
    final page = await query(
      types: ['Movie'],
      anyProviderIdEquals: parts.map((id) => 'tmdb.$id').join(','),
      sortBy: 'PremiereDate,ProductionYear,SortName',
      limit: 300,
      fields: '$cardFields,Taglines',
    );
    return [for (final i in page.items) if (parts.contains(i.tmdbId)) i];
  }

  Future<List<EmbyItem>> allCollections({bool recent = false, int limit = 500}) async {
    final index = collections;
    if (index != null) {
      final list = recent ? await index.recent(limit: limit) : await index.all();
      return [for (final c in list.take(limit)) c.item];
    }
    final page = await query(
      types: ['BoxSet'],
      sortBy: recent ? 'DateLastContentAdded,SortName' : 'SortName',
      descending: recent,
      limit: limit,
    );
    return page.items;
  }

  Future<({EmbyItem collection, List<EmbyItem> films, int? total})?> collectionOf(EmbyItem movie) async {
    if (!movie.isMovie) return null;
    final index = collections;
    if (index == null) return _boxSetOf(movie);
    final tmdbId = movie.tmdbId;
    final cid = movie.localizedCollectionId ??
        (tmdbId != null ? await index.collectionOfMovie(tmdbId) : movie.tmdbCollectionId);
    if (cid == null) return null;
    final info = await index.collection(cid);
    if (info == null || info.parts.length < 2) return null;
    final films = await collectionItems(CollectionIndex.itemFor(info, owned: 0));
    if (films.isEmpty) return null;
    return (collection: CollectionIndex.itemFor(info, owned: films.length), films: films, total: info.parts.length);
  }

  Future<({EmbyItem collection, List<EmbyItem> films, int? total})?> _boxSetOf(EmbyItem movie) async {
    final cid = movie.tmdbCollectionId;
    if (cid != null) {
      final boxSets = await query(types: ['BoxSet'], anyProviderIdEquals: 'tmdb.$cid', limit: 1);
      final collection = boxSets.items.where((b) => b.tmdbId == cid).firstOrNull;
      if (collection != null) {
        final films = await collectionItems(collection);
        if (films.isNotEmpty) return (collection: collection, films: films, total: null);
      }
    }
    final listing = await query(types: ['BoxSet'], listItemIds: movie.id, limit: 6);
    if (listing.total > 5) {
      debugPrint('[collections] the server ignored ListItemIds (${listing.total} box sets)');
      return null;
    }
    for (final collection in listing.items) {
      final films = await collectionItems(collection);
      if (films.any((f) => f.id == movie.id)) return (collection: collection, films: films, total: null);
    }
    debugPrint('[collections] ${movie.name}: in no box set (tmdb collection ${cid ?? '-'})');
    return null;
  }

  Future<List<MovieRef>> movieRefs() async {
    final out = <MovieRef>[];
    const pageSize = 2000;
    for (var start = 0;; start += pageSize) {
      final json = await _janus.client.getJson('/Users/$_userId/Items', queryParameters: {
        'IncludeItemTypes': 'Movie',
        'Recursive': 'true',
        'Fields': 'ProviderIds,DateCreated',
        'StartIndex': '$start',
        'Limit': '$pageSize',
        'EnableImages': 'false',
        'EnableUserData': 'false',
        'EnableTotalRecordCount': 'true',
      });
      final items = json['Items'] as List? ?? const [];
      for (final raw in items) {
        if (raw is! Map || raw['Id'] is! String) continue;
        final ids = {
          for (final e in ((raw['ProviderIds'] as Map?) ?? const {}).entries) '${e.key}'.toLowerCase(): '${e.value}',
        };
        out.add((
          id: raw['Id'] as String,
          tmdbId: int.tryParse(ids['tmdb'] ?? ''),
          collectionHint: int.tryParse(ids['tmdbcollection'] ?? ''),
          added: DateTime.tryParse(raw['DateCreated'] as String? ?? ''),
        ));
      }
      final total = (json['TotalRecordCount'] as num?)?.toInt() ?? 0;
      if (items.length < pageSize || start + pageSize >= total) break;
    }
    return out;
  }

  Future<EmbyItem?> byTmdbId(int tmdbId, {required bool series}) async {
    final page = await query(
      types: [series ? 'Series' : 'Movie'],
      anyProviderIdEquals: 'tmdb.$tmdbId',
      limit: 1,
    );
    return page.items.firstOrNull;
  }

  Future<List<String>> genres({String? parentId, List<String>? types}) async {
    final json = await _janus.client.getJson('/Genres', queryParameters: {
      'UserId': _userId,
      'ParentId': parentId,
      'IncludeItemTypes': types?.join(','),
      'SortBy': 'SortName',
    });
    return [
      for (final raw in (json['Items'] as List? ?? const []))
        if (raw is Map && raw['Name'] is String) raw['Name'] as String,
    ];
  }

  Future<void> setPlayed(String id, bool played) => played
      ? _janus.client.postNoContent('/Users/$_userId/PlayedItems/$id')
      : _janus.client.deleteNoContent('/Users/$_userId/PlayedItems/$id');

  Future<void> setFavorite(String id, bool favorite) => favorite
      ? _janus.client.postNoContent('/Users/$_userId/FavoriteItems/$id')
      : _janus.client.deleteNoContent('/Users/$_userId/FavoriteItems/$id');

  Uri image(String itemId, ImageKind kind, {String? tag, int width = 480, int index = 0}) {
    final type = switch (kind) {
      ImageKind.primary => 'Primary',
      ImageKind.backdrop => 'Backdrop',
      ImageKind.thumb => 'Thumb',
      ImageKind.logo => 'Logo',
    };
    final path = kind == ImageKind.backdrop ? '/Items/$itemId/Images/$type/$index' : '/Items/$itemId/Images/$type';
    return _janus.client.buildUri(path, queryParameters: {
      'maxWidth': '$width',
      'quality': kind == ImageKind.logo ? null : '88',
      'tag': tag,
    });
  }

  Uri personImage(Person p, {int width = 240}) =>
      image(p.id, ImageKind.primary, tag: p.imageTag, width: width);

  Future<List<EmbyItem>> _list(String path, Map<String, String?> params) async {
    final json = await _janus.client.getJson(path, queryParameters: {...params, ..._imageArgs});
    return _localize(_parse(json));
  }

  /// On-demand gap filling for one opened title. Lists never call this.
  Future<EmbyItem> localize(EmbyItem item) async => await localizer?.fillMissing(item) ?? item;

  /// Home page / library / search / recommendation lists render the server's
  /// own scraped metadata. Keeping this a no-op prevents the TMDB request
  /// storms that used to starve detail pages and playback.
  Future<List<EmbyItem>> _localize(List<EmbyItem> items) => Future.value(items);

  static List<EmbyItem> _parse(Map<String, dynamic> json) => [
        for (final raw in (json['Items'] as List? ?? const []))
          if (raw is Map) EmbyItem.fromJson(raw.cast<String, dynamic>()),
      ];
}
