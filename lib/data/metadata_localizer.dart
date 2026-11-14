import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/emby/models/emby_item.dart';
import '../core/storage/blob_store.dart';
import 'tmdb_api.dart';

typedef SeriesTmdbIds = Future<Map<String, int>> Function(Set<String> seriesIds);

final class TmdbCollectionInfo {
  const TmdbCollectionInfo({
    required this.id,
    required this.name,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.logoPath,
    this.parts = const [],
  });

  final int id;
  final String name;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? logoPath;

  final List<int> parts;
}

final class MetadataLocalizer {
  MetadataLocalizer({
    required this._tmdb,
    required this.language,
    required this._seriesTmdbIds,
    this.artworkOnly = false,
  }) {
    keyRejected.value = false;
  }

  final TmdbApi _tmdb;

  final String language;
  final SeriesTmdbIds _seriesTmdbIds;

  /// "Follow the server" mode: fetch localized artwork only, never replace
  /// the titles/synopses the user's own scraper produced.
  final bool artworkOnly;

  static final keyRejected = ValueNotifier<bool>(false);

  bool _rejected = false;

  final _seriesIds = <String, int?>{};
  final _inFlight = <String, Future<Map<String, dynamic>?>>{};
  final _gate = _Gate(6);

  String get _lang => language.split('-').first;
  bool get _english => _lang == 'en';

  /// Ask TMDB for Chinese artwork first. `null` means text-free images,
  /// which are preferable to English ones on a Chinese UI.
  String get _imageLanguages =>
      _english ? 'en,null' : [_lang, if (_lang != 'zh') 'zh', 'null', 'en'].join(',');

  /// The user's Emby/Jellyfin library is already scraped. Lists, shelves,
  /// searches and the home page must NEVER hit TMDB -- they render exactly what
  /// the server has. [fillMissing] is the only path that may issue a request:
  /// once, when a title is opened, and only for fields the server left empty.
  Future<EmbyItem> localize(EmbyItem item) => fillMissing(item);

  /// Explicit, opt-in batch localization. No UI list may call this: the home
  /// page, library, search and recommendations render server metadata only.
  /// It is kept for a future "re-scrape this selection" action, so every
  /// private helper below still has a legitimate (but never automatic) entry.
  Future<List<EmbyItem>> localizeAll(List<EmbyItem> items) async {
    if (items.isEmpty || _rejected) return items;
    if (_gate.backlog > 24) {
      debugPrint('[TMDB] localize skipped for ${items.length} items (${_gate.backlog} queued)');
      return items;
    }
    await _TmdbCache.instance.ready;
    try {
      await _resolveSeries(items);
      return await Future.wait(items.map(_localizeOne)).timeout(const Duration(seconds: 6), onTimeout: () => items);
    } catch (e) {
      debugPrint('[TMDB] localize failed: $e');
      return items;
    }
  }

  final _fillAttempted = <String>{};

  /// A domestic user notices missing artwork, a missing synopsis/genres, or an
  /// empty cast list. If the server supplied all of those, no request is made.
  static bool needsFill(EmbyItem item) {
    if ((item.type != 'Movie' && item.type != 'Series') || item.tmdbId == null) return false;
    final noArtwork = item.primaryImageTag == null &&
        item.thumbImageTag == null &&
        item.seriesPrimaryImageTag == null &&
        item.backdropImageTags.isEmpty &&
        item.parentBackdropImageTags.isEmpty;
    final noText = (item.overview?.trim().isEmpty ?? true) || item.genres.isEmpty;
    return noArtwork || noText || item.people.isEmpty;
  }

  /// On-demand "fill the gaps" for a single title the user just opened.
  /// At most two cached requests (title+images, then credits) and never twice
  /// for the same item in a session, so this cannot turn into a request storm.
  Future<EmbyItem> fillMissing(EmbyItem item) async {
    if (_rejected || !needsFill(item)) return item;
    if (!_fillAttempted.add(item.id)) return item;
    await _TmdbCache.instance.ready;
    try {
      final id = item.tmdbId!;
      final path = item.type == 'Series' ? 'tv/$id' : 'movie/$id';
      final doc = await _doc(path, () => _title('/$path')).timeout(const Duration(seconds: 6));
      if (doc == null) return item;
      var out = _fillGaps(item, doc);
      if (item.people.isEmpty) {
        out = await _fillCast(out, path).timeout(const Duration(seconds: 6), onTimeout: () => out);
      }
      debugPrint('[TMDB] filled gaps for "${item.name}" (${item.id})');
      return out;
    } catch (e) {
      debugPrint('[TMDB] fill ${item.id}: $e');
      return item;
    }
  }

  EmbyItem _fillGaps(EmbyItem item, Map<String, dynamic> doc) {
    final hasPoster = item.primaryImageTag != null || item.thumbImageTag != null || item.seriesPrimaryImageTag != null;
    final hasBackdrop = item.backdropImageTags.isNotEmpty || item.parentBackdropImageTags.isNotEmpty;
    final collection = doc['collection'] is Map ? doc['collection'] as Map : null;
    // copyWith keeps the server value whenever null is passed: this only ever
    // fills blanks, it never replaces the user's own scraped metadata.
    return item.copyWith(
      name: item.name.trim().isEmpty ? _str(doc['title']) : null,
      overview: (item.overview?.trim().isEmpty ?? true) ? _str(doc['overview']) : null,
      genres: item.genres.isEmpty ? [for (final g in (doc['genres'] as List? ?? const [])) if (g is String) g] : null,
      localizedPosterPath: hasPoster ? null : _str(doc['poster']),
      localizedLogoPath: item.logoImageTag == null && item.parentLogoImageTag == null ? _str(doc['logo']) : null,
      localizedBackdropPath: hasBackdrop ? null : _str(doc['backdrop']),
      localizedCollectionId: collection?['id'] as int?,
      localizedCollectionName: _str(collection?['name']),
    );
  }

  Future<EmbyItem> _fillCast(EmbyItem item, String path) async {
    final doc = await _doc('fill/$path/credits', () async {
      final j = await _tmdb.get('/$path/credits', language: language);
      if (j == null) return null;
      return <String, dynamic>{
        'cast': [
          for (final c in (j['cast'] as List? ?? const []))
            if (c is Map && c['name'] is String)
              <String, dynamic>{
                'id': c['id'],
                'name': c['name'],
                'role': c['character'],
                'photo': c['profile_path'],
              },
        ],
      };
    });
    final cast = doc?['cast'] as List? ?? const [];
    if (cast.isEmpty) return item;
    return item.copyWith(people: [
      for (final c in cast)
        if (c is Map)
          Person(
            id: 'tmdb:${c['id'] ?? c['name']}',
            name: _str(c['name']) ?? '',
            role: _str(c['role']),
            type: 'Actor',
            localizedImagePath: _str(c['photo']),
          ),
    ]);
  }

  Future<TmdbCollectionInfo?> collection(int id) async {
    if (_rejected) return null;
    await _TmdbCache.instance.ready;
    try {
      final doc = await _doc('collection/$id', () => _title('/collection/$id'));
      final name = _str(doc?['title']);
      if (doc == null || name == null) return null;
      return TmdbCollectionInfo(
        id: id,
        name: name,
        overview: _str(doc['overview']),
        posterPath: _str(doc['poster']),
        backdropPath: _str(doc['backdrop']),
        logoPath: _str(doc['logo']),
        parts: [for (final p in (doc['parts'] as List? ?? const [])) if (p is int) p],
      );
    } catch (e) {
      debugPrint('[TMDB] collection $id: $e');
      return null;
    }
  }

  Future<int?> movieCollectionId(int tmdbMovieId) async {
    if (_rejected) return null;
    await _TmdbCache.instance.ready;
    try {
      final doc = await _doc('movie/$tmdbMovieId', () => _title('/movie/$tmdbMovieId'));
      final c = doc?['collection'];
      return c is Map && c['id'] is int ? c['id'] as int : null;
    } catch (e) {
      debugPrint('[TMDB] movie $tmdbMovieId collection: $e');
      return null;
    }
  }

  Future<EmbyItem> _localizeOne(EmbyItem item) async {
    try {
      switch (item.type) {
        case 'Movie':
          final id = item.tmdbId;
          if (id == null) return item;
          final out = _apply(item, await _doc('movie/$id', () => _title('/movie/$id')));
          // Cast photos are metadata, not artwork: "follow the server" mode
          // must not pay for a second TMDB request on every single movie.
          if (artworkOnly) return out;
          return await _withCast(out, 'movie/$id');
        case 'Series':
          final id = item.tmdbId;
          if (id == null) return item;
          final out = _apply(item, await _series(id));
          if (artworkOnly) return out;
          return await _withCast(out, 'tv/$id');
        case 'BoxSet':
          final id = item.tmdbId;
          if (id == null) return item;
          return _apply(item, await _doc('collection/$id', () => _title('/collection/$id')), keepTagline: true);
        case 'Season':
          final sid = _seriesIds[item.seriesId];
          final n = item.indexNumber;
          if (sid == null || n == null) return item;
          final (series, season) = await (_series(sid), _season(sid, n)).wait;
          var out = item;
          if (season != null) {
            out = out.copyWith(
              name: artworkOnly ? null : _str(season['title']),
              overview: artworkOnly ? null : _str(season['overview']),
              localizedPosterPath: _str(season['poster']),
            );
          }
          return out.copyWith(
            seriesName: artworkOnly ? null : _str(series?['title']),
            localizedLogoPath: _str(series?['logo']),
            localizedBackdropPath: _str(series?['backdrop']),
          );
        case 'Episode':
          final sid = _seriesIds[item.seriesId];
          final s = item.parentIndexNumber, e = item.indexNumber;
          if (sid == null || s == null || e == null) return item;
          final (series, season) = await (_series(sid), _season(sid, s)).wait;
          final episode = (season?['episodes'] as Map?)?['$e'] as Map?;
          return item.copyWith(
            name: artworkOnly ? null : _str(episode?['title']),
            overview: artworkOnly ? null : _str(episode?['overview']),
            localizedStillPath: _str(episode?['still']),
            seriesName: artworkOnly ? null : _str(series?['title']),
            seasonName: artworkOnly ? null : _str(season?['title']),
            localizedPosterPath: _str(series?['poster']),
            localizedLogoPath: _str(series?['logo']),
            localizedBackdropPath: _str(series?['backdrop']),
          );
        default:
          return item;
      }
    } catch (e) {
      debugPrint('[TMDB] ${item.type} ${item.id}: $e');
      return item;
    }
  }

  EmbyItem _apply(EmbyItem item, Map<String, dynamic>? doc, {bool keepTagline = false}) {
    if (doc == null) return item;
    if (artworkOnly) {
      final collection = doc['collection'] is Map ? doc['collection'] as Map : null;
      return item.copyWith(
        localizedPosterPath: _str(doc['poster']),
        localizedLogoPath: _str(doc['logo']),
        localizedBackdropPath: _str(doc['backdrop']),
        // Collection lookups are metadata-independent and must keep working.
        localizedCollectionId: collection?['id'] as int?,
        localizedCollectionName: _str(collection?['name']),
      );
    }
    final genres = [for (final g in (doc['genres'] as List? ?? const [])) if (g is String) g];
    final collection = doc['collection'] is Map ? doc['collection'] as Map : null;
    final tagline = doc['tagline'];
    return item.copyWith(
      localizedPosterPath: _str(doc['poster']),
      localizedLogoPath: _str(doc['logo']),
      localizedBackdropPath: _str(doc['backdrop']),
      localizedCollectionId: collection?['id'] as int?,
      localizedCollectionName: _str(collection?['name']),
      name: _str(doc['title']),
      overview: _str(doc['overview']),
      tagline: keepTagline || tagline is! String ? item.tagline : _str(tagline),
      genres: genres.isEmpty ? null : genres,
    );
  }

  Future<EmbyItem> _withCast(EmbyItem item, String path) async {
    if (!item.people.any((p) => p.imageTag == null)) return item;
    final doc = await _doc('$path/credits', () async {
      final j = await _tmdb.get('/$path/credits');
      if (j == null) return null;
      return {
        'photos': {
          for (final c in [...(j['cast'] as List? ?? const []), ...(j['crew'] as List? ?? const [])])
            if (c is Map && c['name'] is String && c['profile_path'] is String) c['name']: c['profile_path'],
        },
      };
    });
    final photos = doc?['photos'] as Map? ?? const {};
    if (photos.isEmpty) return item;
    return item.copyWith(people: [
      for (final p in item.people) p.imageTag == null ? p.withLocalizedImage(_str(photos[p.name])) : p,
    ]);
  }

  Future<Map<String, dynamic>?> _series(int id) => _doc('tv/$id', () => _title('/tv/$id'));

  Future<Map<String, dynamic>?> _season(int seriesId, int season) => _doc('tv/$seriesId/season/$season', () async {
        final path = '/tv/$seriesId/season/$season';
        final j = await _tmdb.get(path, language: language, query: {
          'append_to_response': 'images',
          'include_image_language': _imageLanguages,
        });
        if (j == null) return null;
        final episodes = _episodes(j);
        var overview = _str(j['overview']);
        final gaps = overview == null ||
            episodes.values.any((e) => _str(e['title']) == null || _str(e['overview']) == null);
        if (!artworkOnly && !_english && gaps) {
          final en = await _tmdb.get(path, language: 'en-US');
          if (en != null) {
            overview ??= _str(en['overview']);
            _episodes(en).forEach((n, e) {
              final mine = episodes[n];
              if (mine == null) return;
              mine['title'] ??= _str(e['title']);
              mine['overview'] ??= _str(e['overview']);
            });
          }
        }
        final images = j['images'] is Map ? j['images'] as Map : const {};
        return {
          'title': j['name'],
          'overview': overview,
          'poster': _best(images['posters'], _posterOrder) ?? _str(j['poster_path']),
          'episodes': episodes,
        };
      });

  static Map<String, Map<String, dynamic>> _episodes(Map<String, dynamic> season) => {
        for (final ep in (season['episodes'] as List? ?? const []))
          if (ep is Map && ep['episode_number'] is num)
            '${ep['episode_number']}': {
              'title': _str(ep['name']) != null && !_isPlaceholder(ep['name'] as String, (ep['episode_number'] as num).toInt())
                  ? ep['name']
                  : null,
              'overview': _str(ep['overview']),
              'still': _str(ep['still_path']),
            },
      };

  Future<Map<String, dynamic>?> _title(String path) async {
    final j = await _tmdb.get(path, language: language, query: {
      'append_to_response': 'images,translations',
      'include_image_language': _imageLanguages,
    });
    if (j == null) return null;
    final mine = _translation(j, language);
    final en = _english ? null : _translation(j, 'en-US');
    final originalTitle = j['original_language'] == _lang ? _str(j['original_title'] ?? j['original_name']) : null;

    String? text(Map? t, String key) => t == null ? null : _str(t[key]);
    final title = text(mine, 'title') ?? text(mine, 'name') ?? originalTitle ??
        text(en, 'title') ?? text(en, 'name') ?? _str(j['title'] ?? j['name']);

    final String? overview, tagline;
    final localOverview = text(mine, 'overview') ?? _str(j['overview']);
    if (localOverview != null) {
      overview = localOverview;
      tagline = text(mine, 'tagline') ?? (mine == null ? _str(j['tagline']) : null) ?? '';
    } else if (text(en, 'overview') != null) {
      overview = text(en, 'overview');
      tagline = text(en, 'tagline') ?? '';
    } else {
      overview = null;
      tagline = null;
    }

    final images = j['images'] is Map ? j['images'] as Map : const {};
    final collection = j['belongs_to_collection'];
    final parts = j['parts'];
    return {
      'title': title,
      'overview': overview,
      'tagline': tagline,
      'genres': [for (final g in (j['genres'] as List? ?? const [])) if (g is Map) g['name']],
      'poster': _best(images['posters'], _posterOrder) ?? _str(j['poster_path']),
      'logo': _best(images['logos'], _posterOrder),
      'backdrop': _best(images['backdrops'], _backdropOrder) ?? _str(j['backdrop_path']),
      if (collection is Map && collection['id'] is int) 'collection': {'id': collection['id'], 'name': collection['name']},
      if (parts is List) 'parts': [for (final p in parts) if (p is Map && p['id'] is int) p['id']],
    };
  }

  List<String?> get _posterOrder =>
      _english ? const ['en', null] : [_lang, if (_lang != 'zh') 'zh', null, 'en'];

  List<String?> get _backdropOrder =>
      _english ? const [null, 'en'] : [_lang, if (_lang != 'zh') 'zh', null, 'en'];

  static Map? _translation(Map<String, dynamic> j, String tag) {
    final t = j['translations'];
    final list = t is Map ? t['translations'] : null;
    if (list is! List) return null;
    final [lang, ...rest] = tag.split('-');
    final region = rest.firstOrNull;
    Map? any;
    for (final e in list) {
      if (e is! Map || e['iso_639_1'] != lang || e['data'] is! Map) continue;
      if (e['iso_3166_1'] == region) return e['data'] as Map;
      any ??= e['data'] as Map;
    }
    return any;
  }

  static String? _best(Object? images, List<String?> order) {
    if (images is! List) return null;
    for (final lang in order) {
      final list = [
        for (final i in images)
          if (i is Map && i['file_path'] is String && i['iso_639_1'] == lang) i,
      ]..sort((a, b) {
          final byVotes = ((b['vote_average'] as num?) ?? 0).compareTo((a['vote_average'] as num?) ?? 0);
          return byVotes != 0 ? byVotes : ((b['vote_count'] as num?) ?? 0).compareTo((a['vote_count'] as num?) ?? 0);
        });
      if (list.isNotEmpty) return list.first['file_path'] as String;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _doc(String path, Future<Map<String, dynamic>?> Function() fetch) {
    final key = 'v3|$language|$path';
    final cache = _TmdbCache.instance;
    final hit = cache.lookup(key);
    if (hit != null) return Future.value(hit.data);
    if (_rejected) return Future.value();
    return _inFlight[key] ??= () async {
      try {
        final doc = await _gate.run(fetch);
        cache.store(key, doc);
        return doc;
      } on TmdbException catch (e) {
        if (e.status == 401) _reject(e);
        rethrow;
      } finally {
        _inFlight.remove(key);
      }
    }();
  }

  void _reject(TmdbException e) {
    if (_rejected) return;
    _rejected = true;
    debugPrint('[TMDB] key rejected ($e); showing the server\'s metadata');
    keyRejected.value = true;
  }

  Future<void> _resolveSeries(List<EmbyItem> items) async {
    for (final i in items) {
      if (i.isSeries && i.tmdbId != null) _seriesIds[i.id] = i.tmdbId;
    }
    final missing = {
      for (final i in items)
        if ((i.isEpisode || i.isSeason) && i.seriesId != null && !_seriesIds.containsKey(i.seriesId)) i.seriesId!,
    };
    if (missing.isEmpty) return;
    final found = await _seriesTmdbIds(missing);
    for (final id in missing) {
      _seriesIds[id] = found[id];
    }
  }

  static String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

  static bool _isPlaceholder(String name, int episode) {
    final words = name.trim().split(RegExp(r'\s+'));
    return words.length <= 2 && words.last == '$episode';
  }

  static Future<void> clearCache() => _TmdbCache.instance.clear();
}

final class _Gate {
  _Gate(this._max);

  final int _max;
  int _running = 0;
  final _waiting = <Completer<void>>[];

  int get backlog => _waiting.length;

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running >= _max) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    _running++;
    try {
      return await task();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }
}

final class _Entry {
  const _Entry(this.time, this.data);

  final DateTime time;

  final Map<String, dynamic>? data;
}

final class _TmdbCache {
  _TmdbCache._() {
    ready = _load();
  }

  static final instance = _TmdbCache._();

  static const _ttl = Duration(days: 14);
  static const _missingTtl = Duration(days: 2);

  late final Future<void> ready;
  final _entries = <String, _Entry>{};
  static const _name = 'tmdb_cache.json';
  Timer? _saveTimer;

  _Entry? lookup(String key) {
    final e = _entries[key];
    if (e == null) return null;
    final age = DateTime.now().difference(e.time);
    return age < (e.data == null ? _missingTtl : _ttl) ? e : null;
  }

  void store(String key, Map<String, dynamic>? data) {
    _entries[key] = _Entry(DateTime.now(), data);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), _save);
  }

  Future<void> clear() async {
    await ready;
    _entries.clear();
    _saveTimer?.cancel();
    try {
      await deleteBlob(_name);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final text = await readBlob(_name);
      if (text == null) return;
      final raw = await compute(_decode, text);
      raw.forEach((k, v) {
        if (v is! Map || !k.startsWith('v3|')) return;
        final t = v['t'];
        if (t is! int) return;
        _entries[k] = _Entry(DateTime.fromMillisecondsSinceEpoch(t), (v['d'] as Map?)?.cast<String, dynamic>());
      });
    } catch (e) {
      debugPrint('[TMDB] cache load failed: $e');
    }
  }

  static Map<String, dynamic> _decode(String text) => jsonDecode(text) as Map<String, dynamic>;

  Future<void> _save() async {
    final now = DateTime.now();
    _entries.removeWhere((_, e) => now.difference(e.time) > _ttl);
    try {
      final doc = {
        for (final e in _entries.entries) e.key: {'t': e.value.time.millisecondsSinceEpoch, 'd': e.value.data},
      };
      await writeBlob(_name, await compute(jsonEncode, doc));
    } catch (e) {
      debugPrint('[TMDB] cache save failed: $e');
    }
  }
}
