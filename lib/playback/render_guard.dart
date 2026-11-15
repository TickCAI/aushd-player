import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_settings.dart';

/// Keeps playback off a graphics backend that has crashed the process.
///
/// The AMD D3D11 user-mode driver (`amdxx64.dll`) can fault while a swapchain
/// is resized by a fullscreen switch or destroyed when playback exits. That is
/// a native crash: no Dart exception, no clean shutdown, and the log simply
/// stops. A marker is written while a playback session is alive and cleared
/// shortly after it ends; if the marker survives into the next launch, the
/// renderer is stepped down to a backend that avoids the D3D11 presentation
/// path. A graphics API that cannot even initialize is stepped down at once.
abstract final class RenderGuard {
  static const _key = 'render.guard.v1';

  /// Give the native VO teardown time to finish. A crash in
  /// `vo/gpu-next/win32 uninit` happens after the user pressed back but before
  /// mpv is gone, so clearing the marker immediately would hide that failure.
  static const _teardownGrace = Duration(seconds: 20);

  static Timer? _clearTimer;
  static int _steps = 0;

  /// Run once at startup, before any player is created.
  static Future<void> recoverOnStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      Map<String, dynamic> state = <String, dynamic>{};
      if (raw != null) {
        try {
          state = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {}
      }
      final steps = state['steps'];
      _steps = steps is int ? steps : 0;

      final current = await PlayerSettings.load();
      var next = current;

      // Settings written by 1.0.4-1.0.7 still carry the old D3D11 default and
      // have no "the user picked this" flag. Move those installs to Vulkan,
      // which uses a different driver path entirely.
      final migrated = migrateDefault(current);
      if (!identical(migrated, current)) {
        next = migrated;
        debugPrint('[render-guard] moving untouched D3D11 default to Vulkan');
      }

      if (state['playing'] == true) {
        _steps += 1;
        next = fallback(next, _steps);
        debugPrint('[render-guard] previous run died during playback (crash $_steps); '
            'renderer now ${next.safeGpuApi}/${next.hwdec}');
      }

      if (!identical(next, current)) await next.save();
      await _write(prefs, playing: false);
    } catch (e) {
      debugPrint('[render-guard] recovery failed: $e');
    }
  }

  /// Pure default migration, kept separate so it can be unit tested. Only an
  /// untouched D3D11 default is moved; a manual pick is never overwritten.
  static PlayerSettings migrateDefault(PlayerSettings current) =>
      current.gpuApiAuto && current.safeGpuApi == 'd3d11'
          ? current.copyWith(gpuApi: 'vulkan')
          : current;

  /// Pure step-down policy, kept separate so it can be unit tested.
  static PlayerSettings fallback(PlayerSettings current, int crashes) {
    // First crash: move off D3D11 but keep hardware decoding. Any further
    // crash (or a crash already on Vulkan) goes to the most conservative
    // combination: WGL OpenGL, legacy VO and software decoding.
    if (crashes <= 1 && current.safeGpuApi != 'vulkan') {
      return current.copyWith(gpuApi: 'vulkan', hwdec: 'auto-safe', gpuApiAuto: false);
    }
    return current.copyWith(gpuApi: 'opengl', videoOutput: 'gpu', hwdec: 'no', gpuApiAuto: false);
  }

  /// Called when mpv could not be created or initialized at all (missing ICD,
  /// unsupported GPU context, ...). Do not wait for a crash to step down.
  static Future<void> notePlaybackFailure() async {
    try {
      final current = await PlayerSettings.load();
      if (current.safeGpuApi == 'opengl' && current.hwdec == 'no') return;
      final next = fallback(current, 99);
      await next.save();
      debugPrint('[render-guard] mpv failed to start on ${current.safeGpuApi}; '
          'renderer stepped down to ${next.gpuApi}/${next.hwdec}');
    } catch (e) {
      debugPrint('[render-guard] could not step down after a failed start: $e');
    }
  }

  /// Playback session is starting. Cancel any pending clear so a quick
  /// play -> stop -> play sequence cannot erase the marker mid-session.
  static Future<void> markPlaybackStarted() async {
    _clearTimer?.cancel();
    _clearTimer = null;
    try {
      await _write(await SharedPreferences.getInstance(), playing: true);
    } catch (e) {
      debugPrint('[render-guard] could not persist playback marker: $e');
    }
  }

  /// Playback ended (or failed). Keep the marker for a short grace period so a
  /// native fault during VO teardown is still attributed to this session.
  static void markPlaybackFinished() {
    _clearTimer?.cancel();
    _clearTimer = Timer(_teardownGrace, () async {
      _clearTimer = null;
      await finishClean();
    });
  }

  /// Clean application exit. A native crash never reaches this callback, so a
  /// surviving marker always means the previous run died unexpectedly.
  static Future<void> finishClean() async {
    _clearTimer?.cancel();
    _clearTimer = null;
    try {
      await _write(await SharedPreferences.getInstance(), playing: false);
    } catch (e) {
      debugPrint('[render-guard] could not clear playback marker: $e');
    }
  }

  static Future<void> _write(SharedPreferences prefs, {required bool playing}) async {
    await prefs.setString(_key, jsonEncode({
          'playing': playing,
          'steps': _steps,
          'at': DateTime.now().toIso8601String(),
        }));
  }
}
