import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/recipe_detail.dart';

void main() {
  testWidgets('refresh saves a draft before syncing and reloading', (
    tester,
  ) async {
    final api = _DetailApi();
    var syncs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          api: api,
          preview: const {'id': 'creation:r1', 'name': 'Reisgericht'},
          calendar: false,
          onSync: () async {
            syncs++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    expect(tester.getSize(find.byType(ListView)).width, 720);
    await tester.scrollUntilVisible(
      field,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(field, 'Mein neuer Text');
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await refresh.onRefresh();
    await tester.pumpAndSettle();
    expect(syncs, 1);
    expect(api.writes.single['text'], 'Mein neuer Text');
  });

  testWidgets(
    'shows structured recipe details and preserves a conflicting draft',
    (tester) async {
      tester.view.physicalSize = const Size(412, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _DetailApi();
      var syncs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            api: api,
            preview: const {'id': 'creation:r1', 'name': 'Reisgericht'},
            calendar: false,
            onSync: () async {
              syncs++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 EL Öl, erwärmt'), findsOneWidget);
      expect(find.byTooltip('Im Vorrat'), findsOneWidget);
      expect(find.text('Wasser'), findsNothing);
      expect(find.text('Den Reis kochen.'), findsNothing);
      await tester.tap(find.text('Zubereitung'));
      await tester.pumpAndSettle();
      expect(find.text('Den Reis kochen.'), findsOneWidget);
      await tester.tap(find.text('Tipps'));
      await tester.pumpAndSettle();
      expect(find.text('Warm servieren.'), findsOneWidget);
      expect(find.text('Notiz: Interne Testnotiz'), findsNothing);

      final field = find.byType(TextField);
      await tester.enterText(field, 'Eine neue Notiz');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(api.writes.single, {
        'expected': 'Alte Notiz',
        'text': 'Eine neue Notiz',
      });

      api.changedElsewhere = true;
      await tester.enterText(field, 'Mein Entwurf');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(api.writes.last, {
        'expected': 'Eine neue Notiz',
        'text': 'Mein Entwurf',
      });
      expect(tester.widget<TextField>(field).controller!.text, 'Mein Entwurf');
      expect(
        find.textContaining('Dein Text bleibt im Feld erhalten.'),
        findsOneWidget,
      );
      final refresh = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      await refresh.onRefresh();
      await tester.pumpAndSettle();
      expect(syncs, 0);
      expect(tester.widget<TextField>(field).controller!.text, 'Mein Entwurf');
    },
  );
}

class _DetailApi extends RezeptgartenApi {
  _DetailApi() : super(client: HttpClient());

  final writes = <Json>[];
  bool changedElsewhere = false;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async => switch (path) {
    '/api/recipes/creation%3Ar1' => {
      'id': 'creation:r1',
      'name': 'Reisgericht',
      'ingredients_json': '[{"description":"2 EL","name":"Öl","preparation":"erwärmt"},"Wasser"]',
      'hidden_ingredient_positions': [1],
      'ingredient_availability': {'0': true},
      'instructions_json': '[{"title":"Reis","steps":["Den Reis kochen."]}]',
      'tips_json': '["Warm servieren.","Notiz: Interne Testnotiz"]',
      'collections': [
        {'id': 'local:l1', 'name': 'Schnell'},
      ],
    },
    '/api/notes/creation%3Ar1' => {'text': 'Alte Notiz'},
    '/api/collections' => {
      'items': [
        {'id': 'local:l1', 'name': 'Schnell', 'kind': 'local'},
      ],
    },
    _ => throw StateError('Unexpected API path: $path'),
  };

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    if (method != 'PUT' || path != '/api/notes/creation%3Ar1' || body == null) {
      throw StateError('Unexpected API write: $method $path');
    }
    writes.add(body);
    if (changedElsewhere) {
      throw const ApiException('Die Notiz wurde inzwischen geändert.');
    }
    return {'text': body['text']};
  }
}
