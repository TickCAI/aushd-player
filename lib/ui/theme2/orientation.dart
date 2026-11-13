import 'package:flutter/services.dart';

import 'device_form.dart';

/// Runtime orientation policy.
///
/// The manifest now declares `unspecified`; this is the single place that
/// decides the final orientation. TV stays landscape (D-pad layout assumes
/// it), phones stay portrait for browsing but allow landscape so the player
/// can go full-screen, and desktops are untouched.
abstract final class ZOrientation {
  static const _tv = <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  static const _phone = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  static Future<void> apply(DeviceForm form) async {
    if (form == DeviceForm.desktop) return;
    await SystemChrome.setPreferredOrientations(form.isTv ? _tv : _phone);
  }
}
