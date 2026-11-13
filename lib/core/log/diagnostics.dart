import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/release.dart';
import '../host.dart';
import 'app_log.dart';

/// One-file, zero-dependency crash diagnostics bundle.
///
/// The export is deliberately plain text so it can be sent as-is (e.g. over a
/// chat app) without any archive tooling. It never dumps raw settings: only a
/// couple of non-sensitive facts (build mode, launch count, whether the HDR
/// crash-guard marker exists) are reported, and the marker's contents are
/// intentionally omitted. Every I/O operation is guarded so [export] can never
/// throw into the UI.
abstract final class Diagnostics {
  // Keep in sync with DisplayGuard's private key. We only check existence.
  static const _displayGuardKey = 'display.guard.v1';
  static const _launchCountKey = 'diagnostics.launch_count';

  /// Lightweight startup hook.
  ///
  /// AppLog already owns global error capture (FlutterError.onError /
  /// PlatformDispatcher.instance.onError), so this must NOT install another
  /// handler. It only logs readiness and bumps a best-effort launch counter
  /// used by [export] to report which run produced the bundle.
  static void install() {
    debugPrint('[diagnostics] ready');
    unawaited(_bumpLaunchCount());
  }

  static Future<void> _bumpLaunchCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = (prefs.getInt(_launchCountKey) ?? 0) + 1;
      await prefs.setInt(_launchCountKey, next);
    } catch (e) {
      debugPrint('[diagnostics] could not record launch count: $e');
    }
  }

  /// Build a single shareable diagnostics file and return its absolute path,
  /// or null if anything goes wrong. Never throws.
  static Future<String?> export() async {
    try {
      // Make sure recently buffered log lines (including a just-caught crash)
      // are on disk before we snapshot the file.
      await AppLog.flush();

      final buffer = StringBuffer()
        ..writeln('AusHD Player diagnostics')
        ..writeln('========================')
        ..writeln();

      // [1] version
      buffer
        ..writeln('--- [1] AusHD version ---')
        ..writeln('name: ${Release.name}')
        ..writeln('tag: ${Release.tag}')
        ..writeln('build: ${kReleaseMode ? 'release' : kProfileMode ? 'profile' : 'debug'}')
        ..writeln('kReleaseMode: $kReleaseMode')
        ..writeln('appLogVersion: ${AppLog.appVersion}')
        ..writeln();

      // [2] platform
      buffer
        ..writeln('--- [2] platform ---')
        ..writeln('defaultTargetPlatform: ${defaultTargetPlatform.name}')
        ..writeln('Host.isWindows: ${Host.isWindows}')
        ..writeln('Host.isAndroid: ${Host.isAndroid}')
        ..writeln('Host.isLinux: ${Host.isLinux}')
        ..writeln();

      // [3] time
      final now = DateTime.now();
      buffer
        ..writeln('--- [3] time ---')
        ..writeln('generatedAt: ${now.toIso8601String()}')
        ..writeln('localTime: $now')
        ..writeln();

      // Read the current log once and reuse it for sections 4/5/7.
      final logPath = AppLog.file;
      var lines = const <String>[];
      if (logPath != null) {
        try {
          final logFile = File(logPath);
          if (await logFile.exists()) {
            lines = const LineSplitter().convert(await logFile.readAsString());
          }
        } catch (e) {
          debugPrint('[diagnostics] could not read log file: $e');
        }
      }
      final hasLog = lines.isNotEmpty;

      // [4] system info: reuse the [system] lines AppLog.init() wrote.
      buffer.writeln('--- [4] system info ([system] lines) ---');
      if (!hasLog) {
        buffer.writeln('no log file');
      } else {
        final systemLines = lines.where((l) => l.contains('[system]')).toList();
        if (systemLines.isEmpty) {
          buffer.writeln('no [system] lines in log');
        } else {
          for (final line in systemLines) {
            buffer.writeln(line);
          }
        }
      }
      buffer.writeln();

      // [5] recent 400 log lines (tail).
      buffer.writeln('--- [5] recent log tail (last 400 lines) ---');
      if (!hasLog) {
        buffer.writeln('no log file');
      } else {
        final start = lines.length > 400 ? lines.length - 400 : 0;
        for (final line in lines.sublist(start)) {
          buffer.writeln(line);
        }
      }
      buffer.writeln();

      // [6] DisplayGuard marker: presence only, never its contents.
      final guardLine = await _displayGuardLine();
      buffer
        ..writeln('--- [6] DisplayGuard ---')
        ..writeln(guardLine)
        ..writeln();

      // [7] crash entries: [error] lines, capped at 50.
      buffer.writeln('--- [7] crash entries ([error], max 50) ---');
      final errors = lines.where((l) => l.contains('[error]')).take(50).toList();
      if (errors.isEmpty) {
        buffer.writeln('no [error] entries');
      } else {
        for (final line in errors) {
          buffer.writeln(line);
        }
      }
      buffer.writeln();

      // [8] session & desensitized settings note.
      final launchCount = await _launchCount();
      buffer
        ..writeln('--- [8] session & settings (desensitized) ---')
        ..writeln('launchCount: $launchCount')
        ..writeln('settings: not exported (no ui/metadata keys, tokens, secrets or account data)')
        ..writeln();

      final dirPath = AppLog.directory ?? Directory.systemTemp.path;
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final out = File('${dir.path}${Platform.pathSeparator}aushd-diagnostics-${_stamp(now)}.txt');
      await out.writeAsString(buffer.toString(), flush: true);

      // Per contract: flush the running log sink after a successful write.
      await AppLog.flush();
      return out.absolute.path;
    } catch (e) {
      debugPrint('[diagnostics] export failed: $e');
      return null;
    }
  }

  static Future<String> _displayGuardLine() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // getString avoids dumping the marker value; a non-string value would be
      // caught below anyway.
      final present = prefs.getString(_displayGuardKey) != null;
      return 'marker present: $present (contents intentionally not exported)';
    } catch (e) {
      return 'marker state unavailable: $e';
    }
  }

  static Future<int?> _launchCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_launchCountKey);
    } catch (_) {
      return null;
    }
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}
