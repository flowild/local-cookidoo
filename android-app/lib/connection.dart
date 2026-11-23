import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'telegram_service.dart';

enum ConnectionMode { checking, local, telegram, offline }

class ConnectionController extends ChangeNotifier {
  ConnectionController(this.api, this.telegram);

  final RezeptgartenApi api;
  final TelegramService telegram;
  static const _network = MethodChannel('de.rezeptgarten/network');
  static const _changes = EventChannel('de.rezeptgarten/network_changes');
  StreamSubscription<dynamic>? _subscription;
  ConnectionMode mode = ConnectionMode.checking;
  bool hasPermission = false;
  String? error;
  int _generation = 0;
  int? _probingGeneration;
  bool _disposed = false;
  Map<String, dynamic>? _networkStatus;

  void start() {
    api.localAllowed = () => mode == ConnectionMode.local;
    api.telegramAllowed = () => mode == ConnectionMode.telegram;
    api.telegramRequest = telegram.apiRequest;
    telegram.addListener(_telegramChanged);
    _subscription = _changes.receiveBroadcastStream().listen(
      _networkChanged,
      onError: (Object _) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  void _networkChanged(dynamic event) {
    final status = event is Map ? Map<String, dynamic>.from(event) : null;
    if (status != null &&
        mapEquals(status, _networkStatus) &&
        (mode == ConnectionMode.local || _probingGeneration == _generation)) {
      return;
    }
    unawaited(_check(status));
  }

  void _telegramChanged() => unawaited(refresh());

  Future<void> requestPermission() async {
    await _network.invokeMethod<Object?>('requestPermission');
    await refresh();
  }

  Future<void> refresh() => _check(null);

  Future<void> _check(Map<String, dynamic>? event) async {
    final generation = ++_generation;
    ConnectionMode next;
    String? problem;
    var permission = false;
    try {
      final status =
          event ??
          await _network.invokeMapMethod<String, dynamic>('status') ??
          {};
      if (_disposed || generation != _generation) return;
      final previous = _networkStatus;
      _networkStatus = status;
      permission = status['permission'] == true;
      if (permission && status['ssid'] == 'ThomasWlan') {
        if (mode == ConnectionMode.local &&
            previous?['networkId'] != status['networkId']) {
          mode = ConnectionMode.checking;
          notifyListeners();
        }
        try {
          _probingGeneration = generation;
          final health = await api.probeHealth();
          if (health is! Json || health['ok'] != true) {
            throw const ApiException(
              'Der Heimnetzserver hat ungültig geantwortet.',
            );
          }
          next = ConnectionMode.local;
        } catch (failure) {
          next =
              telegram.paired &&
                  telegram.step == TelegramStep.ready &&
                  status['online'] == true
              ? ConnectionMode.telegram
              : ConnectionMode.offline;
          problem = failure.toString();
        } finally {
          if (_probingGeneration == generation) _probingGeneration = null;
        }
      } else if (telegram.paired &&
          telegram.step == TelegramStep.ready &&
          status['online'] == true) {
        next = ConnectionMode.telegram;
      } else {
        next = ConnectionMode.offline;
        problem = !permission
            ? 'WLAN-Erkennung benötigt eine Berechtigung.'
            : status['wifi'] == true && status['ssid'] == null
            ? 'Der WLAN-Name ist nicht verfügbar. Prüfe die Android-Standorteinstellungen.'
            : status['online'] != true
            ? 'Keine Internetverbindung.'
            : 'Telegram ist nicht verbunden.';
      }
    } catch (_) {
      next = ConnectionMode.offline;
      problem = 'Der Verbindungsstatus konnte nicht ermittelt werden.';
    }
    if (_disposed || generation != _generation) return;
    if (mode == next && error == problem && hasPermission == permission) return;
    hasPermission = permission;
    mode = next;
    error = problem;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    api.localAllowed = null;
    api.telegramAllowed = null;
    api.telegramRequest = null;
    _subscription?.cancel();
    telegram.removeListener(_telegramChanged);
    super.dispose();
  }
}
