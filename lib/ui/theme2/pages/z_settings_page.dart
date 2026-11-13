import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/release.dart';
import '../../../core/host.dart';
import '../../../l10n/l10n.dart';
import '../device_form.dart';
import '../tokens.dart';
import '../widgets/diagnostics_button.dart';
import '../z_components.dart';
import '../z_routes.dart';

/// 新设置页（M2）：账户 / 外观 / 诊断 / 更多四块。
///
/// 完整设置项（播放、字幕、元数据、请求……）仍在经典设置页里，
/// 这里只做"新界面第一屏"和最常用的账户操作，并提供经典界面入口。
class ZSettingsPage extends StatelessWidget {
  const ZSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppServicesScope.maybeRead(context);
    final bottomPad = DeviceFormX.of(context).usesDock ? 104.0 : 32.0;
    return ColoredBox(
      color: Zc.bgBase,
      child: ListView(
        padding: EdgeInsets.fromLTRB(24, 20, 24, bottomPad),
        physics: const BouncingScrollPhysics(),
        children: [
          Text(context.l10n.settings, style: Zt.display.copyWith(color: Zc.textPrimary)),
          const SizedBox(height: 2),
          Text(
            '${Release.name}  ·  ${Host.isAndroid ? 'Android' : Host.isWindows ? 'Windows' : 'Linux'}',
            style: Zt.caption.copyWith(color: Zc.textSecondary),
          ),
          const SizedBox(height: 20),
          _section('账户'),
          _account(context, services),
          const SizedBox(height: 20),
          _section('外观'),
          ZCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('浅色 · 小清新（默认）', style: Zt.headline.copyWith(color: Zc.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  '新界面统一使用品牌渐变的浅色主题，播放器保持沉浸深色。',
                  style: Zt.caption.copyWith(color: Zc.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _section('诊断'),
          const DiagnosticsButton(),
          const SizedBox(height: 20),
          _section('更多'),
          _link(
            icon: Icons.grid_view_rounded,
            title: '经典界面（完整功能）',
            hint: '播放设置、字幕、元数据、请求、直播……',
            onTap: () => _openLegacy(context),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '${Release.tag}  ·  ${Release.channel == 'beta' ? '测试版' : Release.channel}',
              style: Zt.micro.copyWith(color: Zc.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(
          title,
          style: Zt.micro.copyWith(color: Zc.textTertiary, letterSpacing: 1.2),
        ),
      );

  Widget _account(BuildContext context, AppServices? services) {
    final signedIn = services?.isSignedIn ?? false;
    final host = signedIn ? services!.janus.session.serverUrl.host : '—';
    final kind = signedIn ? '${services!.janus.session.kind}'.split('.').last : '';
    return ZCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: Zbrand.gradient,
                  borderRadius: BorderRadius.circular(Zr.poster),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.dns_rounded, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Zt.headline.copyWith(color: Zc.textPrimary),
                    ),
                    Text(
                      signedIn ? '已连接 ${kind.toUpperCase()}' : '未连接',
                      style: Zt.caption.copyWith(color: Zc.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (signedIn) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: ZGhostButton(
                label: '退出登录',
                icon: Icons.logout_rounded,
                tint: Zc.danger,
                onPressed: () => unawaited(_confirmSignOut(context, services!)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _link({
    required IconData icon,
    required String title,
    required String hint,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ZCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Zc.brandPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: Zt.headline.copyWith(color: Zc.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: Zt.micro.copyWith(color: Zc.textSecondary, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: Zc.textTertiary),
          ],
        ),
      ),
    );
  }

  static void _openLegacy(BuildContext context) {
    final builder = ZRoutes.fallback(ZTab.more);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'legacy-shell'),
        builder: builder,
      ),
    );
  }

  static Future<void> _confirmSignOut(BuildContext context, AppServices services) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Zc.surface,
        title: Text('退出登录', style: Zt.headline.copyWith(color: Zc.textPrimary)),
        content: Text(
          '退出后需要重新输入服务器地址与账号密码。',
          style: Zt.body.copyWith(color: Zc.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('退出')),
        ],
      ),
    );
    if (ok == true) await services.signOut();
  }
}
