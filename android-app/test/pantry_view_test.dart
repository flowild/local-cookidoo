import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/pantry_view.dart';

void main() {
  testWidgets(
    'adds a suggested ingredient, edits it and confirms category deletion',
    (tester) async {
      final api = _PantryApi();
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PantryView(api: api, collapsed: {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Finder field(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      await tester.tap(find.text('Zutat hinzufügen'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Zutat'), 'rei');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      final suggestion = find.widgetWithText(ActionChip, 'Reis');
      expect(suggestion, findsOneWidget);
      await tester.tap(suggestion);
      await tester.enterText(field('Menge (optional)'), '250 g');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(api.item?['ingredient_id'], 11);
      expect(find.text('250 g'), findsOneWidget);

      await tester.tap(find.byTooltip('Reis bearbeiten'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Menge (optional)'), '500 g');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(api.item?['ingredient_id'], 11);
      expect(find.text('500 g'), findsOneWidget);

      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      list.onReorderItem!(0, 1);
      await tester.pumpAndSettle();
      expect(api.order, [2, 1]);

      await tester.tap(find.byTooltip('Aktionen für Vorräte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kategorie löschen'));
      await tester.pumpAndSettle();
      expect(api.item, isNotNull);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Kategorie löschen'),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.item, isNull);
      expect(find.text('Vorräte'), findsNothing);
    },
  );
}

class _PantryApi extends RezeptgartenApi {
  _PantryApi() : super(client: HttpClient());

  List<int> order = [1, 2];
  Json? item;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    final uri = Uri.parse(path);
    return switch (uri.path) {
      '/api/pantry' => {
        'categories': [
          for (final id in order)
            {'id': id, 'name': id == 1 ? 'Vorräte' : 'Gemüse'},
        ],
        'items': [if (item != null) item],
      },
      '/api/ingredients/suggestions' when uri.queryParameters['q'] == 'rei' => {
        'items': [
          {'id': 11, 'name': 'Reis', 'recipe_count': 1},
        ],
      },
      _ => throw StateError('Unexpected API path: $path'),
    };
  }

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    switch ((method, path)) {
      case ('POST', '/api/pantry/items') || ('PUT', '/api/pantry/items/1'):
        item = {'id': 1, ...body!};
      case ('PUT', '/api/pantry/categories/order'):
        order = (body!['category_ids'] as List).cast<int>().toList();
      case ('DELETE', '/api/pantry/categories/1'):
        order.remove(1);
        item = null;
      default:
        throw StateError('Unexpected API write: $method $path');
    }
    return {'ok': true};
  }
}
