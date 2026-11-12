import 'package:flutter/material.dart';

// M1 设计系统令牌，色值取自 docs/UI重写-苹果系一体沉浸式-方案论证.md 第二节。
// 浅色为浏览层默认，深色用于播放层 / TV / 夜间浏览。

/// 色彩：`Zc` 内浅色用裸名，深色用 `dark` 前缀，避免同名冲突。
abstract final class Zc {
  // 浅色（浏览层默认）
  static const Color bgBase = Color(0xFFF6F9F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color subtle = Color(0xFFEEF4F2);
  static const Color placeholder = Color(0xFFE8EFED);

  static const Color textPrimary = Color(0xFF212228);
  static const Color textSecondary = Color.fromRGBO(33, 34, 40, 0.55);
  static const Color textTertiary = Color.fromRGBO(33, 34, 40, 0.35);
  static const Color separator = Color.fromRGBO(33, 34, 40, 0.08);

  static const Color brandPrimary = Color(0xFF0CBDE6);
  static const Color brandFresh = Color(0xFF9BDFAC);
  static const Color danger = Color(0xFFFF3B30);
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);

  // 深色（播放层 / TV / 夜间浏览）
  static const Color darkBgBase = Color(0xFF0A0F11);
  static const Color darkSurface = Color(0xFF15191C);
  static const Color darkSurface2 = Color(0xFF1C2226);
  static const Color darkBrand = Color(0xFF22C8EE);
  static const Color darkTextPrimary = Color.fromRGBO(255, 255, 255, 0.96);
  static const Color darkTextSecondary = Color.fromRGBO(255, 255, 255, 0.60);
  static const Color darkTextTertiary = Color.fromRGBO(255, 255, 255, 0.36);
}

/// 圆角半径（逻辑像素）。
abstract final class Zr {
  static const double poster = 12;
  static const double card = 16;
  static const double sheet = 20;
  static const double button = 22;
  static const double input = 12;
}

/// 品牌渐变，只用于主按钮 / 进度条 / Tab 指示器 / TV 聚焦光晕 / 启动页。
abstract final class Zbrand {
  static const LinearGradient gradient = LinearGradient(
    colors: <Color>[
      Color(0xFF9BDFAC),
      Color(0xFF5CD5C4),
      Color(0xFF0CBDE6),
    ],
  );
}

/// 字阶（全部无衬线）。
abstract final class Zt {
  static const TextStyle display = TextStyle(fontSize: 34, fontWeight: FontWeight.w700);
  static const TextStyle title = TextStyle(fontSize: 22, fontWeight: FontWeight.w700);
  static const TextStyle headline = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);
  static const TextStyle body = TextStyle(fontSize: 15, fontWeight: FontWeight.w400);
  static const TextStyle caption = TextStyle(fontSize: 13, fontWeight: FontWeight.w500);
  static const TextStyle micro = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);
}

/// 三态主题：light 浏览层 / dark 夜间·TV / playerDark 播放层沉浸深色。
/// dark 与 playerDark 共用深色色板（文档 2.1），以 canvasColor 的
/// 表面一级/二级之差作最小可辨识区分，不做过度配置。
abstract final class ZTheme {
  static ThemeData light() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Zc.bgBase,
        primaryColor: Zc.brandPrimary,
        canvasColor: Zc.surface,
      );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Zc.darkBgBase,
        primaryColor: Zc.darkBrand,
        canvasColor: Zc.darkSurface,
      );

  static ThemeData playerDark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Zc.darkBgBase,
        primaryColor: Zc.darkBrand,
        canvasColor: Zc.darkSurface2,
      );
}
