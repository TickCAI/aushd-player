import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/ui/theme2/tokens.dart';
import 'package:zerk_play/ui/theme2/widgets/z_media.dart';

/// M2 媒体展示组件的契约测试：全部传 `image: null`，不触发任何网络请求。
void main() {
  Widget host(Widget child, {Size size = const Size(800, 600)}) => MaterialApp(
        theme: ZTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: size.width, height: size.height, child: child),
          ),
        ),
      );

  testWidgets('ZPosterTile：无图占位 + 标题 + 进度条 + 可点', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      host(
        Center(
          child: ZPosterTile(
            image: null,
            title: '测试影片',
            subtitle: '2024 · 8.2',
            width: 150,
            progress: 0.42,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('测试影片'), findsOneWidget);
    expect(find.text('2024 · 8.2'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.text('测试影片'));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ZMediaRow：标题行 + 子项横向排布', (tester) async {
    await tester.pumpWidget(
      host(
        ZMediaRow(
          title: '最近添加',
          height: 200,
          children: const [SizedBox(width: 120, child: Text('A')), SizedBox(width: 120, child: Text('B'))],
        ),
      ),
    );

    expect(find.text('最近添加'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ZHeroCarousel：单条时展示标题、简介与两个按钮', (tester) async {
    await tester.pumpWidget(
      host(
        ZHeroCarousel(
          items: [
            ZHeroItem(
              backdrop: null,
              title: '星际穿越',
              meta: '电影 · 2014 · ★ 9.4',
              overview: '一队探险家穿越虫洞寻找新家园。',
              onPlay: () {},
              onOpen: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('星际穿越'), findsOneWidget);
    expect(find.text('电影 · 2014 · ★ 9.4'), findsOneWidget);
    expect(find.text('播放'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ZLandscapeTile 与 ZEmptyState 可渲染', (tester) async {
    await tester.pumpWidget(
      host(
        Column(
          children: [
            SizedBox(
              width: 240,
              child: ZLandscapeTile(
                image: null,
                title: '第 1 集',
                subtitle: '剩余 32 分钟',
                progress: 0.3,
                width: 240,
                onTap: () {},
              ),
            ),
            const ZEmptyState(icon: Icons.movie_outlined, title: '空媒体库', hint: '添加影片后刷新'),
          ],
        ),
      ),
    );

    expect(find.text('第 1 集'), findsOneWidget);
    expect(find.text('剩余 32 分钟'), findsOneWidget);
    expect(find.text('空媒体库'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
