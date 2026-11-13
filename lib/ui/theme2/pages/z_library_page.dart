import 'package:flutter/material.dart';

import '../tokens.dart';

/// M1 占位媒体库页：M2 将替换为完整新设计页面。
///
/// 约定 const 构造、无必填参数、自包含（不依赖 AppServicesScope），
/// 便于 widget test 直接 pump，也便于 M2 逐页替换。
class ZLibraryPage extends StatelessWidget {
  const ZLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(
        color: Zc.bgBase,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('媒体库', style: Zt.title.copyWith(color: Zc.textPrimary)),
              const SizedBox(height: 8),
              Text('M2 页面待接入', style: Zt.caption.copyWith(color: Zc.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
