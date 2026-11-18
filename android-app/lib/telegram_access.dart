import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import 'api.dart';

typedef TelegramRequest = Future<dynamic> Function(
  String token,
  String method,
  Map<String, Object> payload,
);

class TelegramAccess {
  TelegramAccess(this.api, {TelegramRequest? request})
    : _requestOverride = request;

  static const _storage = MethodChannel('de.rezeptgarten/telegram');
  static final _tokenPattern = RegExp(r'^[0-9]{1,20}:[A-Za-z0-9_-]{20,200}$');
  static final _usernamePattern = RegExp(r'^[A-Za-z0-9_]{5,32}$');
  static final _random = Random.secure();

  final RezeptgartenApi api;
  final TelegramRequest? _requestOverride;
  HttpClient? _client;

  static bool validToken(String token) => _tokenPattern.hasMatch(token);

  Future<Json?> _read() async {
    final serialized = await _storage.invokeMethod<String>('read');
    if (serialized == null) return null;
    final Object? config;
    try {
      config = jsonDecode(serialized);
    } on FormatException {
      throw const ApiException(
        'Die gespeicherte Telegram-Kopplung ist ungültig.',
      );
    }
    if (config is! Json ||
        config['token'] is! String ||
        !validToken(config['token'])) {
      throw const ApiException(
        'Die gespeicherte Telegram-Kopplung ist ungültig.',
      );
    }
    return config;
  }

  Future<({bool tokenSet, bool paired})> state() async {
    final config = await _read();
    return (tokenSet: config != null, paired: config?['pair'] is Json);
  }

  Future<void> _save(Json? config) => _storage.invokeMethod<void>(
    'write',
    config == null ? null : jsonEncode(config),
  );

  Future<void> setToken(String token) async {
    if (!validToken(token)) {
      throw const ApiException('Bitte gib ein gültiges Bot-Token ein.');
    }
    await _save({'token': token});
  }

  Future<void> removeToken() => _save(null);

  Future<dynamic> _call(
    String token,
    String method,
    Map<String, Object> payload,
  ) async {
    try {
      if (!validToken(token)) {
        throw const ApiException('Ungültiges Telegram-Token.');
      }
      if (_requestOverride != null) {
        return await _requestOverride(token, method, payload);
      }
      final client = _client ??= HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final request = await client
          .postUrl(Uri.https('api.telegram.org', '/bot$token/$method'))
          .timeout(const Duration(seconds: 8));
      request.followRedirects = false;
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      final body = utf8.encode(
        Uri(
          queryParameters: payload.map((key, value) => MapEntry(key, '$value')),
        ).query,
      );
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          request.abort();
          throw const ApiException('Telegram antwortet nicht.');
        },
      );
      final result = jsonDecode(
        await utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 4)),
      );
      if (response.statusCode != 200 ||
          result is! Json ||
          result['ok'] != true) {
        throw const ApiException('Telegram hat die Anfrage nicht bestätigt.');
      }
      return result['result'];
    } on Exception {
      throw const ApiException(
        'Telegram hat die Anfrage nicht bestätigt. Prüfe Token, Bot-Freigabe und Internetverbindung.',
      );
    }
  }

  Future<void> pair() async {
    final config = await _read();
    if (config == null) {
      throw const ApiException('Speichere zuerst das Android-Client-Token.');
    }
    final bot = await _call(config['token'] as String, 'getMe', {});
    if (bot is! Json || bot['is_bot'] != true || bot['id'] is! int) {
      throw const ApiException(
        'Der Android-Client-Bot konnte nicht bestätigt werden.',
      );
    }
    final key = base64Encode(List.generate(32, (_) => _random.nextInt(256)));
    final result = await api.write('POST', '/api/telegram-pair', {
      'client': 'android',
      'client_id': bot['id'],
      'cart_key': key,
    });
    if (result is! Json ||
        result['id'] is! int ||
        result['username'] is! String ||
        !_usernamePattern.hasMatch(result['username'])) {
      throw const ApiException(
        'Die Server-Bot-Kennung konnte nicht bestätigt werden.',
      );
    }
    await _save({
      'token': config['token'],
      'pair': {
        'server_id': result['id'],
        'username': result['username'],
        'key': key,
        'offset': 0,
      },
    });
  }

  Future<void> test() async {
    final config = await _read();
    final pair = config?['pair'];
    if (config == null ||
        pair is! Json ||
        pair['server_id'] is! int ||
        pair['username'] is! String ||
        !_usernamePattern.hasMatch(pair['username'])) {
      throw const ApiException('Verbinde zuerst die Android-Bots im Heimnetz.');
    }
    final token = config['token'] as String;
    final nonce = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final sent = await _call(token, 'sendMessage', {
      'chat_id': '@${pair['username']}',
      'text': 'rezeptgarten-ping $nonce',
    });
    if (sent is! Json || sent['date'] is! int) {
      throw const ApiException('Telegram hat den Versand nicht bestätigt.');
    }
    final sentAt = sent['date'] as int;
    final server = pair['server_id'] as int;
    var offset = pair['offset'] is int ? pair['offset'] as int : 0;
    final deadline = Stopwatch()..start();
    try {
      while (deadline.elapsed < const Duration(seconds: 45)) {
        final remaining = const Duration(seconds: 45) - deadline.elapsed;
        final updates = await _call(token, 'getUpdates', {
          'offset': offset,
          'timeout': remaining.inSeconds.clamp(0, 8),
          'limit': 50,
          'allowed_updates': '["message"]',
        }).timeout(remaining);
        for (final update in objects(updates)) {
          final id = update['update_id'];
          if (id is! int || id < offset) continue;
          offset = id + 1;
          final message = update['message'];
          if (message is! Json ||
              message['from'] is! Json ||
              message['chat'] is! Json) {
            continue;
          }
          final sender = message['from'] as Json;
          final chat = message['chat'] as Json;
          final date = message['date'];
          if (sender['id'] == server &&
              sender['is_bot'] == true &&
              chat['id'] == server &&
              chat['type'] == 'private' &&
              date is int &&
              date >= sentAt &&
              date <= sentAt + 120 &&
              message['text'] == 'rezeptgarten-pong $nonce') {
            return;
          }
        }
      }
    } on TimeoutException {
      throw const ApiException(
        'Der Telegram-Verbindungstest wurde nicht bestätigt.',
      );
    } finally {
      if (offset != pair['offset']) {
        final current = await _read();
        final currentPair = current?['pair'];
        if (current != null &&
            current['token'] == token &&
            currentPair is Json &&
            currentPair['key'] == pair['key']) {
          await _save({
            ...current,
            'pair': {...currentPair, 'offset': offset},
          });
        }
      }
    }
    throw const ApiException(
      'Der Telegram-Verbindungstest wurde nicht bestätigt.',
    );
  }

  void close() => _client?.close(force: true);
}
