import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/connection.dart';
import 'package:rezeptgarten/recipe_search.dart';
import 'package:rezeptgarten/telegram_service.dart';

class TestConnection extends ConnectionController {
  TestConnection(super.api, super.telegram);
  void change(ConnectionMode value) {
    mode = value;
    notifyListeners();
  }
}

class SearchApi extends RezeptgartenApi {
  final calls = <String>[];
  final pending = <Completer<Json>>[];
  @override
  Future<dynamic> get(String path, {Duration? timeout}) {
    calls.add(path);
    final completer = Completer<Json>();
    pending.add(completer);
    return completer.future;
  }
}

void main() {
  testWidgets('search fits a narrow display with large text', (tester) async {
    tester.view.physicalSize = const Size(332, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = RecipeSearchState(SearchApi(), null);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)),
        child: child!,
      ),
      home: RecipeSearchPage(state: state, openRecipe: (_, _) async {}),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('switching to Telegram cancels the catalog search', (
    tester,
  ) async {
    final api = SearchApi();
    final connection = TestConnection(api, TelegramService());
    connection.change(ConnectionMode.local);
    final state = RecipeSearchState(api, connection);
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeSearchPage(state: state, openRecipe: (_, _) async {}),
      ),
    );
    state.query.text = 'Reis Tomaten';
    state.setCatalog(true);
    await tester.pump();
    expect(api.calls.single, startsWith('/api/cookidoo/search?'));
    connection.change(ConnectionMode.telegram);
    await tester.pump();
    expect(state.catalog, isFalse);
    expect(api.calls.last, startsWith('/api/search/local?'));
    expect(find.text('Cookidoo-Suche im Heimnetz verfügbar.'), findsOneWidget);
    api.pending.first.complete({
      'items': [
        {'id': 'remote', 'name': 'Alt'},
      ],
      'next_page': null,
    });
    api.pending.last.complete({
      'items': [
        {'id': 'local', 'name': 'Reis'},
      ],
      'total': 1,
      'offset': 0,
    });
    await tester.pump();
    expect(find.text('Alt'), findsNothing);
    expect(find.text('Reis'), findsOneWidget);
    expect(state.query.text, 'Reis Tomaten');
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    connection.dispose();
  });
}
