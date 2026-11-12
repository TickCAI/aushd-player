import '../l10n/app_localizations.dart';
import '../core/host.dart';
import 'media3/media3_backend.dart';
import 'mpv/mpv_backend.dart';
import 'osd_presenter.dart';
import 'player_backend.dart';
import 'player_settings.dart';

PlayerBackend createPlayer({
  required OsdPresenter presenter,
  required PlayerSettings settings,
  required bool acceptInvalidCertificates,
  required L10n l10n,
}) =>
    Host.isAndroid
        ? Media3Backend(presenter: presenter, settings: settings)
        : MpvBackend(presenter: presenter, settings: settings, l10n: l10n, acceptInvalidCertificates: acceptInvalidCertificates);
