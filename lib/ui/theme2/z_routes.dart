import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../pages/home_page.dart';
import '../pages/library_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';
import '../shell/shell.dart';
import '../theme/tokens.dart' show buildTheme;
import 'pages/z_home_page.dart';
import 'pages/z_library_page.dart';
import 'pages/z_search_page.dart';
import 'pages/z_settings_page.dart';
import 'tokens.dart';

/// 新壳的五个顶层 tab。
///
/// [labelZh] 是无 Localizations delegate 时（例如 widget test）也能安全显示的
/// 中文兜底文案；arb 里没有 "library" / "more" 两个 key，因此 more 直接用它，
/// library 复用 shell.dart 里已有的 `l10n.navLibrary`。
enum ZTab {
  home(Icons.home_rounded, '首页'),
  library(Icons.video_library_rounded, '媒体库'),
  search(Icons.search_rounded, '搜索'),
  settings(Icons.settings_rounded, '设置'),
  more(Icons.more_horiz_rounded, '更多');

  const ZTab(this.icon, this.labelZh);

  final IconData icon;
  final String labelZh;

  String label(L10n l10n) => switch (this) {
        home => l10n.home,
        library => l10n.navLibrary,
        search => l10n.search,
        settings => l10n.settings,
        more => labelZh,
      };
}

typedef ZPageBuilder = Widget Function(BuildContext context);

/// 新页登记表 + 旧页回落。
///
/// CineIsle 式"一页一页长"：只有登记过新实现的 tab 走新页，其余一律回落
/// 到 v1.0.1 的经典实现，保证任何时刻都不会出现空页面。
abstract final class ZRoutes {
  /// 返回新页 builder；未登记（more）返回 null。
  static ZPageBuilder? page(ZTab tab) => switch (tab) {
        ZTab.home => (_) => const ZHomePage(),
        ZTab.library => (_) => const ZLibraryPage(),
        ZTab.search => (_) => const ZSearchPage(),
        ZTab.settings => (_) => const ZSettingsPage(),
        ZTab.more => null,
      };

  /// 旧页面依赖硬编码深色主题（buildTheme()），这里显式包一层，
  /// 避免新壳的浅色 Theme 让旧页面白底白字。
  static ZPageBuilder fallback(ZTab tab) => (_) => Theme(
        data: buildTheme(),
        child: _legacy(tab),
      );

  static Widget _legacy(ZTab tab) => switch (tab) {
        ZTab.home => const HomePage(),
        ZTab.search => const SearchPage(),
        ZTab.library => const LibraryPage(kind: LibraryKind.movies),
        ZTab.settings => const SettingsPage(),
        // 旧完整壳，保证所有功能仍然可达。
        ZTab.more => const Shell(initialTab: ShellTab.home),
      };
}

/// 新页之间的跳转路由：显式包一层浅色主题。
///
/// Navigator 在 `MaterialApp` 之下、`AdaptiveShell` 之上，因此 push 进来的
/// 页面拿到的是旧 `buildTheme()`（深色）。新页用的是硬编码浅色令牌，
/// 不包这一层就会出现"深底深字"。
Route<void> zRoute(Widget page, {String? name}) => MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: (_) => Theme(data: ZTheme.light(), child: page),
    );
