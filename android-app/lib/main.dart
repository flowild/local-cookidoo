import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'appearance.dart';
import 'debug_api.dart';
import 'expressive_theme.dart';
import 'home.dart';
import 'telegram_service.dart';
import 'telegram_setup.dart';
import 'connection.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(RezeptgartenApp(api: RezeptgartenApi()));
}

class RezeptgartenApp extends StatefulWidget {
  const RezeptgartenApp({super.key, required this.api});

  final RezeptgartenApi api;

  @override
  State<RezeptgartenApp> createState() => _RezeptgartenAppState();
}

class _RezeptgartenAppState extends State<RezeptgartenApp> {
  static const _preferences = MethodChannel('de.rezeptgarten/preferences');
  final appearance = AppearanceController();
  late final _debugApi = DebugRezeptgartenApi();
  bool? _debugMode;

  @override
  void initState() {
    super.initState();
    unawaited(appearance.restore());
    if (Platform.isAndroid) {
      unawaited(_restoreMode());
    } else {
      _debugMode = false;
    }
  }

  Future<void> _restoreMode() async {
    var enabled = false;
    try {
      enabled = await _preferences.invokeMethod<bool>('debugMode') ?? false;
    } on PlatformException {
      // The app can still open if preferences are temporarily unavailable.
    } on MissingPluginException {
      // Older Android activities have no stored mode.
    }
    if (mounted) setState(() => _debugMode = enabled);
  }

  void _switchMode(bool enabled) {
    widget.api.clearImageCache();
    setState(() => _debugMode = enabled);
    unawaited(_saveMode(enabled));
  }

  Future<void> _saveMode(bool enabled) async {
    try {
      await _preferences.invokeMethod<void>('setDebugMode', enabled);
    } on PlatformException {
      // Keep the current selection for this app session.
    } on MissingPluginException {
      // Widget tests keep the selection in memory.
    }
  }

  @override
  void dispose() {
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final debugMode = _debugMode;
    if (debugMode == null) return const SizedBox.shrink();
    return _RezeptgartenSession(
      key: ValueKey(debugMode),
      api: debugMode ? _debugApi : widget.api,
      appearance: appearance,
      onDebugModeChanged: _switchMode,
    );
  }
}

class _RezeptgartenSession extends StatefulWidget {
  const _RezeptgartenSession({
    super.key,
    required this.api,
    required this.appearance,
    required this.onDebugModeChanged,
  });

  final RezeptgartenApi api;
  final AppearanceController appearance;
  final ValueChanged<bool> onDebugModeChanged;

  @override
  State<_RezeptgartenSession> createState() => _RezeptgartenSessionState();
}

class _RezeptgartenSessionState extends State<_RezeptgartenSession> {
  final telegram = TelegramService();
  final navigatorKey = GlobalKey<NavigatorState>();
  ConnectionController? connection;
  bool setupShown = false;
  bool networkIntroDone = false;

  @override
  void initState() {
    super.initState();
    if (widget.api.usesTestData) return;
    telegram.addListener(_telegramChanged);
    unawaited(telegram.start());
    if (Platform.isAndroid) {
      connection = ConnectionController(widget.api, telegram)..start();
      WidgetsBinding.instance.addPostFrameCallback((_) => _networkIntro());
    } else {
      networkIntroDone = true;
    }
  }

  Future<void> _networkIntro() async {
    final current = connection;
    if (current == null) return;
    await current.refresh();
    if (!mounted) return;
    final context = navigatorKey.currentContext;
    if (!current.hasPermission && context != null && context.mounted) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Heimnetz erkennen'),
          content: const Text(
            'Android benötigt die Standortberechtigung, damit Rezeptgarten das WLAN ThomasWlan erkennen kann.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Später'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Weiter'),
            ),
          ],
        ),
      );
      if (approved == true && mounted) {
        try {
          await current.requestPermission();
        } on PlatformException {
          // The offline view offers the permission request again.
        }
      }
    }
    if (!mounted) return;
    networkIntroDone = true;
    _telegramChanged();
  }

  void _telegramChanged() {
    if (!networkIntroDone ||
        setupShown ||
        !{
          TelegramStep.credentials,
          TelegramStep.phone,
          TelegramStep.code,
          TelegramStep.email,
          TelegramStep.emailCode,
          TelegramStep.password,
        }.contains(telegram.step)) {
      return;
    }
    setupShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (!mounted || context == null) return;
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => TelegramSetup(
            telegram: telegram,
            api: widget.api,
            connection: connection,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    connection?.dispose();
    telegram.removeListener(_telegramChanged);
    telegram.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.appearance,
      builder: (context, current, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Rezeptgarten',
        debugShowCheckedModeBanner: false,
        theme: rezeptgartenTheme(Brightness.light, current.accent),
        darkTheme: rezeptgartenTheme(Brightness.dark, current.accent),
        themeMode: current.dark ? ThemeMode.dark : ThemeMode.light,
        home: RezeptgartenHome(
          api: widget.api,
          appearance: widget.appearance,
          telegram: widget.api.usesTestData ? null : telegram,
          connection: connection,
          onDebugModeChanged: widget.onDebugModeChanged,
        ),
      ),
    );
  }
}
