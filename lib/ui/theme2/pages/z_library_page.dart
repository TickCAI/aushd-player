import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/emby/models/emby_item.dart';
import '../../../data/catalog_api.dart';
import '../../../l10n/l10n.dart';
import '../../core/artwork.dart';
import '../../pages/routes.dart';
import '../device_form.dart';
import '../tokens.dart';
import '../widgets/z_media.dart';
import '../z_components.dart';

/// 新媒体库页（M2）：直接读服务端 `/Users/{id}/Views` 的库列表，
/// 选中某个库后按 `ParentId` 分页拉取条目，支持排序与增量加载。
class ZLibraryPage extends StatefulWidget {
  const ZLibraryPage({super.key, this.initialViewId});

  /// 从首页的库入口进来时带上具体的库 id；为空则默认选第一个。
  final String? initialViewId;

  @override
  State<ZLibraryPage> createState() => _ZLibraryPageState();
}

enum _Sort {
  recent('最近添加', 'DateCreated', true),
  name('名称', 'SortName', false),
  rating('评分', 'CommunityRating', true),
  year('年份', 'ProductionYear', true);

  const _Sort(this.label, this.sortBy, this.descending);

  final String label;
  final String sortBy;
  final bool descending;
}

class _ZLibraryPageState extends State<ZLibraryPage> {
  static const _pageSize = 120;

  AppServices? _services;
  final _scroll = ScrollController();

  List<LibraryView> _views = const [];
  String? _viewId;
  final _items = <EmbyItem>[];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;
  _Sort _sort = _Sort.recent;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppServicesScope.maybeRead(context);
    if (identical(services, _services)) return;
    _services?.libraryChanged.removeListener(_reload);
    _services = services;
    _services?.libraryChanged.addListener(_reload);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _services?.libraryChanged.removeListener(_reload);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || _loading) return;
    if (_total != 0 && _items.length >= _total) return;
    final remaining = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 600) unawaited(_loadMore());
  }

  Future<void> _reload() async {
    final services = _services;
    if (services == null || !services.isSignedIn) {
      if (mounted) {
        setState(() {
          _loading = false;
          _views = const [];
          _items.clear();
          _total = 0;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final views = await services.catalog.views();
      final wanted = widget.initialViewId;
      final matched = wanted != null && views.any((v) => v.id == wanted) ? wanted : null;
      final selected = _viewId ?? matched ?? (views.isEmpty ? null : views.first.id);
      if (!mounted) return;
      setState(() {
        _views = views;
        _viewId = selected;
        _items.clear();
        _total = 0;
        _loading = selected != null;
      });
      if (selected != null) await _loadMore(reset: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadMore({bool reset = false}) async {
    final services = _services;
    final viewId = _viewId;
    if (services == null || viewId == null || _loadingMore) return;
    if (!reset && _total != 0 && _items.length >= _total) return;
    setState(() {
      _loadingMore = true;
      if (reset) _loading = true;
    });
    try {
      final page = await services.catalog.query(
        parentId: viewId,
        sortBy: _sort.sortBy,
        descending: _sort.descending,
        start: reset ? 0 : _items.length,
        limit: _pageSize,
        fields: CatalogApi.cardFields,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _total = page.total;
        _loading = false;
        _loadingMore = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _failed = _items.isEmpty;
      });
    }
  }

  void _selectView(String id) {
    if (id == _viewId) return;
    setState(() {
      _viewId = id;
      _items.clear();
      _total = 0;
      _loading = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_loadMore(reset: true));
  }

  void _selectSort(_Sort sort) {
    if (sort == _sort) return;
    setState(() {
      _sort = sort;
      _items.clear();
      _total = 0;
      _loading = true;
    });
    unawaited(_loadMore(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    if (services == null || !services.isSignedIn) {
      return const ColoredBox(
        color: Zc.bgBase,
        child: ZEmptyState(
          icon: Icons.cloud_off_rounded,
          title: '还没有连接服务器',
          hint: '在"更多 → 经典界面"里登录 Emby / Jellyfin 后即可浏览媒体库。',
        ),
      );
    }
    final catalog = services.catalog;
    final bottomPad = DeviceFormX.of(context).usesDock ? 104.0 : 32.0;
    return ColoredBox(
      color: Zc.bgBase,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(child: _header()),
          SliverToBoxAdapter(child: _viewChips()),
          SliverToBoxAdapter(child: _sortBar()),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: ZLoading(label: '正在读取媒体库…'),
            )
          else if (_items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ZEmptyState(
                icon: Icons.movie_filter_outlined,
                title: _failed ? '读取失败' : '这个库里还没有内容',
                hint: _failed ? '检查网络或服务器状态后重试。' : '在 Emby 里添加影片后回到这里刷新。',
                action: ZGhostButton(
                  label: '重试',
                  icon: Icons.refresh_rounded,
                  onPressed: () => unawaited(_loadMore(reset: true)),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(24, 4, 24, bottomPad),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 196,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 18,
                  childAspectRatio: 0.52,
                ),
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final item = _items[i];
                  return ZPosterTile(
                    image: catalog.poster(item, width: 200),
                    title: item.name,
                    subtitle: _subtitle(item),
                    progress: item.progress,
                    onTap: () => openItem(context, item),
                  );
                },
              ),
            ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 28, top: 4),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Zc.brandPrimary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header() {
    final count = _total == 0 ? _items.length : _total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.navLibrary, style: Zt.display.copyWith(color: Zc.textPrimary)),
                Text('共 $count 项', style: Zt.caption.copyWith(color: Zc.textSecondary)),
              ],
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: () => unawaited(_reload()),
            icon: const Icon(Icons.refresh_rounded, color: Zc.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _viewChips() {
    if (_views.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        itemCount: _views.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final v = _views[i];
          final selected = v.id == _viewId;
          return GestureDetector(
            onTap: () => _selectView(v.id),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: selected ? Zbrand.gradient : null,
                color: selected ? null : Zc.surface,
                borderRadius: BorderRadius.circular(Zr.button),
              ),
              child: Text(
                v.name,
                style: Zt.caption.copyWith(color: selected ? Colors.white : Zc.textPrimary),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sortBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
      child: Wrap(
        spacing: 8,
        children: [
          for (final s in _Sort.values)
            GestureDetector(
              onTap: () => _selectSort(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: s == _sort ? Zc.subtle : Colors.transparent,
                  borderRadius: BorderRadius.circular(Zr.button),
                  border: Border.all(color: s == _sort ? Zc.brandPrimary : Zc.separator),
                ),
                child: Text(
                  s.label,
                  style: Zt.micro.copyWith(
                    color: s == _sort ? Zc.brandPrimary : Zc.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _subtitle(EmbyItem item) {
    final parts = <String>[
      if (item.productionYear != null) '${item.productionYear}',
      if (item.isSeries && item.childCount != null) '${item.childCount} 季',
      if (item.isSeason && item.childCount != null) '${item.childCount} 集',
      if (item.communityRating != null && item.communityRating! > 0) item.communityRating!.toStringAsFixed(1),
    ];
    return parts.join(' · ');
  }
}
