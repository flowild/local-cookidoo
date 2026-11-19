import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rezeptgarten/api.dart';

void main() {
  test(
    'read timeout includes a server that stalls the response body',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final api = RezeptgartenApi(
        server: Uri.parse('http://127.0.0.1:${server.port}'),
        client: HttpClient(),
      );
      final release = Completer<void>();
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{');
        await request.response.flush();
        await release.future;
        try {
          await request.response.close();
        } on HttpException {
          /* Client aborted. */
        }
      });
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await api.close();
        await server.close(force: true);
      });
      await expectLater(
        api.get('/api/status', timeout: const Duration(milliseconds: 150)),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'a write does not follow redirects or send data to another origin',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final origin = Uri.parse('http://127.0.0.1:${server.port}');
      final api = RezeptgartenApi(server: origin, client: HttpClient());
      var otherRequests = 0;
      other.listen((request) async {
        otherRequests++;
        await request.response.close();
      });
      server.listen((request) async {
        expect(request.headers.value('Origin'), origin.origin);
        await request.drain<void>();
        request.response.statusCode = HttpStatus.temporaryRedirect;
        request.response.headers.set(
          'Location',
          'http://127.0.0.1:${other.port}/',
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
        await request.response.close();
      });
      addTearDown(() async {
        await api.close();
        await server.close(force: true);
        await other.close(force: true);
      });
      await expectLater(
        api.write('POST', '/api/connect', {'email': 'test@example.invalid'}),
        throwsA(isA<ApiException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(otherRequests, 0);
    },
  );
}
