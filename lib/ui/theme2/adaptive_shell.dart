import 'package:flutter/material.dart';

import 'device_form.dart';
import 'orientation.dart';
import 'tokens.dart';
import 'z_routes.dart';

/// M1 新壳：按设备形态切换 rail / dock / topbar 三套 chrome。
///
/// 整个新壳包在 `ZTheme.light()` 里（新页面浅色）；旧页面由
/// `ZRoutes.fallback` 自己再包一层深色 `buildTheme()`，互不干扰。
class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({super.key, this.initialTab = ZTab.home});

  final ZTab initialTab;

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  late ZTab _tab = widget.initialTab;
  bool _orientationApplied = false;

  void _select(ZTab tab) => setState(() => _tab = tab);

  void _openLegacy(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => ZRoutes.fallback(ZTab.more)(routeContext),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final form = DeviceFormX.of(context);
    // initState 里拿不到可靠的 MediaQuery，用首帧回调一次性应用方向策略。
    if (!_orientationApplied) {
      _orientationApplied = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await ZOrientation.apply(form);
        } catch (_) {
          // 方向设置依赖系统通道：widget test / 无平台实现的环境里不可用，
          // 失败不应冒泡成渲染异常。
        }
      });
    }
    return Theme(
      data: ZTheme.light(),
      child: Scaffold(body: _body(context, form)),
    );
  }

  Widget _body(BuildContext context, DeviceForm form) {
    // 未登记的 tab 一律走 fallback，永不空页面。
    final builder = ZRoutes.page(_tab) ?? ZRoutes.fallback(_tab);
    final page = builder(context);
    if (form.usesRail) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_rail(context), Expanded(child: page)],
      );
    }
    if (form.usesDock) {
      return Stack(
        children: [
          Positioned.fill(child: page),
          Positioned(left: 16, right: 16, bottom: 16, child: _dock()),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_topBar(), Expanded(child: page)],
    );
  }

  /// 桌面 / 平板：宽 76 白色 Rail，顶部品牌渐变 logo，44×44 圆角 tab，
  /// 选中项为品牌渐变胶囊；底部"经典界面"按钮打开旧完整壳。
  Widget _rail(BuildContext context) => Container(
        key: const Key('z_rail'),
        width: 76,
        color: Zc.surface,
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: Zbrand.gradient,
                borderRadius: BorderRadius.circular(Zr.card),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 20),
            for (final t in ZTab.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _railItem(t),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => _openLegacy(context),
              child: Text('经典界面', style: Zt.micro.copyWith(color: Zc.textSecondary)),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );

  Widget _railItem(ZTab t) {
    final selected = t == _tab;
    return Semantics(
      button: true,
      selected: selected,
      label: t.labelZh,
      child: GestureDetector(
        onTap: () => _select(t),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: selected ? Zbrand.gradient : null,
            color: selected ? null : Zc.subtle,
            borderRadius: BorderRadius.circular(Zr.button),
          ),
          alignment: Alignment.center,
          child: Icon(t.icon, size: 22, color: selected ? Colors.white : Zc.textPrimary),
        ),
      ),
    );
  }

  /// 手机：底部悬浮玻璃 Dock（纯色近似磨砂），白色圆角 20、距底/左右 16、高 64。
  Widget _dock() => Container(
        key: const Key('z_dock'),
        height: 64,
        decoration: BoxDecoration(
          color: Zc.surface,
          borderRadius: BorderRadius.circular(Zr.sheet),
          boxShadow: const [
            BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Row(children: [for (final t in ZTab.values) _dockItem(t)]),
      );

  Widget _dockItem(ZTab t) {
    final selected = t == _tab;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(t),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(
                gradient: selected ? Zbrand.gradient : null,
                borderRadius: BorderRadius.circular(Zr.button),
              ),
              child: Icon(t.icon, size: 20, color: selected ? Colors.white : Zc.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              t.labelZh,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Zt.micro.copyWith(color: selected ? Zc.textPrimary : Zc.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// TV：顶部横栏胶囊按钮，选中项放大 1.12 并带渐变 + 描边。
  Widget _topBar() => Container(
        key: const Key('z_topbar'),
        color: Zc.surface,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [for (final t in ZTab.values) _topBarItem(t)],
        ),
      );

  Widget _topBarItem(ZTab t) {
    final selected = t == _tab;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Transform.scale(
        scale: selected ? 1.12 : 1.0,
        child: GestureDetector(
          onTap: () => _select(t),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              gradient: selected ? Zbrand.gradient : null,
              color: selected ? null : Zc.subtle,
              borderRadius: BorderRadius.circular(Zr.button),
              border: selected ? Border.all(color: Zc.brandPrimary, width: 2) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(t.icon, size: 20, color: selected ? Colors.white : Zc.textPrimary),
                const SizedBox(width: 6),
                Text(t.labelZh,
                    style: Zt.caption.copyWith(color: selected ? Colors.white : Zc.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
