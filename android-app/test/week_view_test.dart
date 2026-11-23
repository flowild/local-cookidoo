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
  testWidgets(
    'week shows its layout and recipes while queue status is pending',
    (tester) async {
      final api = _DelayedWeekApi();
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
      expect(find.text('Montag'), findsOneWidget);
      expect(find.text('Noch nichts geplant'), findsNothing);
      api.calendar.complete(await _WeekApi().get('/api/calendar/week') as Json);
      await tester.pump();
      expect(find.text('Reisgericht'), findsOneWidget);
      expect(api.status.isCompleted, isFalse);
      api.status.complete({'calendar_queue': <String, dynamic>{}});
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'week list pills show thumbnails and add once from the trailing plus',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? opened;
      final api = DebugRezeptgartenApi();
      await api.write('PUT', '/api/local-collections/test-alltag', {
        'name': 'Schnelle Alltagsküche',
        'icon': '🥔',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeekView(
              api: api,
              openRecipe: (recipe, _) async {
                opened = recipe['id'] as String;
              },
              cartCountChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tapVisible(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tapVisible(find.text('Lokale Listen'));
      expect(find.text('🥔'), findsOneWidget);
      await tapVisible(find.text('Schnelle Alltagsküche'));
      final pill = find.widgetWithText(
        CompactRecipeTile,
        'Linsensuppe mit Möhren',
      );
      final thumbnail = find.descendant(
        of: pill,
        matching: find.byType(RecipeImage),
      );
      expect(tester.widget<RecipeImage>(thumbnail).filename, 'linsensuppe.png');
      final add = find.descendant(of: pill, matching: find.byIcon(Icons.add));
      expect(
        tester.getCenter(thumbnail).dx,
        lessThan(tester.getCenter(add).dx),
      );
      await tapVisible(
        find.descendant(
          of: pill,
          matching: find.text('Linsensuppe mit Möhren'),
        ),
      );
      expect(opened, 'linsensuppe');
      opened = null;
      await tapVisible(add);
      expect(opened, isNull);
      final added = find.byTooltip(
        'Linsensuppe mit Möhren bereits in der Wochenablage',
      );
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(of: added, matching: find.byType(IconButton)),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'opens a week recipe during a badge read and keeps the loaded week',
    (tester) async {
      final api = _DelayedBadgesApi();
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final closed = Completer<void>();
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeekView(
              api: api,
              cartCountChanged: (_) {},
              openRecipe: (_, _) {
                opens++;
                return closed.future;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.badgeReads, 1);
      await tester.tap(find.text('Reisgericht').first);
      await tester.pump();
      expect(opens, 1);
      api.badges.complete({'items': <Json>[]});
      await tester.pump();
      closed.complete();
      await tester.pumpAndSettle();
      expect(api.weekReads, 1);
    },
  );
  testWidgets('highlights today and the current ISO week across New Year', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(332, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(332, 900),
              textScaler: TextScaler.linear(1.5),
            ),
            child: WeekView(
              api: _WeekBoundaryApi(),
              openRecipe: (_, _) async {},
              cartCountChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final current = find.text('KW 53');
    final next = find.byTooltip('Nächste Woche');
    expect(current, findsOneWidget);
    expect(find.bySemanticsLabel('Aktuelle Kalenderwoche 53'), findsOneWidget);
    final todayButton = find.widgetWithText(FilledButton, 'Heute');
    double page() =>
        tester.widget<PageView>(find.byType(PageView)).controller!.page!;
    expect(page(), 0);
    await tester.tap(todayButton);
    await tester.pumpAndSettle();
    expect(page(), 4);
    expect(find.text('Freitag, 01.01.2027'), findsOneWidget);
    expect(tester.getCenter(current).dy, closeTo(tester.getCenter(next).dy, 1));
    final currentColor = tester.widget<Text>(current).style?.color;

    await tester.tap(next);
    await tester.pumpAndSettle();
    final other = find.text('KW 1');
    expect(other, findsOneWidget);
    expect(find.bySemanticsLabel('Kalenderwoche 1'), findsOneWidget);
    expect(tester.widget<Text>(other).style?.color, isNot(currentColor));
    await tester.drag(find.byType(PageView), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(page(), isNot(4));

    await tester.tap(todayButton);
    await tester.pumpAndSettle();
    expect(current, findsOneWidget);
    expect(page(), 4);
    expect(find.text('Heute'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

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
    final weekButton = tester.getCenter(
      find.widgetWithText(FilledButton, 'Heute'),
    );
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
    final options = find.byType(CompactRecipeTile);
    expect(options, findsNWidgets(6));
    expect(
      tester.getRect(options.at(1)).top - tester.getRect(options.first).bottom,
      AppSpacing.related,
    );
    await tester.tap(
      find.byTooltip('Im Restaurant essen zur Wochenablage hinzufügen'),
    );
    await tester.pumpAndSettle();
    expect(api.placeholder?['create'], isTrue);
    expect(api.placeholder?['target'], 'shelf');
    final placeholder = find.widgetWithText(RecipeCard, 'Im Restaurant essen');
    expect(tester.widget<RecipeCard>(placeholder).compact, isTrue);
    expect(
      tester.getSize(placeholder),
      tester.getSize(find.widgetWithText(RecipeCard, 'Reisgericht')),
    );
    expect(
      tester
          .getCenter(
            find.descendant(of: placeholder, matching: find.text('🍴')),
          )
          .dy,
      lessThan(
        tester
            .getCenter(
              find.descendant(
                of: placeholder,
                matching: find.text('Im Restaurant essen'),
              ),
            )
            .dy,
      ),
    );

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

class _DelayedWeekApi extends _WeekApi {
  final status = Completer<Json>();
  final calendar = Completer<Json>();

  @override
  Future<dynamic> get(String path, {Duration? timeout}) => switch (path) {
    '/api/status' => status.future,
    '/api/calendar/week' => calendar.future,
    _ => super.get(path, timeout: timeout),
  };
}

class _DelayedBadgesApi extends _WeekApi {
  final badges = Completer<Json>();
  int weekReads = 0;
  int badgeReads = 0;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) {
    if (path == '/api/status') {
      return Future.value({'connected': true, 'calendar_queue': queue});
    }
    if (path == '/api/calendar/week') weekReads++;
    if (Uri.parse(path).path == '/api/calendar/badges') {
      badgeReads++;
      return badges.future;
    }
    return super.get(path, timeout: timeout);
  }
}

class _WeekBoundaryApi extends _WeekApi {
  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    final uri = Uri.parse(path);
    if (uri.path != '/api/calendar/week') {
      return super.get(path, timeout: timeout);
    }
    const today = '2027-01-01';
    final monday = DateTime.parse(
      "${uri.queryParameters['day'] ?? '2026-12-28'}T00:00:00Z",
    );
    return {
      'today': today,
      'days': [
        for (var day = 0; day < 7; day++)
          {
            'date': monday
                .add(Duration(days: day))
                .toIso8601String()
                .substring(0, 10),
            'recipes': <Json>[],
          },
      ],
      'shelf': <Json>[],
      'placeholder_placements': <Json>[],
    };
  }
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
