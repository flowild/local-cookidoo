import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

typedef Json = Map<String, dynamic>;

List<Json> objects(Object? value) =>
    value is List ? value.whereType<Json>().toList() : [];

String text(Object? value, [String fallback = '']) =>
    value?.toString() ?? fallback;

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RezeptgartenApi {
  RezeptgartenApi({Uri? server, HttpClient? client})
    : server = server ?? Uri.https('192.168.184.30'),
      _client = client == null ? _localClient() : Future.value(client);

  final Uri server;
  final Future<HttpClient> _client;
  bool Function()? localAllowed;

  static Future<HttpClient> _localClient() async {
    final certificate = await rootBundle.load('assets/rezeptgarten-ca.pem');
    final context = SecurityContext()
      ..setTrustedCertificatesBytes(
        certificate.buffer.asUint8List(
          certificate.offsetInBytes,
          certificate.lengthInBytes,
        ),
      );
    return HttpClient(context: context)
      ..connectionTimeout = const Duration(seconds: 10);
  }

  Future<HttpClientResponse> _request(
    String method,
    String path, {
    Json? body,
    Duration? timeout,
    bool probe = false,
  }) async {
    if (!probe && localAllowed?.call() == false) {
      throw const ApiException('Das Heimnetz ist nicht verbunden.');
    }
    const timeoutError = ApiException(
      'Der Rezeptgarten-Server antwortet nicht.',
    );
    final client = await _client;
    final pending = client.openUrl(method, server.resolve(path));
    final request = timeout == null
        ? await pending
        : await pending.timeout(
            timeout,
            onTimeout: () {
              pending.then<void>(
                (lateRequest) => lateRequest.abort(),
                onError: (Object _) {},
              );
              throw timeoutError;
            },
          );
    request.followRedirects = false;
    if (method != 'GET') {
      request.headers.set('Origin', server.origin);
    }
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = request.close();
    if (timeout == null) return response;
    return response.timeout(
      timeout,
      onTimeout: () {
        request.abort();
        throw timeoutError;
      },
    );
  }

  Future<dynamic> get(String path, {Duration? timeout}) {
    final response = _json('GET', path, timeout: timeout);
    return timeout == null
        ? response
        : response.timeout(
            timeout,
            onTimeout: () {
              throw const ApiException(
                'Der Rezeptgarten-Server antwortet nicht.',
              );
            },
          );
  }

  Future<dynamic> probeHealth() =>
      _json(
        'GET',
        '/api/health',
        timeout: const Duration(milliseconds: 2500),
        probe: true,
      ).timeout(
        const Duration(milliseconds: 2500),
        onTimeout: () => throw const ApiException(
          'Der Rezeptgarten-Server antwortet nicht.',
        ),
      );

  Future<dynamic> write(String method, String path, [Json? body]) =>
      _json(method, path, body: body);

  Future<dynamic> _json(
    String method,
    String path, {
    Json? body,
    Duration? timeout,
    bool probe = false,
  }) async {
    try {
      final response = await _request(
        method,
        path,
        body: body,
        timeout: timeout,
        probe: probe,
      );
      final reading = utf8.decoder.bind(response).join();
      final content = timeout == null
          ? await reading
          : await reading.timeout(timeout);
      final decoded = jsonDecode(content);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          decoded is Json && decoded['detail'] is String
              ? decoded['detail'] as String
              : 'Der Server konnte die Anfrage nicht verarbeiten.',
        );
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on HandshakeException {
      throw const ApiException(
        'Das Zertifikat des Heimnetzservers konnte nicht geprüft werden.',
      );
    } on Exception {
      throw ApiException(
        method == 'GET' ? 'Rezeptgarten ist im Heimnetz nicht erreichbar.' : 'Das Ergebnis konnte nicht bestätigt werden. Bitte lade den aktuellen Stand.',
      );
    }
  }

  Future<Uint8List?> image(Object? filename, {bool full = false}) async {
    if (filename is! String ||
        !RegExp(r'^[a-f0-9]{40}\.webp$').hasMatch(filename)) {
      return null;
    }
    try {
      final response = await _request(
        'GET',
        '/api/images/$filename${full ? '' : '?size=thumb'}',
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      return await _bytes(response);
    } on Exception {
      return null;
    }
  }

  Future<Uint8List> exportCollection() async {
    try {
      final response = await _request('GET', '/api/export');
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw const ApiException(
          'Die Sammlung konnte nicht exportiert werden.',
        );
      }
      return await _bytes(response);
    } on Exception {
      throw const ApiException('Die Sammlung konnte nicht exportiert werden.');
    }
  }

  Future<Uint8List> _bytes(HttpClientResponse response) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<void> close() async => (await _client).close(force: true);
}
