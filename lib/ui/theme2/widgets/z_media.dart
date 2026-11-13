import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';
import '../z_components.dart';
import '../../focus/tv_focusable.dart';
import '../../widgets/net_image.dart';

/// 媒体展示组件族（M2）：海报卡 / 横卡 / 横向列表 / Hero 轮播 / 空态。
///
/// 全部是纯展示组件——图片 Uri 由调用方用 `catalog.poster(...)` 等扩展预解，
/// 组件本身不依赖 `AppServicesScope`，因此可以在 widget test 里直接 pump。

/// 可聚焦包装：鼠标 hover / TV D-pad 焦点都会得到放大 + 品牌色光晕。
///
/// 复用既有 [TvFocusable]（Enter / Select / 手柄 A 激活；方向键交给
/// `ZoneNavigator` 做几何寻路），因此新页面天生支持遥控器。
class ZFocusable extends StatelessWidget {
  const ZFocusable({
    super.key,
    required this.builder,
    this.onSelect,
    this.onMenu,
    this.autofocus = false,
    this.radius = Zr.poster,
    this.scale = 1.04,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onSelect;
  final VoidCallback? onMenu;
  final bool autofocus;
  final double radius;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      onMenu: onMenu,
      builder: (context, focused) => AnimatedScale(
        scale: focused ? scale : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: focused
                ? const [
                    BoxShadow(color: Color(0x590CBDE6), blurRadius: 18, spreadRadius: 1),
                  ]
                : null,
          ),
          child: builder(context, focused),
        ),
      ),
    );
  }
}

double _clamp01(double? v) {
  if (v == null || v.isNaN) return 0;
  if (v < 0) return 0;
  if (v > 1) return 1;
  return v;
}

String _percent(double? progress) => '${(_clamp01(progress) * 100).round()}%';

/// 竖版海报卡：圆角 12 图 + 单行标题 + 单行副标题（年份 / 集数），
/// 底部 3px 品牌色进度条表示观看进度。
class ZPosterTile extends StatelessWidget {
  const ZPosterTile({
    super.key,
    required this.image,
    required this.title,
    required this.onTap,
    this.width,
    this.subtitle,
    this.progress,
    this.badge,
    this.showTitle = true,
  });

  final Uri? image;
  final String title;
  final double? width;
  final VoidCallback onTap;
  final String? subtitle;
  final double? progress;
  final String? badge;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final p = _clamp01(progress);
    return SizedBox(
      width: width,
      child: ZFocusable(
        onSelect: onTap,
        builder: (context, focused) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Zr.poster),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(url: image, fallback: const ColoredBox(color: Zc.placeholder)),
                    if (badge != null)
                      Positioned(left: 8, top: 8, child: ZBadge(text: badge!)),
                    if (p > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: p,
                          minHeight: 3,
                          backgroundColor: const Color(0x4D000000),
                          valueColor: const AlwaysStoppedAnimation<Color>(Zc.brandPrimary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (showTitle) ...[
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Zt.caption.copyWith(color: Zc.textPrimary),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Zt.micro.copyWith(color: Zc.textSecondary, fontWeight: FontWeight.w400),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 横版继续观看卡：16:9 剧照，标题压在图上，底部进度条 + 剩余时间。
class ZLandscapeTile extends StatelessWidget {
  const ZLandscapeTile({
    super.key,
    required this.image,
    required this.title,
    required this.width,
    required this.onTap,
    this.subtitle,
    this.progress,
  });

  final Uri? image;
  final String title;
  final double width;
  final VoidCallback onTap;
  final String? subtitle;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final p = _clamp01(progress);
    return SizedBox(
      width: width,
      child: ZFocusable(
        onSelect: onTap,
        builder: (context, focused) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Zr.card),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(url: image, fallback: const ColoredBox(color: Zc.placeholder)),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[Color(0x00000000), Color(0x99000000)],
                          stops: <double>[0.45, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10,
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Zt.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (p > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: p,
                          minHeight: 3,
                          backgroundColor: const Color(0x4D000000),
                          valueColor: const AlwaysStoppedAnimation<Color>(Zc.brandPrimary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Zt.micro.copyWith(color: Zc.textSecondary, fontWeight: FontWeight.w400),
                      ),
                    ),
                    if (p > 0)
                      Text(
                        _percent(progress),
                        style: Zt.micro.copyWith(color: Zc.brandPrimary),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 一行横向内容：标题 + 可选"全部"按钮 + 横向列表。
class ZMediaRow extends StatelessWidget {
  const ZMediaRow({
    super.key,
    required this.title,
    required this.height,
    required this.children,
    this.onMore,
  });

  final String title;
  final double height;
  final List<Widget> children;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(title, style: Zt.title.copyWith(color: Zc.textPrimary)),
              ),
              if (onMore != null)
                TextButton(
                  onPressed: onMore,
                  child: Text('全部', style: Zt.caption.copyWith(color: Zc.textSecondary)),
                ),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            physics: const BouncingScrollPhysics(),
            itemCount: children.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) => children[i],
          ),
        ),
      ],
    );
  }
}

/// Hero 轮播项。展示字段由调用方预算，组件保持无服务依赖。
@immutable
class ZHeroItem {
  const ZHeroItem({
    required this.backdrop,
    required this.title,
    required this.meta,
    required this.onPlay,
    required this.onOpen,
    this.overview,
    this.logo,
  });

  final Uri? backdrop;
  final String title;
  final String meta;
  final String? overview;
  final Uri? logo;
  final VoidCallback onPlay;
  final VoidCallback onOpen;
}

/// 顶部大图轮播：7 秒自动切换、左右白色渐变让文字压在图上、右下角指示点。
class ZHeroCarousel extends StatefulWidget {
  const ZHeroCarousel({super.key, required this.items, this.autoplay = true});

  final List<ZHeroItem> items;
  final bool autoplay;

  @override
  State<ZHeroCarousel> createState() => _ZHeroCarouselState();
}

class _ZHeroCarouselState extends State<ZHeroCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(ZHeroCarousel old) {
    super.didUpdateWidget(old);
    if (old.items.length != widget.items.length) {
      _index = 0;
      _restart();
    }
  }

  void _restart() {
    _timer?.cancel();
    if (!widget.autoplay || widget.items.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || !_controller.hasClients || widget.items.length < 2) return;
      final next = (_index + 1) % widget.items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 960.0;
        final height = math.min(width * 0.42, 420.0).clamp(220.0, 420.0).toDouble();
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: items.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _slide(items[i], height, width),
              ),
              if (items.length > 1)
                Positioned(right: 44, bottom: 24, child: _dots(items.length)),
            ],
          ),
        );
      },
    );
  }

  Widget _slide(ZHeroItem item, double height, double width) {
    final textWidth = math.min(width * 0.52, 560.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Zr.sheet),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetImage(url: item.backdrop, fallback: const ColoredBox(color: Zc.placeholder)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[Color(0xF2FFFFFF), Color(0xBFFFFFFF), Color(0x00FFFFFF)],
                  stops: <double>[0.0, 0.46, 1.0],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(36, 16, 24, 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: textWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.logo != null)
                        SizedBox(
                          height: 56,
                          width: textWidth,
                          child: NetImage(
                            url: item.logo,
                            fit: BoxFit.contain,
                            alignment: Alignment.centerLeft,
                            fallback: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Zt.display.copyWith(color: Zc.textPrimary),
                            ),
                          ),
                        )
                      else
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Zt.display.copyWith(color: Zc.textPrimary),
                        ),
                      if (item.meta.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          item.meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Zt.caption.copyWith(color: Zc.textSecondary),
                        ),
                      ],
                      if (item.overview != null && item.overview!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          item.overview!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Zt.body.copyWith(color: Zc.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ZPrimaryButton(label: '播放', onPressed: item.onPlay),
                          const SizedBox(width: 12),
                          ZGhostButton(
                            label: '详情',
                            icon: Icons.info_outline_rounded,
                            onPressed: item.onOpen,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dots(int count) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _index ? Zc.brandPrimary : const Color(0x4D000000),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
}

/// 空态：图标 + 标题 + 说明，可选一个操作按钮。
class ZEmptyState extends StatelessWidget {
  const ZEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: Zc.subtle, shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: Zc.textTertiary),
            ),
            const SizedBox(height: 14),
            Text(title, style: Zt.headline.copyWith(color: Zc.textPrimary)),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: Zt.body.copyWith(color: Zc.textSecondary),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 品牌色加载态，避免默认 Material 圆形进度在浅色底上偏灰。
class ZLoading extends StatelessWidget {
  const ZLoading({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: Zc.brandPrimary),
          ),
          if (label != null) ...[
            const SizedBox(height: 12),
            Text(label!, style: Zt.caption.copyWith(color: Zc.textSecondary)),
          ],
        ],
      ),
    );
  }
}

/// 响应式海报网格：按可用宽度算列数，poster 宽随列宽自适应。
class ZPosterGrid extends StatelessWidget {
  const ZPosterGrid({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(24, 8, 24, 32),
    this.minTileWidth = 132,
    this.controller,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final double minTileWidth;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: controller,
      padding: padding,
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: minTileWidth * 1.6,
        crossAxisSpacing: 14,
        mainAxisSpacing: 18,
        childAspectRatio: 0.55,
      ),
      itemCount: children.length,
      itemBuilder: (context, i) => children[i],
    );
  }
}
