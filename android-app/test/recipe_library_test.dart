import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/recipe_library.dart';
import 'package:rezeptgarten/recipe_card.dart';

void main() {
  testWidgets('equal-width recipe cards keep the same height with long titles', (
    tester,
  ) async {
    final api = _LibraryApi();
    const longTitle =
        'Gebratener Reis mit winterlichem Ofengemüse, Kichererbsen und Kräutern';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 144,
                child: RecipeCard(api: api, recipe: const {'name': 'Reis'}),
              ),
              SizedBox(
                width: 144,
                child: RecipeCard(
                  api: api,
                  recipe: const {
                    'name': longTitle,
                    'difficulty': 'advanced',
                    'total_seconds': 3600,
                    'version_servings': [2, 4, 6, 8, 10],
                    'has_note': true,
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cards = find.byType(RecipeCard);
    expect(tester.getSize(cards.first), tester.getSize(cards.last));
    final title = tester.widget<Text>(find.text(longTitle));
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recipe cards display advanced difficulty in German', (
    tester,
  ) async {
    final api = _LibraryApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeCard(
            api: api,
            recipe: const {
              'id': 'r1',
              'name': 'Reis',
              'difficulty': 'advanced',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Anspruchsvoll'), findsOneWidget);
  });
  testWidgets(
    'search, sorting and multiple ingredient filters use the recipe API',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _LibraryApi()..present = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecipeBrowser(api: api, openRecipe: (_) async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Gemüse');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(api.lastRecipeQuery['q'], ['Gemüse']);
      await tester.tap(find.text('Name · A bis Z'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kürzeste Gesamtzeit'));
      await tester.pumpAndSettle();
      expect(api.lastRecipeQuery['sort'], ['time']);

      await tester.tap(find.text('Filtern'));
      await tester.pumpAndSettle();
      expect(find.text('Rezepte filtern'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      Finder field(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      await tester.enterText(field('Zutat'), 'Paprika');
      await tester.tap(find.byTooltip('Zutat zum Filter hinzufügen'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Zutat'), 'Reis');
      await tester.enterText(field('Mindestens Portionen'), '4');
      await tester.enterText(field('Gesamtzeit höchstens (Min.)'), '30');
      await tester.ensureVisible(find.text('Anwenden'));
      await tester.tap(find.text('Anwenden'));
      await tester.pumpAndSettle();
      expect(api.lastRecipeQuery['ingredient'], ['Paprika', 'Reis']);
      expect(api.lastRecipeQuery['min_servings'], ['4']);
      expect(api.lastRecipeQuery['max_minutes'], ['30']);
      expect(find.text('2 Rezepte'), findsOneWidget);
      final card = find.ancestor(
        of: find.text('Gemüsesuppe'),
        matching: find.byType(Opacity),
      );
      expect(card, findsOneWidget);
      expect(tester.widget<Opacity>(card).opacity, lessThan(1));
    },
  );

  testWidgets('compact recipe grid stays visible until search returns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(332, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _LibraryApi()..present = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeBrowser(api: api, openRecipe: (_) async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byType(RecipeCard).at(0)).dy,
      tester.getTopLeft(find.byType(RecipeCard).at(1)).dy,
    );

    final sort = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Name · A bis Z'),
    );
    final filter = tester.getRect(find.widgetWithText(FilledButton, 'Filtern'));
    final search = tester.getRect(find.byType(TextField));
    expect(sort.width, filter.width);
    expect(sort.top, filter.top);
    expect(sort.height, filter.height);
    expect(sort.left, search.left);
    expect(filter.right, search.right);

    final result = Completer<void>();
    api.searchPending = result.future;
    await tester.enterText(find.byType(TextField), 'Reis');
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.lastRecipeQuery['offset'], ['0']);
    expect(find.text('Gemüsesuppe'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    result.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.byTooltip('Suche leeren'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(api.lastRecipeQuery['q'], ['']);
  });

  testWidgets('adds and removes recipes from the same list editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Abendessen',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anlegen'));
    await tester.pumpAndSettle();
    expect(api.name, 'Abendessen');

    await tester.tap(find.text('Abendessen'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('Abendessen')).style?.fontWeight,
      FontWeight.w700,
    );
    expect(find.byType(RecipeCard), findsOneWidget);
    final preview = tester.widget<Card>(
      find.descendant(of: find.byType(RecipeCard), matching: find.byType(Card)),
    );
    expect((preview.shape! as OutlinedBorder).side.style, BorderStyle.solid);
    expect(find.text('Liste öffnen'), findsNothing);
    await tester.tap(find.byTooltip('Liste verwalten'));
    await tester.pumpAndSettle();
    expect(find.text('Alle Rezepte'), findsOneWidget);
    expect(find.text('Gemüsesuppe'), findsOneWidget);
    expect(find.byTooltip('Reis zur Liste hinzufügen'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Reis');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Gemüsesuppe'), findsNothing);
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(syncs, 1);
    expect(api.lastRecipeQuery['exclude_collection'], ['local:meals']);
    expect(api.lastRecipeQuery['q'], ['Reis']);
    final addRice = find.byTooltip('Reis zur Liste hinzufügen');
    final riceCard = find.ancestor(
      of: addRice,
      matching: find.byType(RecipeCard),
    );
    expect(riceCard, findsOneWidget);
    final card = tester.widget<RecipeCard>(riceCard);
    final candidate = tester.widget<Card>(
      find.descendant(of: riceCard, matching: find.byType(Card)),
    );
    expect((candidate.shape! as OutlinedBorder).side.style, BorderStyle.solid);
    expect(card.cornerAction?.icon, Icons.add);
    final bounds = tester.getRect(riceCard);
    final addCenter = tester.getCenter(addRice);
    expect(addCenter.dx, greaterThan(bounds.center.dx));
    expect(addCenter.dy, lessThan(bounds.center.dy));
    await tester.tap(addRice);
    await tester.pumpAndSettle();
    expect(api.present, isTrue);
    expect(find.byTooltip('Reis zur Liste hinzufügen'), findsNothing);
    expect(find.text('In dieser Liste'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(RecipeCard), matching: find.text('Reis')),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Reis',
    );
    await tester.tap(find.byTooltip('Suche leeren'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Gemüsesuppe'), findsOneWidget);

    final removeRice = find.byTooltip('Reis aus der Liste entfernen');
    expect(removeRice, findsNothing);
    await tester.tap(find.byTooltip('Rezepte entfernen'));
    await tester.pump();
    expect(removeRice, findsOneWidget);
    final rice = find.widgetWithText(RecipeCard, 'Reis');
    final initialPosition = tester.getTopLeft(rice);
    await tester.pump(const Duration(milliseconds: 65));
    expect(tester.getTopLeft(rice), isNot(initialPosition));
    await tester.tap(removeRice);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.present, isFalse);
    expect(removeRice, findsNothing);
    expect(addRice, findsOneWidget);

    await tester.tap(find.byTooltip('Fertig'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Gemüsesuppe aus der Liste entfernen'), findsNothing);
    final deleteButton = find.descendant(
      of: find.byType(AppBar),
      matching: find.byTooltip('Liste löschen'),
    );
    expect(deleteButton, findsOneWidget);
    expect(find.text('Liste löschen'), findsNothing);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(api.name, 'Abendessen');
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(api.name, 'Abendessen');
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
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

  testWidgets('long press reorders lists and restores the device order', (
    tester,
  ) async {
    const preferences = MethodChannel('de.rezeptgarten/preferences');
    final messenger = tester.binding.defaultBinaryMessenger;
    String? saved;
    messenger.setMockMethodCallHandler(preferences, (call) async {
      if (call.method == 'collectionOrder') return saved;
      expect(call.method, 'setCollectionOrder');
      saved = (call.arguments as Map)['order'] as String;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(preferences, null));
    final api = _LibraryApi()
      ..name = 'Abendessen'
      ..moreLists = true;

    Future<void> openLists() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecipeCollections(api: api, openRecipe: (_) async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await openLists();
    final dinner = find.text('Abendessen');
    final breakfast = find.text('Frühstück');
    final start = tester.getCenter(dinner);
    final end = tester.getCenter(breakfast);
    expect(start.dy, lessThan(end.dy));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 650));
    expect(find.byTooltip('Reihenfolge fertig'), findsOneWidget);
    for (var step = 1; step <= 5; step++) {
      await gesture.moveTo(
        Offset.lerp(start, end + const Offset(0, 70), step / 5)!,
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Reihenfolge fertig'));
    await tester.pumpAndSettle();
    expect(saved, '["cookidoo:breakfast","local:meals"]');
    expect(
      tester.getCenter(breakfast).dy,
      lessThan(tester.getCenter(dinner).dy),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await openLists();
    expect(
      tester.getCenter(breakfast).dy,
      lessThan(tester.getCenter(dinner).dy),
    );
  });

  testWidgets('opened lists show two recipe cards per row below their title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(332, 830);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _LibraryApi()
      ..name = 'Abendessen'
      ..present = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeCollections(api: api, openRecipe: (_) async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('Neue Liste')).dy,
      lessThan(tester.getCenter(find.byType(TextField)).dy),
    );
    await tester.tap(find.text('Abendessen'));
    await tester.pumpAndSettle();
    final cards = find.byType(RecipeCard);
    expect(cards, findsNWidgets(2));
    expect(tester.getTopLeft(cards.first).dy, tester.getTopLeft(cards.last).dy);
    expect(
      tester.getTopLeft(cards.first).dx,
      lessThan(tester.getTopLeft(cards.last).dx),
    );
    expect(tester.takeException(), isNull);
  });
}

class _LibraryApi extends RezeptgartenApi {
  _LibraryApi() : super(client: HttpClient());
  Map<String, List<String>> lastRecipeQuery = {};
  String? name;
  bool present = false;
  bool moreLists = false;
  Future<void>? searchPending;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    final uri = Uri.parse(path);
    switch (uri.path) {
      case '/api/recipes':
        lastRecipeQuery = uri.queryParametersAll;
        await searchPending;
        final candidate = uri.queryParameters.containsKey('exclude_collection');
        final editor =
            candidate || uri.queryParameters.containsKey('collection');
        final query = uri.queryParameters['q']?.toLowerCase() ?? '';
        final items = [
          if (candidate != present)
            {
              'id': 'r1',
              'name': 'Reis',
              'matches': true,
              'difficulty': 'advanced',
            },
          if (!candidate && (!editor || 'gemüsesuppe'.contains(query)))
            {'id': 'r2', 'name': 'Gemüsesuppe', 'matches': false},
        ];
        return {
          'items': items,
          'total': editor ? items.length : 2,
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
            if (moreLists)
              {'id': 'cookidoo:breakfast', 'name': 'Frühstück', 'kind': 'list'},
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
