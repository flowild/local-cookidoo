import 'package:flutter_test/flutter_test.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/telegram_service.dart';

void main() {
  test('reads incoming and confirmed outgoing messages in the bot chat', () {
    const incoming = {
      'id': 24,
      'chat_id': 42,
      'is_outgoing': false,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 42},
      'content': {'@type': 'messageDocument'},
    };
    const outgoing = {'id': 25, 'chat_id': 42, 'is_outgoing': true};
    expect(telegramReadCommand(incoming, 42, 42), {
      '@type': 'viewMessages',
      'chat_id': 42,
      'message_ids': [24],
      'force_read': true,
    });
    expect(telegramReadCommand(outgoing, 42, 42)?['message_ids'], [25]);
    expect(telegramReadCommand(incoming, 99, 42), isNull);
    expect(telegramReadCommand(incoming, 42, 99), isNull);
    expect(telegramReadCommand(incoming, null, null), isNull);
    expect(
      telegramReadCommand(
        {
          ...outgoing,
          'sending_state': {'@type': 'messageSendingStatePending'},
        },
        42,
        42,
      ),
      isNull,
    );
  });

  test('Telegram uses revisions for repeated recipe reads', () async {
    final api = RezeptgartenApi();
    final revisions = <String?>[];
    api.localAllowed = () => false;
    api.telegramAllowed = () => true;
    api.telegramRequest = (method, path, body, {revision}) async {
      expect(method, 'GET');
      expect(path, '/api/recipes');
      revisions.add(revision);
      return {
        'status': revision == null ? 200 : 304,
        'revision': 'current',
        'body': revision == null ? {'items': []} : null,
      };
    };

    final initial = await api.get('/api/recipes');
    expect(await api.get('/api/recipes'), initial);
    expect(revisions, [null, 'current']);
    api.clearImageCache();
    await api.get('/api/recipes');
    expect(revisions.last, isNull);
  });

  test('Telegram writes and errors are handled by the usual API', () async {
    final api = RezeptgartenApi();
    api.localAllowed = () => false;
    api.telegramAllowed = () => true;
    api.telegramRequest = (method, path, body, {revision}) async {
      expect(method, 'PUT');
      expect(path, '/api/cart/entry/owned');
      expect(body, {'owned': true});
      return {
        'status': 409,
        'body': {'detail': 'Konflikt'},
      };
    };
    await expectLater(
      api.write('PUT', '/api/cart/entry/owned', {'owned': true}),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Konflikt',
        ),
      ),
    );
  });
}
