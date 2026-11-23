import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/pantry_view.dart';

void main() {
  testWidgets('pantry headers and ingredient names share fixed columns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(332, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _PantryApi()
      ..categoryNames = ['Vorräte', 'Frisches Gemüse und tiefgekühlte Kräuter']
      ..extraItems = [
        {'id': 2, 'category_id': 1, 'name': 'Pfeffer', 'quantity': ''},
        {'id': 3, 'category_id': 1, 'name': 'Ingwer', 'quantity': '250 g'},
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(332, 900),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: PantryView(api: api, collapsed: {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double left(String label) => tester.getTopLeft(find.text(label)).dx;
    expect(left('Vorräte'), left(api.categoryNames[1]));
    expect(left('Pfeffer'), left('Ingwer'));
    expect(left('Pfeffer'), left('Vorräte'));
    expect(
      tester.getCenter(find.byTooltip('Aktionen für Vorräte')).dx,
      tester
          .getCenter(find.byTooltip('Aktionen für ${api.categoryNames[1]}'))
          .dx,
    );
    expect(tester.takeException(), isNull);
  });

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
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🍎  Apfel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(api.item?['ingredient_id'], 11);
      expect(find.text('250 g'), findsOneWidget);
      expect(api.item?['icon'], '🍎');
      expect(find.text('🍎'), findsOneWidget);

      await tester.tap(find.text('Reis'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Menge (optional)'), '500 g');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(api.item?['ingredient_id'], 11);
      expect(find.text('500 g'), findsOneWidget);

      await tester.tap(find.byTooltip('Vorratsaktionen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alle einklappen'));
      await tester.pumpAndSettle();
      expect(find.text('500 g'), findsNothing);
      await tester.tap(find.byTooltip('Vorratsaktionen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alle ausklappen'));
      await tester.pumpAndSettle();
      expect(find.text('500 g'), findsOneWidget);

      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      list.onReorderItem!(0, 1);
      await tester.pumpAndSettle();
      expect(api.order, [2, 1]);

      await tester.tap(find.byTooltip('Aktionen für Vorräte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kategorie bearbeiten'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🥕  Möhre').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(api.categoryIcon, '🥕');
      expect(find.text('🥕'), findsOneWidget);

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
  List<String> categoryNames = ['Vorräte', 'Gemüse'];
  List<Json> extraItems = [];
  String? categoryIcon;
  Json? item;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    final uri = Uri.parse(path);
    return switch (uri.path) {
      '/api/pantry' => {
        'categories': [
          for (final id in order)
            {
              'id': id,
              'name': categoryNames[id - 1],
              'icon': id == 1 ? categoryIcon : null,
            },
        ],
        'items': [...extraItems, if (item != null) item],
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
      case ('PUT', '/api/pantry/categories/1'):
        categoryIcon = body!['icon'] as String?;
      case ('DELETE', '/api/pantry/categories/1'):
        order.remove(1);
        item = null;
      default:
        throw StateError('Unexpected API write: $method $path');
    }
    return {'ok': true};
  }
}
