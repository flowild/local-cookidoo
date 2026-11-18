import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'appearance.dart';
import 'telegram_access.dart';

const _regions = {'de': 'Deutschland', 'at': 'Österreich', 'ch': 'Schweiz'};
const _intervals = {
  0: 'Nur manuell',
  1: 'Jede Stunde',
  6: 'Alle 6 Stunden',
  24: 'Einmal täglich',
};

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.api, required this.appearance});
  final RezeptgartenApi api;
  final AppearanceController appearance;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  static const _update = MethodChannel('de.rezeptgarten/update');
  static const _documents = MethodChannel('de.rezeptgarten/documents');
  static const _preferences = MethodChannel('de.rezeptgarten/preferences');

  Json? _status;
  String? _error;
  String? _version;
  String? _updateMessage;
  String? _updateStatus;
  bool _checkingUpdate = false;
  bool _downloadingUpdate = false;
  bool _loading = false;
  bool _busy = false;
  int _request = 0;
  Timer? _poll;
  late final _telegram = TelegramAccess(widget.api);
  ({bool tokenSet, bool paired})? _telegramState;
  String? _telegramMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_load(showLoading: true));
    unawaited(_loadVersion());
    unawaited(_checkUpdate());
    unawaited(_loadTelegram());
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_busy && !_loading && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_load());
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _telegram.close();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final version = await _preferences.invokeMethod<String>('version');
      if (mounted) setState(() => _version = version);
    } on PlatformException {
      // The settings screen is still available.
    } on MissingPluginException {
      // App metadata is only available in the Android activity.
    }
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate || _downloadingUpdate) return;
    setState(() => _checkingUpdate = true);
    var status = 'Der Updatestatus konnte nicht geprüft werden.';
    try {
      final metadata = await _update.invokeMapMethod<String, Object?>(
        'checkUpdate',
      );
      if (metadata case {
        'version': final String version,
        'build': final int build,
        'installedBuild': final int installedBuild,
      }) {
        status = switch (build.compareTo(installedBuild)) {
          > 0 => 'Update verfügbar · Version $version (Build $build)',
          0 => 'Deine App ist aktuell.',
          _ => 'Deine App ist neuer als der Build auf dem Server.',
        };
      }
    } on PlatformException catch (error) {
      status = error.message ?? status;
    } on MissingPluginException {
      status = 'Die Updateprüfung ist nur in der Android-App verfügbar.';
    } finally {
      if (mounted) {
        setState(() {
          _updateStatus = status;
          _checkingUpdate = false;
        });
      }
    }
  }

  Future<void> _installUpdate() async {
    if (_downloadingUpdate) return;
    setState(() {
      _downloadingUpdate = true;
      _updateMessage = null;
    });
    String? message;
    try {
      final result = await _update.invokeMethod<String>('downloadAndInstall');
      if (result != 'installerOpened') {
        message = 'Der Android-Installer konnte nicht geöffnet werden.';
      }
    } on PlatformException catch (error) {
      message = error.message ?? 'Die APK konnte nicht geladen werden.';
    } on MissingPluginException {
      message = 'Der APK-Download ist nur in der Android-App verfügbar.';
    } finally {
      if (mounted) {
        setState(() {
          _updateMessage = message;
          _downloadingUpdate = false;
        });
      }
    }
  }

  Future<void> _loadTelegram() async {
    try {
      final state = await _telegram.state();
      if (mounted) setState(() => _telegramState = state);
    } on MissingPluginException {
      // Protected storage is supplied by the Android activity.
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _telegramMessage = error.message);
      }
    } on Exception {
      if (mounted) {
        setState(
          () => _telegramMessage =
              'Die gespeicherte Telegram-Kopplung konnte nicht gelesen werden.',
        );
      }
    }
  }

  Future<void> _telegramToken({required bool server}) async {
    final token = await showDialog<String>(
      context: context,
      builder: (_) => _ValueDialog(
        title: server ? 'Server-Bot-Token' : 'Android-Client-Bot-Token',
        label: 'Bot-Token',
        maxLength: 221,
        secret: true,
        validate: (value) => TelegramAccess.validToken(value)
            ? null
            : 'Bitte gib ein gültiges Bot-Token ein.',
      ),
    );
    if (token == null || !mounted) return;
    if (server) {
      await _write('POST', '/api/telegram-server-bot', {
        'token': token,
      }, 'Server-Bot-Token gespeichert. Verbinde die Bots erneut.');
    } else {
      await _perform(() async {
        await _telegram.setToken(token);
        await _loadTelegram();
        _message('Android-Client-Bot-Token gespeichert.');
      });
    }
  }

  Future<void> _removeTelegramToken({required bool server}) async {
    final accepted = await _confirm(
      server
          ? 'Server-Bot-Token und alle Server-Kopplungen entfernen?'
          : 'Android-Client-Token und lokale Kopplung entfernen?',
      'Entfernen',
    );
    if (!accepted || !mounted) return;
    if (server) {
      await _write(
        'DELETE',
        '/api/telegram-server-bot',
        null,
        'Server-Bot-Token entfernt.',
      );
    } else {
      await _perform(() async {
        await _telegram.removeToken();
        await _loadTelegram();
      });
    }
  }

  Future<void> _pairTelegram() => _perform(() async {
    if (mounted) setState(() => _telegramMessage = null);
    await _telegram.pair();
    await _loadTelegram();
    if (mounted) {
      setState(
        () => _telegramMessage =
            'Bots verbunden. Der Nachrichtentest kann jetzt gestartet werden.',
      );
    }
  });

  Future<void> _testTelegram() => _perform(() async {
    setState(() => _telegramMessage = 'Telegram-Nachrichtentest läuft …');
    try {
      await _telegram.test();
      if (mounted) {
        setState(() => _telegramMessage = 'Telegram-Verbindung bestätigt.');
      }
    } on Exception {
      if (mounted) {
        setState(
          () => _telegramMessage = 'Telegram-Verbindungstest nicht bestätigt.',
        );
      }
      rethrow;
    }
  });

  Future<void> _load({bool showLoading = false}) async {
    final request = ++_request;
    if (showLoading) setState(() => _loading = true);
    try {
      final status = await widget.api.get(
        '/api/status',
        timeout: const Duration(milliseconds: 2500),
      ) as Json;
      if (!mounted || request != _request) return;
      setState(() {
        _status = status;
        _error = null;
      });
    } on Exception catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _status = null;
        _error = error.toString();
      });
    } finally {
      if (mounted && request == _request && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _perform(
    Future<void> Function() run, {
    bool refresh = false,
  }) async {
    if (_busy) return;
    ++_request;
    setState(() {
      _busy = true;
      _loading = false;
    });
    try {
      await run();
    } on PlatformException catch (error) {
      _message(
        error.message ?? 'Die Android-Aktion konnte nicht ausgeführt werden.',
      );
    } on MissingPluginException {
      _message('Diese Aktion ist auf Android verfügbar.');
    } on Exception catch (error) {
      _message(error.toString());
    } finally {
      if (mounted && refresh) await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _write(
    String method,
    String path, [
    Json? body,
    String? notice,
  ]) => _perform(() async {
    await widget.api.write(method, path, body);
    if (notice != null) _message(notice);
  }, refresh: true);

  Future<bool> _confirm(String question, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          content: Text(question),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _connect(Json? account) async {
    final credentials = await showDialog<Json>(
      context: context,
      builder: (_) => _AccountDialog(account: account),
    );
    if (credentials != null && mounted) {
      await _write(
        'POST',
        '/api/connect',
        credentials,
        'Cookidoo wurde verbunden.',
      );
    }
  }

  Future<void> _disconnect() async {
    if (await _confirm(
          'Cookidoo-Verbindung trennen? Deine lokale Sammlung bleibt erhalten.',
          'Verbindung trennen',
        ) &&
        mounted) {
      await _write(
        'POST',
        '/api/disconnect',
        null,
        'Cookidoo-Verbindung getrennt.',
      );
    }
  }

  Future<void> _sync() => _perform(() async {
    final response = await widget.api.write('POST', '/api/sync') as Json;
    _message(
      response['started'] == true
          ? 'Synchronisierung gestartet.'
          : 'Die Synchronisierung läuft bereits.',
    );
  }, refresh: true);

  Future<void> _export() => _perform(() async {
    final bytes = await widget.api.exportCollection();
    if (!mounted) return;
    final saved = await _documents.invokeMethod<bool>('saveCollection', bytes);
    if (saved == true) _message('Die Sammlung wurde als JSON gespeichert.');
  });

  Future<void> _googleKey() async {
    final key = await showDialog<String>(
      context: context,
      builder: (_) => _ValueDialog(
        title: 'Google API-Schlüssel',
        label: 'API-Schlüssel',
        maxLength: 512,
        secret: true,
        validate: (value) =>
            value.isEmpty ||
                value.runes.length > 512 ||
                RegExp(r'\s').hasMatch(value)
            ? 'Bitte gib einen gültigen API-Schlüssel ein.'
            : null,
      ),
    );
    if (key != null && mounted) {
      await _write('POST', '/api/google-api-key', {
        'key': key,
      }, 'Google API-Schlüssel gespeichert.');
    }
  }

  Future<void> _removeGoogleKey() async {
    if (await _confirm(
          'Gespeicherten Google API-Schlüssel entfernen?',
          'Entfernen',
        ) &&
        mounted) {
      await _write(
        'DELETE',
        '/api/google-api-key',
        null,
        'Google API-Schlüssel entfernt.',
      );
    }
  }

  String _hex(int accent) =>
      '#${(accent & 0x00ffffff).toRadixString(16).padLeft(6, '0')}';

  Future<void> _pickAccent(int accent) async {
    final selection = await showDialog<String>(
      context: context,
      builder: (_) => _ValueDialog(
        title: 'Akzentfarbe',
        label: 'Farbwert (#RRGGBB)',
        initial: _hex(accent),
        maxLength: 7,
        validate: (value) => RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(value)
            ? null
            : 'Gib eine Farbe im Format #RRGGBB ein.',
      ),
    );
    if (selection != null && mounted) {
      await _perform(
        () => widget.appearance.update(
          accent: int.parse(selection.substring(1), radix: 16) | 0xff000000,
        ),
      );
    }
  }

  Widget _card(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );

  Widget _appearance() => ValueListenableBuilder(
    valueListenable: widget.appearance,
    builder: (context, appearance, _) => _card('Darstellung', [
      SwitchListTile(
        title: const Text('Dunkelmodus'),
        contentPadding: EdgeInsets.zero,
        value: appearance.dark,
        onChanged: _busy
            ? null
            : (dark) => _perform(() => widget.appearance.update(dark: dark)),
      ),
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pickAccent(appearance.accent),
            icon: Icon(Icons.circle, color: Color(appearance.accent)),
            label: Text('Akzentfarbe ${_hex(appearance.accent)}'),
          ),
          TextButton(
            onPressed: _busy || appearance.accent == defaultAccent
                ? null
                : () => _perform(
                    () => widget.appearance.update(accent: defaultAccent),
                  ),
            child: const Text('Standardfarbe'),
          ),
        ],
      ),
    ]),
  );

  List<Widget> _serverOptions(Json status) {
    final account = status['account'] as Json?;
    final sync = status['sync'] as Json?;
    final stats = status['stats'] as Json?;
    final last = status['last_result'] as Json?;
    final connected = status['connected'] == true;
    final running = sync?['running'] == true;
    final interval = status['sync_hours'];
    final savedKey = status['google_api_key_set'] == true;
    final done = sync?['done'];
    final total = sync?['total'];
    return [
      _card('Dein Cookidoo-Konto', [
        if (connected) ...[
          Text(text(account?['email'])),
          Text('Verbunden mit Cookidoo ${_regions[account?['region']] ?? ''}'),
        ] else
          const Text(
            'Verbinde dein Konto, um Rezeptlisten und Kollektionen zu laden.',
          ),
        FilledButton(
          onPressed: _busy || running ? null : () => _connect(account),
          child: Text(connected ? 'Konto neu verbinden' : 'Cookidoo verbinden'),
        ),
        if (connected)
          TextButton(
            onPressed: _busy || running ? null : _disconnect,
            child: const Text('Verbindung trennen'),
          ),
      ]),
      _card('Synchronisierung', [
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Automatischer Abgleich',
          ),
          child: DropdownButton<int>(
            isExpanded: true,
            underline: const SizedBox.shrink(),
            value: _intervals.containsKey(interval) ? interval as int : 6,
            onChanged: _busy
                ? null
                : (hours) {
                    if (hours != null) {
                      unawaited(
                        _write('POST', '/api/settings', {
                          'sync_hours': hours,
                        }, 'Synchronisierungsintervall gespeichert.'),
                      );
                    }
                  },
            items: [
              for (final entry in _intervals.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
          ),
        ),
        if (stats?['last_sync'] case final String value)
          Text('Letzter erfolgreicher Abgleich: ${formatSyncDate(value)}'),
        if (running) ...[
          Text(text(sync?['message'], 'Synchronisierung läuft …')),
          LinearProgressIndicator(
            value: done is num && total is num && total > 0
                ? (done / total).clamp(0, 1).toDouble()
                : null,
          ),
        ] else if (last?['phase'] == 'error')
          Text(
            text(last?['message']),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton.icon(
          onPressed: _busy || !connected || running ? null : _sync,
          icon: const Icon(Icons.sync),
          label: const Text('Jetzt synchronisieren'),
        ),
      ]),
      _card('Google API', [
        Text(
          savedKey
              ? 'Ein API-Schlüssel ist gespeichert.'
              : 'Noch kein API-Schlüssel gespeichert.',
        ),
        OutlinedButton(
          onPressed: _busy ? null : _googleKey,
          child: Text(
            savedKey ? 'API-Schlüssel ersetzen' : 'API-Schlüssel speichern',
          ),
        ),
        if (savedKey)
          TextButton(
            onPressed: _busy ? null : _removeGoogleKey,
            child: const Text('Schlüssel entfernen'),
          ),
      ]),
      _card('Deine Sammlung', [
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.save_alt),
          label: const Text('Sammlung als JSON exportieren'),
        ),
      ]),
    ];
  }

  Widget _telegramOptions() {
    final server = _status?['telegram_server_bot_set'];
    final client = _telegramState?.tokenSet;
    return _card('Telegram', [
      Text(switch (server) {
        true => 'Ein Server-Bot-Token ist gespeichert.',
        false => 'Kein Server-Bot-Token gespeichert.',
        _ => 'Status des Server-Bot-Tokens unbekannt.',
      }),
      if (server is bool)
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : () => _telegramToken(server: true),
              child: Text(
                server ? 'Server-Token ersetzen' : 'Server-Token speichern',
              ),
            ),
            if (server)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _removeTelegramToken(server: true),
                child: const Text('Server-Token entfernen'),
              ),
          ],
        ),
      Text(switch (client) {
        true => 'Ein Android-Client-Bot-Token ist gespeichert.',
        false => 'Kein Android-Client-Bot-Token gespeichert.',
        _ => 'Status des Android-Client-Bot-Tokens unbekannt.',
      }),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: _busy ? null : () => _telegramToken(server: false),
            child: Text(
              client == true
                  ? 'Android-Token ersetzen'
                  : 'Android-Token speichern',
            ),
          ),
          if (client == true)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _removeTelegramToken(server: false),
              child: const Text('Android-Token entfernen'),
            ),
        ],
      ),
      const Text(
        'Verwende für Android einen eigenen Client-Bot. Beide Bots benötigen die Bot-zu-Bot-Freigabe und einen eigenen Update-Kanal.',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: _busy || client != true || server != true
                ? null
                : _pairTelegram,
            child: const Text('Android-Bots verbinden'),
          ),
          OutlinedButton(
            onPressed: _busy || _telegramState?.paired != true
                ? null
                : _testTelegram,
            child: const Text('Nachrichtentest starten'),
          ),
        ],
      ),
      if (_telegramMessage != null) Text(_telegramMessage!),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Einstellungen')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _appearance(),
          if (_loading || _busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!),
            TextButton(
              onPressed: _busy ? null : () => _load(showLoading: true),
              child: const Text('Erneut laden'),
            ),
          ],
          if (_status case final Json status) ..._serverOptions(status),
          _telegramOptions(),
          _card('Rezeptgarten für Android', [
            if (_version != null) Text('Installierte Version $_version'),
            Semantics(
              liveRegion: true,
              child: Text(
                _checkingUpdate
                    ? 'Suche nach Updates …'
                    : _updateStatus ?? 'Updatestatus unbekannt.',
              ),
            ),
            TextButton.icon(
              onPressed: _checkingUpdate || _downloadingUpdate
                  ? null
                  : _checkUpdate,
              icon: const Icon(Icons.refresh),
              label: const Text('Nach Updates suchen'),
            ),
            OutlinedButton.icon(
              onPressed: _downloadingUpdate ? null : _installUpdate,
              icon: const Icon(Icons.download),
              label: const Text('APK herunterladen und installieren'),
            ),
            if (_downloadingUpdate) ...[
              const LinearProgressIndicator(),
              const Text('APK wird heruntergeladen und geprüft …'),
            ],
            if (_updateMessage != null) Text(_updateMessage!),
          ]),
        ],
      ),
    ),
  );
}

String formatSyncDate(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return value;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year}, ${two(date.hour)}:${two(date.minute)}';
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({this.account});
  final Json? account;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final _email = TextEditingController(
    text: text(widget.account?['email']),
  );
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  late String _region = _regions.containsKey(widget.account?['region'])
      ? widget.account!['region'] as String
      : 'de';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, {
        'email': _email.text.trim(),
        'password': _password.text,
        'region': _region,
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Cookidoo verbinden'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            maxLength: 254,
            decoration: const InputDecoration(
              labelText: 'E-Mail-Adresse',
              counterText: '',
            ),
            validator: (value) =>
                value != null && value.contains('@') && value.trim().length >= 3
                ? null
                : 'Bitte prüfe die E-Mail-Adresse.',
          ),
          TextFormField(
            controller: _password,
            obscureText: true,
            maxLength: 512,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Cookidoo-Passwort',
              counterText: '',
            ),
            validator: (value) => value == null || value.isEmpty
                ? 'Bitte gib dein Passwort ein.'
                : null,
          ),
          DropdownButtonFormField<String>(
            initialValue: _region,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Land'),
            onChanged: (region) {
              if (region != null) _region = region;
            },
            items: [
              for (final entry in _regions.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Verbinden')),
    ],
  );
}

class _ValueDialog extends StatefulWidget {
  const _ValueDialog({
    required this.title,
    required this.label,
    required this.maxLength,
    required this.validate,
    this.initial = '',
    this.secret = false,
  });

  final String title;
  final String label;
  final String initial;
  final int maxLength;
  final bool secret;
  final String? Function(String) validate;

  @override
  State<_ValueDialog> createState() => _ValueDialogState();
}

class _ValueDialogState extends State<_ValueDialog> {
  final _form = GlobalKey<FormState>();
  late final _value = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _value.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _value,
        autofocus: true,
        obscureText: widget.secret,
        autocorrect: false,
        maxLength: widget.maxLength,
        decoration: InputDecoration(labelText: widget.label, counterText: ''),
        validator: (value) => widget.validate((value ?? '').trim()),
        onFieldSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Speichern')),
    ],
  );
}
