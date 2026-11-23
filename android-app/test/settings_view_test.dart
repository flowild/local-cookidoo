import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/appearance.dart';
import 'package:rezeptgarten/main.dart';
import 'package:rezeptgarten/settings_view.dart';

void main() {
  testWidgets('keeps loaded settings visible when a background read fails', (
    tester,
  ) async {
    final api = _SettingsApi();
    await tester.pumpWidget(MaterialApp(
      home: SettingsView(api: api, appearance: AppearanceController()),
    ));
    await tester.pumpAndSettle();
    final account = find.text('Dein Cookidoo-Konto');
    expect(account, findsOneWidget);
    api.statusUnavailable = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(account, findsOneWidget);
    expect(find.text('Status nicht erreichbar.'), findsOneWidget);
    api.statusUnavailable = false;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(account, findsOneWidget);
    expect(find.text('Status nicht erreichbar.'), findsNothing);
  });

  testWidgets('settings remain usable on a narrow screen with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
        child: child!,
      ),
      home: SettingsView(api: _SettingsApi(), appearance: AppearanceController()),
    ));
    await tester.pumpAndSettle();
    final button = find.text('Nach Updates suchen');
    await tester.scrollUntilVisible(button, 200);
    await tester.pumpAndSettle();
    expect(button, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hands an APK update to Android without opening a browser', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('de.rezeptgarten/update');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final pending = Completer<String>();
    var requests = 0;
    var checks = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'checkUpdate') {
        checks++;
        if (checks == 1) {
          throw PlatformException(
            code: 'update_check',
            message: 'Updateprüfung fehlgeschlagen.',
          );
        }
        return {
          'version': '0.16.0',
          'build': 12,
          'installedBuild': checks == 2 ? 12 : 11,
        };
      }
      expect(call.method, 'downloadAndInstall');
      requests++;
      return pending.future;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsView(
          api: _SettingsApi(),
          appearance: AppearanceController(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final check = find.text('Nach Updates suchen');
    await tester.scrollUntilVisible(check, 240);
    await tester.pumpAndSettle();
    expect(checks, 0);
    expect(find.text('Updatestatus unbekannt.'), findsOneWidget);
    expect(find.text('APK herunterladen und installieren'), findsNothing);
    expect(find.text('Open-Source-Lizenzen'), findsNothing);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(find.text('Updateprüfung fehlgeschlagen.'), findsOneWidget);
    expect(find.text('APK herunterladen und installieren'), findsNothing);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(find.text('Deine App ist aktuell.'), findsOneWidget);
    expect(find.text('APK herunterladen und installieren'), findsNothing);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(
      find.text('Update verfügbar · Version 0.16.0 (Build 12)'),
      findsOneWidget,
    );
    expect(check, findsNothing);
    final button = find.text('APK herunterladen und installieren');
    await tester.scrollUntilVisible(button, 240);
    await tester.tap(button);
    await tester.pump();
    expect(find.text('APK wird heruntergeladen und geprüft …'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.ancestor(
              of: button,
              matching: find.byWidgetPredicate(
                (widget) => widget is OutlinedButton,
              ),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(requests, 1);
    pending.complete('installerOpened');
    await tester.pumpAndSettle();
    expect(find.text('APK wird heruntergeladen und geprüft …'), findsNothing);
    expect(button, findsOneWidget);
  });

  testWidgets(
    'saves appearance and account settings without a JSON export action',
    (tester) async {
      tester.view.physicalSize = const Size(412, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _SettingsApi();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const prefs = MethodChannel('de.rezeptgarten/preferences');
      final changes = <Map<dynamic, dynamic>>[];
      messenger.setMockMethodCallHandler(prefs, (call) async {
        switch (call.method) {
          case 'appearance':
            return {'dark': false, 'accent': 0xff234d3c};
          case 'weekDay':
            return 0;
          case 'version':
            return '0.14.0-test';
          case 'setAppearance':
            changes.add(call.arguments as Map);
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(prefs, null);
      });

      await tester.pumpWidget(RezeptgartenApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Einstellungen öffnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dunkelmodus'));
      await tester.pumpAndSettle();
      expect(changes.single['dark'], true);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );

      Finder field(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      await tester.tap(find.text('Cookidoo verbinden'));
      await tester.pumpAndSettle();
      await tester.enterText(field('E-Mail-Adresse'), 'test@example.invalid');
      await tester.enterText(field('Cookidoo-Passwort'), 'fixture-password');
      expect(
        tester.widget<TextField>(field('Cookidoo-Passwort')).obscureText,
        isTrue,
      );
      await tester.tap(find.text('Verbinden'));
      await tester.pumpAndSettle();
      expect(api.account?['email'], 'test@example.invalid');
      expect(api.account?.containsKey('password'), isFalse);

      expect(find.text('Synchronisierung'), findsNothing);
      expect(find.text('Automatischer Abgleich'), findsNothing);

      expect(find.text('Sammlung als JSON exportieren'), findsNothing);
      final version = find.text('Installierte Version 0.14.0-test');
      await tester.scrollUntilVisible(version, 280);
      expect(version, findsOneWidget);
      expect(find.text('Telegram'), findsOneWidget);
      expect(find.text('Google API'), findsNothing);
    },
  );
}

class _SettingsApi extends RezeptgartenApi {
  _SettingsApi() : super(client: HttpClient());

  Json? account;
  bool statusUnavailable = false;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async => switch (path) {
    '/api/status' when statusUnavailable => throw const ApiException('Status nicht erreichbar.'),
    '/api/status' => {
      'account': account,
      'connected': account != null,
      'telegram_server_bot_set': true,
      'google_api_key_set': true,
    },
    '/api/calendar/week' => {
      'today': '2026-11-18',
      'days': [
        {'date': '2026-11-16', 'recipes': []},
      ],
    },
    _ => throw StateError('Unexpected path: $path'),
  };

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    switch ((method, path)) {
      case ('POST', '/api/connect'):
        expect(body?['password'], 'fixture-password');
        account = {'email': body?['email'], 'region': body?['region']};
      default:
        throw StateError('Unexpected write: $method $path');
    }
    return {'ok': true};
  }
}
