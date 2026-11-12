import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/ui/theme2/tokens.dart';

void main() {
  group('Zc 色彩令牌', () {
    test('浅色（浏览层默认）关键色值', () {
      expect(Zc.bgBase, const Color(0xFFF6F9F8));
      expect(Zc.surface, const Color(0xFFFFFFFF));
      expect(Zc.subtle, const Color(0xFFEEF4F2));
      expect(Zc.placeholder, const Color(0xFFE8EFED));
      expect(Zc.textPrimary, const Color(0xFF212228));
      expect(Zc.textSecondary, const Color.fromRGBO(33, 34, 40, 0.55));
      expect(Zc.textTertiary, const Color.fromRGBO(33, 34, 40, 0.35));
      expect(Zc.separator, const Color.fromRGBO(33, 34, 40, 0.08));
      expect(Zc.brandPrimary, const Color(0xFF0CBDE6));
      expect(Zc.brandFresh, const Color(0xFF9BDFAC));
      expect(Zc.danger, const Color(0xFFFF3B30));
      expect(Zc.success, const Color(0xFF34C759));
      expect(Zc.warning, const Color(0xFFFF9500));
    });

    test('深色（播放层 / TV / 夜间）关键色值', () {
      expect(Zc.darkBgBase, const Color(0xFF0A0F11));
      expect(Zc.darkSurface, const Color(0xFF15191C));
      expect(Zc.darkSurface2, const Color(0xFF1C2226));
      expect(Zc.darkBrand, const Color(0xFF22C8EE));
      expect(Zc.darkTextPrimary, const Color.fromRGBO(255, 255, 255, 0.96));
      expect(Zc.darkTextSecondary, const Color.fromRGBO(255, 255, 255, 0.60));
      expect(Zc.darkTextTertiary, const Color.fromRGBO(255, 255, 255, 0.36));
    });
  });

  group('Zr 圆角令牌', () {
    test('圆角常量', () {
      expect(Zr.poster, 12);
      expect(Zr.card, 16);
      expect(Zr.sheet, 20);
      expect(Zr.button, 22);
      expect(Zr.input, 12);
    });
  });

  group('Zt 字阶令牌', () {
    test('字号与字重', () {
      expect(Zt.display.fontSize, 34);
      expect(Zt.display.fontWeight, FontWeight.w700);
      expect(Zt.title.fontSize, 22);
      expect(Zt.title.fontWeight, FontWeight.w700);
      expect(Zt.headline.fontSize, 17);
      expect(Zt.headline.fontWeight, FontWeight.w600);
      expect(Zt.body.fontSize, 15);
      expect(Zt.body.fontWeight, FontWeight.w400);
      expect(Zt.caption.fontSize, 13);
      expect(Zt.caption.fontWeight, FontWeight.w500);
      expect(Zt.micro.fontSize, 11);
      expect(Zt.micro.fontWeight, FontWeight.w600);
    });
  });

  group('Zbrand 品牌渐变', () {
    test('恰好 3 个 stop 且取自 logo 中段到尾段', () {
      final colors = Zbrand.gradient.colors;
      expect(colors.length, 3);
      expect(colors[0], const Color(0xFF9BDFAC));
      expect(colors[1], const Color(0xFF5CD5C4));
      expect(colors[2], const Color(0xFF0CBDE6));
    });
  });

  group('ZTheme 三态', () {
    test('light 为浅色，scaffold/primary 取浅色令牌', () {
      final theme = ZTheme.light();
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, Zc.bgBase);
      expect(theme.primaryColor, Zc.brandPrimary);
    });

    test('dark 为深色，scaffold/primary 取深色令牌', () {
      final theme = ZTheme.dark();
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, Zc.darkBgBase);
      expect(theme.primaryColor, Zc.darkBrand);
    });

    test('playerDark 为深色，brightness 正确', () {
      final theme = ZTheme.playerDark();
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, Zc.darkBgBase);
    });
  });
}
