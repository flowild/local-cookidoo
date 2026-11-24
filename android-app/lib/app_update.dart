import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppUpdateController extends ChangeNotifier {
  static const _channel = MethodChannel('de.rezeptgarten/update');

  String? status;
  String? message;
  bool available = false;
  bool checking = false;
  bool downloading = false;
  bool _disposed = false;

  Future<void> check() async {
    if (checking || downloading) return;
    checking = true;
    message = null;
    notifyListeners();
    var checkedStatus = 'Der Updatestatus konnte nicht geprüft werden.';
    var newer = false;
    try {
      final metadata = await _channel.invokeMapMethod<String, Object?>(
        'checkUpdate',
      );
      if (metadata case {
        'version': final String version,
        'build': final int build,
        'installedBuild': final int installedBuild,
      }) {
        newer = build > installedBuild;
        checkedStatus = switch (build.compareTo(installedBuild)) {
          > 0 => 'Update verfügbar · Version $version (Build $build)',
          0 => 'Deine App ist aktuell.',
          _ => 'Deine App ist neuer als der Build auf dem Server.',
        };
      }
    } on PlatformException catch (error) {
      checkedStatus = error.message ?? checkedStatus;
    } on MissingPluginException {
      checkedStatus = 'Die Updateprüfung ist nur in der Android-App verfügbar.';
    } finally {
      checking = false;
      if (!_disposed) {
        status = checkedStatus;
        available = newer;
        notifyListeners();
      }
    }
  }

  Future<void> install() async {
    if (!available || checking || downloading) return;
    downloading = true;
    message = null;
    notifyListeners();
    try {
      final result = await _channel.invokeMethod<String>('downloadAndInstall');
      if (result != 'installerOpened') {
        message = 'Der Android-Installer konnte nicht geöffnet werden.';
      }
    } on PlatformException catch (error) {
      message = error.message ?? 'Die APK konnte nicht geladen werden.';
    } on MissingPluginException {
      message = 'Der APK-Download ist nur in der Android-App verfügbar.';
    } finally {
      downloading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
