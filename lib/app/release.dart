abstract final class Release {
  /// UI-redesign branch test series (v0.1 → v0.2 → …). Test packages ship
  /// through a separate channel and never trigger the self-hosted updater.
  ///
  /// pubspec.yaml intentionally keeps a monotonic versionCode so a test build
  /// can still be installed over v1.0.1 on Android; the user-visible version
  /// is this one, not the pubspec version.
  static const name = 'AusHD Player 0.1 测试版';
  static const tag = 'v0.1';
  static const channel = String.fromEnvironment('AUSHD_CHANNEL', defaultValue: 'beta');
  static const distributionApi =
      String.fromEnvironment('AUSHD_DIST_URL', defaultValue: '');
  static const hub = String.fromEnvironment('AUSHD_HUB_URL', defaultValue: '');

  /// Default TMDB API key so metadata works out of the box for this
  /// distribution. Users can override it in Settings; a build can replace it
  /// with --dart-define=AUSHD_TMDB_KEY=...
  static const tmdbApiKey =
      String.fromEnvironment('AUSHD_TMDB_KEY', defaultValue: '5c164a7eb020764869811ddc6177bb19');

  /// Reject empty values, malformed URLs and documentation placeholders so a
  /// misconfigured CI run can never ship a client pointing at a dead domain.
  static bool isUsableUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    const reserved = ['example.com', 'example.org', 'example.net', 'invalid'];
    for (final domain in reserved) {
      if (host == domain || host.endsWith('.$domain')) return false;
    }
    return true;
  }

  static bool get distributionConfigured => isUsableUrl(distributionApi);
  static bool get hubConfigured => isUsableUrl(hub);

  /// Kept for diagnostics / release links. The updater no longer queries the
  /// upstream GitHub repository directly (see services/updater/updater.dart).
  static const repository = 'aushd/aushd-player';
}
