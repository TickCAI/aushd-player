import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/emby/models/emby_item.dart';
import '../../../data/catalog_api.dart';
import '../../../l10n/l10n.dart';
import '../../core/artwork.dart';
import '../../core/playback_launcher.dart';
import '../../pages/routes.dart';
import '../device_form.dart';
import '../tokens.dart';
import '../widgets/z_media.dart';
import '../z_components.dart';
import '../z_routes.dart';
import 'z_library_page.dart';

/// 新首页（M2）：Hero 海报轮播 + 继续观看 + 最近添加（电影 / 剧集）+ 媒体库入口。
///
/// 数据全部走 `CatalogApi`（Emby/Jellyfin 原生接口），不做二次索引：
/// `views()` 拿服务端媒体库，`latest()` 拿最近入库，`continueWatching()`
/// 合并 Resume 与 NextUp。
class ZHomePage extends StatefulWidget {
  const ZHomePage({super.key});

  @override
  State<ZHomePage> createState() => _ZHomePageState();
}

class _ZHomePageState extends State<ZHomePage> {
  AppServices? _services;
  Future<_HomeData>? _future;

  static const _rowPosterWidth = 150.0;
  static const _rowCardWidth = 252.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppServicesScope.maybeRead(context);
    if (identical(services, _services)) return;
    _services?.libraryChanged.removeListener(_reload);
    _services = services;
    _services?.libraryChanged.addListener(_reload);
    _future = _load();
  }

  @override
  void dispose() {
    _services?.libraryChanged.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  Future<_HomeData> _load() async {
    final services = _services;
    if (services == null || !services.isSignedIn) return _HomeData.empty;
    final catalog = services.catalog;
    final views = await catalog.views().catchError((Object _) => const <LibraryView>[]);
    final (resume, movies, shows) = await (
      catalog.continueWatching(limit: 12).catchError((Object _) => const <EmbyItem>[]),
      catalog.latest(types: const ['Movie'], limit: 18).catchError((Object _) => const <EmbyItem>[]),
      catalog.latest(types: const ['Series'], limit: 18).catchError((Object _) => const <EmbyItem>[]),
    ).wait;
    return _HomeData(
      resume: resume,
      movies: movies,
      shows: shows,
      views: views,
      hero: _heroPool(resume, movies, shows),
    );
  }

  /// Hero 候选：先放最近入库的电影 / 剧集（有 backdrop 的优先），再补继续观看。
  static List<EmbyItem> _heroPool(List<EmbyItem> resume, List<EmbyItem> movies, List<EmbyItem> shows) {
    final pool = <EmbyItem>[];
    final seen = <String>{};
    void add(Iterable<EmbyItem> source) {
      for (final i in source) {
        if (pool.length >= 6) return;
        if (!seen.add(i.id)) continue;
        pool.add(i);
      }
    }

    add([...movies, ...shows].where((i) => i.backdropImageTags.isNotEmpty || i.localizedBackdropPath != null));
    add([...movies, ...shows]);
    add(resume);
    return pool;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Zc.bgBase,
      child: _body(),
    );
  }

  Widget _body() {
    final services = _services;
    if (services == null || !services.isSignedIn) {
      return const ZEmptyState(
        icon: Icons.cloud_off_rounded,
        title: '还没有连接服务器',
        hint: '在"更多 → 经典界面"里登录 Emby / Jellyfin 后即可浏览媒体库。',
      );
    }
    return FutureBuilder<_HomeData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ZLoading(label: '正在加载媒体库…');
        }
        final data = snapshot.data;
        if (data == null || data.isEmpty) {
          return ZEmptyState(
            icon: Icons.movie_filter_outlined,
            title: '媒体库里还没有内容',
            hint: snapshot.hasError ? '读取服务器数据失败，可稍后重试。' : '先在 Emby 里添加影片或剧集，然后回到这里刷新。',
            action: ZGhostButton(label: '重新加载', icon: Icons.refresh_rounded, onPressed: _reload),
          );
        }
        return RefreshIndicator(
          color: Zc.brandPrimary,
          onRefresh: () async {
            final next = _load();
            setState(() => _future = next);
            await next;
          },
          child: _content(data, services),
        );
      },
    );
  }

  Widget _content(_HomeData data, AppServices services) {
    final catalog = services.catalog;
    final bottomPad = DeviceFormX.of(context).usesDock ? 104.0 : 36.0;
    return ListView(
      padding: EdgeInsets.only(top: 20, bottom: bottomPad),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      children: [
        _header(services),
        const SizedBox(height: 16),
        if (data.hero.isNotEmpty) ZHeroCarousel(items: [for (final i in data.hero) _hero(i, catalog)]),
        const SizedBox(height: 26),
        ZMediaRow(
          title: context.l10n.continueWatching,
          height: _rowCardWidth * 9 / 16 + 30,
          children: [
            for (final i in data.resume)
              ZLandscapeTile(
                image: catalog.landscape(i, width: _rowCardWidth),
                title: _resumeTitle(i),
                subtitle: _remaining(i) ?? _meta(i),
                progress: i.progress,
                width: _rowCardWidth,
                onTap: () => _open(i),
              ),
          ],
        ),
        if (data.resume.isNotEmpty) const SizedBox(height: 26),
        ZMediaRow(
          title: context.l10n.latestMovies,
          height: _rowPosterWidth * 1.5 + 44,
          children: _posters(data.movies, catalog),
          onMore: data.views.isEmpty ? null : () => _openLibrary(null),
        ),
        if (data.movies.isNotEmpty) const SizedBox(height: 26),
        ZMediaRow(
          title: context.l10n.latestShows,
          height: _rowPosterWidth * 1.5 + 44,
          children: _posters(data.shows, catalog),
          onMore: data.views.isEmpty ? null : () => _openLibrary(null),
        ),
        if (data.shows.isNotEmpty) const SizedBox(height: 30),
        if (data.views.isNotEmpty) _librarySection(data.views, services),
      ],
    );
  }

  Widget _header(AppServices services) {
    final host = services.janus.session.serverUrl.host;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 16, 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: Zbrand.gradient,
              borderRadius: BorderRadius.circular(Zr.card),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.home, style: Zt.display.copyWith(color: Zc.textPrimary)),
                Text(
                  host.isEmpty ? 'AusHD Player' : host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Zt.caption.copyWith(color: Zc.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded, color: Zc.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _librarySection(List<LibraryView> views, AppServices services) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Text(context.l10n.navLibrary, style: Zt.title.copyWith(color: Zc.textPrimary)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final v in views)
                _LibraryChip(
                  name: v.name,
                  icon: _libraryIcon(v.collectionType),
                  onTap: () => _openLibrary(v.id),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static IconData _libraryIcon(String? collectionType) => switch (collectionType) {
        'movies' => Icons.movie_outlined,
        'tvshows' => Icons.live_tv_outlined,
        'music' => Icons.music_note_outlined,
        'books' => Icons.menu_book_outlined,
        'boxsets' => Icons.collections_bookmark_outlined,
        _ => Icons.folder_outlined,
      };

  List<Widget> _posters(List<EmbyItem> items, CatalogApi catalog) => [
        for (final i in items)
          ZPosterTile(
            image: catalog.poster(i, width: _rowPosterWidth),
            title: i.isEpisode ? (i.seriesName ?? i.name) : i.name,
            subtitle: _meta(i),
            progress: i.progress,
            width: _rowPosterWidth,
            onTap: () => _open(i),
          ),
      ];

  ZHeroItem _hero(EmbyItem item, CatalogApi catalog) => ZHeroItem(
        backdrop: catalog.backdrop(item, width: 1920),
        logo: catalog.logo(item),
        title: item.isEpisode ? (item.seriesName ?? item.name) : item.name,
        meta: _heroMeta(item),
        overview: item.overview,
        onPlay: () => unawaited(playItem(context, item)),
        onOpen: () => _open(item),
      );

  void _open(EmbyItem item) => openItem(context, item);

  void _openLibrary(String? viewId) {
    Navigator.of(context).push(zRoute(ZLibraryPage(initialViewId: viewId), name: 'z-library:$viewId'));
  }

  static String _resumeTitle(EmbyItem i) {
    if (!i.isEpisode) return i.name;
    final series = i.seriesName ?? i.name;
    final code = i.episodeCode;
    return code == null ? series : '$series · $code';
  }

  static String _meta(EmbyItem i) {
    final parts = <String>[
      if (i.productionYear != null) '${i.productionYear}',
      if (i.isEpisode && i.episodeCode != null) i.episodeCode!,
      if (i.communityRating != null && i.communityRating! > 0) i.communityRating!.toStringAsFixed(1),
      if (i.genres.isNotEmpty) i.genres.first,
    ];
    return parts.join(' · ');
  }

  static String _heroMeta(EmbyItem i) {
    final parts = <String>[
      if (i.isSeries) '剧集' else if (i.isMovie) '电影',
      if (i.productionYear != null) '${i.productionYear}',
      if (i.genres.isNotEmpty) i.genres.take(2).join(' / '),
      if (i.communityRating != null && i.communityRating! > 0) '★ ${i.communityRating!.toStringAsFixed(1)}',
      if (i.runtime != null) '${i.runtime!.inMinutes} 分钟',
      if (i.officialRating != null) i.officialRating!,
    ];
    return parts.join('  ·  ');
  }

  static String? _remaining(EmbyItem i) {
    final rt = i.runtime;
    final pos = i.resumePosition;
    if (rt == null || pos == null) return null;
    final left = rt - pos;
    if (left.inMinutes < 1) return null;
    return '剩余 ${left.inMinutes} 分钟';
  }
}

final class _HomeData {
  const _HomeData({
    required this.resume,
    required this.movies,
    required this.shows,
    required this.views,
    required this.hero,
  });

  final List<EmbyItem> resume;
  final List<EmbyItem> movies;
  final List<EmbyItem> shows;
  final List<LibraryView> views;
  final List<EmbyItem> hero;

  static const empty = _HomeData(
    resume: <EmbyItem>[],
    movies: <EmbyItem>[],
    shows: <EmbyItem>[],
    views: <LibraryView>[],
    hero: <EmbyItem>[],
  );

  bool get isEmpty => resume.isEmpty && movies.isEmpty && shows.isEmpty && views.isEmpty && hero.isEmpty;
}

class _LibraryChip extends StatelessWidget {
  const _LibraryChip({required this.name, required this.icon, required this.onTap});

  final String name;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Zc.surface,
          borderRadius: BorderRadius.circular(Zr.card),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Zc.brandPrimary),
            const SizedBox(width: 8),
            Text(name, style: Zt.caption.copyWith(color: Zc.textPrimary)),
          ],
        ),
      ),
    );
  }
}
