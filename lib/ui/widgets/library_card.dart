import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../data/catalog_api.dart';
import '../../l10n/l10n.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'mixed_cards.dart' show spotlightWidth;
import 'net_image.dart';

/// Library tiles use the same 640x360 spotlight size as "Recommended for you".
/// A 380-wide landscape card made a server library look like a shrunken poster
/// and cut off the library name.
const double libraryCardWidth = spotlightWidth;

/// A wide tile for a real Emby/Jellyfin library (a `CollectionFolder`).
///
/// Artwork comes straight from the server: a real backdrop from an item inside
/// the library is preferred, because `ImageTags.Primary` is usually an
/// auto-generated tall collage of movie posters. Whatever the source, the image
/// is shown *uncropped* (`BoxFit.contain`) over a blurred copy of itself, so a
/// vertical cover never has its titles sliced off by a 16:9 crop.
class LibraryCard extends StatelessWidget {
  const LibraryCard({
    super.key,
    required this.view,
    this.width = libraryCardWidth,
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
    final cover = catalog.libraryArtwork(view, width: (width * 1.6).round());
    final logo = view.logoImageTag == null
        ? null
        : catalog.image(view.id, ImageKind.logo, tag: view.logoImageTag, width: 500);
    final count = view.itemCount;
    final overview = view.overview?.trim();
    final titleText = Text(view.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Zt.title);

    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      onFocusChange: (focused) {
        if (focused) onFocus?.call();
      },
      builder: (context, focused) => FocusFrame(
        focused: focused,
        scale: 1.04,
        radius: Zs.radiusLarge,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(fit: StackFit.expand, children: [
            if (cover != null) ...[
              // Blurred, full-bleed underlay fills the letterbox when the
              // server only has a tall poster collage.
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                child: NetImage(url: cover, width: width, height: height, fit: BoxFit.cover),
              ),
              const DecoratedBox(decoration: BoxDecoration(color: Color(0x59000000))),
            ],
            // The actual artwork, complete and uncropped.
            NetImage(
              url: cover,
              width: width,
              height: height,
              fit: BoxFit.contain,
              fallback: TitleArt(title: view.name, icon: Icons.video_library_outlined),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xF0000000), Color(0x99000000), Color(0x00000000)],
                  stops: [0.0, 0.45, 0.85],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (logo != null)
                    SizedBox(
                      height: 76,
                      width: width * 0.55,
                      child: NetImage(
                        url: logo,
                        width: width * 0.55,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomLeft,
                        fallback: titleText,
                      ),
                    )
                  else
                    titleText,
                  const SizedBox(height: 10),
                  MetaLine(
                    [typeLabel(view.collectionType, l10n), if (count != null && count > 0) l10n.filmCount(count)],
                    style: Zt.caption.copyWith(color: Zc.textMuted),
                  ),
                  if (overview != null && overview.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      overview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Zt.caption.copyWith(color: Zc.textMuted, height: 1.35),
                    ),
                  ],
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
    );
  }
}
