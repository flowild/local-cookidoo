import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/debug_api.dart';
import 'package:rezeptgarten/recipe_card.dart';
import 'package:rezeptgarten/spacing.dart';
import 'package:rezeptgarten/week_view.dart';

void main() {
  testWidgets('recipe metadata stays below the action in narrow day columns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekView(
            api: DebugRezeptgartenApi(),
            openRecipe: (_, _) async {},
            cartCountChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);
    final weekButton = tester.getCenter(find.text('Diese Woche'));
    final shoppingButton = tester.getCenter(
      find.byTooltip('In den Einkaufswagen'),
    );
    expect(weekButton.dy, closeTo(shoppingButton.dy, 1));
    final monday = tester.getRect(
      find.ancestor(
        of: find.textContaining('Montag,'),
        matching: find.byType(Card),
      ),
    );
    final tuesday = tester.getRect(
      find.ancestor(
        of: find.textContaining('Dienstag,'),
        matching: find.byType(Card),
      ),
    );
    expect(tuesday.left - monday.right, closeTo(AppSpacing.item, 0.01));
    final action = tester.getRect(
      find.byTooltip('Linsensuppe mit Möhren in die Ablage'),
    );
    final duration = tester.getRect(find.text('35 Min.'));
    final portions = tester.getRect(find.text('4 Port.'));
    final photo = tester.getRect(
      find
          .ancestor(of: find.text('35 Min.'), matching: find.byType(ClipRRect))
          .first,
    );
    expect(duration.top, greaterThanOrEqualTo(action.bottom));
    expect(portions.top, greaterThanOrEqualTo(action.bottom));
    expect(duration.right, lessThan(photo.center.dx));
    expect(portions.left, greaterThan(photo.center.dx));
    expect(duration.bottom, lessThan(photo.bottom));
    expect(portions.bottom, lessThan(photo.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reports whether week shopping was empty, already present or added',
    (tester) async {
      tester.view.physicalSize = const Size(412, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _WeekApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeekView(
              api: api,
              openRecipe: (_, _) async {},
              cartCountChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final (result, message) in <(Json, String)>[
        (
          {'status': 'empty', 'added': 0},
          'In dieser Woche sind ab heute keine Rezepte eingeplant.',
        ),
        (
          {'status': 'ok', 'added': 0},
          'Die Rezepte dieser Woche stehen bereits im Einkaufswagen.',
        ),
        (
          {'status': 'ok', 'added': 2},
          '2 Rezepte wurden zum Einkaufswagen hinzugefügt.',
        ),
      ]) {
        api.shoppingResult = result;
        await tester.tap(find.byTooltip('In den Einkaufswagen'));
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        tester
            .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
            .clearSnackBars();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('late stored day does not override a day selected by the user', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final saved = Completer<int>();
    const preferences = MethodChannel('de.rezeptgarten/preferences');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(preferences, (call) async {
      if (call.method == 'weekDay') return saved.future;
      if (call.method == 'setWeekDay') return null;
      throw StateError('Unexpected preference request');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(preferences, null));
    final api = _MultipleDaysApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekView(
            api: api,
            openRecipe: (_, _) async {},
            cartCountChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final page = tester.widget<PageView>(find.byType(PageView));
    page.controller!.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(page.controller!.page, 1);
    saved.complete(0);
    await tester.pumpAndSettle();
    expect(page.controller!.page, 1);
  });

  testWidgets('the shelf shows recipe thumbnails in one scrollable row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekView(
            api: _ShelfApi(),
            openRecipe: (_, _) async {},
            cartCountChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = tester.getCenter(find.text('Ablagerezept 1'));
    final last = find.text('Ablagerezept 4');
    final lastBefore = tester.getCenter(last);
    expect(lastBefore.dy, closeTo(first.dy, 1));
    final cards = find.byWidgetPredicate(
      (widget) => widget is RecipeCard && widget.compact,
    );
    expect(cards, findsNWidgets(4));
    expect(
      find.descendant(of: cards, matching: find.byType(Image)),
      findsNWidgets(4),
    );
    expect(
      tester
          .getRect(
            find.descendant(of: cards.first, matching: find.byType(Image)),
          )
          .bottom,
      lessThan(first.dy),
    );
    final shelf = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    final bounds = tester.getRect(shelf);
    await tester.dragFrom(
      Offset(bounds.right - 12, bounds.center.dy),
      const Offset(-310, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getCenter(last).dx, lessThan(lastBefore.dx - 150));
  });

  testWidgets('swipes a selected recipe to the shelf and undoes its removal', (
    tester,
  ) async {
    final api = _WeekApi();
    tester.view.physicalSize = const Size(412, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekView(
            api: api,
            openRecipe: (_, _) async {},
            cartCountChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final recipe = find.text('Reisgericht');
    final resting = tester.getCenter(recipe);
    final shortSwipe = await tester.startGesture(resting);
    await tester.pump(const Duration(milliseconds: 270));
    await shortSwipe.moveBy(const Offset(0, -110));
    await tester.pump();
    expect(find.text('Entfernen'), findsOneWidget);
    expect(tester.getCenter(recipe).dy, lessThan(resting.dy));
    await shortSwipe.up();
    await tester.pumpAndSettle();
    expect(api.queued, isEmpty);
    expect(find.text('Entfernen'), findsNothing);
    expect(tester.getCenter(recipe), resting);

    final swipe = await tester.startGesture(resting);
    await swipe.moveBy(const Offset(0, 150));
    await tester.pump();
    expect(find.text('In die Ablage'), findsOneWidget);
    expect(tester.getCenter(recipe).dy, greaterThan(resting.dy));
    expect(api.queued, isEmpty);
    await swipe.up();
    await tester.pumpAndSettle();
    expect(api.shelf, isTrue);
    expect(api.queued.single['source'], '2026-11-16');
    expect(api.queued.single['target'], 'shelf');

    expect(find.byTooltip('Reisgericht entfernen'), findsNothing);
    final remove = await tester.startGesture(tester.getCenter(recipe));
    await tester.pump(const Duration(milliseconds: 270));
    await remove.moveBy(const Offset(0, 120));
    await tester.pump();
    expect(find.text('Entfernen'), findsOneWidget);
    await remove.up();
    await tester.pump();
    expect(api.shelf, isFalse);
    expect(find.text('Rückgängig'), findsOneWidget);
    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(api.shelf, isTrue);
    expect(find.text('Reisgericht'), findsOneWidget);

    await tester.tap(find.text('Platzhalter'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byTooltip('Im Restaurant essen zur Wochenablage hinzufügen'),
    );
    await tester.pumpAndSettle();
    expect(api.placeholder?['create'], isTrue);
    expect(api.placeholder?['target'], 'shelf');

    await tester.tap(find.byTooltip('Nächste Woche'));
    await tester.pumpAndSettle();
    expect(find.text('Woche nicht verfügbar.'), findsOneWidget);
    expect(find.byTooltip('Reisgericht entfernen'), findsNothing);
    expect(
      find.byTooltip('Im Restaurant essen zur Wochenablage hinzufügen'),
      findsNothing,
    );
  });
}

class _MultipleDaysApi extends _WeekApi {
  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    if (path == '/api/calendar/week') {
      return {
        'today': '2026-11-18',
        'days': [
          for (var day = 16; day <= 22; day++)
            {'date': '2026-11-$day', 'recipes': <Json>[]},
        ],
        'shelf': <Json>[],
        'placeholder_placements': <Json>[],
      };
    }
    return super.get(path, timeout: timeout);
  }
}

class _ShelfApi extends _WeekApi {
  final _bytes = File('assets/icon.png').readAsBytesSync();

  @override
  Future<Uint8List?> image(Object? filename, {bool full = false}) async =>
      filename == 'test-thumbnail.png' ? _bytes : null;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    final result = await super.get(path, timeout: timeout);
    if (path != '/api/calendar/week') return result;
    return <String, dynamic>{
      ...result as Json,
      'shelf': [
        for (var i = 1; i <= 4; i++)
          {
            'id': 's$i',
            'name': 'Ablagerezept $i',
            'image_file': 'test-thumbnail.png',
          },
      ],
    };
  }
}

class _WeekApi extends RezeptgartenApi {
  _WeekApi() : super(client: HttpClient());

  static const recipe = {
    'id': 'r1',
    'calendar_id': 'r1',
    'custom': false,
    'name': 'Reisgericht',
  };
  bool shelf = false;
  Json? placeholder;
  String? undoId;
  Json shoppingResult = {'status': 'empty', 'added': 0};
  List<Json> queued = [];

  Json get queue => {
    'phase': queued.isEmpty ? 'idle' : 'waiting',
    'items': queued,
  };

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async => switch (path) {
    '/api/status' => {'cart_recipe_count': 0, 'calendar_queue': queue},
    '/api/calendar/week' => {
      'today': '2026-11-18',
      'days': [
        {
          'date': '2026-11-16',
          'recipes': [recipe],
        },
      ],
      'shelf': [if (shelf) recipe],
      'placeholder_placements': [
        if (placeholder != null)
          {
            'id': 'p1',
            'placeholder': placeholder!['placeholder'],
            'target': placeholder!['target'],
          },
      ],
    },
    '/api/calendar/week?day=2026-11-23' => throw const ApiException(
      'Woche nicht verfügbar.',
    ),
    _ => throw StateError('Unexpected API path: $path'),
  };

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    switch ((method, path)) {
      case ('POST', '/api/calendar/shopping'):
        return shoppingResult;
      case ('POST', '/api/calendar/placement'):
        if (body!['source'] == '2026-11-16' && body['target'] == 'shelf') {
          shelf = true;
          queued = [body];
        } else if (body['source'] == 'shelf' && body['target'] == 'trash') {
          shelf = false;
          undoId = text(body['move_id']);
        } else {
          throw StateError('Unexpected placement.');
        }
        return queue;
      case ('POST', '/api/calendar/undo-removal'):
        if (undoId == null || body?['move_id'] != undoId) {
          throw StateError('Unexpected undo ID.');
        }
        shelf = true;
        return queue;
      case ('PUT', '/api/calendar/placeholders'):
        placeholder = body;
        return {
          'placements': [
            {
              'id': 'p1',
              'placeholder': body!['placeholder'],
              'target': body['target'],
            },
          ],
        };
      default:
        throw StateError('Unexpected API write: $method $path');
    }
  }
}
