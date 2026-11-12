import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zerk_play/core/windows/native_window.dart';
import 'package:zerk_play/playback/display_guard.dart';

// The storage key is a private const in display_guard.dart; this literal must
// stay in sync with it so the tests can inspect the marker directly.
const _markerKey = 'display.guard.v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Capture the production hooks before setUp swaps in test doubles; tearDown
  // puts them back so a stub never leaks into a later test file's run.
  final defaultStatus = DisplayGuard.status;
  final defaultSetHdrState = DisplayGuard.setHdrState;
  final defaultWaitForHdrState = DisplayGuard.waitForHdrState;

  Future<String?> readMarker() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_markerKey);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Route every platform call through harmless doubles; individual tests
    // override the ones they assert on. No real method channel is ever hit.
    DisplayGuard.status = () async => const DisplayHdrStatus();
    DisplayGuard.setHdrState = (enabled) async => true;
    DisplayGuard.waitForHdrState = (enabled) async => true;
  });

  tearDown(() {
    DisplayGuard.status = defaultStatus;
    DisplayGuard.setHdrState = defaultSetHdrState;
    DisplayGuard.waitForHdrState = defaultWaitForHdrState;
  });

  test('markHdrAutoEnabled writes a marker with hdr=true as valid JSON',
      () async {
    await DisplayGuard.markHdrAutoEnabled();

    final raw = await readMarker();
    expect(raw, isNotNull, reason: 'marker should be persisted');
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded['hdr'], isTrue);
  });

  test('clean path: mark -> clear -> recover never calls setHdrState', () async {
    final calls = <String>[];
    DisplayGuard.status = () async {
      calls.add('status');
      return const DisplayHdrStatus(enabled: true);
    };
    DisplayGuard.setHdrState = (enabled) async {
      calls.add('set');
      return true;
    };
    DisplayGuard.waitForHdrState = (enabled) async {
      calls.add('wait');
      return true;
    };

    await DisplayGuard.markHdrAutoEnabled();
    await DisplayGuard.clear();
    await DisplayGuard.recoverOnStartup();

    expect(calls, isEmpty,
        reason: 'a cleared marker means no crash recovery should run');
    expect(await readMarker(), isNull, reason: 'marker stays removed');
  });

  test('crash path: HDR left on is turned off exactly once and marker cleared',
      () async {
    final setArgs = <bool>[];
    final waitArgs = <bool>[];
    DisplayGuard.status = () async =>
        const DisplayHdrStatus(supported: true, enabled: true);
    DisplayGuard.setHdrState = (enabled) async {
      setArgs.add(enabled);
      return true;
    };
    DisplayGuard.waitForHdrState = (enabled) async {
      waitArgs.add(enabled);
      return true;
    };

    await DisplayGuard.markHdrAutoEnabled();
    await DisplayGuard.recoverOnStartup();

    expect(setArgs, equals(<bool>[false]),
        reason: 'setHdrState(false) must run exactly once');
    expect(waitArgs, equals(<bool>[false]),
        reason: 'waitForHdrState(false) must run');
    expect(await readMarker(), isNull,
        reason: 'marker is removed before recovery');
  });

  test('status reports HDR disabled: setHdrState is not called', () async {
    final setArgs = <bool>[];
    DisplayGuard.status = () async =>
        const DisplayHdrStatus(supported: true, enabled: false);
    DisplayGuard.setHdrState = (enabled) async {
      setArgs.add(enabled);
      return true;
    };

    await DisplayGuard.markHdrAutoEnabled();
    await DisplayGuard.recoverOnStartup();

    expect(setArgs, isEmpty, reason: 'nothing to restore when HDR is off');
    expect(await readMarker(), isNull, reason: 'marker is still removed');
  });

  test('corrupted marker: no throw, marker removed, setHdrState not called',
      () async {
    final setArgs = <bool>[];
    DisplayGuard.setHdrState = (enabled) async {
      setArgs.add(enabled);
      return true;
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_markerKey, '{not-valid-json');

    await expectLater(DisplayGuard.recoverOnStartup(), completes);

    expect(setArgs, isEmpty,
        reason: 'a broken marker must not trigger an HDR change');
    expect(await readMarker(), isNull, reason: 'broken marker is removed');
  });
}
