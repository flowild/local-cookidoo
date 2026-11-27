import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/debug_api.dart';
import 'package:rezeptgarten/expressive_theme.dart';
import 'package:rezeptgarten/recipe_card.dart';
import 'package:rezeptgarten/spacing.dart';
import 'package:rezeptgarten/week_view.dart';

void main() {
  testWidgets(
    'week shows its layout and recipes while queue status is pending',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
    final previous = find.byTooltip('Vorherige Woche');
    final rotate = find.byTooltip('Ins Querformat drehen');
    final cart = find.byTooltip('In den Einkaufswagen');
    expect(
      tester.getRect(cart).right,
      closeTo(tester.getRect(find.text('Meine Woche')).right, 1),
    );
    final controls = [previous, current, next, todayButton, rotate, cart];
    final centers = controls.map(tester.getCenter).toList();
    for (final (index, center) in centers.indexed.skip(1)) {
      expect(center.dy, closeTo(centers.first.dy, 1));
      expect(center.dx, greaterThan(centers[index - 1].dx));
    }
    for (final button in [previous, next, todayButton, rotate, cart]) {
      expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
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

  testWidgets('week rotation requests one fixed orientation per tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final orientations = <Object?>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        orientations.add(call.arguments);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekView(
            api: _WeekApi(),
            openRecipe: (_, _) async {},
            cartCountChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(orientations, isEmpty);
    await tester.tap(find.byTooltip('Ins Querformat drehen'));
    expect(orientations, [
      ['DeviceOrientation.landscapeLeft'],
    ]);

    tester.view.physicalSize = const Size(840, 390);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ins Hochformat drehen'));
    expect(orientations, [
      ['DeviceOrientation.landscapeLeft'],
      ['DeviceOrientation.portraitUp'],
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape shows the week and plans between days and shelf', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    for (final day in ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']) {
      expect(find.text(day).hitTestable(), findsOneWidget);
    }
    expect(
      find.bySemanticsLabel('Heute, Mittwoch, 18.11.2026'),
      findsOneWidget,
    );
    expect(find.text('Lokale Listen').hitTestable(), findsOneWidget);

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tap(find.text('Platzhalter'));
    await tap(find.text('Sushi'));
    await tap(find.byTooltip('Freitag, 20.11.2026'));
    expect(api.placeholder?['create'], isTrue);
    expect(api.placeholder?['target'], '2026-11-20');

    await tap(find.byTooltip('Sushi'));
    await tap(find.byTooltip('Donnerstag, 19.11.2026'));
    expect(api.placeholder?['target'], '2026-11-19');

    await tap(find.byTooltip('Sushi'));
    await tap(find.text('In die Ablage'));
    expect(api.placeholder?['target'], 'shelf');
    await tap(find.text('Ablage'));
    await tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Sushi'),
      ),
    );
    await tap(find.byTooltip('Sonntag, 22.11.2026'));
    expect(api.placeholder?['target'], '2026-11-22');
    expect(tester.takeException(), isNull);
  });

  testWidgets('today reveals its day in the wider large-text planner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(640, 320),
              textScaler: TextScaler.linear(2),
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
    expect(find.text('Fr').hitTestable(), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Heute'));
    await tester.pumpAndSettle();
    expect(find.text('Fr').hitTestable(), findsOneWidget);
    expect(find.text('Ablage').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape recipe taps open details without a move dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _PlannerApi();
    final opened = <(String, bool)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekView(
            api: api,
            openRecipe: (recipe, calendar) async {
              opened.add((text(recipe['id']), calendar));
            },
            cartCountChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.more_horiz), findsNothing);

    for (final title in ['Linsensuppe mit Möhren', 'Apfelporridge']) {
      await tester.tap(find.widgetWithText(InkWell, title));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    }
    expect(opened, [('linsensuppe', true), ('apfelporridge', true)]);

    final shelf = find.widgetWithText(TextButton, 'Ablage');
    await tester.tap(shelf);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Apfelporridge'));
    await tester.pumpAndSettle();
    expect(opened.last, ('apfelporridge', true));
    expect(opened, hasLength(3));
    expect(find.byType(AlertDialog), findsNothing);
    expect(api.moves, isEmpty);

    await tester.tap(shelf);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Apfelporridge aus der Ablage entfernen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.moves.single['target'], 'trash');
    expect(find.text('Rückgängig'), findsOneWidget);
  });

  testWidgets('touch moves a shelf thumbnail onto and between planner days', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final haptics = <Object?>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final api = _PlannerApi();
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
    final shelf = find.widgetWithText(TextButton, 'Ablage');
    final apple = find.widgetWithText(InkWell, 'Apfelporridge');
    expect(apple, findsOneWidget);
    expect(tester.getCenter(apple).dy, tester.getCenter(shelf).dy);
    final title = find.descendant(
      of: apple,
      matching: find.text('Apfelporridge'),
    );
    expect(title, findsOneWidget);
    expect(tester.widget<Text>(title).maxLines, 3);
    expect(tester.getRect(apple).contains(tester.getCenter(title)), isTrue);
    expect(tester.getSize(apple).height, greaterThanOrEqualTo(88));

    final sunday = find.bySemanticsLabel(RegExp(r'(Heute, )?Sonntag, '));
    final saturday = find.bySemanticsLabel(RegExp(r'(Heute, )?Samstag, '));
    Future<void> dragTo(Finder day, Duration hold, int expectedHaptics) async {
      final finger = await tester.startGesture(tester.getCenter(apple));
      await tester.pump(hold);
      expect(haptics.length, expectedHaptics);
      await finger.moveTo(tester.getCenter(day));
      await tester.pump();
      await finger.up();
      await tester.pumpAndSettle();
    }

    await dragTo(sunday, const Duration(milliseconds: 140), 0);
    expect(api.moves, isEmpty);
    await dragTo(sunday, const Duration(milliseconds: 160), 1);
    final week = await api.get('/api/calendar/week') as Json;
    final dates = objects(week['days']).map((day) => day['date']).toList();
    expect(api.moves.single['source'], 'shelf');
    expect(api.moves.single['target'], dates[6]);
    expect(
      tester.getCenter(apple).dx,
      greaterThan(tester.getTopLeft(sunday).dx),
    );

    await dragTo(saturday, const Duration(milliseconds: 160), 2);
    expect(api.moves.last['source'], dates[6]);
    expect(api.moves.last['target'], dates[5]);
    expect(haptics, List.filled(2, 'HapticFeedbackType.lightImpact'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('short landscape shows the first two-line recipe in full', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 228);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const title = 'Linsensuppe mit Möhren';
    final api = _WeekApi(recipeName: title)
      ..queued = [
        {'source': '2026-11-16', 'target': 'shelf', 'recipe_id': 'anderes'},
      ];
    await tester.pumpWidget(
      MaterialApp(
        theme: rezeptgartenTheme(Brightness.light, 0xff234d3c),
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
    expect(find.text('Änderungen vorgemerkt').hitTestable(), findsOneWidget);
    final recipe = find.text(title);
    final dayCard = find.ancestor(of: recipe, matching: find.byType(Card));
    expect(dayCard, findsOneWidget);
    expect(
      tester.getRect(recipe).bottom,
      lessThan(tester.getRect(dayCard).bottom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('local list planning stages the recipe before placing it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(670, 330);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _PlannerApi();
    await api.write('PUT', '/api/local-collections/test-alltag', {
      'name': 'Schnelle Alltagsküche',
    });
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

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tap(find.text('Lokale Listen'));
    await tap(find.text('Schnelle Alltagsküche'));
    await tap(find.byTooltip('Linsensuppe mit Möhren einplanen'));
    await tap(find.byTooltip(RegExp(r'^Sonntag, ')));
    expect(api.moves.map((move) => move['source']), ['library', 'shelf']);
    expect(api.moves.first['target'], 'shelf');
    final week = await api.get('/api/calendar/week') as Json;
    final sunday = objects(week['days']).last;
    expect(api.moves.last['target'], sunday['date']);
    expect(
      objects(sunday['recipes']).map((recipe) => recipe['id']),
      contains('linsensuppe'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('recipe metadata stays below the action in narrow day columns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1100);
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
    final shoppingButton = tester.getRect(
      find.byTooltip('In den Einkaufswagen'),
    );
    expect(weekButton.dy, closeTo(shoppingButton.center.dy, 1));
    expect(
      shoppingButton.right,
      closeTo(tester.getRect(find.text('Meine Woche')).right, 1),
    );
    expect(shoppingButton.left - weekButton.dx, greaterThan(300));
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

  testWidgets('a planned placeholder shows its bundled image on the day', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _WeekApi()
      ..placeholder = {'placeholder': 'sushi', 'target': '2026-11-16'};
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
    final card = find.widgetWithText(RecipeCard, 'Sushi');
    final image = tester.widget<Image>(
      find.descendant(of: card, matching: find.byType(Image)),
    );
    expect(
      image.image,
      const AssetImage('assets/week_placeholders/sushi.webp'),
    );
    final move = find.byTooltip('Sushi in die Ablage');
    await tester.ensureVisible(move);
    await tester.pumpAndSettle();
    await tester.tap(move);
    await tester.pumpAndSettle();
    expect(api.placeholder?['target'], 'shelf');
    expect(tester.widget<RecipeCard>(card).compact, isTrue);
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
    final thumbnails = find.descendant(
      of: options,
      matching: find.byType(Image),
    );
    expect(tester.widgetList<Image>(thumbnails).map((image) => image.image), [
      for (final type in [
        'restaurant',
        'fastfood',
        'sushi',
        'pasta',
        'abendbrot',
        'resteessen',
      ])
        AssetImage('assets/week_placeholders/$type.webp'),
    ]);
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
            find.descendant(of: placeholder, matching: find.byType(Image)),
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
      final week = await super.get(path, timeout: timeout) as Json;
      return {
        ...week,
        'today': '2026-11-18',
        'days': [
          for (var day = 16; day <= 22; day++)
            {'date': '2026-11-$day', 'recipes': <Json>[]},
        ],
        'shelf': <Json>[],
      };
    }
    return super.get(path, timeout: timeout);
  }
}

class _PlannerApi extends DebugRezeptgartenApi {
  final moves = <Json>[];

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    if (path == '/api/calendar/placement' && body != null) {
      if (body['source'] == 'library' && body['target'] != 'shelf') {
        throw const ApiException('Ungültiges Ziel für diese Woche.');
      }
      moves.add(body);
    }
    return super.write(method, path, body);
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
  _WeekApi({this.recipeName = 'Reisgericht'}) : super(client: HttpClient());

  final String recipeName;
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
          'recipes': [
            {...recipe, 'name': recipeName},
          ],
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
