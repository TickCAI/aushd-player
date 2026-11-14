import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../data/catalog_api.dart';
import '../../l10n/l10n.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'net_image.dart';

/// A wide 16:9 tile for a real Emby/Jellyfin library (a `CollectionFolder`).
///
/// Library artwork is read straight from the server. It deliberately does NOT
/// go through the movie artwork pipeline, because localized TMDB posters would
/// otherwise be pasted onto a library tile, and `ImageTags.Primary` is often an
/// auto-generated collage of unrelated movie posters.
class LibraryCard extends StatelessWidget {
  const LibraryCard({
    super.key,
    required this.view,
    this.width = Zs.landscapeWidth,
    this.autofocus = false,
    this.onFocus,
    this.onSelect,
  });

  final LibraryView view;
  final double width;
  final bool autofocus;
  final VoidCallback? onFocus;
  final VoidCallback? onSelect;

  static String typeLabel(String? type, L10n l10n) {
    final zh = ContentZh.enabled;
    return switch (type) {
      'movies' || 'boxsets' => l10n.movies,
      'tvshows' => l10n.shows,
      'music' => zh ? '音乐' : 'Music',
      'photos' || 'homevideos' => zh ? '相册' : 'Photos',
      'books' => zh ? '图书' : 'Books',
      'livetv' => zh ? '直播电视' : 'Live TV',
      'mixed' => zh ? '混合内容' : 'Mixed',
      'playlists' => zh ? '播放列表' : 'Playlists',
      _ => zh ? '媒体库' : 'Library',
    };
  }

  @override
  Widget build(BuildContext context) {
    final catalog = AppServicesScope.read(context).catalog;
    final l10n = context.l10n;
    final height = width * 9 / 16;
    final pixels = (width * 1.5).round();

    Uri? cover;
    if (view.backdropImageTags.isNotEmpty) {
      cover = catalog.image(view.id, ImageKind.backdrop, tag: view.backdropImageTags.first, width: pixels);
    } else if (view.thumbImageTag != null) {
      cover = catalog.image(view.id, ImageKind.thumb, tag: view.thumbImageTag, width: pixels);
    } else if (view.imageTag != null) {
      cover = catalog.image(view.id, ImageKind.primary, tag: view.imageTag, width: pixels);
    }
    final logo = view.logoImageTag == null
        ? null
        : catalog.image(view.id, ImageKind.logo, tag: view.logoImageTag, width: 400);
    final count = view.itemCount;

    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      onFocusChange: (focused) {
        if (focused) onFocus?.call();
      },
      builder: (context, focused) => SizedBox(
        width: width,
        child: FocusFrame(
          focused: focused,
          scale: 1.035,
          radius: Zs.radiusLarge,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(fit: StackFit.expand, children: [
              NetImage(
                url: cover,
                width: width,
                height: height,
                fit: BoxFit.cover,
                fallback: TitleArt(title: view.name, icon: Icons.video_library_outlined),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x11000000), Color(0x33000000), Color(0xE6000000)],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (logo != null)
                      SizedBox(
                        height: 46,
                        width: width * 0.55,
                        child: NetImage(
                          url: logo,
                          width: width * 0.55,
                          fit: BoxFit.contain,
                          alignment: Alignment.topLeft,
                          fallback: const SizedBox.shrink(),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      view.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Zt.label.copyWith(fontSize: 25, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    MetaLine(
                      [typeLabel(view.collectionType, l10n), if (count != null && count > 0) l10n.filmCount(count)],
                      style: Zt.caption.copyWith(fontSize: 17, color: Zc.textMuted),
                    ),
                  ],
                ),
              ),
              if (focused)
                Positioned(
                  top: 14,
                  right: 14,
                  child: Pill(ContentZh.enabled ? '进入' : 'Open', icon: Icons.arrow_forward_rounded, color: Zc.accent),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
