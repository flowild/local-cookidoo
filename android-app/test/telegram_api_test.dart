import 'package:flutter_test/flutter_test.dart';
import 'package:rezeptgarten/api.dart';

void main() {
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
