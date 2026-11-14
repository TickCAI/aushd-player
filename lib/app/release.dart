abstract final class Release {
  /// Version shown in Settings and sent to the distribution service.
  static const version = '1.0.5';
  static const name = 'AusHD Player $version';
  static const tag = 'v$version';

  /// Build-time configuration. GitHub Actions injects these with --dart-define.
  ///
  /// An empty value is a valid, intentional state: "no self-hosted service is
  /// configured". In that state the updater, hub link and log upload stay
  /// dormant instead of talking to a placeholder host or to the upstream
  /// author's services. Local development may point these at 127.0.0.1.
  static const channel = String.fromEnvironment('AUSHD_CHANNEL', defaultValue: 'stable');
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
