import 'package:flutter/widgets.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../l10n/l10n.dart';
import '../../playback/live_session.dart';
import '../../playback/platform_player.dart';
import '../../playback/playback_session.dart';
import '../../playback/player_settings.dart';
import '../../playback/trailer/trailer_player.dart';
import '../widgets/common.dart';
import '../widgets/profile_widgets.dart';
import '../widgets/trailer.dart';
import 'artwork.dart';

final class PlaybackOutcome {
  const PlaybackOutcome(this.reason, this.lastItem);

  final PlaybackEndReason reason;
  final EmbyItem? lastItem;
}

bool _playing = false;
DateTime? _playingSince;

const _launchLockTimeout = Duration(seconds: 30);

bool get playbackActive => _playing;

final playbackActiveNotifier = ValueNotifier(false);

bool get liveActive => _live;
bool _live = false;

void _setPlaying(bool v) {
  _playing = v;
  _playingSince = v ? DateTime.now() : null;
  playbackActiveNotifier.value = v;
}

/// Returns false when the caller should NOT start a new playback, because a
/// previous launch is still in flight. A launch that never returned (a stuck
/// platform channel, for instance) must not lock the whole session forever.
bool _acquireLaunchLock() {
  if (!_playing) return true;
  final started = _playingSince;
  if (started != null && DateTime.now().difference(started) > _launchLockTimeout) {
    debugPrint('[playback] stale launch lock after ${DateTime.now().difference(started).inSeconds}s: resetting');
    _setPlaying(false);
    return true;
  }
  debugPrint('[playback] ignored: a previous launch is still active');
  return false;
}

Future<PlaybackOutcome?> playItem(
  BuildContext context,
  EmbyItem item, {
  Duration? start,
  String? mediaSourceId,
  int? audioIndex,
  int? subtitleIndex,
}) async {
  if (!_acquireLaunchLock()) return null;
  _setPlaying(true);
  final l10n = context.l10n;
  try {
    final services = AppServicesScope.read(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    TrailerController.suspendAll();
    debugPrint('[playback] launching ${item.type} ${item.id}');
    await TrailerPlayer.stopAll().timeout(const Duration(seconds: 5), onTimeout: () {
      debugPrint('[playback] stopping trailers timed out');
      return Future<void>.value();
    });
    final target = item.isSeries || item.isSeason ? await services.catalog.episodeToPlay(item) : item;
    if (target == null) return null;
    // MediaSources must come straight from Emby. Localization can queue behind
    // background TMDB work and used to leave the play button unresponsive.
    final full = target.mediaSources.isNotEmpty || target.isChannel
        ? target
        : await services.catalog.item(target.id, localizeMetadata: false);
    final settings = await PlayerSettings.load();
    final acceptBadCerts = services.settings.acceptInvalidCertificates;
    final session = PlaybackSession(
      player: createPlayer(
        navigator: navigator,
        settings: settings,
        acceptInvalidCertificates: acceptBadCerts,
        l10n: l10n,
      ),
      api: services.playback,
      artwork: (item) => (
        backdrop: services.catalog.backdrop(item),
        logo: services.catalog.logo(item),
        still: services.catalog.landscape(item, width: 640),
      ),
      localize: services.catalog.localize,
      together: services.together,
      avatarOf: (member) => memberAvatar(services, member),
      fetchItem: (id) => services.catalog.item(id, localizeMetadata: false),
      settings: settings,
      l10n: l10n,
      acceptInvalidCertificates: acceptBadCerts,
      versionPreferences: services.settings.versionPreferences,
      onVersionChosen: (scope, key) {
        final prefs = Map<String, String>.from(services.settings.versionPreferences)..[scope] = key;
        services.updateSettings(services.settings.copyWith(versionPreferences: prefs));
      },
    );
    final reason = await session.run(PlaybackRequest(
      full,
      start: start,
      mediaSourceId: mediaSourceId,
      audioIndex: audioIndex,
      subtitleIndex: subtitleIndex,
    ));
    services.markLibraryChanged();
    return PlaybackOutcome(reason, session.lastItem ?? full);
  } catch (e, stack) {
    // Without this, an mpv initialization failure (bad gpu-api, missing
    // native window, etc.) looked exactly like "clicking play does nothing".
    debugPrint('[playback] launch failed: $e\n$stack');
    if (context.mounted) showToast(context, l10n.playbackFailedWith('$e'));
    return null;
  } finally {
    _setPlaying(false);
  }
}

Future<void> playChannel(BuildContext context, ZapList zap, int index) async {
  final c = zap.channels[index];
  final sources = ZapList.sourcesOf(c);
  if (sources.isEmpty) return;
  await playShared(context, LiveShare(key: LiveShare.keyOf(sources.first), title: c.name, sources: sources),
      zap: zap, channel: index);
}

Future<void> playShared(BuildContext context, LiveShare share, {ZapList? zap, int channel = 0}) async {
  if (!_acquireLaunchLock()) return;
  _setPlaying(true);
  _live = true;
  final l10n = context.l10n;
  try {
    final services = AppServicesScope.read(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    TrailerController.suspendAll();
    await TrailerPlayer.stopAll().timeout(const Duration(seconds: 5), onTimeout: () {
      debugPrint('[playback] stopping trailers timed out');
      return Future<void>.value();
    });
    final settings = await PlayerSettings.load();
    final session = LiveSession(
      player: createPlayer(
        navigator: navigator,
        settings: settings,
        acceptInvalidCertificates: services.settings.acceptInvalidCertificates,
        l10n: l10n,
      ),
      server: services.xtream,
      title: share.title,
      sources: share.sources,
      settings: settings,
      l10n: l10n,
      together: services.together,
      share: share,
      zap: zap,
      channel: channel,
    );
    await session.run(share.first);
  } catch (e, stack) {
    debugPrint('[playback] shared launch failed: $e\n$stack');
    if (context.mounted) showToast(context, l10n.playbackFailedWith('$e'));
  } finally {
    _live = false;
    _setPlaying(false);
  }
}

