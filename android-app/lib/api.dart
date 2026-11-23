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
  bool Function()? telegramAllowed;
  Future<Json> Function(
    String method,
    String path,
    Json? body, {
    String? revision,
  })?
  telegramRequest;
  bool get _viaTelegram => telegramAllowed?.call() == true;
  static final _photoName = RegExp(r'^[a-f0-9]{40}\.webp$');
  static final _ownerName = RegExp(r'^[a-f0-9]{64}$');
  static final _maxAge = RegExp(r'(?:^|,)\s*max-age=(\d+)');
  static const _photoBudget = 12 * 1024 * 1024;
  static const _photoTimeout = Duration(seconds: 10);
  final _photos = <String, ({Uint8List bytes, DateTime expires})>{};
  final _photoRequests = <String, Future<Uint8List?>>{};
  final _recipeReads = <String, ({String revision, Object? content})>{};
  int _photoBytes = 0;
  int _photoGeneration = 0;
  String? _imageOwner;
  Future<void>? _warmingImages;
  Future<Directory?>? _imageDirectory;

  Future<Directory?> _diskImages() => _imageDirectory ??= () async {
    if (!Platform.isAndroid) return null;
    try {
      final root = await const MethodChannel('de.rezeptgarten/storage')
          .invokeMethod<String>('noBackupDirectory');
      return root == null ? null : Directory('$root/recipe-images');
    } on Exception {
      return null;
    }
  }();

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
    if (_viaTelegram) return _telegramJson('GET', path);
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
      _viaTelegram
      ? _telegramJson(method, path, body)
      : _json(method, path, body: body);

  Future<dynamic> _telegramJson(
    String method,
    String path, [
    Json? body,
  ]) async {
    final generation = _photoGeneration;
    final cached = method == 'GET' ? _recipeReads[path] : null;
    final result = await telegramRequest!(
      method,
      path,
      body,
      revision: cached?.revision,
    );
    if (!_viaTelegram || generation != _photoGeneration) {
      throw const ApiException('Die Verbindung hat sich geändert.');
    }
    final owner = result['owner'];
    _imageOwner = owner is String && _ownerName.hasMatch(owner) ? owner : null;
    final status = result['status'];
    final content = result['body'];
    final revision = result['revision'];
    if (status == 304 && cached != null && revision == cached.revision) {
      return cached.content;
    }
    if (status is! int || status < 200 || status >= 300) {
      throw ApiException(
        content is Json && content['detail'] is String
            ? content['detail'] as String
            : 'Der Server konnte die Anfrage nicht verarbeiten.',
      );
    }
    if (revision is String) {
      _recipeReads.remove(path);
      if (_recipeReads.length >= 48) {
        _recipeReads.remove(_recipeReads.keys.first);
      }
      _recipeReads[path] = (revision: revision, content: content);
    }
    return content;
  }

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
        (!_viaTelegram && localAllowed?.call() == false)) {
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
      return _findPhoto(filename, path, generation, full: full).whenComplete(
        () {
          if (generation == _photoGeneration) _photoRequests.remove(path);
        },
      );
    });
  }

  Future<void> warmRecipeImages({bool afterCurrent = false}) {
    final generation = _photoGeneration;
    final current = _warmingImages;
    if (current != null) {
      return afterCurrent
          ? current.then((_) async {
              if (generation == _photoGeneration) await warmRecipeImages();
            })
          : current;
    }
    return _warmingImages = _warmImages(generation).whenComplete(() {
      if (generation == _photoGeneration) _warmingImages = null;
    });
  }

  Future<void> _warmImages(int generation) async {
    final disk = await _diskImages();
    if (disk == null) return;
    var cursor = '';
    try {
      while (generation == _photoGeneration && localAllowed?.call() == true) {
        final page = await get('/api/android-images?after=$cursor') as Json;
        final owner = page['owner'];
        if (generation != _photoGeneration ||
            localAllowed?.call() != true ||
            owner is! String ||
            !_ownerName.hasMatch(owner)) {
          return;
        }
        _imageOwner = owner;
        final names = (page['images'] as List)
            .whereType<String>()
            .where(_photoName.hasMatch)
            .toList();
        for (var index = 0; index < names.length; index += 3) {
          if (generation != _photoGeneration || localAllowed?.call() != true) {
            return;
          }
          await Future.wait([
            for (final name in names.skip(index).take(3))
              _findPhoto(
                name,
                '/api/images/$name?size=thumb',
                generation,
                full: false,
              ),
          ]);
        }
        final next = page['next'];
        if (next is! String || !_photoName.hasMatch(next) || next == cursor) {
          break;
        }
        cursor = next;
      }
      if (generation == _photoGeneration) await _trimDiskImages(disk);
    } on Exception {
      // Images remain available on demand when background loading fails.
    }
  }

  Future<void> _trimDiskImages(Directory disk) async {
    final files = <({File file, FileStat stat})>[];
    if (!await disk.exists()) return;
    await for (final entry in disk.list(recursive: true, followLinks: false)) {
      if (entry is File && entry.path.endsWith('.webp')) {
        files.add((file: entry, stat: await entry.stat()));
      }
    }
    files.sort((a, b) => b.stat.modified.compareTo(a.stat.modified));
    var bytes = 0;
    for (final entry in files) {
      bytes += entry.stat.size;
      if (bytes > 200 * 1024 * 1024) await entry.file.delete();
    }
  }

  Future<Uint8List?> _findPhoto(
    String filename,
    String path,
    int generation, {
    required bool full,
  }) async {
    final owner = _imageOwner;
    final disk = owner == null ? null : await _diskImages();
    final folder = disk == null ? null : Directory('${disk.path}/$owner');
    final file = folder == null
        ? null
        : File('${folder.path}/${full ? 'full-' : ''}$filename');
    try {
      if (file != null && await file.exists()) {
        final bytes = await file.readAsBytes();
        return generation == _photoGeneration && owner == _imageOwner
            ? bytes
            : null;
      }
    } on FileSystemException {
      // The file may have been removed while trimming the cache.
    }
    if (generation != _photoGeneration || owner != _imageOwner) return null;
    if (_viaTelegram) return full ? image(filename) : null;
    final bytes = await _loadPhoto(path, generation);
    if (bytes != null &&
        _photos.containsKey(path) &&
        file != null &&
        generation == _photoGeneration &&
        owner == _imageOwner) {
      try {
        await folder!.create(recursive: true);
        final temporary = File('${file.path}.${newCalendarMoveId()}.tmp');
        try {
          await temporary.writeAsBytes(bytes, flush: true);
          await temporary.rename(file.path);
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
      } on FileSystemException {
        // The loaded image is still usable if writing the cache failed.
      }
    }
    return generation == _photoGeneration &&
            (owner == null || owner == _imageOwner)
        ? bytes
        : null;
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
        _photoBytes -= _photos.remove(path)?.bytes.lengthInBytes ?? 0;
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
    _recipeReads.clear();
    _photoBytes = 0;
    _imageOwner = null;
    _warmingImages = null;
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
