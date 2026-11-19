import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/week_view.dart';

void main() {
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
        await tester.tap(find.text('In den Einkaufswagen'));
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

    await tester.longPress(find.text('Reisgericht'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Reisgericht'), const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(api.shelf, isTrue);
    expect(api.queued.single['source'], '2026-11-16');
    expect(api.queued.single['target'], 'shelf');

    await tester.tap(find.byTooltip('Reisgericht entfernen'));
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
