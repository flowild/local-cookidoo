import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/main.dart';

void main() {
  testWidgets('starts a sync on opening and on pull to refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _SyncTestApi();
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pump();
    expect(api.syncs, 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator).first,
    );
    final pending = refresh.onRefresh();
    await tester.pump();
    expect(api.syncs, 2);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    await pending;
  });

  testWidgets('week action opens a cart with a persistent checkbox', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _TestApi();
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('In den Einkaufswagen'));
    await tester.pumpAndSettle();
    expect(api.addedDay, '2026-11-16');

    await tester.tap(find.byTooltip('Einkaufswagen öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('100 g Reis'), findsOneWidget);

    final checkbox = find.byType(Checkbox);
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    final visibleCheckbox = checkbox.hitTestable();
    expect(visibleCheckbox, findsOneWidget);
    await tester.tap(visibleCheckbox);
    await tester.pumpAndSettle();
    expect(api.owned, isTrue);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
  });

  testWidgets('additional item supports explicit transfer and review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _TestApi();
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Einkaufswagen öffnen'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  Küchenrolle  ');
    await tester.tap(find.text('Hinzufügen').hitTestable());
    await tester.pumpAndSettle();
    expect(api.cartItem, 'Küchenrolle');
    expect(api.extraStatus, 'pending');

    await tester.tap(find.text('An Cookidoo übertragen').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Übertragung ungeklärt'), findsOneWidget);
    expect(find.text('Cookidoo prüfen.'), findsOneWidget);
    await tester.tap(find.text('Dort vorhanden').hitTestable());
    await tester.pumpAndSettle();
    expect(api.extraStatus, 'uncertain');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Dort vorhanden'),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.extraStatus, 'done');
    expect(find.text('Übertragen'), findsOneWidget);

    await tester.tap(find.byTooltip('Küchenrolle entfernen').hitTestable());
    await tester.pumpAndSettle();
    expect(api.cartItem, isNull);
  });
}

class _SyncTestApi extends _TestApi {
  int syncs = 0;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    if (path.startsWith('/api/calendar/badges?')) return {'items': <Json>[]};
    if (path == '/api/status') {
      return {
        'connected': true,
        'sync': {'running': false},
        'cart_recipe_count': 0,
      };
    }
    return super.get(path, timeout: timeout);
  }

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    if (method == 'POST' && path == '/api/sync') {
      syncs++;
      return {'started': true};
    }
    return super.write(method, path, body);
  }
}

class _TestApi extends RezeptgartenApi {
  _TestApi() : super(client: HttpClient());

  String? addedDay;
  bool owned = false;
  String? cartItem;
  String extraStatus = 'pending';

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async => switch (path) {
    '/api/status' => {'cart_recipe_count': addedDay == null ? 0 : 1},
    '/api/calendar/week' => {
      'today': '2026-11-18',
      'days': [
        {
          'date': '2026-11-16',
          'recipes': [
            {'id': 'r1', 'name': 'Reis mit Gemüse'},
          ],
        },
      ],
    },
    '/api/cart' => {
      'items': [
        if (cartItem != null)
          {
            'id': 'cart-extra',
            'kind': 'additional',
            'status': extraStatus,
            'data': {'name': cartItem, 'owned': false},
          },
        if (addedDay != null)
          {
            'id': 'cart-entry',
            'recipe_id': 'r1',
            'kind': 'recipe',
            'status': 'pending',
            'data': {
              'name': 'Reis mit Gemüse',
              'ingredients': [
                {'name': 'Reis', 'text': '100 g Reis', 'owned': owned},
              ],
            },
          },
      ],
    },
    _ => throw StateError('Unexpected API path: $path'),
  };

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    switch ((method, path)) {
      case ('POST', '/api/calendar/shopping'):
        addedDay = body?['day'] as String?;
      case ('PUT', '/api/cart/cart-entry/ingredients/0'):
        owned = body?['owned'] == true;
      case ('POST', '/api/cart/items'):
        cartItem = body?['name'] as String?;
      case ('POST', '/api/cart/transfer'):
        extraStatus = 'uncertain';
        return {'status': 'partial', 'message': 'Cookidoo prüfen.'};
      case ('POST', '/api/cart/cart-extra/resolve'):
        extraStatus = body?['status'] as String;
      case ('DELETE', '/api/cart/cart-extra'):
        cartItem = null;
      default:
        throw StateError('Unexpected API write: $method $path');
    }
    return {'ok': true};
  }
}
