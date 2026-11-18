import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rezeptgarten/api.dart';

void main() {
  test(
    'loads the week, adds it to the cart and confirms the checkbox',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final origin = Uri.parse('http://127.0.0.1:${server.port}');
      final api = RezeptgartenApi(server: origin, client: HttpClient());
      addTearDown(() async {
        await api.close();
        await server.close(force: true);
      });

      const day = '2026-11-16';
      var hasRecipe = false;
      var owned = false;
      server.listen((request) async {
        final path = request.uri.path;
        final response = request.response;
        response.headers.contentType = ContentType.json;
        final method = request.method;
        if (method != 'GET' &&
            request.headers.value('Origin') != origin.origin) {
          response.statusCode = HttpStatus.forbidden;
          response.write(jsonEncode({'detail': 'Origin fehlt'}));
        } else if (method == 'GET' && path == '/api/calendar/week') {
          response.write(
            jsonEncode({
              'days': [
                {'date': day},
              ],
            }),
          );
        } else if (method == 'POST' && path == '/api/calendar/shopping') {
          final payload = jsonDecode(await utf8.decoder.bind(request).join());
          hasRecipe = payload['day'] == day;
          response.write(jsonEncode({'added': hasRecipe ? 1 : 0}));
        } else if (method == 'GET' && path == '/api/cart') {
          response.write(
            jsonEncode({
              'items': [
                if (hasRecipe)
                  {
                    'id': 'recipe',
                    'data': {
                      'ingredients': [
                        {'owned': owned},
                      ],
                    },
                  },
              ],
            }),
          );
        } else if (method == 'PUT' &&
            path == '/api/cart/recipe/ingredients/0') {
          final payload = jsonDecode(await utf8.decoder.bind(request).join());
          owned = hasRecipe && payload['owned'] == true;
          response.write(jsonEncode({'ok': owned}));
        } else {
          response.statusCode = HttpStatus.notFound;
          response.write('{}');
        }
        await response.close();
      });

      final week = await api.get('/api/calendar/week') as Json;
      final monday = objects(week['days']).single['date'];
      await api.write('POST', '/api/calendar/shopping', {'day': monday});
      final cart = await api.get('/api/cart') as Json;
      final entry = objects(cart['items']).single;
      await api.write('PUT', '/api/cart/${entry['id']}/ingredients/0', {
        'owned': true,
      });
      final reloaded = await api.get('/api/cart') as Json;
      final updated = objects(reloaded['items']).single;
      expect(updated['data']['ingredients'][0]['owned'], isTrue);
    },
  );
}
