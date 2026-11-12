import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../playback/media3/osd_model.dart';
import '../../playback/osd_presenter.dart';
import 'player_osd.dart';

final class NavigatorOsdPresenter implements OsdPresenter {
  NavigatorOsdPresenter(this._navigator);

  final NavigatorState _navigator;
  Route<void>? _route;

  @override
  void show({required OsdModel model, bool controls = true, Widget? background}) {
    final route = PlayerOsdRoute(model: model, controls: controls, background: background);
    _route = route;
    unawaited(_navigator.push(route));
  }

  @override
  void dismiss() {
    final route = _route;
    _route = null;
    if (route != null && route.isActive) _navigator.removeRoute(route);
  }
}
