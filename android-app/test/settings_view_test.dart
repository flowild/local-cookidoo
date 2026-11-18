import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/main.dart';

void main() {
  testWidgets(
    'saves appearance, account settings and a JSON document in Android',
    (tester) async {
      tester.view.physicalSize = const Size(412, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _SettingsApi();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const prefs = MethodChannel('de.rezeptgarten/preferences');
      const documents = MethodChannel('de.rezeptgarten/documents');
      final changes = <Map<dynamic, dynamic>>[];
      Uint8List? exported;
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
      messenger.setMockMethodCallHandler(documents, (call) async {
        expect(call.method, 'saveCollection');
        exported = call.arguments as Uint8List;
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(prefs, null);
        messenger.setMockMethodCallHandler(documents, null);
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

      await tester.tap(find.text('Alle 6 Stunden'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nur manuell').last);
      await tester.pumpAndSettle();
      expect(api.hours, 0);

      await tester.tap(find.text('Sammlung als JSON exportieren'));
      await tester.pumpAndSettle();
      expect(exported, orderedEquals([123, 125]));
      final version = find.text('Installierte Version 0.14.0-test');
      await tester.scrollUntilVisible(version, 280);
      expect(version, findsOneWidget);
    },
  );
}

class _SettingsApi extends RezeptgartenApi {
  _SettingsApi() : super(client: HttpClient());

  Json? account;
  int hours = 6;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async => switch (path) {
    '/api/status' => {
      'account': account,
      'connected': account != null,
      'sync_hours': hours,
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
  Future<Uint8List> exportCollection() async => Uint8List.fromList([123, 125]);

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    switch ((method, path)) {
      case ('POST', '/api/connect'):
        expect(body?['password'], 'fixture-password');
        account = {'email': body?['email'], 'region': body?['region']};
      case ('POST', '/api/settings'):
        hours = body?['sync_hours'] as int;
      default:
        throw StateError('Unexpected write: $method $path');
    }
    return {'ok': true};
  }
}
