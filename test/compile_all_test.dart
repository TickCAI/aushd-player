// Compile gate. `flutter analyze` only resolves names; it does not prove the
// app builds. Importing the entry point makes dart2kernel compile the entire
// transitive application graph (shell -> every page -> data/playback layer),
// so a broken import anywhere in the app fails here in seconds, without any
// platform SDK or native toolchain.
import 'package:flutter_test/flutter_test.dart';
import 'package:zerk_play/app/release.dart' show Release;
import 'package:zerk_play/data/tmdb_api.dart' show TmdbApi;
import 'package:zerk_play/main.dart' as app;
import 'package:zerk_play/ui/pages/hero.dart' show HeroPanel;
import 'package:zerk_play/ui/pages/home_page.dart' show HomePage;
import 'package:zerk_play/ui/pages/library_page.dart' show LibraryPage;

void main() {
  test('whole application compiles and exposes its entry point', () {
    expect(app.main, isA<Function>());
    expect(HomePage.new, isA<Function>());
    expect(LibraryPage.new, isA<Function>());
    expect(HeroPanel.new, isA<Function>());
    expect(TmdbApi.new, isA<Function>());
  });

  test('version has a single source of truth', () {
    expect(Release.name, 'AusHD Player ${Release.version}');
    expect(Release.tag, 'v${Release.version}');
  });
}
