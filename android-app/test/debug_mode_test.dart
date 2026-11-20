import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/debug_api.dart';
import 'package:rezeptgarten/main.dart';

void main() {
  testWidgets('the settings switch works with an unreachable server', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _UnreachableApi();
    await tester.pumpWidget(RezeptgartenApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Testserver nicht erreichbar.'), findsOneWidget);

    await tester.tap(find.byTooltip('Einstellungen öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Debug-Modus'));
    await tester.pumpAndSettle();
    final calls = api.calls;
    expect(find.text('Debug-Modus · Testdaten'), findsOneWidget);
    expect(find.text('Linsensuppe mit Möhren'), findsOneWidget);

    await tester.tap(find.byTooltip('Einkaufswagen öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('Mein Einkaufswagen'), findsOneWidget);
    expect(find.text('200 g Rote Linsen'), findsOneWidget);

    await tester.tap(find.byTooltip('Einstellungen öffnen'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
      isTrue,
    );
    expect(find.text('Nach Updates suchen'), findsNothing);
    expect(api.calls, calls);
    await tester.tap(find.text('Debug-Modus'));
    await tester.pumpAndSettle();
    expect(find.text('Debug-Modus · Testdaten'), findsNothing);
    expect(find.text('Testserver nicht erreichbar.'), findsOneWidget);
    expect(api.calls, greaterThan(calls));
  });

  test('sample edits are isolated and exported as test data', () async {
    final first = DebugRezeptgartenApi();
    final second = DebugRezeptgartenApi();
    const note = '/api/notes/zitronenpasta';
    await first.write('PUT', note, {'text': 'Testnotiz', 'expected': ''});
    expect(await first.get(note), {'text': 'Testnotiz'});
    expect(await second.get(note), {'text': ''});

    final week = await first.get('/api/calendar/week') as Json;
    final monday = objects(week['days']).first['date'];
    await first.write('POST', '/api/calendar/placement', {
      'week': monday,
      'source': 'shelf',
      'target': 'trash',
      'recipe_id': 'apfelporridge',
      'move_id': 'test-move',
    });
    expect((await first.get('/api/calendar/week') as Json)['shelf'], isEmpty);
    await first.write('POST', '/api/calendar/undo-removal', {
      'move_id': 'test-move',
    });
    expect(
      (await first.get('/api/calendar/week') as Json)['shelf'],
      hasLength(1),
    );
    await first.write('POST', '/api/calendar/shopping', {'day': monday});
    expect(
      (await first.get('/api/cart') as Json)['items'],
      hasLength(greaterThan(1)),
    );
    expect(
      jsonDecode(utf8.decode(await first.exportCollection()))['debug'],
      isTrue,
    );
  });
}

class _UnreachableApi extends RezeptgartenApi {
  int calls = 0;

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    calls++;
    throw const ApiException('Testserver nicht erreichbar.');
  }
}
