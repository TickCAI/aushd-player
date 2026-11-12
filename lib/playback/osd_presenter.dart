import 'package:flutter/widgets.dart';
import 'media3/osd_model.dart';

/// Injected by the UI layer. Playback backends never build player-UI routes.
abstract interface class OsdPresenter {
  void show({required OsdModel model, bool controls = true, Widget? background});
  void dismiss();
}
