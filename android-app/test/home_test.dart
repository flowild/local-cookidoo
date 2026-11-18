import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/main.dart';

void main() {
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
}

class _TestApi extends RezeptgartenApi {
  _TestApi() : super(client: HttpClient());

  String? addedDay;
  bool owned = false;

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
      default:
        throw StateError('Unexpected API write: $method $path');
    }
    return {'ok': true};
  }
}
