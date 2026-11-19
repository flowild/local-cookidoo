import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'telegram_service.dart';

enum ConnectionMode { checking, local, telegram, offline }

class ConnectionController extends ChangeNotifier with WidgetsBindingObserver {
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
  bool _disposed = false;

  void start() {
    api.localAllowed = () => mode == ConnectionMode.local;
    WidgetsBinding.instance.addObserver(this);
    telegram.addListener(_telegramChanged);
    _subscription = _changes.receiveBroadcastStream().listen(
      (_) => _networkChanged(),
      onError: (Object _) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  void _networkChanged() {
    if (mode != ConnectionMode.checking) {
      mode = ConnectionMode.checking;
      notifyListeners();
    }
    unawaited(refresh());
  }

  void _telegramChanged() => unawaited(refresh());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _networkChanged();
  }

  Future<void> requestPermission() async {
    await _network.invokeMethod<Object?>('requestPermission');
    await refresh();
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    ConnectionMode next;
    String? problem;
    var permission = false;
    try {
      final status =
          await _network.invokeMapMethod<String, dynamic>('status') ?? {};
      permission = status['permission'] == true;
      if (status['ssid'] == 'ThomasWlan') {
        try {
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
    _subscription?.cancel();
    telegram.removeListener(_telegramChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
