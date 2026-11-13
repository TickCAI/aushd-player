import 'package:flutter/material.dart';

import '../../core/host.dart';

/// The three form factors AusHD 2.0 ships as one design language.
///
/// The distinction is deliberately based on logical pixels, not platform
/// channels: it is deterministic in widget tests and needs no native code.
/// TV sets are large landscape Android displays (>= 900dp shortest side);
/// phones are small Android displays (< 600dp); anything in between uses the
/// desktop-like rail shell (tablets), matching CineIsle's >= 600dp rail rule.
enum DeviceForm {
  desktop,
  phone,
  tv;

  bool get isTv => this == DeviceForm.tv;
  bool get isPhone => this == DeviceForm.phone;
  bool get usesRail => this == DeviceForm.desktop;
  bool get usesDock => this == DeviceForm.phone;
  bool get usesTopBar => this == DeviceForm.tv;
}

abstract final class DeviceFormX {
  /// Kept as a settable override so tests and CI builds can force a shell
  /// without a real device (e.g. `--dart-define=AUSHD_FORM=phone`).
  static const forced = String.fromEnvironment('AUSHD_FORM', defaultValue: '');

  static DeviceForm of(BuildContext context) {
    final forcedForm = switch (forced) {
      'desktop' => DeviceForm.desktop,
      'phone' => DeviceForm.phone,
      'tv' => DeviceForm.tv,
      _ => null,
    };
    if (forcedForm != null) return forcedForm;
    if (Host.isDesktop) return DeviceForm.desktop;
    final media = MediaQuery.of(context);
    final shortest = media.size.shortestSide;
    if (Host.isAndroid &&
        media.orientation == Orientation.landscape &&
        shortest >= 900) {
      return DeviceForm.tv;
    }
    if (shortest < 600) return DeviceForm.phone;
    // Tablets get the rail shell: they have room for it and no TV D-pad.
    return DeviceForm.desktop;
  }
}
