import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/telegram_service.dart';
import 'package:rezeptgarten/telegram_view.dart';

class FakeTelegram extends TelegramService {
  final calls = <String>[];
  Map<String, bool> saved = {};
  Completer<Map<String, bool>>? pendingChecks;

  @override
  Future<Json> snapshot(String kind, {String? day}) async {
    calls.add('$kind ${day ?? ''}');
    if (kind == 'cart') {
      return {
        'items': [
          {
            'kind': 'recipe',
            'name': 'Suppe',
            'ingredients': [
              {
                'check_id': 'a',
                'text': '2 Karotten',
                'icon_name': 'Karotte',
                'category': 'Gemüse',
                'owned': false,
              },
              {
                'check_id': 'b',
                'text': 'Mehl',
                'icon_name': 'Mehl',
                'in_pantry': true,
              },
            ],
          },
        ],
      };
    }
    return {
      'today': '2026-01-07',
      'days': [
        {
          'date': day,
          'recipes': ['Suppe'],
          'placeholders': ['sushi'],
        },
      ],
      'shelf': ['Brot'],
      'shelf_placeholders': ['resteessen'],
      'queue_phase': 'pending',
    };
  }

  @override
  Future<Map<String, bool>> loadChecks() async =>
      pendingChecks?.future ?? Map.of(saved);

  @override
  Future<void> saveChecks(Map<String, bool> checks) async =>
      saved = Map.of(checks);
}

void main() {
  testWidgets('shows week snapshots and changes the requested week', (
    tester,
  ) async {
    final telegram = FakeTelegram();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TelegramView(telegram: telegram, cart: false)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Suppe'), findsOneWidget);
    expect(find.text('Sushi'), findsOneWidget);
    expect(find.text('Resteessen'), findsOneWidget);
    expect(telegram.calls.last, 'week 2026-01-05');
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(telegram.calls.last, 'week 2026-01-12');
    telegram.dispose();
  });

  testWidgets('cart checks are local and pantry ingredients stay hidden', (
    tester,
  ) async {
    final telegram = FakeTelegram();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TelegramView(telegram: telegram, cart: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 Karotten'), findsOneWidget);
    expect(find.text('Mehl'), findsNothing);
    await tester.tap(find.text('Rezepte (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Suppe'), findsNWidgets(2));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(telegram.saved, {'a': true});
    await tester.tap(find.text('Häkchen zurücksetzen'));
    await tester.pumpAndSettle();
    expect(telegram.saved, isEmpty);
    telegram.dispose();
  });

  testWidgets('late saved checks do not overwrite a new change', (
    tester,
  ) async {
    final telegram = FakeTelegram()
      ..pendingChecks = Completer<Map<String, bool>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TelegramView(telegram: telegram, cart: true)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    telegram.pendingChecks!.complete({'a': false});
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    telegram.dispose();
  });
}
