import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'appearance.dart';

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
  static const _links = MethodChannel('de.rezeptgarten/links');
  static const _documents = MethodChannel('de.rezeptgarten/documents');
  static const _preferences = MethodChannel('de.rezeptgarten/preferences');

  Json? _status;
  String? _error;
  String? _version;
  bool _loading = false;
  bool _busy = false;
  int _request = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_load(showLoading: true));
    unawaited(_loadVersion());
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_busy && !_loading && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_load());
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
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
          _card('Rezeptgarten für Android', [
            if (_version != null) Text('Installierte Version $_version'),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _perform(
                      () => _links.invokeMethod<void>('openDownload'),
                    ),
              icon: const Icon(Icons.download),
              label: const Text('APK-Download öffnen'),
            ),
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
