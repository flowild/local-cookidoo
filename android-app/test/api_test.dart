import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rezeptgarten/api.dart';

void main() {
  test('photo reads share a request and reuse private cache bytes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = RezeptgartenApi(
      server: Uri.parse('http://127.0.0.1:${server.port}'),
      client: HttpClient(),
    );
    final filename = '${'a' * 40}.webp';
    var reads = 0;
    server.listen((request) async {
      reads++;
      request.response.headers.set(
        'Cache-Control',
        request.uri.hasQuery ? 'private, max-age=300' : 'no-store',
      );
      request.response.add([1, 2, 3]);
      await request.response.close();
    });
    addTearDown(() async {
      await api.close();
      await server.close(force: true);
    });

    final first = api.image(filename);
    expect(identical(api.image(filename), first), isTrue);
    final bytes = await first;
    expect(bytes, [1, 2, 3]);
    expect(identical(await api.image(filename), bytes), isTrue);
    expect(reads, 1);
    api.localAllowed = () => false;
    expect(await api.image(filename), isNull);
    api.localAllowed = () => true;
    api.clearImageCache();
    expect(await api.image(filename), [1, 2, 3]);
    expect(reads, 2);
    await api.image(filename, full: true);
    await api.image(filename, full: true);
    expect(reads, 4);
  });

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
