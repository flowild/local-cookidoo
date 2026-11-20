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

  @override
  Future<dynamic> probeHealth() {
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

class SwitchableConnection extends ConnectionController {
  SwitchableConnection(super.api, super.telegram);

  void transition(ConnectionMode value) {
    mode = value;
    notifyListeners();
  }
}

class NavigationApi extends FakeApi {
  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    if (path == '/api/status') {
      return {'connected': false, 'cart_recipe_count': 0};
    }
    if (path == '/api/collections') return <Json>[];
    if (path == '/api/calendar/week') return {'days': <Json>[]};
    throw StateError('Unexpected request: $path');
  }
}

void main() {
  testWidgets('keeps the selected page during a temporary network check', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final api = NavigationApi();
    final telegram = FakeTelegram()..step = TelegramStep.ready;
    final connection = SwitchableConnection(api, telegram)
      ..mode = ConnectionMode.local;
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
    connection.transition(ConnectionMode.checking);
    await tester.pump();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    connection.transition(ConnectionMode.local);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    tester.view.physicalSize = const Size(840, 600);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      1,
    );
    connection.transition(ConnectionMode.telegram);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
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
  });

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
