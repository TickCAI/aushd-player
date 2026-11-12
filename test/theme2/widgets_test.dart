import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/ui/theme2/tokens.dart';
import 'package:zerk_play/ui/theme2/z_components.dart';

Widget _host(ThemeData theme, Widget child) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  final themes = <String, ThemeData>{
    'light': ZTheme.light(),
    'dark': ZTheme.dark(),
  };

  for (final entry in themes.entries) {
    testWidgets('theme2 基础组件在 ${entry.key} 主题下渲染无异常', (tester) async {
      await tester.pumpWidget(_host(
        entry.value,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ZCard(key: Key('zc_card'), child: Text('卡片内容')),
            ZPrimaryButton(label: '播放', onPressed: () {}),
            const ZBadge(text: 'HDR'),
          ],
        ),
      ));

      // 渲染无异常
      expect(tester.takeException(), isNull);

      // ZPrimaryButton / ZBadge / ZCard 子树文字可见
      expect(find.text('播放'), findsOneWidget);
      expect(find.text('HDR'), findsOneWidget);
      expect(find.text('卡片内容'), findsOneWidget);

      // ZCard 默认圆角取 Zr.card
      final container = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(const Key('zc_card')),
              matching: find.byType(Container),
            ),
          )
          .first;
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(Zr.card));
    });
  }
}
