import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../app/app_services.dart';
import '../../app/app_settings.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/catalog_api.dart' show CatalogApi;
import '../../data/catalog_api.dart' as catalog show LibraryView;
import '../../data/collection_index.dart';
import '../../l10n/l10n.dart';
import '../core/artwork.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import '../widgets/net_image.dart';
import '../widgets/side_panel.dart';
import 'details_parts.dart';
import 'routes.dart';

enum LibraryKind { movies, shows, favorites }

enum _Sort {
  name('SortName', false),
  added('DateCreated,SortName', true),
  released('PremiereDate,SortName', true),
  rating('CommunityRating,SortName', true),
  played('DatePlayed,SortName', true),
  random('Random', false);

  const _Sort(this.field, this.descending);

  final String field;
  final bool descending;

  String label(L10n l10n) => switch (this) {
        name => l10n.sortAToZ,
        added => l10n.sortRecentlyAdded,
        released => l10n.sortReleaseDate,
        rating => l10n.sortRating,
        played => l10n.sortRecentlyWatched,
        random => l10n.sortRandom,
      };
}

enum _Watched { all, unwatched, watched, favorites }

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.kind, this.view, this.onViewChanged});

  final LibraryKind kind;

  /// Server library picked from the navigation rail, null means "all media".
  final catalog.LibraryView? view;

  /// Keeps the rail highlight in sync when the in-page chips change library.
  final ValueChanged<catalog.LibraryView?>? onViewChanged;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  static const _pageSize = 120;

  _Sort _sort = _Sort.added;
  late _Watched _watched = widget.kind == LibraryKind.favorites ? _Watched.favorites : _Watched.all;
  String? _genre;
  List<String> _genres = const [];

  /// Real libraries reported by the Emby/Jellyfin server, not the app's
  /// hard-coded "Movies / Shows / Favorites" taxonomy.
  List<catalog.LibraryView> _views = const [];
  String? _viewId;

  catalog.LibraryView? get _view {
    if (_viewId == null) return null;
    for (final v in _views) {
      if (v.id == _viewId) return v;
    }
    return null;
  }

  final _items = <EmbyItem>[];
  int _total = -1;
  bool _loading = false;
  int _generation = 0;
  final _grid = RevealController(margin: 120);

  List<String> get _types {
    // A server library has its own content type. Browsing a "TV Shows"
    // library must show series even when the Movies tab is selected.
    final type = _view?.collectionType;
    if (type == 'movies' || type == 'boxsets') return const ['Movie'];
    if (type == 'tvshows') return const ['Series'];
    return switch (widget.kind) {
      LibraryKind.movies => const ['Movie'],
      LibraryKind.shows => const ['Series'],
      LibraryKind.favorites => const ['Movie', 'Series'],
    };
  }

  @override
  void initState() {
    super.initState();
    if (widget.view != null) {
      _views = [widget.view!];
      _viewId = widget.view!.id;
    }
    _reload();
    _loadGenres();
    _loadViews();
  }

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compare against the live selection, not the previous widget: changing the
    // view through the in-page chips already reloaded, so a shell rebuild must
    // not trigger a second identical query.
    if (widget.view?.id != _viewId) {
      _viewId = widget.view?.id;
      _genre = null;
      _loadGenres();
      _reload();
    }
  }

  void _loadGenres() {
    AppServicesScope.read(context)
        .catalog
        .genres(types: _types, parentId: _viewId)
        .then((g) {
      if (mounted) setState(() => _genres = g);
    }).catchError((_) {});
  }

  Future<void> _loadViews() async {
    try {
      final views = await AppServicesScope.read(context).catalog.views();
      if (!mounted) return;
      final list = [for (final v in views) if (v.name.isNotEmpty) v];
      final chosen = widget.view;
      if (chosen != null && !list.any((v) => v.id == chosen.id)) list.insert(0, chosen);
      setState(() => _views = list);
    } catch (e) {
      debugPrint('[library] views: $e');
    }
  }

  void _selectView(String? id) {
    if (id == _viewId) return;
    _viewId = id;
    _genre = null;
    widget.onViewChanged?.call(_view);
    _loadGenres();
    _reload();
  }

  @override
  void dispose() {
    _grid.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _items.clear();
      _total = -1;
      _generation++;
    });
    if (_grid.hasClients) _grid.jumpTo(0);
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || (_total >= 0 && _items.length >= _total)) return;
    _loading = true;
    final generation = _generation;
    final settings = AppServicesScope.read(context).settings;
    if (_grouped(settings)) return _loadGrouped(generation);
    try {
      final page = await AppServicesScope.read(context).catalog.query(
            parentId: _viewId,
            collapseBoxSets: _grouped(settings),
            types: _types,
            sortBy: _sort.field,
            descending: _sort.descending,
            start: _items.length,
            limit: _pageSize,
            genres: _genre == null ? null : [_genre!],
            filters: switch (_watched) {
              _Watched.all => null,
              _Watched.unwatched => 'IsUnplayed',
              _Watched.watched => 'IsPlayed',
              _Watched.favorites => 'IsFavorite',
            },
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.total;
      });
    } catch (e) {
      debugPrint('[library] $e');
    } finally {
      _loading = false;
    }
  }

  Future<void> _pick<T>(String title, Map<T, String> options, T current, ValueChanged<T> apply) async {
    final chosen = await showSidePanel<T>(context, title: title, options: [
      for (final e in options.entries) PanelOption(value: e.key, title: e.value, selected: e.key == current),
    ]);
    if (chosen != null && chosen != current) {
      apply(chosen);
      _reload();
    }
  }

  Future<void> _loadGrouped(int generation) async {
    try {
      final page = await AppServicesScope.read(context).catalog.query(
            parentId: _viewId,
            types: _types,
            sortBy: 'SortName',
            limit: 5000,
            collapseBoxSets: true,
            fields: '${CatalogApi.cardFields},DateCreated',
          );
      if (!mounted || generation != _generation) return;
      final items = await _withTmdbCollections(page.items);
      if (!mounted || generation != _generation) return;
      int newest(DateTime? a, DateTime? b) => (b ?? DateTime(1900)).compareTo(a ?? DateTime(1900));
      switch (_sort) {
        case _Sort.name:
          break;
        case _Sort.added:
          items.sort((a, b) => newest(a.dateCreated, b.dateCreated));
        case _Sort.released:
          items.sort((a, b) => newest(a.premiereDate, b.premiereDate));
        case _Sort.rating:
          items.sort((a, b) => (b.communityRating ?? 0).compareTo(a.communityRating ?? 0));
        case _Sort.played:
          items.sort((a, b) => newest(a.lastPlayedDate, b.lastPlayedDate));
        case _Sort.random:
          items.shuffle();
      }
      setState(() {
        _items.addAll(items);
        _total = items.length;
      });
    } catch (e) {
      debugPrint('[library] grouped: $e');
    } finally {
      _loading = false;
    }
  }

  Future<List<EmbyItem>> _withTmdbCollections(List<EmbyItem> grouped) async {
    final index = AppServicesScope.read(context).catalog.collections;
    if (index == null) return [...grouped];
    final List<LibraryCollection> tmdb;
    try {
      tmdb = await index.all();
    } catch (e) {
      debugPrint('[library] tmdb collections: $e');
      return [...grouped];
    }
    final loose = {for (final i in grouped) if (i.isMovie) i.id: i};
    final serverSets = {for (final i in grouped) if (i.isCollection) ?i.tmdbId};
    final hidden = <String>{};
    final added = <EmbyItem>[];
    for (final c in tmdb) {
      final members = [for (final id in c.ownedIds) ?loose[id]];
      if (members.isEmpty) continue;
      if (serverSets.contains(c.info.id)) {
        hidden.addAll(members.map((m) => m.id));
        continue;
      }
      if (members.length < 2) continue;
      hidden.addAll(members.map((m) => m.id));
      DateTime? latest(Iterable<DateTime?> dates) =>
          dates.nonNulls.fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      added.add(CollectionIndex.itemFor(
        c.info,
        owned: members.length,
        added: latest(members.map((m) => m.dateCreated)),
        released: latest(members.map((m) => m.premiereDate)),
      ));
    }
    debugPrint('[library] grouped: ${grouped.length} from the server, ${added.length} TMDB collections '
        'replace ${hidden.length} films');
    return [for (final i in grouped) if (!hidden.contains(i.id)) i, ...added]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  bool _grouped(AppSettings settings) =>
      widget.kind == LibraryKind.movies && settings.groupCollections && _types.contains('Movie') &&
      _genre == null && _watched == _Watched.all;

  Future<void> _toggleGrouping(AppServices services) async {
    await services.updateSettings(services.settings.copyWith(groupCollections: !services.settings.groupCollections));
    if (mounted) _reload();
  }

  Future<void> _pickView(AppServices services) async {
    final l10n = context.l10n;
    final current = services.settings.libraryView;
    final chosen = await showSidePanel<LibraryView>(context, title: l10n.libraryViewSetting, options: [
      for (final v in LibraryView.values) PanelOption(value: v, title: _viewLabel(l10n, v), icon: _viewIcon(v), selected: v == current),
    ]);
    if (chosen != null && chosen != current) await services.updateSettings(services.settings.copyWith(libraryView: chosen));
  }

  static String _viewLabel(L10n l10n, LibraryView v) => switch (v) {
        LibraryView.posters => l10n.viewPosters,
        LibraryView.cards => l10n.viewCards,
        LibraryView.list => l10n.viewList,
      };

  static IconData _viewIcon(LibraryView v) => switch (v) {
        LibraryView.posters => Icons.grid_view_rounded,
        LibraryView.cards => Icons.view_module_rounded,
        LibraryView.list => Icons.view_list_rounded,
      };

  Widget _tile(BuildContext context, LibraryView view, int i, double cardW) {
    if (i >= _items.length) {
      return switch (view) {
        LibraryView.posters => SkeletonBox(width: cardW, height: cardW * 1.5),
        LibraryView.cards => SkeletonBox(width: cardW, height: cardW * 9 / 16),
        LibraryView.list => SkeletonBox(width: cardW, height: _ListRow.height - 24),
      };
    }
    if (i > _items.length - 40) _loadMore();
    final item = _items[i];
    void open() => openItem(context, item);
    return switch (view) {
      LibraryView.posters => Align(
          alignment: Alignment.topLeft,
          child: LayoutBuilder(
            builder: (context, box) => PosterCard(item: item, width: box.maxWidth, autofocus: i == 0, onSelect: open),
          ),
        ),
      LibraryView.cards => Align(
          alignment: Alignment.topLeft,
          child: LayoutBuilder(
            builder: (context, box) => LandscapeCard(
              item: item,
              width: box.maxWidth,
              autofocus: i == 0,
              preferEpisodeStill: false,
              subtitle: [?item.productionYear?.toString(), ?item.officialRating].join('  ·  '),
              onSelect: open,
            ),
          ),
        ),
      LibraryView.list => _ListRow(item: item, autofocus: i == 0, onSelect: open),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selectedView = _view;
    final String title;
    if (selectedView != null) {
      title = selectedView.name;
    } else {
      title = switch (widget.kind) {
        LibraryKind.movies => l10n.movies,
        LibraryKind.shows => l10n.shows,
        LibraryKind.favorites => l10n.favorites,
      };
    }
    final services = AppServicesScope.of(context);
    final view = services.settings.libraryView;
    final columns = switch (view) {
      LibraryView.posters => services.settings.posterSize.columns,
      LibraryView.cards => (services.settings.posterSize.columns / 2).ceil(),
      LibraryView.list => 1,
    };
    // The toolbar, the server-library chips and the poster grid share ONE
    // scroll view. The old layout pinned the header above an Expanded GridView
    // with Clip.none, so posters painted over the header while scrolling and
    // the whole header strip stopped receiving pointer hits.
    return LayoutBuilder(builder: (context, box) {
      final cardW = view == LibraryView.list
          ? box.maxWidth - contentLeft - 120
          : posterGridCardWidth(box.maxWidth, columns);
      return FocusZone(
        debugLabel: 'library-scroll',
        child: CustomScrollView(
          controller: _grid,
          clipBehavior: Clip.hardEdge,
          scrollCacheExtent: const ScrollCacheExtent.pixels(900),
          slivers: [
            SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(left: contentLeft, top: 70, right: 120, bottom: 26),
                  child: Row(children: [
                    Text(title, style: Zt.headline),
                    const SizedBox(width: 18),
                    if (_total >= 0) Text('$_total', style: Zt.title.copyWith(color: Zc.textFaint)),
                    const Spacer(),
                    FocusZone(
                      debugLabel: 'library-toolbar',
                      child: Row(children: [
                        TvButton(
                          label: _sort.label(l10n),
                          icon: Icons.sort_rounded,
                          onSelect: () => _pick(l10n.sortBy, {for (final s in _Sort.values) s: s.label(l10n)}, _sort, (v) => _sort = v),
                        ),
                        const SizedBox(width: 14),
                        TvButton(
                          label: _genre ?? l10n.allGenres,
                          icon: Icons.category_outlined,
                          onSelect: () => _pick<String>(l10n.genre, {'': l10n.allGenres, for (final g in _genres) g: g}, _genre ?? '',
                              (v) => _genre = v.isEmpty ? null : v),
                        ),
                        if (widget.kind != LibraryKind.favorites) ...[
                          const SizedBox(width: 14),
                          TvButton(
                            label: switch (_watched) {
                              _Watched.all => l10n.filterAll,
                              _Watched.unwatched => l10n.unwatched,
                              _Watched.watched => l10n.watched,
                              _Watched.favorites => l10n.favorites,
                            },
                            icon: Icons.filter_list_rounded,
                            onSelect: () => _pick(l10n.filterShow, {
                              _Watched.all: l10n.filterEverything,
                              _Watched.unwatched: l10n.unwatched,
                              _Watched.watched: l10n.watched,
                              _Watched.favorites: l10n.favorites,
                            }, _watched, (v) => _watched = v),
                          ),
                        ],
                        if (widget.kind == LibraryKind.movies) ...[
                          const SizedBox(width: 14),
                          TvButton(
                            label: l10n.groupCollections,
                            icon: services.settings.groupCollections ? Icons.collections_bookmark_rounded : Icons.collections_bookmark_outlined,
                            collapsed: true,
                            primary: services.settings.groupCollections,
                            onSelect: () => _toggleGrouping(services),
                          ),
                        ],
                        const SizedBox(width: 14),
                        TvButton(
                          label: _viewLabel(l10n, view),
                          icon: _viewIcon(view),
                          collapsed: true,
                          onSelect: () => _pickView(services),
                        ),
                      ]),
                    ),
                  ]),
                ),
                if (_views.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: contentLeft, right: 120, bottom: 18),
                    child: FocusZone(
                      debugLabel: 'library-views',
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          TvButton(label: l10n.filterAll, primary: _viewId == null, onSelect: () => _selectView(null)),
                          for (final v in _views) ...[
                            const SizedBox(width: 12),
                            TvButton(label: v.name, primary: _viewId == v.id, onSelect: () => _selectView(v.id)),
                          ],
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
            if (_total == 0)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.only(left: contentLeft, top: 40),
                  child: Text(l10n.nothingWithFilters, style: Zt.body),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(contentLeft, 16, 120, 140),
                sliver: SliverGrid(
                  key: ValueKey('$_generation:${view.name}'),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 26,
                    crossAxisSpacing: Zs.cardGap,
                    childAspectRatio: switch (view) {
                      LibraryView.posters => cardW / (cardW * 1.5 + 70),
                      LibraryView.cards => cardW / (cardW * 9 / 16 + 76),
                      LibraryView.list => cardW / _ListRow.height,
                    },
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _tile(context, view, i, cardW),
                    childCount: _total < 0 ? 14 : _items.length,
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.item, required this.onSelect, this.autofocus = false});

  static const double height = 200;

  final EmbyItem item;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final catalog = AppServicesScope.read(context).catalog;
    final meta = standardMeta(context.l10n, item).whereType<String>().where((s) => s.isNotEmpty).join('  ·  ');
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (context, focused) => AnimatedContainer(
        duration: Zm.fast,
        height: height - 24,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: focused ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(Zs.radius),
          border: Border.all(color: focused ? Colors.white : Colors.transparent, width: 3),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Zs.radius - 4),
            child: SizedBox(
              width: (height - 54) / 1.5,
              height: height - 54,
              child: NetImage(url: catalog.poster(item, width: 160), width: 160, fallback: TitleArt(title: item.name)),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.title.copyWith(fontSize: 26)),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.meta),
              ],
              if (item.overview != null) ...[
                const SizedBox(height: 10),
                Text(item.overview!, maxLines: 2, overflow: TextOverflow.ellipsis, style: Zt.body.copyWith(fontSize: 20)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
