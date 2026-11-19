import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'appearance.dart';
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
  final appearance = AppearanceController();
  final telegram = TelegramService();
  final navigatorKey = GlobalKey<NavigatorState>();
  ConnectionController? connection;
  bool setupShown = false;
  bool networkIntroDone = false;

  @override
  void initState() {
    super.initState();
    unawaited(appearance.restore());
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
      if (approved == true) {
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
    appearance.dispose();
    connection?.dispose();
    telegram.removeListener(_telegramChanged);
    telegram.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: appearance,
      builder: (context, current, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Rezeptgarten',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light, current.accent),
        darkTheme: _theme(Brightness.dark, current.accent),
        themeMode: current.dark ? ThemeMode.dark : ThemeMode.light,
        home: RezeptgartenHome(
          api: widget.api,
          appearance: appearance,
          telegram: telegram,
          connection: connection,
        ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness, int accent) {
    final light = brightness == Brightness.light;
    final selected = Color(accent);
    final colors =
        ColorScheme.fromSeed(
          seedColor: selected,
          brightness: brightness,
        ).copyWith(
          primary: light ? selected : null,
          onPrimary: light
              ? (ThemeData.estimateBrightnessForColor(selected) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black)
              : null,
          surface: light ? const Color(0xfff7f7f2) : null,
          onSurface: light ? const Color(0xff253c31) : null,
          secondaryContainer: light && accent == defaultAccent
              ? const Color(0xffedf1e5)
              : null,
        );
    return ThemeData(
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        color: light ? Colors.white : colors.surfaceContainer,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: light ? const Color(0xffe5e7dd) : colors.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}
