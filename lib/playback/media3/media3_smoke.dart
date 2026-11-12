import '../osd_presenter.dart';
import '../player_settings.dart';
import '../player_smoke.dart';
import 'media3_backend.dart';

Future<void> runMedia3Smoke({required OsdPresenter presenter, bool subtitleBackground = false}) =>
    runPlayerSmoke(Media3Backend(presenter: presenter, settings: PlayerSettings(subtitleBackground: subtitleBackground)));
