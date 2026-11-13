import 'package:flutter/material.dart';

import '../../core/emby/models/emby_item.dart';
import '../../data/seerr_api.dart';
import '../core/navigation.dart';
import '../theme/tokens.dart' show buildTheme;
import 'collection_page.dart';
import 'details_page.dart';
import 'person_page.dart';
import 'request_page.dart';
import 'series_page.dart';

/// 经典页面是为硬编码深色主题写的。它们平时吃 `MaterialApp.theme`；
/// 但新壳（theme2）里 Navigator 位于 MaterialApp 之下、浅色 Theme 之上，
/// push 进来的经典页会拿到浅色主题，出现"白底白字"。
/// 统一在这里包一层深色，保证两条入口视觉一致。
Widget _dark(Widget page) => Theme(data: buildTheme(), child: page);

Route<void> detailsRoute(EmbyItem item) =>
    tvRoute(_dark(DetailsPage(itemId: item.id, initial: item)), name: 'details:${item.id}');

Route<void> itemRoute(EmbyItem item) {
  if (item.isSeries) return tvRoute(_dark(SeriesPage(seriesId: item.id)), name: 'series:${item.id}');
  if (item.isSeason && item.seriesId != null) {
    return tvRoute(
      _dark(SeriesPage(seriesId: item.seriesId!, initialSeasonId: item.id)),
      name: 'series:${item.seriesId}',
    );
  }
  if (item.isCollection) {
    final key = item.id.isEmpty ? 'tmdb${item.tmdbId}' : item.id;
    return tvRoute(_dark(CollectionPage(collection: item)), name: 'collection:$key');
  }
  return detailsRoute(item);
}

void openItem(BuildContext context, EmbyItem item) => Navigator.of(context).push(itemRoute(item));

void openSeries(BuildContext context, String seriesId, {String? focusEpisodeId}) {
  Navigator.of(context).push(
    tvRoute(
      _dark(SeriesPage(seriesId: seriesId, focusEpisodeId: focusEpisodeId)),
      name: 'series:$seriesId',
    ),
  );
}

void openRequest(BuildContext context, SeerrMedia media) {
  Navigator.of(context).push(tvRoute(_dark(RequestPage(media: media)), name: 'request:${media.key}'));
}

void openPerson(BuildContext context, Person person) {
  Navigator.of(context).push(tvRoute(_dark(PersonPage(person: person)), name: 'person:${person.id}'));
}
