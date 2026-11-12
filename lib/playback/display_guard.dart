import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/windows/native_window.dart';

/// Crash-safe display guard.
///
/// Turning Windows HDR on for HDR videos is safe as long as it can be undone.
/// The in-memory restore paths only run on clean exits, so after a crash the
/// display can stay in HDR forever: on a monitor without proper HDR support
/// the whole desktop looks washed out, and the setting survives reboots.
///
/// This guard persists a marker the moment HDR is switched on and undoes it
/// on the next launch, no matter how the previous run ended.
abstract final class DisplayGuard {
  static const _key = 'display.guard.v1';

  // Platform-call seams. Production keeps the original NativeWindow behaviour;
  // tests swap these out so no real method-channel calls are made.
  @visibleForTesting
  static Future<DisplayHdrStatus> Function() status = NativeWindow.hdrStatus;

  @visibleForTesting
  static Future<bool> Function(bool enabled) setHdrState = NativeWindow.setHdr;

  @visibleForTesting
  static Future<bool> Function(bool enabled) waitForHdrState =
      (enabled) => NativeWindow.waitForHdr(enabled);

  /// Persist "we switched Windows HDR on for playback" before anything else
  /// can go wrong. The state we are replacing is known: HDR was off, because
  /// [PlaybackSession] only enables it when it was off.
  static Future<void> markHdrAutoEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key, jsonEncode({'hdr': true, 'at': DateTime.now().toIso8601String()}));
    } catch (e) {
      debugPrint('[display-guard] could not persist marker: $e');
    }
  }

  /// Called on every clean restore path (playback finished, app closing).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (e) {
      debugPrint('[display-guard] could not clear marker: $e');
    }
  }

  /// Undo whatever a previous run left behind. Called once at startup.
  static Future<void> recoverOnStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      await prefs.remove(_key);
      if ((jsonDecode(raw) as Map<String, dynamic>)['hdr'] != true) return;
      final hdrStatus = await status();
      if (!hdrStatus.enabled) return;
      debugPrint('[display-guard] previous run crashed with Windows HDR on; turning it off');
      await setHdrState(false);
      await waitForHdrState(false);
    } catch (e) {
      debugPrint('[display-guard] recovery failed: $e');
    }
  }
}
