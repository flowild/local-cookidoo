import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/recipe_library.dart';
import 'package:rezeptgarten/recipe_card.dart';

void main() {
  testWidgets('recipe cards display advanced difficulty in German', (tester) async {
    final api = _LibraryApi();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RecipeCard(
      api: api,
      recipe: const {'id': 'r1', 'name': 'Reis', 'difficulty': 'advanced'},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Anspruchsvoll'), findsOneWidget);
  });
  testWidgets('search and multiple ingredient filters use the collection API', (
    tester,
  ) async {
    final api = _LibraryApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeBrowser(
            api: api,
            collection: const {
              'id': 'local:meals',
              'name': 'Meine Rezepte',
              'kind': 'local',
            },
            openRecipe: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Gemüse');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(api.lastRecipeQuery['q'], ['Gemüse']);
    expect(api.lastRecipeQuery['show_all'], ['true']);

    await tester.tap(find.text('Filtern'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    await tester.enterText(field('Zutat'), 'Paprika');
    await tester.tap(find.byTooltip('Zutat zum Filter hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Zutat'), 'Reis');
    await tester.enterText(field('Mindestens Portionen'), '4');
    await tester.enterText(field('Gesamtzeit höchstens (Min.)'), '30');
    await tester.tap(find.text('Anwenden'));
    await tester.pumpAndSettle();
    expect(api.lastRecipeQuery['ingredient'], ['Paprika', 'Reis']);
    expect(api.lastRecipeQuery['min_servings'], ['4']);
    expect(api.lastRecipeQuery['max_minutes'], ['30']);
    expect(find.text('1 von 2 Rezepten passen zum Filter'), findsOneWidget);
    final card = find.ancestor(
      of: find.text('Gemüsesuppe'),
      matching: find.byType(Opacity),
    );
    expect(card, findsOneWidget);
    expect(tester.widget<Opacity>(card).opacity, lessThan(1));
  });

  testWidgets('creates a local list, adds a candidate and confirms removal', (
    tester,
  ) async {
    final api = _LibraryApi();
    var syncs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeCollections(
            api: api,
            openRecipe: (_) async {},
            onSync: () async {
              syncs++;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neue Liste'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Abendessen');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anlegen'));
    await tester.pumpAndSettle();
    expect(api.name, 'Abendessen');

    await tester.tap(find.text('Abendessen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rezepte hinzufügen'));
    await tester.pumpAndSettle();
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(syncs, 1);
    expect(api.lastRecipeQuery['exclude_collection'], ['local:meals']);
    await tester.tap(find.byTooltip('Reis zur Liste hinzufügen'));
    await tester.pumpAndSettle();
    expect(api.present, isTrue);
    expect(find.byTooltip('Reis zur Liste hinzufügen'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Liste löschen'));
    await tester.pumpAndSettle();
    expect(api.name, 'Abendessen');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Liste löschen'),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.name, isNull);
    expect(find.text('Abendessen'), findsNothing);
  });
}

class _LibraryApi extends RezeptgartenApi {
  _LibraryApi() : super(client: HttpClient());
  Map<String, List<String>> lastRecipeQuery = {};
  String? name;
  bool present = false;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    final uri = Uri.parse(path);
    switch (uri.path) {
      case '/api/recipes':
        lastRecipeQuery = uri.queryParametersAll;
        final candidate = lastRecipeQuery.containsKey('exclude_collection');
        final items = [
          if (candidate != present)
            {
              'id': 'r1',
              'name': 'Reis',
              'matches': true,
              'difficulty': 'advanced',
            },
          if (!candidate) {'id': 'r2', 'name': 'Gemüsesuppe', 'matches': false},
        ];
        return {
          'items': items,
          'total': candidate ? items.length : 2,
          'match_total': 1,
        };
      case '/api/collections':
        return {
          'items': [
            if (name != null)
              {
                'id': 'local:meals',
                'name': name,
                'kind': 'local',
                'recipe_count': present ? 1 : 0,
              },
          ],
        };
      case '/api/collections/local:meals/filter-options':
      case '/api/collections/local%3Ameals/filter-options':
        return {
          'ingredients': ['Paprika', 'Reis'],
          'ingredient_aliases': {
            'Paprika': ['Peperoni'],
          },
        };
      default:
        throw StateError('Unexpected API path: $path');
    }
  }

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    switch ((method, path)) {
      case ('POST', '/api/local-collections'):
        name = body!['name'] as String;
      case ('PUT', '/api/local-collections/local%3Ameals/recipes/r1'):
        present = body!['present'] == true;
      case ('DELETE', '/api/local-collections/local%3Ameals'):
        name = null;
      default:
        throw StateError('Unexpected API write: $method $path');
    }
    return {'ok': true};
  }
}
