abstract final class Release {
  /// Version shown in Settings and sent to the distribution service.
  static const name = 'AusHD Player 1.0.0';
  static const tag = 'v1.0.0';

  /// Build-time configuration. GitHub Actions injects these with --dart-define.
  /// Local defaults point at a local distribution server so a dev build never
  /// talks to the upstream author's services.
  static const channel = String.fromEnvironment('AUSHD_CHANNEL', defaultValue: 'stable');
  static const distributionApi =
      String.fromEnvironment('AUSHD_DIST_URL', defaultValue: 'http://127.0.0.1:8787');
  static const hub = String.fromEnvironment('AUSHD_HUB_URL', defaultValue: 'http://127.0.0.1:8787');

  /// Kept for diagnostics / release links. The updater no longer queries the
  /// upstream GitHub repository directly (see services/updater/updater.dart).
  static const repository = 'aushd/aushd-player';
}
