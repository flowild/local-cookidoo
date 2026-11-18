import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const defaultAccent = 0xff234d3c;
const _preferences = MethodChannel('de.rezeptgarten/preferences');

class AppearanceController extends ValueNotifier<({bool dark, int accent})> {
  AppearanceController() : super((dark: false, accent: defaultAccent));
  bool _closed = false;
  bool _changed = false;

  Future<void> restore() async {
    try {
      final stored = await _preferences.invokeMapMethod<String, Object?>(
        'appearance',
      );
      if (_closed || _changed || stored == null) return;
      final color = stored['accent'];
      value = (
        dark: stored['dark'] == true,
        accent: color is int && color >= 0xff000000 && color <= 0xffffffff
            ? color
            : defaultAccent,
      );
    } on PlatformException {
      // Keep the default appearance if Android storage is unavailable.
    } on MissingPluginException {
      // Preferences are optional in the widget harness.
    }
  }

  Future<void> update({bool? dark, int? accent}) async {
    _changed = true;
    value = (dark: dark ?? value.dark, accent: accent ?? value.accent);
    try {
      await _preferences.invokeMethod<void>('setAppearance', {
        'dark': value.dark,
        'accent': value.accent,
      });
    } on MissingPluginException {
      // Appearance remains available in memory in the widget harness.
    }
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
