import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rezeptgarten/api.dart';
import 'package:rezeptgarten/telegram_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'registers an Android pairing and accepts only its matching private reply',
    () async {
      const channel = MethodChannel('de.rezeptgarten/telegram');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? stored;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'write') stored = call.arguments as String?;
        return call.method == 'read' ? stored : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const sentAt = 1750000000;
      final api = _PairApi();
      String? nonce;
      final offsets = <Object?>[];
      final telegram = TelegramAccess(
        api,
        request: (_, method, payload) async {
          switch (method) {
            case 'getMe':
              return {'id': 123, 'is_bot': true};
            case 'sendMessage':
              expect(payload['chat_id'], '@TestServerBot');
              nonce = (payload['text'] as String).split(' ').last;
              expect(nonce, matches(RegExp(r'^[0-9a-f]{32}$')));
              return {'date': sentAt};
            case 'getUpdates':
              offsets.add(payload['offset']);
              if (offsets.length == 1) {
                return [
                  _update(2, 999, sentAt, 'rezeptgarten-pong $nonce'),
                  _update(3, 222, sentAt - 1, 'rezeptgarten-pong $nonce'),
                  _update(
                    4,
                    222,
                    sentAt,
                    'rezeptgarten-pong 00000000000000000000000000000000',
                  ),
                ];
              }
              return [_update(5, 222, sentAt, 'rezeptgarten-pong $nonce')];
            default:
              throw StateError('Unexpected fixture request.');
          }
        },
      );
      await telegram.setToken('123:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');
      await telegram.pair();
      expect(api.pair?['client'], 'android');
      expect(api.pair?['client_id'], 123);
      expect(base64Decode(api.pair?['cart_key'] as String), hasLength(32));
      expect(await telegram.state(), (tokenSet: true, paired: true));
      await telegram.test();
      expect(offsets, [0, 5]);
      expect((jsonDecode(stored!) as Json)['pair']['offset'], 6);
      await telegram.removeToken();
      expect(await telegram.state(), (tokenSet: false, paired: false));
    },
  );
}

Json _update(int id, int sender, int date, String text) => {
  'update_id': id,
  'message': {
    'from': {'id': sender, 'is_bot': true},
    'chat': {'id': sender, 'type': 'private'},
    'date': date,
    'text': text,
  },
};

class _PairApi extends RezeptgartenApi {
  _PairApi() : super(client: HttpClient());

  Json? pair;

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    expect((method, path), ('POST', '/api/telegram-pair'));
    pair = body;
    return {'id': 222, 'username': 'TestServerBot'};
  }
}
