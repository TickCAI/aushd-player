import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitType;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/release.dart';
import '../../core/host.dart';

final class AppUpdate {
  const AppUpdate({
    required this.tag,
    required this.name,
    required this.download,
    required this.size,
    this.sha256 = '',
    this.notes = '',
  });

  final String tag;
  final String name;
  final Uri download;
  final int size;
  final String sha256;
  final String notes;
}

final class UpdateNotAllowed implements Exception {
  const UpdateNotAllowed();
}

/// Reads release metadata from the self-hosted AusHD distribution service
/// instead of the upstream author's GitHub releases.
abstract final class Updater {
  static const _channel = MethodChannel('zerk/updater');

  static const playStore = bool.fromEnvironment('PLAY_STORE');
  static bool get supported => !playStore && (Host.isWindows || Host.isAndroid);

  static String get _platform =>
      Host.isWindows ? 'windows' : Host.isAndroid ? 'androidtv' : 'linux';

  static String _endpoint(String path) {
    final base = Uri.parse(Release.distributionApi);
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$prefix$path').toString();
  }

  static Future<AppUpdate?> check() async {
    final url = Uri.parse(_endpoint('/api/releases/latest')).replace(
      queryParameters: {
        'platform': _platform,
        'channel': Release.channel,
        'current': Release.tag,
      },
    );
    final res = await http
        .get(url, headers: {'accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 204 || res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw HttpException('Distribution server answered ${res.statusCode}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    if (json is! Map || json['tag'] is! String || json['download'] is! String) return null;
    if (json['available'] == false || json['tag'] == Release.tag) return null;
    final tag = '${json['tag']}';
    final name = (json['name'] as String?)?.trim() ?? '';
    return AppUpdate(
      tag: tag,
      name: name.isEmpty ? tag : name,
      download: Uri.parse('${json['download']}'),
      size: (json['size'] as num?)?.toInt() ?? 0,
      sha256: '${json['sha256'] ?? ''}',
      notes: '${json['notes'] ?? ''}',
    );
  }

  static Future<File> download(
    AppUpdate update, {
    void Function(double progress)? onProgress,
  }) async {
    final asset = p.basename(update.download.path);
    final name = asset.isEmpty ? 'aushd-update.bin' : asset;
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'aushd_update'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, name));
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', update.download));
      if (res.statusCode != 200) throw HttpException('Download answered ${res.statusCode}');
      final total = res.contentLength ?? update.size;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && received != total) {
        throw const HttpException('The download was cut short');
      }
      if (update.sha256.isNotEmpty) {
        final digest = await sha256.bind(file.openRead()).last;
        if (digest.toString().toLowerCase() != update.sha256.toLowerCase()) {
          await file.delete();
          throw const HttpException('Checksum mismatch: download was discarded.');
        }
      }
      debugPrint('[update] downloaded $received bytes to ${file.path}');
      return file;
    } finally {
      client.close();
    }
  }

  static Future<void> install(File file) async {
    if (Host.isAndroid) {
      if (await _channel.invokeMethod<bool>('canInstall') != true) {
        await _channel.invokeMethod('allowInstalls');
        throw const UpdateNotAllowed();
      }
      await _channel.invokeMethod('install', file.path);
      return;
    }
    await Process.start(
      file.path,
      ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    await ServicesBinding.instance.exitApplication(AppExitType.required);
  }
}
