import 'package:flutter/material.dart';

import '../tokens.dart';
import '../widgets/diagnostics_button.dart';

/// M1 占位设置页：先接入诊断卡片，M2 再替换为完整新设计页面。
///
/// 约定 const 构造、无必填参数、自包含（不依赖 AppServicesScope），
/// 便于 widget test 直接 pump，也便于 M2 逐页替换。
class ZSettingsPage extends StatelessWidget {
  const ZSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(
        color: Zc.bgBase,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('设置', style: Zt.title.copyWith(color: Zc.textPrimary)),
              const SizedBox(height: 16),
              const SizedBox(width: 320, child: DiagnosticsButton()),
            ],
          ),
        ),
      ),
    );
  }
}
