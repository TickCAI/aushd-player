import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/l10n/l10n.dart';
import 'package:zerk_play/ui/theme2/adaptive_shell.dart';
import 'package:zerk_play/ui/theme2/tokens.dart';
import 'package:zerk_play/ui/theme2/z_routes.dart';

void main() {
  // 不覆盖 debugDefaultTargetPlatformOverride：flutter_test 在 FLUTTER_TEST
  // 下 defaultTargetPlatform 已经是 android，而显式设置它会在 postTest 的
  // 不变量校验里报 "foundation debug variable was changed by the test"。
  // TV 态需要 isAndroid + landscape + shortest>=900，本测试只覆盖桌面 / 手机两态。

  testWidgets('桌面 1200x800：左侧 rail 存在，点击 tab 无异常', (tester) async {
    await _pumpShell(tester, const Size(1200, 800));
    expect(find.byKey(const Key('z_rail')), findsOneWidget);
    expect(find.byKey(const Key('z_dock')), findsNothing);

    final rail = find.byKey(const Key('z_rail'));
    await tester.tap(
      find.descendant(of: rail, matching: find.byIcon(Icons.search_rounded)).first,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机 400x800：底部 dock 存在，点击 tab 无异常', (tester) async {
    await _pumpShell(tester, const Size(400, 800));
    expect(find.byKey(const Key('z_dock')), findsOneWidget);
    expect(find.byKey(const Key('z_rail')), findsNothing);

    final dock = find.byKey(const Key('z_dock'));
    await tester.tap(
      find.descendant(of: dock, matching: find.byIcon(Icons.settings_rounded)).first,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('ZRoutes：未登记的 more 走 fallback，四个新页已登记', () {
    expect(ZRoutes.page(ZTab.more), isNull);
    expect(ZRoutes.fallback(ZTab.more), isNotNull);
    for (final tab in const [ZTab.home, ZTab.library, ZTab.search, ZTab.settings]) {
      expect(ZRoutes.page(tab), isNotNull, reason: '$tab 应登记新页');
      expect(ZRoutes.fallback(tab), isNotNull, reason: '$tab 应有旧页回落');
    }
  });
}

Future<void> _pumpShell(WidgetTester tester, Size size) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ZTheme.light(),
      // M2 的真实页面用 context.l10n 取文案，测试里必须带齐 delegate。
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: const AdaptiveShell(),
      ),
    ),
  );
}
