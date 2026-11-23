import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/recipe_card.dart';
import 'package:rezeptgarten/recipe_detail.dart';

void main() {
  testWidgets('opens the recipe preview before the detail response', (
    tester,
  ) async {
    final api = _PendingRecipeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          api: api,
          preview: const {'id': 'creation:r1', 'name': 'In der Vorschau'},
          calendar: false,
        ),
      ),
    );
    expect(find.byType(RecipeCard), findsOneWidget);
    expect(find.text('In der Vorschau'), findsWidgets);
    expect(find.text('Zutaten'), findsNothing);
    api.detail.complete(
      await _DetailApi().get('/api/recipes/creation%3Ar1') as Json,
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Zutaten'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Zutaten'), findsOneWidget);
  });

  testWidgets(
    'a late note for a previous version cannot replace the current note',
    (tester) async {
      final api = _VersionApi();
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            api: api,
            preview: const {'id': 'v1'},
            calendar: false,
          ),
        ),
      );
      await tester.pump();
      final versions = find.byType(DropdownButton<String>);
      await tester.ensureVisible(versions);
      await tester.tap(versions);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('Meine Kreation 1').last);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      api.oldNote.complete({'text': 'Veraltete Notiz'});
      await tester.pumpAndSettle();
      final note = find.byType(TextField);
      await tester.ensureVisible(note);
      expect(tester.widget<TextField>(note).controller!.text, 'Aktuelle Notiz');
    },
  );
  testWidgets('a loaded note can be edited while tips are pending', (
    tester,
  ) async {
    final api = _DelayedDetailsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          api: api,
          preview: const {'id': 'creation:r1'},
          calendar: false,
        ),
      ),
    );
    await tester.pump();
    final field = find.byType(TextField);
    await tester.ensureVisible(field);
    expect(tester.widget<TextField>(field).readOnly, isFalse);
    await tester.enterText(field, 'Entwurf');
    api.tips.complete({
      'tips': ['Später Tipp'],
    });
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'Entwurf');
  });

  testWidgets(
    'opens local memberships in a bottom sheet and saves each change',
    (tester) async {
      final api = _ListMembershipApi();
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            api: api,
            preview: const {'id': 'creation:r1'},
            calendar: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.text('Zu lokalen Listen hinzufügen');
      await tester.scrollUntilVisible(
        button,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(api.listReads, 0);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      final quick = find.widgetWithText(CheckboxListTile, 'Schnell');
      final guests = find.widgetWithText(CheckboxListTile, 'Für Gäste');
      expect(tester.widget<CheckboxListTile>(quick).value, isTrue);
      expect(tester.widget<CheckboxListTile>(guests).value, isFalse);
      expect(find.text('Importiert'), findsNothing);

      await tester.tap(guests);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(guests).value, isTrue);
      expect(api.membershipWrites, [true]);
      await tester.tap(find.byTooltip('Schließen'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(guests).value, isTrue);
      await tester.tap(guests);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(guests).value, isFalse);
      expect(api.membershipWrites, [true, false]);
    },
  );
  testWidgets('plans the selected days from the recipe detail', (tester) async {
    final api = _DetailApi();
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          api: api,
          preview: const {'id': 'creation:r1'},
          calendar: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final plan = find
        .widgetWithText(FilledButton, 'Diese Woche kochen')
        .hitTestable();
    await tester.scrollUntilVisible(
      plan,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(plan);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(CheckboxListTile),
      ),
      findsNWidgets(3),
    );
    expect(find.text('Donnerstag, 19.11.2026'), findsNothing);
    final submit = find.widgetWithText(FilledButton, 'Einplanen');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(find.text('Freitag, 20.11.2026'));
    await tester.pump();
    await tester.tap(find.text('Sonntag, 22.11.2026'));
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(api.planned, ['2026-11-20', '2026-11-22']);
    expect(
      find.textContaining('Nicht bestätigt für 22.11.2026'),
      findsOneWidget,
    );
  });

  testWidgets('adds the selected recipe to the current week shelf', (
    tester,
  ) async {
    final api = _DetailApi();
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          api: api,
          preview: const {'id': 'creation:r1', 'name': 'Reisgericht'},
          calendar: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final add = find.text('Zur Ablage hinzufügen');
    await tester.scrollUntilVisible(
      find.text('Diese Woche kochen'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.getCenter(add).dy,
      lessThan(tester.getCenter(find.text('Diese Woche kochen')).dy),
    );
    for (final (label, icon, type) in [
      ('Zur Ablage hinzufügen', Icons.playlist_add, FilledButton),
      ('Diese Woche kochen', Icons.calendar_today_outlined, FilledButton),
      ('Zum Einkaufswagen hinzufügen', Icons.add_shopping_cart, FilledButton),
      ('In Cookidoo öffnen', Icons.open_in_new, OutlinedButton),
    ]) {
      final text = find.text(label);
      final button = find.ancestor(
        of: text,
        matching: find.byWidgetPredicate((widget) {
          return type == FilledButton
              ? widget is FilledButton
              : widget is OutlinedButton;
        }),
      );
      final leading = find.descendant(of: button, matching: find.byIcon(icon));
      expect(leading, findsOneWidget);
      final group = tester
          .getRect(leading)
          .expandToInclude(tester.getRect(text));
      expect(group.center.dx, closeTo(tester.getCenter(button).dx, 1));
      expect(
        tester.getRect(leading).right,
        lessThan(tester.getRect(text).left),
      );
    }
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(api.placements.single, {
      'week': '2026-11-16',
      'source': 'preview',
      'target': 'shelf',
      'recipe_id': 'r1',
      'custom': true,
      'recipe': <String, dynamic>{},
      'move_id': matches(RegExp(r'^[a-f0-9]{32}$')),
    });
    expect(
      find.text('Zur Ablage der aktuellen Woche hinzugefügt.'),
      findsOneWidget,
    );
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(api.placements, hasLength(1));
  });

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
      expect(find.byTooltip('Nicht im Vorrat'), findsOneWidget);
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

class _PendingRecipeApi extends _DetailApi {
  final detail = Completer<Json>();

  @override
  Future<dynamic> get(String path, {Duration? timeout}) =>
      path == '/api/recipes/creation%3Ar1'
      ? detail.future
      : super.get(path, timeout: timeout);
}

class _VersionApi extends _DetailApi {
  final oldNote = Completer<Json>();

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    if (path == '/api/notes/v1') return oldNote.future;
    if (path == '/api/notes/v2') return {'text': 'Aktuelle Notiz'};
    return {
      'id': path.split('/').last,
      'name': 'Versionsrezept',
      'tips_json': [],
      'versions': [
        {'id': 'v1'},
        {'id': 'v2', 'origin_recipe_id': 'v1'},
      ],
    };
  }
}

class _DelayedDetailsApi extends _DetailApi {
  final tips = Completer<Json>();

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    if (path.endsWith('/tips')) return tips.future;
    final result = await super.get(path, timeout: timeout);
    if (path.startsWith('/api/recipes/')) (result as Json).remove('tips_json');
    return result;
  }
}

class _ListMembershipApi extends _DetailApi {
  int listReads = 0;
  final membershipWrites = <bool>[];

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    if (path != '/api/collections') return super.get(path, timeout: timeout);
    listReads++;
    return {
      'items': [
        {'id': 'local:l1', 'kind': 'local', 'name': 'Schnell'},
        {'id': 'local:l2', 'kind': 'local', 'name': 'Für Gäste'},
        {'id': 'imported', 'kind': 'managed', 'name': 'Importiert'},
      ],
    };
  }

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    if (method == 'PUT' &&
        path == '/api/local-collections/local%3Al2/recipes/creation%3Ar1') {
      membershipWrites.add(body!['present'] as bool);
      return {'ok': true};
    }
    return super.write(method, path, body);
  }
}

class _DetailApi extends RezeptgartenApi {
  _DetailApi() : super(client: HttpClient());

  final writes = <Json>[];
  final placements = <Json>[];
  Object? planned;
  bool changedElsewhere = false;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async => switch (path) {
    '/api/recipes/creation%3Ar1' => {
      'id': 'creation:r1',
      'name': 'Reisgericht',
      'source_url': 'https://example.test/recipe',
      'ingredients_json': '[{"description":"2 EL","name":"Öl","preparation":"erwärmt"},"Wasser","Mehl"]',
      'hidden_ingredient_positions': [1],
      'ingredient_availability': {'0': true, '2': false},
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
    '/api/calendar/week' => {
      'days': [
        {'date': '2026-11-16'},
      ],
      'shelf': [
        if (placements.isNotEmpty) {'id': 'creation:r1'},
      ],
    },
    '/api/calendar/cooking-days' => {
      'days': ['2026-11-20', '2026-11-21', '2026-11-22'],
    },
    _ => throw StateError('Unexpected API path: $path'),
  };

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    if (method == 'POST' && path == '/api/recipes/creation%3Ar1/plan-week') {
      planned = body?['days'];
      return {
        'confirmed': ['2026-11-20'],
        'unconfirmed': ['2026-11-22'],
      };
    }
    if (method == 'POST' && path == '/api/calendar/placement' && body != null) {
      placements.add(body);
      return {
        'shelf_recipe': {'id': 'creation:r1'},
      };
    }
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
