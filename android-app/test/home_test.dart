import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/main.dart';

void main() {
  testWidgets('returning to recipes keeps the search and avoids a new load', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _RecipeSearchApi();
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rezepte suchen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Reis');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Reis'), findsOneWidget);
    final reads = api.recipeReads;

    await tester.tap(find.text('Woche'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Rezepte'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'Reis',
    );
    expect(api.recipeReads, reads);
  });

  testWidgets('narrow phones use a shorter start label', (tester) async {
    tester.view.physicalSize = const Size(332, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RezeptgartenApp(api: _TestApi()));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Übersicht'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('main navigation fits a narrow screen with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _TestApi();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: RezeptgartenApp(api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late older status cannot hide a newly started sync', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _StaleStatusApi();
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pump();
    expect(api.syncs, 1);
    api.stale.complete({
      'connected': true,
      'sync': {'running': false},
      'cart_recipe_count': 0,
    });
    await tester.pump();
    expect(find.byTooltip('Synchronisierung läuft'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.byTooltip('Synchronisieren'), findsOneWidget);
  });

  testWidgets('retries a failed sync status read until the sync completes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _SyncTestApi()..keepRunning = true;
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pump();
    expect(api.syncs, 1);
    api.statusFailures = 1;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.byTooltip('Synchronisierung läuft'), findsOneWidget);
    expect(find.textContaining('wird erneut geprüft'), findsOneWidget);
    api.keepRunning = false;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.byTooltip('Synchronisieren'), findsOneWidget);
  });

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

    await tester.tap(find.byTooltip('In den Einkaufswagen'));
    await tester.pumpAndSettle();
    expect(api.addedDay, '2026-11-16');

    await tester.tap(find.byTooltip('Einkaufswagen öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('100 g Reis'), findsOneWidget);

    final checkbox = find.byType(Checkbox);
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    final visibleCheckbox = checkbox.hitTestable();
    expect(visibleCheckbox, findsOneWidget);
    final ingredient = find.text('100 g Reis');
    final ingredientPosition = tester.getCenter(ingredient);
    final write = Completer<void>();
    api.ingredientWrite = write.future;
    await tester.tap(ingredient.hitTestable());
    await tester.pump();
    expect(tester.getCenter(ingredient), ingredientPosition);
    write.complete();
    await tester.pumpAndSettle();
    expect(api.owned, isTrue);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    final remove = find.byTooltip('Reis mit Gemüse entfernen');
    await tester.scrollUntilVisible(remove, 250);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(api.addedDay, isNull);
    expect(find.text('0'), findsOneWidget);
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

    await tester.tap(find.text('Artikel hinzufügen'));
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

  testWidgets('large shopping lists build rows as they scroll into view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RezeptgartenApp(api: _LargeCartApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Einkaufswagen öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('Artikel 000'), findsOneWidget);
    final last = find.text('Artikel 099');
    expect(last, findsNothing);
    await tester.scrollUntilVisible(last, 300);
    expect(last, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _LargeCartApi extends _TestApi {
  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    if (path == '/api/cart') {
      return {
        'items': [
          for (var i = 0; i < 100; i++)
            {
              'id': '$i',
              'kind': 'additional',
              'status': 'pending',
              'data': {'name': 'Artikel ${i.toString().padLeft(3, '0')}'},
            },
        ],
      };
    }
    return super.get(path, timeout: timeout);
  }
}

class _StaleStatusApi extends _SyncTestApi {
  int statusReads = 0;
  final stale = Completer<Json>();

  @override
  Future<dynamic> get(String path, {Duration? timeout}) {
    if (path == '/api/status' && ++statusReads == 2) return stale.future;
    return super.get(path, timeout: timeout);
  }
}

class _SyncTestApi extends _TestApi {
  int syncs = 0;
  int statusFailures = 0;
  bool keepRunning = false;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    if (path.startsWith('/api/calendar/badges?')) return {'items': <Json>[]};
    if (path == '/api/status') {
      if (statusFailures > 0) {
        statusFailures--;
        throw const ApiException('Server vorübergehend nicht erreichbar.');
      }
      return {
        'connected': true,
        'sync': {'running': keepRunning && syncs > 0},
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

class _RecipeSearchApi extends _TestApi {
  int recipeReads = 0;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    if (Uri.parse(path).path == '/api/recipes') {
      recipeReads++;
      return {'items': <Json>[], 'total': 0, 'match_total': 0};
    }
    return super.get(path, timeout: timeout);
  }
}

class _TestApi extends RezeptgartenApi {
  _TestApi() : super(client: HttpClient());

  String? addedDay;
  bool owned = false;
  Future<void>? ingredientWrite;
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
        await ingredientWrite;
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
      case ('DELETE', '/api/cart/cart-entry'):
        addedDay = null;
      default:
        throw StateError('Unexpected API write: $method $path');
    }
    return {'ok': true};
  }
}
