import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/connection.dart';
import 'package:rezeptgarten/telegram_service.dart';
import 'package:rezeptgarten/appearance.dart';
import 'package:rezeptgarten/home.dart';
import 'package:material_ui/material_ui.dart';

class FakeApi extends RezeptgartenApi {
  FakeApi() : super(client: HttpClient());
  Completer<dynamic>? pending;
  bool fail = false;
  Json health = {'ok': true};
  int healthReads = 0;

  @override
  Future<dynamic> probeHealth() {
    healthReads++;
    if (pending != null) return pending!.future;
    if (fail) {
      return Future.error(const ApiException('Server nicht erreichbar.'));
    }
    return Future.value(health);
  }
}

class FakeTelegram extends TelegramService {
  bool available = true;
  @override
  bool get paired => available;

  @override
  Future<Json> snapshot(String kind, {String? day}) async => {
    'today': day,
    'days': <Json>[],
    'shelf': <String>[],
    'shelf_placeholders': <String>[],
    'queue_phase': 'idle',
  };

  @override
  Future<Map<String, bool>> loadChecks() async => {};
}

class NavigationApi extends FakeApi {
  int listReads = 0;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    if (path == '/api/status') {
      return {'connected': false, 'cart_recipe_count': 0};
    }
    if (path == '/api/collections') {
      listReads++;
      return {'items': <Json>[]};
    }
    if (Uri.parse(path).path == '/api/recipes') {
      return {'items': <Json>[], 'total': 0, 'match_total': 0};
    }
    if (path == '/api/calendar/week') return {'days': <Json>[]};
    throw StateError('Unexpected request: $path');
  }
}

void main() {
  testWidgets(
    'keeps local content interactive during Wi-Fi events and resume',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final api = NavigationApi();
      final telegram = FakeTelegram()..step = TelegramStep.ready;
      const channel = MethodChannel('de.rezeptgarten/network');
      const events = EventChannel('de.rezeptgarten/network_changes');
      final messenger = tester.binding.defaultBinaryMessenger;
      late MockStreamHandlerEventSink networkEvents;
      final home = {
        'ssid': 'ThomasWlan',
        'networkId': 1,
        'wifi': true,
        'permission': true,
        'online': true,
      };
      messenger.setMockMethodCallHandler(channel, (_) async => home);
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(onListen: (_, sink) {
          networkEvents = sink;
        }),
      );
      final connection = ConnectionController(api, telegram)..start();
      await tester.pump();
      final appearance = AppearanceController();
      await tester.pumpWidget(
        MaterialApp(
          home: RezeptgartenHome(
            api: api,
            appearance: appearance,
            telegram: telegram,
            connection: connection,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Listen').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      final search = find.widgetWithText(TextField, 'Listen suchen');
      await tester.enterText(search, 'Suppe');
      final reads = api.healthReads;
      final listReads = api.listReads;
      for (var i = 0; i < 3; i++) {
        networkEvents.success(home);
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Suppe'), findsOneWidget);
        expect(find.text('Verbindung wird geprüft.'), findsNothing);
      }
      expect(api.healthReads, reads);
      final delayed = Completer<dynamic>();
      api.pending = delayed;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(api.healthReads, reads + 1);
      expect(api.localAllowed!(), isTrue);
      await tester.enterText(search, 'Pasta');
      delayed.complete({'ok': true});
      await tester.pumpAndSettle();
      expect(find.text('Pasta'), findsOneWidget);
      expect(api.listReads, listReads);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      tester.view.physicalSize = const Size(840, 600);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        1,
      );
      networkEvents.success({...home, 'ssid': 'Gastnetz', 'networkId': 2});
      await tester.pumpAndSettle();
      expect(api.localAllowed!(), isFalse);
      expect(find.text('Pasta'), findsNothing);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        3,
      );
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.destinations[2].disabled, isTrue);
      expect(rail.destinations[4].disabled, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      appearance.dispose();
      connection.dispose();
      telegram.dispose();
      await api.close();
    },
  );

  testWidgets('disables unavailable navigation in Telegram mode', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi();
    final telegram = FakeTelegram()..step = TelegramStep.ready;
    final connection = ConnectionController(api, telegram)
      ..mode = ConnectionMode.telegram;
    final appearance = AppearanceController();
    await tester.pumpWidget(
      MaterialApp(
        home: RezeptgartenHome(
          api: api,
          appearance: appearance,
          telegram: telegram,
          connection: connection,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final recipes = tester.widget<NavigationDestination>(
      find
          .ancestor(
            of: find.text('Rezepte'),
            matching: find.byType(NavigationDestination),
          )
          .first,
    );
    final week = tester.widget<NavigationDestination>(
      find
          .ancestor(
            of: find.text('Woche'),
            matching: find.byType(NavigationDestination),
          )
          .first,
    );
    expect(recipes.enabled, isFalse);
    expect(week.enabled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    appearance.dispose();
    connection.dispose();
    telegram.dispose();
    await api.close();
  });

  testWidgets(
    'selects the authenticated local server and rejects stale checks',
    (tester) async {
      const channel = MethodChannel('de.rezeptgarten/network');
      const events = MethodChannel('de.rezeptgarten/network_changes');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var status = <String, Object?>{
        'ssid': 'ThomasWlan',
        'permission': true,
        'online': true,
      };
      messenger.setMockMethodCallHandler(channel, (_) async => status);
      messenger.setMockMethodCallHandler(events, (_) async => null);
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(events, null);
      });
      final api = FakeApi();
      final telegram = FakeTelegram()..step = TelegramStep.ready;
      final controller = ConnectionController(api, telegram)..start();
      await tester.pumpAndSettle();
      expect(controller.mode, ConnectionMode.local);
      expect(api.localAllowed!(), isTrue);

      final delayed = Completer<dynamic>();
      api.pending = delayed;
      final old = controller.refresh();
      await tester.pump();
      status = {'ssid': 'Gastnetz', 'permission': true, 'online': true};
      await controller.refresh();
      expect(controller.mode, ConnectionMode.telegram);
      expect(api.localAllowed!(), isFalse);
      delayed.complete({'ok': true});
      await old;
      expect(controller.mode, ConnectionMode.telegram);

      api.pending = null;
      api.fail = true;
      status = {'ssid': 'ThomasWlan', 'permission': true, 'online': true};
      await controller.refresh();
      expect(controller.mode, ConnectionMode.telegram);
      expect(controller.error, contains('Server nicht erreichbar'));
      api.fail = false;
      api.health = {'ok': false};
      await controller.refresh();
      expect(controller.mode, ConnectionMode.telegram);
      expect(controller.error, contains('ungültig'));
      telegram.available = false;
      status = {'ssid': null, 'wifi': true, 'permission': true, 'online': true};
      await controller.refresh();
      expect(controller.mode, ConnectionMode.offline);
      expect(controller.error, contains('WLAN-Name'));
      status = {'ssid': null, 'permission': false, 'online': false};
      await controller.refresh();
      expect(controller.mode, ConnectionMode.offline);
      controller.dispose();
      telegram.dispose();
      await api.close();
    },
  );
}
