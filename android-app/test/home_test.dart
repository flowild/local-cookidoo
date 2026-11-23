import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/appearance.dart';
import 'package:rezeptgarten/debug_api.dart';
import 'package:rezeptgarten/expressive_theme.dart';
import 'package:rezeptgarten/home.dart';
import 'package:rezeptgarten/main.dart';
import 'package:rezeptgarten/pill_widgets.dart';
import 'package:rezeptgarten/recipe_card.dart';
import 'package:rezeptgarten/week_view.dart';

void main() {
  testWidgets('start and cart show controls before their data arrives', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _DelayedStartApi();
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Übersicht').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Deine Sammlung'), findsOneWidget);
    expect(find.text('Kein Zufallsrezept vorhanden.'), findsNothing);
    api.previews.complete({
      'items': [
        {'id': 'r1', 'name': 'Frühe Vorschau'},
      ],
    });
    await tester.pump();
    expect(find.text('Frühe Vorschau'), findsOneWidget);
    expect(api.featured.isCompleted, isFalse);
    api.featured.complete({});
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Einkaufswagen öffnen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Mein Einkaufswagen'), findsOneWidget);
    expect(find.text('Artikel hinzufügen'), findsOneWidget);
    expect(find.text('Noch keine Rezepte im Einkaufswagen.'), findsNothing);
    api.cart.complete({'items': <Json>[]});
    await tester.pumpAndSettle();
    expect(find.text('Noch keine Rezepte im Einkaufswagen.'), findsOneWidget);
  });

  for (final (width, scale, columns) in [
    (332.0, 1.0, 2),
    (332.0, 1.6, 1),
    (1100.0, 1.0, 4),
  ]) {
    testWidgets(
      'collection shortcuts align in $columns columns at $width / $scale',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final appearance = AppearanceController();
        addTearDown(appearance.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: rezeptgartenTheme(Brightness.light, defaultAccent),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RezeptgartenHome(
              api: DebugRezeptgartenApi(),
              appearance: appearance,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final navigation = find.byType(
          width < 600 ? NavigationBar : NavigationRail,
        );
        await tester.tap(
          find
              .descendant(
                of: navigation,
                matching: find.bySemanticsLabel(
                  RegExp(width < 360 ? 'Start' : 'Übersicht'),
                ),
              )
              .hitTestable()
              .first,
        );
        await tester.pumpAndSettle();
        final grid = find.byType(ActionPillGrid);
        final buttons = find.descendant(
          of: grid,
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        );
        expect(buttons, findsNWidgets(4));
        final bounds = tester.getRect(grid);
        final rects = [
          for (var i = 0; i < 4; i++) tester.getRect(buttons.at(i)),
        ];
        for (var i = 0; i < 4; i++) {
          final rect = rects[i];
          expect(rect.width, closeTo(rects.first.width, 0.01));
          expect(rect.height, greaterThanOrEqualTo(48));
          if (i % columns == 0) expect(rect.left, closeTo(bounds.left, 0.01));
          if (i % columns == columns - 1) {
            expect(rect.right, closeTo(bounds.right, 0.01));
          }
          expect(rect.top, rects[i - i % columns].top);
          if (i >= columns) {
            expect(rect.top, greaterThan(rects[i - columns].bottom));
          }
        }
        final cart = find.descendant(
          of: grid,
          matching: find.text('Einkaufswagen'),
        );
        await tester.ensureVisible(cart);
        await tester.pumpAndSettle();
        await tester.tap(cart);
        await tester.pumpAndSettle();
        expect(find.text('Mein Einkaufswagen'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final (width, brightness) in [
    (332.0, Brightness.dark),
    (1100.0, Brightness.light),
  ]) {
    testWidgets(
      'main sections and settings fit at width $width with large text',
      (tester) async {
        tester.view.physicalSize = Size(width, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final appearance = AppearanceController();
        addTearDown(appearance.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: rezeptgartenTheme(brightness, defaultAccent),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.5),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: RezeptgartenHome(
              api: DebugRezeptgartenApi(),
              appearance: appearance,
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in [
          width < 360 ? 'Start' : 'Übersicht',
          'Listen',
          'Rezepte',
          'Woche',
          'Einkauf',
          'Vorrat',
        ]) {
          final navigation = width < 600
              ? find.byType(NavigationBar)
              : find.byType(NavigationRail);
          final destination = find.descendant(
            of: navigation,
            matching: find.bySemanticsLabel(RegExp(label)),
          );
          await tester.tap(destination.hitTestable().first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
        }
        await tester.tap(find.byTooltip('Einstellungen öffnen').hitTestable());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('Android uses the web surface and accent colors in both modes', () {
    final light = rezeptgartenTheme(Brightness.light, defaultAccent);
    final dark = rezeptgartenTheme(Brightness.dark, defaultAccent);
    expect(light.scaffoldBackgroundColor, const Color(0xfff7f7f2));
    expect(light.cardTheme.color, Colors.white);
    expect(light.colorScheme.primary, const Color(0xff234d3c));
    expect(light.colorScheme.secondaryContainer, const Color(0xffedf1e5));
    expect(dark.scaffoldBackgroundColor, const Color(0xff102729));
    expect(dark.cardTheme.color, const Color(0xff1b383a));
    expect(dark.colorScheme.primary, const Color(0xff8fc9c5));
    expect(dark.colorScheme.secondaryContainer, const Color(0xff294a4b));
    final custom = rezeptgartenTheme(Brightness.light, 0xff8b3264);
    expect(custom.colorScheme.primary, isNot(light.colorScheme.primary));
    expect(custom.scaffoldBackgroundColor, light.scaffoldBackgroundColor);
  });

  testWidgets('returning to recipes keeps the search and avoids a new load', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _RecipeSearchApi();
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rezepte suchen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Reis');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Reis'), findsOneWidget);
    final reads = api.recipeReads;

    await tester.tap(find.text('Woche'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Rezepte'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'Reis',
    );
    expect(api.recipeReads, reads);
  });

  testWidgets(
    'reading a search result keeps the results and adding it updates the cart badge',
    (tester) async {
      final api = _SectionReadsApi();
      await tester.pumpWidget(RezeptgartenApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rezepte').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Zitrone');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final reads = api.reads['/api/recipes'];
      await tester.tap(find.text('Zitronenpasta').first);
      await tester.pumpAndSettle();
      final add = find.text('Zum Einkaufswagen hinzufügen');
      await tester.scrollUntilVisible(
        add.hitTestable(),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(add.hitTestable());
        await tester.pumpAndSettle();
        expect(
          find.text(
            attempt == 0
                ? 'Rezept im Einkaufswagen.'
                : 'Rezept bereits im Einkaufswagen.',
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(api.reads['/api/recipes'], reads);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Zitrone',
      );
      expect(
        find.descendant(
          of: find.byTooltip('Einkaufswagen öffnen'),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('narrow phones use a shorter start label', (tester) async {
    tester.view.physicalSize = const Size(332, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RezeptgartenApp(api: _TestApi()));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Übersicht'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'overview and library share two recipe columns on narrow phones',
    (tester) async {
      tester.view.physicalSize = const Size(332, 875);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(RezeptgartenApp(api: DebugRezeptgartenApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      final previews = find.descendant(
        of: find.byType(RecipePreviewGrid),
        matching: find.byType(RecipeCard),
      );
      final first = tester.getRect(previews.at(0));
      final second = tester.getRect(previews.at(1));
      expect(first.width, second.width);
      expect(first.top, second.top);

      await tester.tap(find.text('Rezepte'));
      await tester.pumpAndSettle();
      final cards = find.byType(RecipeCard);
      final libraryFirst = tester.getRect(cards.at(0));
      final librarySecond = tester.getRect(cards.at(1));
      expect(libraryFirst.width, first.width);
      expect(librarySecond.top, libraryFirst.top);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('swipes through main sections and keeps the week day swipe', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RezeptgartenApp(api: DebugRezeptgartenApi()));
    await tester.pumpAndSettle();

    int selectedSection() =>
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;
    expect(selectedSection(), 3);
    final pager = find.byKey(const ValueKey('main-pager'));
    final week = find.byWidgetPredicate(
      (widget) =>
          widget is PageView && widget.key != const ValueKey('main-pager'),
    );
    final days = tester.widget<PageView>(week).controller!;
    final initialDay = days.page!.round();
    final dayDelta = initialDay == 6 ? 1.0 : -1.0;
    await tester.drag(week, Offset(260 * dayDelta, 0));
    await tester.pumpAndSettle();
    expect(days.page, isNot(initialDay));
    expect(selectedSection(), 3);

    final body = tester.getRect(find.byKey(const ValueKey('main-content')));
    final swipeStart = Offset(body.center.dx, body.top + 32);
    final today = find.widgetWithText(FilledButton, 'Heute');
    final todayX = tester.getCenter(today).dx;
    final originalWeek = tester.widget<WeekView>(find.byType(WeekView));
    final shortDrag = await tester.startGesture(swipeStart);
    await shortDrag.moveBy(const Offset(24, 0));
    await shortDrag.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(tester.getCenter(today).dx, greaterThan(todayX));
    await shortDrag.up();
    await tester.pumpAndSettle();
    expect(selectedSection(), 3);
    expect(tester.getCenter(today).dx, todayX);

    final drag = await tester.startGesture(swipeStart);
    await drag.moveBy(const Offset(24, 0));
    await drag.moveBy(const Offset(250, 0));
    await tester.pump();
    final search = find.byType(TextField);
    expect(tester.getCenter(today).dx, closeTo(todayX + 250, 1));
    expect(tester.getRect(search).left, lessThan(body.left));
    expect(tester.getRect(search).right, greaterThan(body.left));
    expect(selectedSection(), 2);
    expect(
      tester.widget<WeekView>(find.byType(WeekView)),
      same(originalWeek),
      reason: 'Crossing the midpoint only updates the navigation indicator.',
    );
    await drag.moveBy(const Offset(-200, 0));
    await tester.pump();
    expect(selectedSection(), 3);
    expect(tester.widget<WeekView>(find.byType(WeekView)), same(originalWeek));
    await drag.moveBy(const Offset(200, 0));
    await tester.pump();
    expect(selectedSection(), 2);
    expect(
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .animationDuration,
      Duration.zero,
    );
    await drag.up();
    await tester.pumpAndSettle();
    expect(selectedSection(), 2);
    expect(tester.getRect(search).left, greaterThanOrEqualTo(body.left));

    Future<void> swipe(double dx) async {
      final body = tester.getRect(find.byKey(const ValueKey('main-content')));
      await tester.dragFrom(
        Offset(body.center.dx, body.top + 32),
        Offset(dx, 0),
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Listen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      tester.widget<PageView>(pager).controller!.page,
      allOf(greaterThan(1), lessThan(2)),
    );
    await tester.pumpAndSettle();
    expect(selectedSection(), 1);

    await tester.flingFrom(swipeStart, const Offset(-100, 0), 1100);
    await tester.pumpAndSettle();
    expect(selectedSection(), 2);

    for (final section in [1, 0, 0]) {
      await swipe(260);
      expect(selectedSection(), section);
    }
    for (final section in [1, 2, 3, 4, 5, 5]) {
      await swipe(-260);
      expect(selectedSection(), section);
    }
  });

  testWidgets(
    'a fast tab fling settles without passing its destination or reversing',
    (tester) async {
      await tester.pumpWidget(RezeptgartenApp(api: DebugRezeptgartenApi()));
      await tester.pumpAndSettle();
      final pager = tester.widget<PageView>(
        find.byKey(const ValueKey('main-pager')),
      );
      final position = pager.controller!.position;
      final target = position.viewportDimension * 2;
      for (final speed in [-6000.0, -3000.0, 3000.0, 6000.0]) {
        final start = target - speed.sign * 24;
        final metrics = position.copyWith(pixels: start);
        final motion = position.physics.createBallisticSimulation(
          metrics,
          speed,
        )!;
        var previous = start;
        for (var ms = 1; ms <= 1000; ms++) {
          final offset = motion.x(ms / 1000);
          expect((target - offset) * speed.sign, greaterThanOrEqualTo(-0.001));
          expect(
            (offset - previous) * speed.sign,
            greaterThanOrEqualTo(-0.001),
          );
          previous = offset;
        }
        expect(previous, closeTo(target, 0.001));
      }
    },
  );

  testWidgets('main navigation fits a narrow screen with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _TestApi();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: RezeptgartenApp(api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipes to visited sections without reloading them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _SectionReadsApi();
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pumpAndSettle();

    for (final (target, from, dx, path, anchor) in [
      ('Listen', 'Rezepte', 260.0, '/api/collections', 'Schnelle Alltagsküche'),
      (
        'Woche',
        'Rezepte',
        -260.0,
        '/api/calendar/week',
        'Ablage für diese Woche',
      ),
      ('Vorrat', 'Einkauf', -260.0, '/api/pantry', 'Trockenwaren'),
      ('Einkauf', 'Vorrat', 260.0, '/api/cart', 'Mein Einkaufswagen'),
      (
        'Übersicht',
        'Listen',
        260.0,
        '/api/featured-recipe',
        'Dein Rezeptmix',
      ),
    ]) {
      await tester.tap(find.text(target));
      await tester.pumpAndSettle();
      final item = find.text(anchor);
      final originalPosition = tester.getTopLeft(item);
      await tester.tap(find.text(from));
      await tester.pumpAndSettle();

      final reads = api.reads[path];
      final body = tester.getRect(find.byKey(const ValueKey('main-content')));
      await tester.dragFrom(
        Offset(body.center.dx, body.top + 32),
        Offset(dx, 0),
      );
      await tester.pumpAndSettle();
      expect(api.reads[path], reads);
      expect(tester.getTopLeft(item), originalPosition);
    }
  });

  final syncProgress = find.byWidgetPredicate(
    (widget) =>
        widget is CircularProgressIndicator &&
        widget.semanticsLabel == 'Synchronisierung läuft',
  );

  testWidgets('a late older status cannot hide a newly started sync', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _StaleStatusApi();
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pump();
    expect(api.syncs, 1);
    api.stale.complete({
      'connected': true,
      'sync': {'running': false},
      'cart_recipe_count': 0,
    });
    await tester.pump();
    expect(syncProgress, findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(syncProgress, findsNothing);
  });

  testWidgets('retries a failed sync status read until the sync completes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _SyncTestApi()..keepRunning = true;
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pump();
    expect(api.syncs, 1);
    api.statusFailures = 1;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(syncProgress, findsOneWidget);
    expect(find.textContaining('wird erneut geprüft'), findsOneWidget);
    api.keepRunning = false;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(syncProgress, findsNothing);
  });

  testWidgets('starts a sync on opening and on pull to refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _SyncTestApi();
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pump();
    expect(api.syncs, 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    final appBar = find.byType(AppBar);
    expect(
      find.descendant(of: appBar, matching: find.byIcon(Icons.sync)),
      findsNothing,
    );
    final content = tester.getRect(find.byType(RefreshIndicator).first);
    await tester.dragFrom(
      Offset(content.center.dx, content.top + 30),
      const Offset(0, 430),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(api.syncs, 2);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      api.weekReads,
      3,
      reason: 'Initial load, startup sync and manual refresh load the week once each.',
    );
  });

  testWidgets('week action opens a cart with a persistent checkbox', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _TestApi();
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('In den Einkaufswagen'));
    await tester.pumpAndSettle();
    expect(api.addedDay, '2026-11-16');

    await tester.tap(find.byTooltip('Einkaufswagen öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('100 g Reis'), findsOneWidget);

    final checkbox = find.byType(Checkbox);
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    final visibleCheckbox = checkbox.hitTestable();
    expect(visibleCheckbox, findsOneWidget);
    final ingredient = find.text('100 g Reis');
    final ingredientPosition = tester.getCenter(ingredient);
    final write = Completer<void>();
    api.ingredientWrite = write.future;
    await tester.tap(ingredient.hitTestable());
    await tester.pump();
    expect(tester.getCenter(ingredient), ingredientPosition);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    expect(api.owned, isFalse);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'An Cookidoo übertragen',
            ),
          )
          .onPressed,
      isNull,
    );
    write.complete();
    await tester.pumpAndSettle();
    expect(api.owned, isTrue);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);

    final conflict = Completer<void>();
    api.ingredientWrite = conflict.future;
    await tester.ensureVisible(ingredient);
    await tester.tap(ingredient.hitTestable());
    await tester.pump();
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    api.ownedRevision++;
    conflict.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    final remove = find.byTooltip('Reis mit Gemüse entfernen');
    await tester.scrollUntilVisible(remove, 250, scrollable: _verticalScroll);
    await tester.pumpAndSettle();
    final image = find.descendant(
      of: find.widgetWithText(CompactRecipeTile, 'Reis mit Gemüse'),
      matching: find.byType(RecipeImage),
    );
    expect(tester.widget<RecipeImage>(image).filename, '${'a' * 40}.webp');
    expect(tester.getSize(image), const Size.square(40));
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(api.addedDay, isNull);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('additional item supports explicit transfer and review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _TestApi();
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Einkaufswagen öffnen'));
    await tester.pumpAndSettle();

    final transfer = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton && widget.tooltip == 'An Cookidoo übertragen',
    );
    expect(find.byTooltip('Einkaufswagenaktionen'), findsNothing);
    expect(tester.widget<IconButton>(transfer).onPressed, isNull);
    expect(
      tester.getCenter(transfer).dy,
      closeTo(tester.getCenter(find.text('Mein Einkaufswagen')).dy, 1),
    );
    await tester.tap(find.text('Artikel hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'küch');
    await tester.pumpAndSettle();
    final suggestion = find.widgetWithText(ActionChip, 'Küchenrolle');
    expect(suggestion, findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Reis'), findsNothing);
    await tester.tap(suggestion);
    await tester.pumpAndSettle();
    expect(api.cartItem, isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Küchenrolle',
    );
    await tester.tap(find.text('Hinzufügen').hitTestable());
    await tester.pumpAndSettle();
    expect(api.cartItem, 'Küchenrolle');
    expect(api.extraStatus, 'pending');

    await tester.tap(transfer.hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Übertragung ungeklärt'), findsOneWidget);
    expect(find.text('Cookidoo prüfen.'), findsOneWidget);
    await tester.tap(find.text('Dort vorhanden').hitTestable());
    await tester.pumpAndSettle();
    expect(api.extraStatus, 'uncertain');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Dort vorhanden'),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.extraStatus, 'done');
    expect(find.text('Übertragen'), findsOneWidget);

    await tester.tap(find.byTooltip('Küchenrolle entfernen').hitTestable());
    await tester.pumpAndSettle();
    expect(api.cartItem, isNull);
  });

  testWidgets('large shopping lists build rows as they scroll into view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RezeptgartenApp(api: _LargeCartApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Einkaufswagen öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('Artikel 000'), findsOneWidget);
    final last = find.text('Artikel 099');
    expect(last, findsNothing);
    await tester.scrollUntilVisible(last, 300, scrollable: _verticalScroll);
    expect(last, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final _verticalScroll = find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

class _DelayedStartApi extends DebugRezeptgartenApi {
  final featured = Completer<Json>();
  final previews = Completer<Json>();
  final cart = Completer<Json>();

  @override
  Future<dynamic> get(String path, {Duration? timeout}) => switch (path) {
    '/api/featured-recipe' => featured.future,
    '/api/recipes?limit=8' => previews.future,
    '/api/cart' => cart.future,
    _ => super.get(path, timeout: timeout),
  };
}

class _LargeCartApi extends _TestApi {
  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    if (path == '/api/cart') {
      return {
        'items': [
          for (var i = 0; i < 100; i++)
            {
              'id': '$i',
              'kind': 'additional',
              'status': 'pending',
              'data': {'name': 'Artikel ${i.toString().padLeft(3, '0')}'},
            },
        ],
      };
    }
    return super.get(path, timeout: timeout);
  }
}

class _StaleStatusApi extends _SyncTestApi {
  int statusReads = 0;
  final stale = Completer<Json>();

  @override
  Future<dynamic> get(String path, {Duration? timeout}) {
    if (path == '/api/status' && ++statusReads == 2) return stale.future;
    return super.get(path, timeout: timeout);
  }
}

class _SyncTestApi extends _TestApi {
  int weekReads = 0;
  int syncs = 0;
  int statusFailures = 0;
  bool keepRunning = false;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    if (path == '/api/calendar/week') weekReads++;
    if (path.startsWith('/api/calendar/badges?')) return {'items': <Json>[]};
    if (path == '/api/status') {
      if (statusFailures > 0) {
        statusFailures--;
        throw const ApiException('Server vorübergehend nicht erreichbar.');
      }
      return {
        'connected': true,
        'sync': {'running': keepRunning && syncs > 0},
        'cart_recipe_count': 0,
      };
    }
    return super.get(path, timeout: timeout);
  }

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    if (method == 'POST' && path == '/api/sync') {
      syncs++;
      return {'started': true};
    }
    return super.write(method, path, body);
  }
}

class _SectionReadsApi extends DebugRezeptgartenApi {
  final reads = <String, int>{};

  @override
  Future<dynamic> get(String path, {Duration? timeout}) {
    reads.update(Uri.parse(path).path, (count) => count + 1, ifAbsent: () => 1);
    return super.get(path, timeout: timeout);
  }
}

class _RecipeSearchApi extends _TestApi {
  int recipeReads = 0;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    if (Uri.parse(path).path == '/api/recipes') {
      recipeReads++;
      return {'items': <Json>[], 'total': 0, 'match_total': 0};
    }
    return super.get(path, timeout: timeout);
  }
}

class _TestApi extends RezeptgartenApi {
  _TestApi() : super(client: HttpClient());

  String? addedDay;
  bool owned = false;
  int ownedRevision = 0;
  Future<void>? ingredientWrite;
  String? cartItem;
  String extraStatus = 'pending';

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async => switch (path) {
    '/api/status' => {'cart_recipe_count': addedDay == null ? 0 : 1},
    '/api/pantry' => {
      'items': [
        {'name': 'Küchenrolle', 'icon': '🧻'},
        {'name': 'Reis'},
      ],
    },
    '/api/calendar/week' => {
      'today': '2026-11-18',
      'days': [
        {
          'date': '2026-11-16',
          'recipes': [
            {'id': 'r1', 'name': 'Reis mit Gemüse'},
          ],
        },
      ],
    },
    '/api/cart' => {
      'items': [
        if (cartItem != null)
          {
            'id': 'cart-extra',
            'kind': 'additional',
            'status': extraStatus,
            'data': {'name': cartItem, 'owned': false},
          },
        if (addedDay != null)
          {
            'id': 'cart-entry',
            'recipe_id': 'r1',
            'kind': 'recipe',
            'status': 'pending',
            'data': {
              'name': 'Reis mit Gemüse',
              'image_file': '${'a' * 40}.webp',
              'ingredients': [
                {
                  'name': 'Reis',
                  'text': '100 g Reis',
                  'owned': owned,
                  'owned_revision': ownedRevision,
                },
              ],
            },
          },
      ],
    },
    _ => throw StateError('Unexpected API path: $path'),
  };

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    switch ((method, path)) {
      case ('POST', '/api/calendar/shopping'):
        addedDay = body?['day'] as String?;
      case ('PUT', '/api/cart/cart-entry/ingredients/0'):
        await ingredientWrite;
        if (body?['owned'] == true ||
            body?['owned_revision'] == ownedRevision) {
          owned = body?['owned'] == true;
          ownedRevision++;
        }
        return {'ok': true, 'owned': owned, 'owned_revision': ownedRevision};
      case ('POST', '/api/cart/items'):
        cartItem = body?['name'] as String?;
      case ('POST', '/api/cart/transfer'):
        extraStatus = 'uncertain';
        return {'status': 'partial', 'message': 'Cookidoo prüfen.'};
      case ('POST', '/api/cart/cart-extra/resolve'):
        extraStatus = body?['status'] as String;
      case ('DELETE', '/api/cart/cart-extra'):
        cartItem = null;
      case ('DELETE', '/api/cart/cart-entry'):
        addedDay = null;
      default:
        throw StateError('Unexpected API write: $method $path');
    }
    return {'ok': true};
  }
}
