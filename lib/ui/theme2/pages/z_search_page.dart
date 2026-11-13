import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/emby/models/emby_item.dart';
import '../../../l10n/l10n.dart';
import '../../core/artwork.dart';
import '../../pages/routes.dart';
import '../device_form.dart';
import '../tokens.dart';
import '../widgets/z_media.dart';
import '../z_components.dart';

/// 新搜索页（M2）：输入 350ms 防抖后直接打 Emby 的 `SearchTerm` 查询，
/// 结果按海报网格展示，点开走现有详情路由。
class ZSearchPage extends StatefulWidget {
  const ZSearchPage({super.key});

  @override
  State<ZSearchPage> createState() => _ZSearchPageState();
}

class _ZSearchPageState extends State<ZSearchPage> {
  static const _debounce = Duration(milliseconds: 350);

  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _sequence = 0;

  String _query = '';
  List<EmbyItem> _results = const [];
  bool _searching = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // 清除按钮与聚焦描边需要跟着输入/焦点状态刷新。
    _controller.addListener(_onTextChanged);
    _focus.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.removeListener(_onTextChanged);
    _focus.removeListener(_onTextChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    final trimmed = value.trim();
    if (trimmed == _query && !_searching) return;
    _timer = Timer(_debounce, () => _search(trimmed));
  }

  Future<void> _search(String term) async {
    final services = AppServicesScope.maybeRead(context);
    if (!mounted) return;
    if (term.isEmpty || services == null || !services.isSignedIn) {
      setState(() {
        _query = term;
        _results = const [];
        _searching = false;
        _failed = false;
      });
      return;
    }
    final seq = ++_sequence;
    setState(() {
      _query = term;
      _searching = true;
      _failed = false;
    });
    try {
      final page = await services.catalog.query(
        searchTerm: term,
        types: const ['Movie', 'Series', 'BoxSet'],
        sortBy: 'SortName',
        limit: 90,
      );
      if (!mounted || seq != _sequence) return;
      setState(() {
        _results = page.items;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || seq != _sequence) return;
      setState(() {
        _results = const [];
        _searching = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServicesScope.maybeRead(context);
    final bottomPad = DeviceFormX.of(context).usesDock ? 104.0 : 32.0;
    return ColoredBox(
      color: Zc.bgBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Text(context.l10n.search, style: Zt.display.copyWith(color: Zc.textPrimary)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _searchField(),
          ),
          const SizedBox(height: 8),
          Expanded(child: _results_area(services, bottomPad)),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Zc.surface,
        borderRadius: BorderRadius.circular(Zr.input),
        border: Border.all(color: _focus.hasFocus ? Zc.brandPrimary : Zc.separator),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 20, color: Zc.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: false,
              textInputAction: TextInputAction.search,
              style: Zt.body.copyWith(color: Zc.textPrimary),
              cursorColor: Zc.brandPrimary,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '搜索电影、剧集、合集',
                hintStyle: Zt.body.copyWith(color: Zc.textTertiary),
              ),
              onChanged: _onChanged,
              onSubmitted: (v) => _search(v.trim()),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _controller.clear();
                _search('');
                _focus.requestFocus();
              },
              child: const Icon(Icons.close_rounded, size: 18, color: Zc.textTertiary),
            ),
        ],
      ),
    );
  }

  Widget _results_area(AppServices? services, double bottomPad) {
    if (services == null || !services.isSignedIn) {
      return const ZEmptyState(
        icon: Icons.cloud_off_rounded,
        title: '还没有连接服务器',
        hint: '登录 Emby / Jellyfin 后即可搜索媒体库。',
      );
    }
    if (_searching) return const ZLoading(label: '正在搜索…');
    if (_query.isEmpty) {
      return const ZEmptyState(
        icon: Icons.manage_search_rounded,
        title: '输入关键词开始搜索',
        hint: '支持电影、剧集和合集名称，输入即搜。',
      );
    }
    if (_failed) {
      return ZEmptyState(
        icon: Icons.error_outline_rounded,
        title: '搜索失败',
        hint: '服务器没有响应，稍后重试。',
        action: ZGhostButton(label: '重试', icon: Icons.refresh_rounded, onPressed: () => _search(_query)),
      );
    }
    if (_results.isEmpty) {
      return ZEmptyState(
        icon: Icons.search_off_rounded,
        title: '没有找到"$_query"',
        hint: '换个关键词，或者到经典界面的「探索」里按类型筛选。',
      );
    }
    final catalog = services.catalog;
    return ZPosterGrid(
      padding: EdgeInsets.fromLTRB(24, 12, 24, bottomPad),
      children: [
        for (final item in _results)
          ZPosterTile(
            image: catalog.poster(item, width: 200),
            title: item.name,
            subtitle: _subtitle(item),
            progress: item.progress,
            onTap: () => openItem(context, item),
          ),
      ],
    );
  }

  static String _subtitle(EmbyItem item) {
    final parts = <String>[
      if (item.isSeries) '剧集' else if (item.isCollection) '合集' else if (item.isMovie) '电影',
      if (item.productionYear != null) '${item.productionYear}',
      if (item.communityRating != null && item.communityRating! > 0) item.communityRating!.toStringAsFixed(1),
    ];
    return parts.join(' · ');
  }
}
