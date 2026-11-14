import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/log/logging_http_client.dart';
import '../core/tv_scale.dart';
import 'image_disk_cache.dart';

/// A small URL-level backup registry for artwork.
///
/// Chinese TMDB artwork is preferred on a Chinese UI, but the CDN can fail on
/// domestic networks. `Artwork` registers the user's own Emby/Jellyfin image as
/// a backup for each localized URL, so a failed CDN request silently falls back
/// instead of leaving an empty card. No widget needs to know about the backup.
abstract final class ArtworkFallback {
  static const _maxEntries = 3000;
  static final Map<Uri, Uri> _byUrl = <Uri, Uri>{};

  static Uri? of(Uri url) => _byUrl[url];

  static void register(Uri primary, Uri? backup) {
    // A null backup means "no server image available": drop any stale mapping
    // instead of leaving the old (possibly deleted) URL in place.
    if (backup == null || backup == primary) {
      _byUrl.remove(primary);
      return;
    }
    // Evict the oldest entry. Clearing the whole table made in-flight images
    // lose their backup mid-scroll.
    if (_byUrl.length >= _maxEntries && !_byUrl.containsKey(primary)) {
      _byUrl.remove(_byUrl.keys.first);
    }
    _byUrl[primary] = backup;
  }

  static void clear() => _byUrl.clear();
}

@immutable
class NetImageProvider extends ImageProvider<NetImageProvider> {
  const NetImageProvider(this.url, {this.decodeWidth});

  final Uri url;
  final int? decodeWidth;

  static final _client = LoggingHttpClient(tag: 'image', quiet: true);

  @override
  Future<NetImageProvider> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(NetImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1,
      debugLabel: url.toString(),
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await _bytes();
    try {
      return await _decode(decode, bytes);
    } catch (error) {
      // TMDB logos are often SVG, which Flutter's image codec cannot decode.
      // Network-level fallback alone never caught these, so the logo simply
      // disappeared. Retry with the server's own artwork on decode failures.
      final backup = ArtworkFallback.of(url);
      if (backup == null || backup == url) rethrow;
      debugPrint('[image] decode fallback $url -> $backup ($error)');
      return _decode(decode, await _fetch(backup));
    }
  }

  Future<ui.Codec> _decode(ImageDecoderCallback decode, Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer, getTargetSize: (w, h) {
      final target = decodeWidth;
      if (target == null || w <= target) return ui.TargetImageSize(width: w, height: h);
      return ui.TargetImageSize(width: target);
    });
  }

  Future<Uint8List> _bytes() async {
    try {
      // Only URLs that actually have a server backup get the short timeout;
      // ordinary server/avatar images keep the full network budget.
      final hasBackup = ArtworkFallback.of(url) != null;
      return await _fetch(url, timeout: hasBackup ? const Duration(seconds: 8) : const Duration(seconds: 20));
    } catch (error) {
      final backup = ArtworkFallback.of(url);
      if (backup == null || backup == url) rethrow;
      debugPrint('[image] fallback $url -> $backup ($error)');
      final data = await _fetch(backup);
      // Cache under the primary URL too, otherwise every cold start waits the
      // full CDN timeout again before showing the server image.
      writeCachedImage(url, data);
      return data;
    }
  }

  Future<Uint8List> _fetch(Uri uri, {Duration timeout = const Duration(seconds: 20)}) async {
    final cached = await readCachedImage(uri);
    if (cached != null) return cached;
    final res = await _client.get(uri).timeout(timeout);
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      throw NetworkImageLoadException(statusCode: res.statusCode, uri: uri);
    }
    writeCachedImage(uri, res.bodyBytes);
    return res.bodyBytes;
  }

  @override
  bool operator ==(Object other) =>
      other is NetImageProvider && other.url == url && other.decodeWidth == decodeWidth;

  @override
  int get hashCode => Object.hash(url, decodeWidth);
}

class NetImage extends StatelessWidget {
  const NetImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fallback,
    this.fadeDuration = const Duration(milliseconds: 260),
  });

  final Uri? url;

  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? fallback;
  final Duration fadeDuration;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null) return fallback ?? const SizedBox.shrink();
    final ratio = TvScale.decodeRatio(context);
    final decode = width == null ? null : (width! * ratio).round();
    return Image(
      image: NetImageProvider(u, decodeWidth: decode),
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, error, _) {
        debugPrint('[image] $u: $error');
        return fallback ?? const SizedBox.shrink();
      },
      frameBuilder: (context, child, frame, sync) {
        if (sync) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: fadeDuration,
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
  }
}
