import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:handy_tdlib_next/client.dart';

import 'api.dart';

enum TelegramStep {
  loading,
  credentials,
  phone,
  code,
  email,
  emailCode,
  password,
  ready,
  unsupported,
}

@visibleForTesting
Future<Json> decodeTelegramSnapshot(
  String encoded,
  String key,
  String nonce,
) async {
  final packed = base64Decode(encoded);
  if (packed.length < 28 || packed.length > 40500) {
    throw FormatException('Ungültige Telegram-Antwort.');
  }
  final plain = await AesGcm.with256bits().decrypt(
    SecretBox(
      packed.sublist(12, packed.length - 16),
      nonce: packed.sublist(0, 12),
      mac: Mac(packed.sublist(packed.length - 16)),
    ),
    secretKey: SecretKey(base64Decode(key)),
    aad: utf8.encode(nonce),
  );
  final decoded = jsonDecode(utf8.decode(zlib.decode(plain)));
  if (decoded is! Json) throw FormatException('Ungültige Telegram-Antwort.');
  return decoded;
}

class TelegramService extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  Timer? _poll;
  int? _client;
  int _sequence = 0;
  int? _apiId;
  String? _apiHash;
  String? _databaseKey;
  bool _initializing = false;
  bool _disposed = false;
  int? _botChat;
  int? _botId;
  String? _cartKey;
  String? _pairingChallenge;
  Completer<void>? _pairingResult;
  Completer<void>? _logoutClosed;
  final _snapshots = <String, TelegramSnapshotParts>{};
  final _pings = <String, Completer<void>>{};
  Future<void> _checkWrites = Future.value();
  TelegramStep step = TelegramStep.loading;
  String? error;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (!Platform.isAndroid) {
      step = TelegramStep.unsupported;
      _changed();
      return;
    }
    try {
      _apiId = int.tryParse(await _storage.read(key: 'telegram_api_id') ?? '');
      _apiHash = await _storage.read(key: 'telegram_api_hash');
      _databaseKey = await _storage.read(key: 'telegram_database_key');
      final pairing = await _storage.read(key: 'telegram_pairing');
      if (pairing != null) {
        final data = jsonDecode(pairing);
        if (data is Map &&
            data['key'] is String &&
            data['bot_id'] is int &&
            data['chat_id'] is int) {
          _cartKey = data['key'] as String;
          _botId = data['bot_id'] as int;
          _botChat = data['chat_id'] as int;
        }
      }
      await TdPlugin.initialize();
      final logResult = TdPlugin.instance.tdExecute(
        jsonEncode({
          '@type': 'setLogStream',
          'log_stream': {'@type': 'logStreamEmpty'},
        }),
      );
      if (logResult == null ||
          (jsonDecode(logResult) as Map)['@type'] != 'ok') {
        throw StateError(
          'Telegram-Protokollierung konnte nicht deaktiviert werden.',
        );
      }
      _client = TdPlugin.instance.tdCreateClientId();
      _poll = Timer.periodic(
        const Duration(milliseconds: 40),
        (_) => _receive(),
      );
      final state = await request({'@type': 'getAuthorizationState'});
      if (step == TelegramStep.loading) _authorization(state);
    } catch (_) {
      step = TelegramStep.unsupported;
      error = 'Telegram konnte nicht gestartet werden.';
      _changed();
    }
  }

  Future<Map<String, dynamic>> request(Map<String, dynamic> command) {
    final id = ++_sequence;
    final result = Completer<Map<String, dynamic>>();
    _pending[id] = result;
    TdPlugin.instance.tdSend(_client!, jsonEncode({...command, '@extra': id}));
    return result.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('Telegram antwortet nicht.');
      },
    );
  }

  void _receive() {
    for (var i = 0; i < 50; i++) {
      final raw = TdPlugin.instance.tdReceive(0);
      if (raw == null) break;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['@client_id'] != _client) continue;
      final id = data['@extra'];
      final pending = id is int ? _pending.remove(id) : null;
      if (pending != null) {
        if (data['@type'] == 'error') {
          pending.completeError(StateError('Telegram-Anfrage fehlgeschlagen.'));
        } else {
          pending.complete(data);
        }
      } else if (data['@type'] == 'updateAuthorizationState') {
        _authorization(data['authorization_state'] as Map<String, dynamic>);
      } else if (data['@type'] == 'updateNewMessage') {
        _receiveMessage(data['message']);
      }
    }
  }

  void _authorization(Map<String, dynamic> state) {
    switch (state['@type']) {
      case 'authorizationStateWaitTdlibParameters':
        if (_apiId == null || _apiHash == null || _databaseKey == null) {
          step = TelegramStep.credentials;
        } else {
          unawaited(_initializeParameters());
        }
      case 'authorizationStateWaitPhoneNumber':
        step = TelegramStep.phone;
      case 'authorizationStateWaitCode':
        step = TelegramStep.code;
      case 'authorizationStateWaitEmailAddress':
        step = TelegramStep.email;
      case 'authorizationStateWaitEmailCode':
        step = TelegramStep.emailCode;
      case 'authorizationStateWaitPassword':
        step = TelegramStep.password;
      case 'authorizationStateReady':
        step = TelegramStep.ready;
      case 'authorizationStateClosing':
      case 'authorizationStateLoggingOut':
        step = TelegramStep.loading;
      case 'authorizationStateClosed':
        if (_logoutClosed != null && !_logoutClosed!.isCompleted) {
          _logoutClosed!.complete();
          step = TelegramStep.loading;
        } else {
          step = TelegramStep.unsupported;
          error = 'Die Telegram-Sitzung wurde geschlossen. Bitte die App neu starten.';
        }
      default:
        step = TelegramStep.unsupported;
        error = 'Dieser Telegram-Anmeldeschritt wird noch nicht unterstützt.';
    }
    _changed();
  }

  Future<void> setCredentials(String id, String hash) async {
    final parsed = int.tryParse(id.trim());
    if (parsed == null || parsed <= 0 || hash.trim().isEmpty) {
      error = 'Bitte eine gültige API-ID und einen API-Hash eingeben.';
      _changed();
      return;
    }
    try {
      _apiId = parsed;
      _apiHash = hash.trim();
      final random = Random.secure();
      _databaseKey ??= base64Encode(
        List.generate(32, (_) => random.nextInt(256)),
      );
      await _storage.write(key: 'telegram_api_id', value: '$_apiId');
      await _storage.write(key: 'telegram_api_hash', value: _apiHash);
      await _storage.write(key: 'telegram_database_key', value: _databaseKey);
      await _initializeParameters();
    } catch (_) {
      error = 'Die Zugangsdaten konnten nicht gespeichert werden.';
      _changed();
    }
  }

  Future<void> _initializeParameters() async {
    if (_initializing) return;
    _initializing = true;
    try {
      error = null;
      final dir = await const MethodChannel('de.rezeptgarten/storage')
          .invokeMethod<String>('noBackupDirectory');
      if (dir == null) throw StateError('Telegram-Speicher nicht verfügbar.');
      final version = await const MethodChannel('de.rezeptgarten/preferences')
          .invokeMethod<String>('version');
      await request({
        '@type': 'setTdlibParameters',
        'use_test_dc': false,
        'database_directory': '$dir/telegram',
        'files_directory': '$dir/telegram/files',
        'database_encryption_key': _databaseKey,
        'use_file_database': true,
        'use_chat_info_database': true,
        'use_message_database': false,
        'use_secret_chats': false,
        'api_id': _apiId,
        'api_hash': _apiHash,
        'system_language_code': 'de',
        'device_model': 'Rezeptgarten',
        'system_version': '',
        'application_version': version ?? 'unknown',
      });
    } catch (_) {
      step = TelegramStep.credentials;
      error = 'Telegram-Einrichtung fehlgeschlagen. Bitte Zugangsdaten prüfen.';
      _changed();
    } finally {
      _initializing = false;
    }
  }

  Future<void> submit(String value) async {
    final command = switch (step) {
      TelegramStep.phone => {
        '@type': 'setAuthenticationPhoneNumber',
        'phone_number': value.trim(),
      },
      TelegramStep.code => {
        '@type': 'checkAuthenticationCode',
        'code': value.trim(),
      },
      TelegramStep.email => {
        '@type': 'setAuthenticationEmailAddress',
        'email_address': value.trim(),
      },
      TelegramStep.emailCode => {
        '@type': 'checkAuthenticationEmailCode',
        'code': {
          '@type': 'emailAddressAuthenticationCode',
          'code': value.trim(),
        },
      },
      TelegramStep.password => {
        '@type': 'checkAuthenticationPassword',
        'password': value,
      },
      _ => null,
    };
    if (command == null) return;
    try {
      error = null;
      await request(command);
    } catch (_) {
      error = 'Anmeldung fehlgeschlagen. Bitte Eingabe überprüfen.';
      _changed();
    }
  }

  bool get paired => _cartKey != null && _botId != null && _botChat != null;

  Future<Map<String, bool>> loadChecks() async {
    final raw = await _storage.read(key: 'telegram_cart_checks');
    if (raw == null) return {};
    try {
      final envelope = jsonDecode(raw);
      final value = envelope is Map && envelope['pair'] == _cartKey
          ? envelope['checks']
          : null;
      if (value is Map) {
        return {
          for (final entry in value.entries)
            if (entry.key is String && entry.value is bool)
              entry.key as String: entry.value as bool,
        };
      }
    } on FormatException {
      return {};
    }
    return {};
  }

  Future<void> saveChecks(Map<String, bool> checks) {
    final value = jsonEncode({
      'pair': _cartKey,
      'checks': Map<String, bool>.of(checks),
    });
    _checkWrites = _checkWrites
        .catchError((Object _) {})
        .then((_) => _storage.write(key: 'telegram_cart_checks', value: value));
    return _checkWrites;
  }

  Future<void> pair(RezeptgartenApi api) async {
    if (step != TelegramStep.ready) {
      throw StateError('Bitte zuerst bei Telegram anmelden.');
    }
    final me = await request({'@type': 'getMe'});
    final random = Random.secure();
    final key = base64Encode(List.generate(32, (_) => random.nextInt(256)));
    final result = await api.write('POST', '/api/telegram-android-pair', {
      'client_id': me['id'],
      'cart_key': key,
    }) as Json;
    final botId = result['id'] as int;
    final challenge = result['challenge'] as String;
    final chat = await request({
      '@type': 'searchPublicChat',
      'username': result['username'],
    });
    final chatId = chat['id'] as int;
    final chatType = chat['type'];
    if (chatType is! Map ||
        chatType['@type'] != 'chatTypePrivate' ||
        chatType['user_id'] != botId) {
      throw StateError('Der Telegram-Bot stimmt nicht mit dem Server überein.');
    }
    final pending = Completer<void>();
    final previousId = _botId;
    final previousChat = _botChat;
    var saved = false;
    _botId = botId;
    _botChat = chatId;
    _pairingChallenge = challenge;
    _pairingResult = pending;
    try {
      await Future.wait([
        _send('rezeptgarten-pair $challenge'),
        pending.future.timeout(const Duration(seconds: 45)),
      ], eagerError: true);
      await _storage.write(
        key: 'telegram_pairing',
        value: jsonEncode({'bot_id': botId, 'chat_id': chatId, 'key': key}),
      );
      _cartKey = key;
      saved = true;
      _changed();
    } finally {
      if (!saved) {
        _botId = previousId;
        _botChat = previousChat;
      }
      _pairingChallenge = null;
      _pairingResult = null;
    }
  }

  Future<void> _send(String message) async {
    await request({
      '@type': 'sendMessage',
      'chat_id': _botChat,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': message, 'entities': []},
        'clear_draft': false,
      },
    });
  }

  Future<void> testConnection() async {
    if (!paired || step != TelegramStep.ready) {
      throw StateError('Telegram ist nicht gekoppelt.');
    }
    final random = Random.secure();
    final nonce = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final result = Completer<void>();
    _pings[nonce] = result;
    try {
      await Future.wait([
        _send('rezeptgarten-ping $nonce'),
        result.future.timeout(const Duration(seconds: 30)),
      ], eagerError: true);
    } finally {
      _pings.remove(nonce);
    }
  }

  Future<void> disconnect(RezeptgartenApi api) async {
    await api.write('DELETE', '/api/telegram-android-pair');
    await _storage.delete(key: 'telegram_pairing');
    await _storage.delete(key: 'telegram_cart_checks');
    _cartKey = null;
    _botId = null;
    _botChat = null;
    _changed();
  }

  Future<void> changeCredentials(RezeptgartenApi api) async {
    if (step != TelegramStep.ready) {
      throw StateError('Telegram ist nicht angemeldet.');
    }
    if (paired) await disconnect(api);
    final closed = Completer<void>();
    _logoutClosed = closed;
    try {
      await Future.wait([
        request({'@type': 'logOut'}),
        closed.future.timeout(const Duration(seconds: 30)),
      ], eagerError: true);
      await _storage.delete(key: 'telegram_api_id');
      await _storage.delete(key: 'telegram_api_hash');
      await _storage.delete(key: 'telegram_database_key');
      _apiId = null;
      _apiHash = null;
      _databaseKey = null;
      _client = TdPlugin.instance.tdCreateClientId();
      final state = await request({'@type': 'getAuthorizationState'});
      _authorization(state);
    } finally {
      _logoutClosed = null;
    }
  }

  Future<Json> snapshot(String kind, {String? day}) async {
    if (!paired || step != TelegramStep.ready) {
      throw StateError('Telegram ist nicht gekoppelt.');
    }
    if (kind != 'cart' && (kind != 'week' || day == null)) {
      throw ArgumentError('Ungültige Anfrage.');
    }
    final random = Random.secure();
    final nonce = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final pending = TelegramSnapshotParts(kind, nonce);
    _snapshots[nonce] = pending;
    try {
      final result = await Future.wait<Object?>([
        _send('rezeptgarten-${kind}z $nonce${day == null ? '' : ' $day'}'),
        pending.result.future.timeout(const Duration(seconds: 60)),
      ], eagerError: true);
      return await decodeTelegramSnapshot(
        result[1] as String,
        _cartKey!,
        nonce,
      );
    } finally {
      _snapshots.remove(nonce);
    }
  }

  void _receiveMessage(Object? raw) {
    if (raw is! Map ||
        raw['chat_id'] != _botChat ||
        raw['is_outgoing'] != false) {
      return;
    }
    final sender = raw['sender_id'];
    final content = raw['content'];
    if (sender is! Map ||
        sender['@type'] != 'messageSenderUser' ||
        sender['user_id'] != _botId ||
        content is! Map ||
        content['@type'] != 'messageText') {
      return;
    }
    final formatted = content['text'];
    final message = formatted is Map ? formatted['text'] : null;
    if (message is! String) return;
    final pong = RegExp(r'^rezeptgarten-pong ([a-f0-9]{32})$')
        .firstMatch(message);
    if (pong != null) {
      final pending = _pings[pong[1]];
      if (pending != null && !pending.isCompleted) pending.complete();
      return;
    }
    if (message == 'rezeptgarten-paired $_pairingChallenge' &&
        _pairingResult != null &&
        !_pairingResult!.isCompleted) {
      _pairingResult!.complete();
      return;
    }
    final match = RegExp(
      r'^rezeptgarten-(cart|week)-(part|error) ([a-f0-9]{32})(?: (\d+)/(\d+) ([A-Za-z0-9+/=]+))?$',
    ).firstMatch(message);
    if (match == null) return;
    final pending = _snapshots[match[3]];
    pending?.accept(message);
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    if (_client != null) {
      TdPlugin.instance.tdSend(_client!, jsonEncode({'@type': 'close'}));
    }
    for (final pending in _pending.values) {
      pending.completeError(StateError('Telegram geschlossen.'));
    }
    _pending.clear();
    super.dispose();
  }
}

@visibleForTesting
class TelegramSnapshotParts {
  TelegramSnapshotParts(this.kind, this.nonce);
  final String kind;
  final String nonce;
  final result = Completer<String>();
  final parts = <int, String>{};
  int? total;

  void accept(String message) {
    final match = RegExp(
      r'^rezeptgarten-(cart|week)-(part|error) ([a-f0-9]{32})(?: (\d+)/(\d+) ([A-Za-z0-9+/=]+))?$',
    ).firstMatch(message);
    if (match == null ||
        match[3] != nonce ||
        match[1] != kind ||
        result.isCompleted) {
      return;
    }
    if (match[2] == 'error') {
      result.completeError(StateError('Telegram-Abfrage fehlgeschlagen.'));
      return;
    }
    final index = int.tryParse(match[4] ?? '');
    final total = int.tryParse(match[5] ?? '');
    final piece = match[6];
    if (index == null ||
        total == null ||
        piece == null ||
        total < 1 ||
        total > 18 ||
        index < 1 ||
        index > total ||
        piece.length > 3000 ||
        (this.total != null && this.total != total)) {
      return;
    }
    this.total = total;
    if (parts.containsKey(index) && parts[index] != piece) {
      result.completeError(
        FormatException('Widersprüchliche Telegram-Antwort.'),
      );
      return;
    }
    parts[index] = piece;
    if (parts.length == total) {
      result.complete(List.generate(total, (i) => parts[i + 1]!).join());
    }
  }
}
