import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // `flutter test` runs with the package root as the working directory, so the
  // relative lib/ paths below resolve to the checked-out sources.
  const osdImport = 'ui/player/player_osd.dart';
  const navigatorPush = '_navigator.push';
  const osdRoute = 'PlayerOsdRoute(';

  const backendPaths = <String>[
    'lib/playback/mpv/mpv_backend.dart',
    'lib/playback/media3/media3_backend.dart',
  ];
  const platformPlayerPath = 'lib/playback/platform_player.dart';

  String readSource(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue,
        reason: '$path must exist (run flutter test from the package root)');
    return file.readAsStringSync();
  }

  test('playback layer does not import the player OSD UI', () {
    for (final path in <String>[...backendPaths, platformPlayerPath]) {
      expect(readSource(path), isNot(contains(osdImport)),
          reason: '$path must not depend on the player OSD UI');
    }
  });

  test('backends do not push routes or build the OSD route themselves', () {
    for (final path in backendPaths) {
      final source = readSource(path);
      expect(source, isNot(contains(navigatorPush)),
          reason: '$path must not push routes through a navigator');
      expect(source, isNot(contains(osdRoute)),
          reason: '$path must not construct PlayerOsdRoute');
    }
  });
}
