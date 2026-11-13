import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zerk_play/core/log/diagnostics.dart';
import 'package:zerk_play/ui/theme2/widgets/diagnostics_button.dart';

void main() {
  // Required for SharedPreferences' in-memory mock and for widget tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Diagnostics.export() writes a readable file with version and platform',
      () async {
    // On Linux CI AppLog.directory is null (AppLog.init() is not called here),
    // so export() must fall back to Directory.systemTemp.path.
    final path = await Diagnostics.export();

    expect(path, isNotNull, reason: 'export should return an absolute path');
    final file = File(path!);
    expect(await file.exists(), isTrue, reason: 'diagnostics file must exist');

    final text = await file.readAsString();
    expect(text, contains('AusHD'));
    expect(text, contains('platform'));
    expect(text, contains('--- [6] DisplayGuard ---'));
    expect(text, contains('--- [7] crash entries'));

    // Keep the temp directory clean between runs.
    try {
      await file.delete();
    } catch (_) {}
  });

  // Importing and pumping the widget forces `flutter test` (the CI hard gate)
  // to compile diagnostics_button.dart, which no production code references yet.
  testWidgets('DiagnosticsButton renders without errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const Center(child: DiagnosticsButton()),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('导出诊断包'), findsOneWidget);
    expect(find.text('打开日志目录'), findsOneWidget);
  });
}
