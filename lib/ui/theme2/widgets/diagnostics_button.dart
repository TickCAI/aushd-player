import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/log/app_log.dart';
import '../../../core/log/diagnostics.dart';
import '../z_components.dart';

/// Settings tile that exports the one-file diagnostics bundle and lets the
/// user open the log folder. Referenced by the settings page; kept standalone
/// so it can be dropped in without touching existing wiring.
class DiagnosticsButton extends StatelessWidget {
  const DiagnosticsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ZCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ZPrimaryButton(
            label: '导出诊断包',
            onPressed: () => unawaited(_export(context)),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: () => unawaited(AppLog.openFolder()),
              child: const Text('打开日志目录'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    // Capture the messenger before the async gap so `context` is never used
    // across await. export() already swallows every error and returns null on
    // failure, so no extra try/catch is needed here.
    final messenger = ScaffoldMessenger.of(context);
    final path = await Diagnostics.export();
    if (path == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('导出失败，请重试')),
      );
      return;
    }
    final name = path.replaceAll('\\', '/').split('/').last;
    messenger.showSnackBar(
      SnackBar(content: Text('已导出：$name')),
    );
  }
}
