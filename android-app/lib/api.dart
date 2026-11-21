import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';

typedef Json = Map<String, dynamic>;

List<Json> objects(Object? value) =>
    value is List ? value.whereType<Json>().toList() : [];

String text(Object? value, [String fallback = '']) =>
    value?.toString() ?? fallback;

final _calendarMoveRandom = Random.secure();

String newCalendarMoveId() => List.generate(
  16,
  (_) => _calendarMoveRandom.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RezeptgartenApi {
  RezeptgartenApi({Uri? server, HttpClient? client})
    : server = server ?? Uri.https('192.168.184.30'),
      _providedClient = client;

  final Uri server;
  final HttpClient? _providedClient;
  late final Future<HttpClient> _client = _providedClient == null
      ? _localClient()
      : Future.value(_providedClient);
  bool get usesTestData => false;
  bool Function()? localAllowed;
  static final _photoName = RegExp(r'^[a-f0-9]{40}\.webp$');
  static final _maxAge = RegExp(r'(?:^|,)\s*max-age=(\d+)');
  static const _photoBudget = 12 * 1024 * 1024;
  static const _photoTimeout = Duration(seconds: 10);
  final _photos = <String, ({Uint8List bytes, DateTime expires})>{};
  final _photoRequests = <String, Future<Uint8List?>>{};
  int _photoBytes = 0;
  int _photoGeneration = 0;

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

  Future<Uint8List?> image(Object? filename, {bool full = false}) {
    if (filename is! String ||
        !_photoName.hasMatch(filename) ||
        localAllowed?.call() == false) {
      return Future.value();
    }
    final path = '/api/images/$filename${full ? '' : '?size=thumb'}';
    final entry = _photos.remove(path);
    if (entry != null) {
      if (entry.expires.isAfter(DateTime.now())) {
        _photos[path] = entry;
        return Future.value(entry.bytes);
      }
      _photoBytes -= entry.bytes.lengthInBytes;
    }
    return _photoRequests.putIfAbsent(path, () {
      final generation = _photoGeneration;
      return _loadPhoto(path, generation).whenComplete(() {
        if (generation == _photoGeneration) _photoRequests.remove(path);
      });
    });
  }

  Future<Uint8List?> _loadPhoto(String path, int generation) async {
    try {
      final response = await _request('GET', path, timeout: _photoTimeout);
      final stream = response.timeout(_photoTimeout);
      if (response.statusCode != 200) {
        await stream.drain<void>();
        return null;
      }
      final bytes = await _bytes(stream);
      if (generation != _photoGeneration || localAllowed?.call() == false) {
        return null;
      }
      final control = response.headers.value(HttpHeaders.cacheControlHeader);
      final lifetime = int.tryParse(
        _maxAge.firstMatch(control ?? '')?.group(1) ?? '',
      );
      if (control != null &&
          !control.contains('no-store') &&
          !control.contains('no-cache') &&
          lifetime != null &&
          lifetime > 0 &&
          bytes.isNotEmpty &&
          bytes.lengthInBytes <= _photoBudget) {
        while (_photoBytes + bytes.lengthInBytes > _photoBudget) {
          _photoBytes -= _photos
              .remove(_photos.keys.first)!
              .bytes
              .lengthInBytes;
        }
        _photos[path] = (
          bytes: bytes,
          expires: DateTime.now().add(
            Duration(seconds: lifetime > 86400 ? 86400 : lifetime),
          ),
        );
        _photoBytes += bytes.lengthInBytes;
      }
      return bytes;
    } on Exception {
      return null;
    }
  }

  void clearImageCache() {
    _photoGeneration++;
    _photos.clear();
    _photoRequests.clear();
    _photoBytes = 0;
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

  Future<Uint8List> _bytes(Stream<List<int>> response) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<void> close() async {
    clearImageCache();
    (await _client).close(force: true);
  }
}
