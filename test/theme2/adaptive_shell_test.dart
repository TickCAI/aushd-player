import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/ui/theme2/adaptive_shell.dart';
import 'package:zerk_play/ui/theme2/tokens.dart';
import 'package:zerk_play/ui/theme2/z_routes.dart';

void main() {
  // flutter_test 默认即 android；显式钉死，保证 DeviceFormX.of 的桌面/手机
  // 判定只由 MediaQuery 尺寸决定，不随 CI 平台漂移（TV 态需要 isAndroid +
  // landscape + shortest>=900，无法在本测试里同时稳定模拟，故只测两态）。
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

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
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: const AdaptiveShell(),
      ),
    ),
  );
}
