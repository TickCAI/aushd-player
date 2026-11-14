import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/catalog_api.dart';
import '../../data/recommendations.dart';
import '../../data/seerr_api.dart';
import '../../data/taste_profile.dart';
import '../../data/title_tags.dart';
import '../../core/log/app_log.dart';
import '../../l10n/l10n.dart';
import '../core/artwork.dart';
import '../core/input_mode.dart';
import '../core/playback_launcher.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/backdrop.dart';
import '../widgets/cards.dart';
import '../widgets/cinema_loader.dart';
import '../widgets/media_row.dart';
import '../widgets/mixed_cards.dart';
import '../widgets/mood_shelf.dart';
import '../widgets/trailer.dart';
import 'hero.dart';
import 'title_extras.dart';
import 'routes.dart';

enum _Kind {
  cards,

  continueWatching,
  collections,

  moods,
}

class _Row {
  _Row(this.title, this.load, {this.style = CardStyle.poster, this.kind = _Kind.cards, this.recommends = true});

  String Function(L10n) title;

  final Future<MixedItems> Function() load;
  final CardStyle style;
  final _Kind kind;

  final bool recommends;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onOpenLibraryView});

  /// Called when a server-library tile on the home page is activated.
  final ValueChanged<LibraryView>? onOpenLibraryView;

  static final firstLoad = ValueNotifier(true);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _hero = Debounced<HeroInfo?>(null);
  final _scroll = RevealController(mode: RevealMode.anchored, anchor: 64);
  List<_Row>? _rows;
  final _data = <_Row, Future<MixedItems>>{};

  final _allowed = <_Row>{};
  int _loading = 0;
  static const _parallelRows = 3;

  final _resolved = <_Row, MixedItems>{};
  bool _heroSet = false;

  /// Auto-rotating hero candidates. Only entries with a reachable backdrop
  /// enter the pool, so the carousel never fades to an empty frame.
  final _heroPool = <HeroInfo>[];
  static const _heroPoolLimit = 8;
  static const _heroDwell = Duration(seconds: 7);
  static const _heroPinTime = Duration(seconds: 12);
  int _heroIndex = 0;
  Timer? _carousel;
  Timer? _heroUnpin;
  bool _heroPinned = false;
  bool _animationsEnabled = true;

  bool _loaded = false;
  bool _showLoader = false;

  Future<TasteProfile>? _taste;

  Future<List<TitleTag>>? _tasteTags;

  AppServices? _services;
  String _pickedCollections = '';

  _Row? _myListRow;
  String _myListKeys = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rows == null) {
      _rows = _buildRows(AppServicesScope.read(context));
      _allowFirstRows();
      _scroll.addListener(_onScroll);
      _awaitFirstRows();
    }
    if (_services == null) {
      _services = AppServicesScope.read(context);
      _services!.libraryChanged.addListener(refresh);
      _services!.profiles.addListener(_onProfile);
      _pickedCollections = _collectionsKey(_services!);
      _services!.addListener(_onServices);
    }
  }

  static List<(String, String)> _collections(AppServices s) =>
      s.isSignedIn ? s.settings.homeCollectionsOf(s.janus.session.userId) : const [];

  static String _collectionsKey(AppServices s) => [for (final (id, _) in _collections(s)) id].join(',');

  void _onServices() {
    final key = _collectionsKey(_services!);
    if (key == _pickedCollections || !mounted) return;
    _pickedCollections = key;
    setState(() {
      _rows = _buildRows(_services!);
      _data.clear();
      _resolved.clear();
      _heroPool.clear();
      _heroSet = false;
      _heroIndex = 0;
      _allowFirstRows();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _pump());
  }

  void _onProfile() {
    final keys = [for (final e in _services!.profiles.profile?.list ?? const []) e.key].join(',');
    if (keys == _myListKeys) return;
    _myListKeys = keys;
    final row = _myListRow;
    if (row != null && mounted) setState(() => _data.remove(row));
  }

  void _allowFirstRows() {
    _allowed
      ..clear()
      ..addAll(_rows!.take(6).where((r) => !r.recommends && r.kind != _Kind.moods));
  }

  void _pump({int upTo = -1}) {
    final rows = _rows!;
    var changed = false;
    for (var i = 0; i < rows.length && i <= upTo; i++) {
      changed |= _allowed.add(rows[i]);
    }
    if (_loaded) {
      for (final r in rows) {
        if (_loading >= _parallelRows) break;
        if (_allowed.add(r)) {
          changed = true;
          if (!_data.containsKey(r)) _loading++;
          _load(r, counted: true);
        }
      }
    }
    if (changed && mounted) setState(() {});
  }

  void _onScroll() {
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final upTo = (offset + MediaQuery.sizeOf(context).height * 2) ~/ 320;
    if (upTo >= 0 && _rows!.take(upTo + 1).any((r) => !_allowed.contains(r))) _pump(upTo: upTo);
  }

  void _awaitFirstRows() {
    if (!AppServicesScope.read(context).isSignedIn) {
      _loaded = true;
      HomePage.firstLoad.value = false;
      return;
    }
    final first = _rows!
        .where((r) => r.kind == _Kind.continueWatching || (r.kind == _Kind.cards && !r.recommends))
        .take(2);
    Timer(const Duration(milliseconds: 400), () {
      if (mounted && !_loaded && AppServicesScope.read(context).isSignedIn) setState(() => _showLoader = true);
    });
    Future.wait(first.map((r) => _load(r).catchError((Object _) => const <Object>[])))
        .timeout(const Duration(seconds: 45), onTimeout: () => const [])
        .whenComplete(() {
      AppLog.mark('home rows loaded');
      HomePage.firstLoad.value = false;
      if (mounted) setState(() => _loaded = true);
      _pump();
    });
  }

  @override
  void dispose() {
    _services?.libraryChanged.removeListener(refresh);
    _services?.profiles.removeListener(_onProfile);
    _services?.removeListener(_onServices);
    _carousel?.cancel();
    _heroUnpin?.cancel();
    _hero.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void refresh() {
    setState(() {
      _data.clear();
      _taste = null;
      _tasteTags = null;
      _heroPool.clear();
      _heroSet = false;
      _heroIndex = 0;
      _allowFirstRows();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _pump());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.wait(_data.values.map((f) => f.catchError((Object _) => const <Object>[]))).whenComplete(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final focus = FocusManager.instance.primaryFocus;
          if (focus == null || focus.context == null || !focus.context!.mounted) _focusFirstCard();
        });
      });
    });
  }

  void _focusFirstCard() {
    final ctx = context;
    final scope = FocusScope.of(ctx);
    for (final n in scope.descendants) {
      if (n is ZoneScopeNode && n.items.isNotEmpty) {
        ZoneNavigator.enter(n);
        return;
      }
    }
  }

  Future<TasteProfile> _profile(AppServices s) => _taste ??= TasteProfile.load(s.catalog).catchError((Object e) {
        debugPrint('[home] taste profile: $e');
        return const TasteProfile();
      });

  Future<List<TitleTag>> _tags(AppServices s) => _tasteTags ??= () async {
        final tags = s.titleTags;
        if (tags == null) return const <TitleTag>[];
        return tags.taste(await _profile(s));
      }()
          .catchError((Object e) {
        debugPrint('[home] taste tags: $e');
        return const <TitleTag>[];
      });

  List<_Row> _buildRows(AppServices s) {
    final c = s.catalog;
    final seerr = s.seerr;
    final r = s.recommender;
    Future<MixedItems> items(Future<ItemPage> page) async => (await page).items;

    return [
      _Row((l) => l.continueWatching, () => c.continueWatching(), kind: _Kind.continueWatching, recommends: false),
      _Row((l) => l.myLibraries, () async => <Object>[
        for (final v in await c.views())
          if (v.name.isNotEmpty) v,
      ], style: CardStyle.poster, recommends: false),
      for (final (id, name) in _collections(s))
        _Row((l) => name,
            () => items(c.query(parentId: id, recursive: false, sortBy: 'PremiereDate,ProductionYear,SortName', limit: 100)),
            recommends: false),
      _myListRow = _Row((l) => l.myList, s.myList, recommends: false),
      _because(s, (t) => t.recentMovies, 0),
      _Row((l) => l.latestMovies, () => c.latest(types: ['Movie']), recommends: false),
      if (r.tmdb != null) _Row((l) => l.moodShelfTitle, () async => const [], kind: _Kind.moods, recommends: false),
      _Row((l) => l.latestShows, () => c.latest(types: ['Episode', 'Series']), style: CardStyle.landscape, recommends: false),
      if (seerr != null)
        _Row((l) => l.trendingThisWeek, () => r.mixed((p) => seerr.trending(page: p, timeWindow: 'week'), limit: 10),
            style: CardStyle.ranked),
      _Row((l) => l.recommendedForYou, () => _forYou(s), style: CardStyle.spotlight),
      _starring(s, 0),
      _likeTag(s, 0),
      _Row((l) => l.collections, () => c.allCollections(recent: true, limit: 20), kind: _Kind.collections, recommends: false),
      _because(s, (t) => t.recentSeries, 0, style: CardStyle.landscape),
      _Row((l) => l.topRatedMovies, () => items(c.query(types: ['Movie'], sortBy: 'CommunityRating', descending: true, minCommunityRating: 7, limit: 24))),
      _directedBy(s, 0),
      _likeTag(s, 1, style: CardStyle.landscape),
      _because(s, (t) => t.recentMovies, 1, style: CardStyle.landscape),
      _Row((l) => l.yourFavorites,
          () => items(c.query(types: ['Movie', 'Series'], filters: 'IsFavorite', sortBy: 'Random', limit: 30)),
          style: CardStyle.landscape, recommends: false),
      _starring(s, 1, style: CardStyle.landscape),
      _moreGenre(s, 0),
      _likeTag(s, 2),
      _Row((l) => l.recentlyReleased, () => items(c.query(types: ['Movie'], sortBy: 'PremiereDate', descending: true, limit: 24))),
      _because(s, (t) => t.recentSeries, 1),
      _Row((l) => l.topRatedShows, () => items(c.query(types: ['Series'], sortBy: 'CommunityRating', descending: true, minCommunityRating: 7, limit: 24)),
          style: CardStyle.landscape),
      _starring(s, 2),
      _moreGenre(s, 1, style: CardStyle.landscape),
      _likeTag(s, 3),
      _Row((l) => l.somethingUnseen, () => items(c.query(types: ['Movie'], sortBy: 'Random', filters: 'IsUnplayed', limit: 24))),
      if (seerr != null)
        _Row((l) => l.popularToRequest, () async {
          final (movies, shows) = await (
            r.requestable((p) => r.discover(SeerrMediaType.movie, page: p, voteCountGte: 200), limit: 20),
            r.requestable((p) => r.discover(SeerrMediaType.tv, page: p, voteCountGte: 100), limit: 20),
          ).wait;
          return _interleave(movies, shows);
        }),
    ];
  }

  static List<Object> _interleave(List<Object> a, List<Object> b) => [
        for (var i = 0; i < a.length || i < b.length; i++) ...[if (i < a.length) a[i], if (i < b.length) b[i]],
      ];

  _Row _because(AppServices s, List<EmbyItem> Function(TasteProfile) pick, int index, {CardStyle style = CardStyle.poster}) {
    late final _Row row;
    return row = _Row((l) => '', () async {
      final seeds = pick(await _profile(s));
      if (seeds.length <= index) return const [];
      final seed = await s.catalog.localize(seeds[index]);
      row.title = (l) => l.becauseYouWatched(seed.name);
      final seerr = s.seerr;
      final tmdbId = seed.tmdbId;
      final MixedItems items;
      if (seerr != null && tmdbId != null) {
        items = await s.recommender.mixed(
            (p) => seerr.recommendations(tmdbId, seed.isSeries ? SeerrMediaType.tv : SeerrMediaType.movie, page: p),
            pages: 2,
            hidePlayed: true);
      } else {
        items = [for (final i in await s.catalog.similar(seed.id, limit: 24)) if (!i.isPlayed) i];
      }
      return [for (final i in items) if (i is! EmbyItem || i.id != seed.id) i];
    }, style: style);
  }

  _Row _likeTag(AppServices s, int index, {CardStyle style = CardStyle.poster}) {
    late final _Row row;
    return row = _Row((l) => '', () async {
      final l10n = context.l10n;
      final said = <String>{};
      final tags = [
        for (final t in await _tags(s))
          if (tagRowTitle(l10n, t) case final title? when said.add(title)) t,
      ];
      if (tags.length <= index) return const [];
      final tag = tags[index];
      row.title = (l) => tagRowTitle(l, tag) ?? tagLabel(l, tag);
      final r = s.recommender;
      final (movies, shows) = await (
        r.tagged(tag, SeerrMediaType.movie, hidePlayed: true),
        r.tagged(tag, SeerrMediaType.tv, hidePlayed: true),
      ).wait;
      final all = _interleave(movies, shows);
      return all.length < 4 ? const [] : all.take(40).toList();
    }, style: style);
  }

  _Row _starring(AppServices s, int index, {CardStyle style = CardStyle.poster}) {
    late final _Row row;
    return row = _Row((l) => '', () async {
      final actors = (await _profile(s)).actors;
      if (actors.length <= index) return const [];
      final person = actors[index].person;
      row.title = (l) => l.starring(person.name);
      return _personWork(s, person, types: const ['Movie', 'Series']);
    }, style: style);
  }

  _Row _directedBy(AppServices s, int index, {CardStyle style = CardStyle.poster}) {
    late final _Row row;
    return row = _Row((l) => '', () async {
      final directors = (await _profile(s)).directors;
      if (directors.length <= index) return const [];
      final person = directors[index].person;
      row.title = (l) => l.directedBy(person.name);
      return _personWork(s, person, types: const ['Movie'], movieCreditsOnly: true);
    }, style: style);
  }

  static Future<MixedItems> _personWork(AppServices s, Person person,
      {required List<String> types, bool movieCreditsOnly = false}) async {
    final c = s.catalog;
    final seerr = s.seerr;
    final (library, details) = await (
      c.query(personIds: person.id, types: types, filters: 'IsUnplayed', sortBy: 'CommunityRating', descending: true, limit: 40),
      seerr == null ? Future<EmbyItem?>.value() : c.item(person.id).then<EmbyItem?>((v) => v, onError: (Object _) => null),
    ).wait;
    final requestable = <SeerrMedia>[];
    final tmdbId = details?.tmdbId;
    if (seerr != null && tmdbId != null) {
      try {
        final credits = await seerr.personCredits(tmdbId, name: person.name);
        final kept = [
          for (final m in credits)
            if (RecommendationFilter.keep(m) && (m.voteCount ?? 0) >= 50 && (!movieCreditsOnly || !m.isTv)) m,
        ].take(40).toList();
        requestable.addAll((await s.recommender.resolve(kept)).whereType<SeerrMedia>());
      } catch (e) {
        debugPrint('[home] credits of ${person.name}: $e');
      }
    }
    final all = <Object>[...library.items, ...requestable.take(24)];
    return all.length < 4 ? const [] : all;
  }

  _Row _moreGenre(AppServices s, int index, {CardStyle style = CardStyle.poster}) {
    late final _Row row;
    return row = _Row((l) => '', () async {
      final genres = (await _profile(s)).genres;
      if (genres.length <= index) return const [];
      final genre = genres[index].genre;
      row.title = (l) => l.moreGenre(lowerFirst(ContentZh.genre(genre)));
      final page = await s.catalog.query(
          types: ['Movie', 'Series'], genres: [genre], filters: 'IsUnplayed', sortBy: 'Random', minCommunityRating: 6.5, limit: 30);
      return page.items;
    }, style: style);
  }

  Future<MixedItems> _forYou(AppServices s) async {
    final genres = (await _profile(s)).genres.take(3).map((g) => g.genre).toList();
    final page = await s.catalog.query(
      types: ['Movie', 'Series'],
      genres: genres.isEmpty ? null : genres,
      filters: 'IsUnplayed',
      sortBy: 'Random',
      minCommunityRating: 7,
      limit: 12,
    );
    return [for (final i in page.items) if (s.catalog.landscape(i) != null || s.catalog.backdrop(i) != null) i];
  }

  Future<MixedItems> _load(_Row row, {bool counted = false}) => _data.putIfAbsent(row, () async {
        // Capture everything that needs a BuildContext before the first await.
        final l10n = context.l10n;
        final services = AppServicesScope.read(context);
        if (!counted) _loading++;
        try {
          var items = await row.load();
          if (row.recommends) items = [for (final i in items) if (i.keptInRecommendations) i];
          _resolved[row] = items;
          _collectHero(items, l10n, services);
          return items;
        } finally {
          _loading--;
          scheduleMicrotask(() => mounted ? _pump() : null);
        }
      });

  static HeroInfo? _infoFor(Object data, L10n l10n, AppServices services) {
    if (data is EmbyItem) return HeroInfo.fromItem(l10n, services, data);
    if (data is SeerrMedia) return HeroInfo.fromRequest(l10n, data);
    return null;
  }

  /// Feed resolved rows into the carousel pool. An entry without a backdrop
  /// is skipped so an unreachable TMDB CDN can never produce a blank hero.
  void _collectHero(MixedItems items, L10n l10n, AppServices services) {
    if (_heroPool.length >= _heroPoolLimit) return;
    final keys = {for (final h in _heroPool) h.key};
    for (final data in items) {
      if (_heroPool.length >= _heroPoolLimit) break;
      final info = _infoFor(data, l10n, services);
      if (info == null || info.backdrop == null || !keys.add(info.key)) continue;
      _heroPool.add(info);
    }
    if (!_heroSet && _heroPool.isNotEmpty) {
      _heroSet = true;
      _heroIndex = 0;
      _hero.set(_heroPool.first, immediate: true);
    }
    _syncCarousel();
  }

  void _syncCarousel() {
    final want = _animationsEnabled && mounted && _heroPool.length >= 2;
    if (want == (_carousel != null)) return;
    _carousel?.cancel();
    _carousel = want ? Timer.periodic(_heroDwell, (_) => _advanceHero()) : null;
  }

  void _advanceHero() {
    if (!mounted || _heroPinned || _heroPool.length < 2) return;
    _heroIndex = (_heroIndex + 1) % _heroPool.length;
    _hero.set(_heroPool[_heroIndex]);
  }

  /// A focused card owns the hero for a while: silently rotating the backdrop
  /// while someone is reading a row with a remote is disorienting.
  void _pinHero() {
    _heroPinned = true;
    _heroUnpin?.cancel();
    _heroUnpin = Timer(_heroPinTime, () {
      if (!mounted) return;
      _heroPinned = false;
    });
  }

  void _focusHeroInfo(HeroInfo info) {
    _pinHero();
    for (var i = 0; i < _heroPool.length; i++) {
      if (_heroPool[i].key == info.key) {
        _heroIndex = i;
        break;
      }
    }
    _hero.set(info);
  }

  void _focusData(Object data, {bool immediate = false}) {
    final info = _infoFor(data, context.l10n, AppServicesScope.read(context));
    if (info == null) return;
    _pinHero();
    for (var i = 0; i < _heroPool.length; i++) {
      if (_heroPool[i].key == info.key) {
        _heroIndex = i;
        break;
      }
    }
    _hero.set(info, immediate: immediate);
  }

  Future<void> _play(EmbyItem item) => playItem(context, item);

  @override
  Widget build(BuildContext context) {
    final rows = _rows!;
    final size = MediaQuery.sizeOf(context);
    final height = size.height;
    final heroHeight = (height * 0.42).clamp(260.0, 520.0);
    // Keep the text clear of the artwork on narrow windows instead of the old
    // hard-coded right: 600, which swallowed the whole panel on small screens.
    final rightInset = (size.width * 0.42).clamp(140.0, 600.0);
    final animations = !MediaQuery.of(context).disableAnimations;
    if (animations != _animationsEnabled) {
      _animationsEnabled = animations;
      _syncCarousel();
    }

    return Stack(children: [
      const Positioned.fill(child: ColoredBox(color: Zc.background)),
      // The backdrop parallax-scrolls more slowly than the page and fades out
      // once the first rows have covered it.
      Positioned.fill(
        child: AnimatedBuilder(
          animation: _scroll,
          builder: (context, child) {
            final offset = _scroll.hasClients ? _scroll.offset.clamp(0.0, heroHeight) : 0.0;
            final t = (offset / heroHeight).clamp(0.0, 1.0);
            return Transform.translate(
              offset: Offset(0, -offset * 0.35),
              child: Opacity(opacity: 1 - t * 0.92, child: child),
            );
          },
          child: RepaintBoundary(
            child: ValueListenableBuilder<HeroInfo?>(
              valueListenable: _hero,
              builder: (_, info, _) => Backdrop(url: info?.backdrop),
            ),
          ),
        ),
      ),
      // Hero and rows share ONE scroll view, so scrolling really does move the
      // hero off screen. Previously only the lower half of the window scrolled
      // while the hero stayed pinned on top.
      Positioned.fill(
        child: CardTrailers(
          child: SingleChildScrollView(
            controller: _scroll,
            child: ValueListenableBuilder<bool>(
              valueListenable: InputMode.pointer,
              builder: (context, pointer, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedBuilder(
                    animation: _scroll,
                    builder: (context, child) {
                      final offset = _scroll.hasClients ? _scroll.offset.clamp(0.0, heroHeight) : 0.0;
                      final t = (offset / heroHeight).clamp(0.0, 1.0);
                      return Opacity(opacity: 1 - t, child: child);
                    },
                    child: SizedBox(
                      height: heroHeight,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: EdgeInsets.only(left: contentLeft, right: rightInset, bottom: 28),
                          child: ValueListenableBuilder<HeroInfo?>(
                            valueListenable: _hero,
                            builder: (_, info, _) => info == null ? const _HeroSkeleton() : HeroPanel(info: info),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 24, bottom: pointer ? 60 : height * 0.5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final (i, row) in rows.indexed) _buildRow(row, first: i == 0)],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (_showLoader && AppServicesScope.of(context).isSignedIn)
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _loaded,
            child: AnimatedOpacity(
              opacity: _loaded ? 0 : 1,
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOut,
              onEnd: () {
                if (_loaded && mounted) setState(() => _showLoader = false);
              },
              child: const CinemaLoader(),
            ),
          ),
        ),
    ]);
  }

  Widget _buildRow(_Row row, {required bool first}) {
    if (row.kind == _Kind.moods) {
      if (!_allowed.contains(row)) return const SizedBox.shrink();
      return MoodShelf(
        favoriteGenres: _profile(AppServicesScope.read(context)).then((t) => [for (final g in t.genres) g.genre]),
        onFocusHero: _focusHeroInfo,
      );
    }
    return FutureBuilder<MixedItems>(
      future: _allowed.contains(row) ? _load(row) : null,
      initialData: _resolved[row],
      builder: (context, snap) {
        final (cardW, areaH) = switch (row.kind) {
          _Kind.collections => (560.0, 560 * 0.42 + 44),
          _Kind.continueWatching => (Zs.landscapeWidth, cardAreaHeight(CardStyle.landscape)),
          _ => (cardWidth(row.style), cardAreaHeight(row.style)),
        };
        if (snap.data == null && !snap.hasError) {
          return Padding(
            padding: const EdgeInsets.only(bottom: Zs.rowGap),
            child: SkeletonRow(cardWidth: cardW, cardHeight: areaH - 100),
          );
        }
        final items = snap.data ?? const [];
        if (snap.hasError) debugPrint('[home] ${row.title(context.l10n)}: ${snap.error}');
        if (items.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: Zs.rowGap),
          child: MediaRow(
            title: row.title(context.l10n),
            height: areaH,
            gap: switch ((row.kind, row.style)) {
              (_Kind.collections, _) => 28,
              (_, CardStyle.ranked) => 8,
              (_, CardStyle.spotlight) => 30,
              _ => Zs.cardGap,
            },
            itemCount: items.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _card(row, items[i], rank: i + 1, autofocus: first && i == 0),
            ),
          ),
        );
      },
    );
  }

  Widget _card(_Row row, Object data, {required int rank, required bool autofocus}) {
    if (data is LibraryView) {
      // Use the server's own library cover as a poster tile; tapping it
      // selects that view in the library page (same path as the rail).
      return PosterCard(
        item: EmbyItem(id: data.id, name: data.name, type: 'CollectionFolder', primaryImageTag: data.imageTag),
        width: cardWidth(CardStyle.poster),
        autofocus: autofocus,
        onFocus: () => _focusData(data),
        onSelect: () => widget.onOpenLibraryView?.call(data),
      );
    }
    if (row.kind == _Kind.collections && data is EmbyItem) {
      return CollectionCard(item: data, autofocus: autofocus, onFocus: () => _focusData(data), onSelect: () => openItem(context, data));
    }
    if (row.kind == _Kind.continueWatching && data is EmbyItem) {
      final item = data;
      final remaining = item.resumePosition == null || item.runtime == null
          ? null
          : formatRuntime(context.l10n, item.runtime! - item.resumePosition!);
      return LandscapeCard(
        item: item,
        autofocus: autofocus,
        title: item.isEpisode ? item.seriesName ?? item.name : item.name,
        subtitle: item.isEpisode
            ? [item.episodeCode, item.name].whereType<String>().join('  ')
            : remaining != null
                ? context.l10n.timeLeft(remaining)
                : item.productionYear?.toString(),
        preferEpisodeStill: false,
        onFocus: () => _focusData(item),
        onSelect: () => openItem(context, item),
        onMenu: () => _play(item),
        onPlay: () => _play(item),
      );
    }
    if (row.style == CardStyle.landscape && data is EmbyItem && data.isEpisode) {
      return LandscapeCard(
        item: data,
        autofocus: autofocus,
        title: data.seriesName ?? data.name,
        subtitle: [data.episodeCode, data.name].whereType<String>().join('  '),
        onFocus: () => _focusData(data),
        onSelect: () => openItem(context, data),
        onPlay: () => _play(data),
      );
    }
    return mixedCard(context, data, style: row.style, rank: rank, autofocus: autofocus, onFocus: () => _focusData(data));
  }
}

/// Shown until the first row resolves a usable backdrop, so the top of the
/// page never reads as an empty black rectangle while the library loads.
class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      bar(340, 46),
      const SizedBox(height: 18),
      bar(240, 16),
      const SizedBox(height: 12),
      bar(420, 14),
      const SizedBox(height: 10),
      bar(360, 14),
    ]);
  }
}
