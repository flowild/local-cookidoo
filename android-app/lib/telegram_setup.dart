import 'package:material_ui/material_ui.dart';

import 'spacing.dart';

import 'telegram_service.dart';
import 'api.dart';
import 'connection.dart';

class TelegramSetup extends StatefulWidget {
  const TelegramSetup({
    super.key,
    required this.telegram,
    required this.api,
    this.connection,
  });

  final TelegramService telegram;
  final RezeptgartenApi api;
  final ConnectionController? connection;

  @override
  State<TelegramSetup> createState() => _TelegramSetupState();
}

class _TelegramSetupState extends State<TelegramSetup> {
  final id = TextEditingController();
  final hash = TextEditingController();
  final value = TextEditingController();
  bool busy = false;
  String? pairingMessage;

  @override
  void dispose() {
    id.dispose();
    hash.dispose();
    value.dispose();
    super.dispose();
  }

  Future<void> pair() async {
    if (busy) return;
    setState(() {
      busy = true;
      pairingMessage = null;
    });
    try {
      if (widget.connection != null &&
          widget.connection!.mode != ConnectionMode.local) {
        throw StateError('Heimnetz nicht verbunden.');
      }
      await widget.telegram.pair(widget.api);
      pairingMessage = 'Telegram ist mit Rezeptgarten verbunden.';
    } catch (_) {
      pairingMessage = 'Die Verbindung konnte nicht bestätigt werden. Bitte im Heimnetz erneut versuchen.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> testConnection() async {
    if (busy) return;
    setState(() {
      busy = true;
      pairingMessage = null;
    });
    try {
      await widget.telegram.testConnection();
      pairingMessage = 'Die Telegram-Verbindung funktioniert.';
    } catch (_) {
      pairingMessage = 'Die Telegram-Verbindung konnte nicht bestätigt werden.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> disconnect() async {
    if (busy) return;
    setState(() {
      busy = true;
      pairingMessage = null;
    });
    try {
      if (widget.connection != null &&
          widget.connection!.mode != ConnectionMode.local) {
        throw StateError('Heimnetz nicht verbunden.');
      }
      await widget.telegram.disconnect(widget.api);
      pairingMessage = 'Die Verbindung wurde getrennt.';
    } catch (_) {
      pairingMessage = 'Die Verbindung konnte nicht getrennt werden. Bitte im Heimnetz erneut versuchen.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> changeCredentials() async {
    if (busy) return;
    setState(() {
      busy = true;
      pairingMessage = null;
    });
    try {
      if (widget.telegram.paired &&
          widget.connection != null &&
          widget.connection!.mode != ConnectionMode.local) {
        throw StateError('Heimnetz nicht verbunden.');
      }
      await widget.telegram.changeCredentials(widget.api);
    } catch (_) {
      pairingMessage = 'Die Telegram-Zugangsdaten konnten nicht geändert werden. Bitte im Heimnetz erneut versuchen.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() => busy = true);
    if (widget.telegram.step == TelegramStep.credentials) {
      await widget.telegram.setCredentials(id.text, hash.text);
      if (mounted) hash.clear();
    } else {
      await widget.telegram.submit(value.text);
      if (mounted) value.clear();
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> loadCredentials() async {
    if (busy) return;
    setState(() {
      busy = true;
      pairingMessage = null;
    });
    try {
      if (widget.connection != null &&
          widget.connection!.mode != ConnectionMode.local) {
        throw StateError('Heimnetz nicht verbunden.');
      }
      final data = await widget.api.get('/api/telegram-app-credentials') as Json;
      if (widget.telegram.step == TelegramStep.credentials) {
        await widget.telegram.setCredentials(
          data['api_id'] as String,
          data['api_hash'] as String,
        );
      }
    } catch (_) {
      pairingMessage = 'Die Zugangsdaten konnten nicht übernommen werden. Bitte prüfe die Freigabe im Heimnetz.';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.telegram,
      builder: (context, _) {
        final step = widget.telegram.step;
        final label = switch (step) {
          TelegramStep.phone => 'Telefonnummer mit Ländervorwahl',
          TelegramStep.code => 'Bestätigungscode',
          TelegramStep.email => 'Telegram-E-Mail-Adresse',
          TelegramStep.emailCode => 'E-Mail-Bestätigungscode',
          TelegramStep.password => 'Zwei-Schritt-Passwort',
          _ => '',
        };
        return AlertDialog(
          title: Text(
            step == TelegramStep.ready && widget.telegram.paired
                ? 'Telegram verwalten'
                : 'Telegram einrichten',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: AppSpacing.item,
              children: [
                const Text(
                  'Rezeptmix nutzt Telegram für den Zugriff unterwegs und sendet dazu Anfragen an den Rezeptgarten-Bot.',
                ),
                if (step == TelegramStep.credentials) ...[
                  OutlinedButton(
                    onPressed: busy ? null : loadCredentials,
                    child: const Text('Aus dem Heimnetz übernehmen'),
                  ),
                  if (pairingMessage != null) Text(pairingMessage!),
                  TextField(
                    controller: id,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Telegram API-ID',
                    ),
                  ),
                  TextField(
                    controller: hash,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Telegram API-Hash',
                    ),
                  ),
                  const Text(
                    'Die Zugangsdaten erhältst du unter my.telegram.org bei „API development tools“.',
                  ),
                ] else if (label.isNotEmpty)
                  TextField(
                    controller: value,
                    obscureText: step == TelegramStep.password,
                    decoration: InputDecoration(labelText: label),
                  ),
                if (step == TelegramStep.loading)
                  const CircularProgressIndicator(),
                if (step == TelegramStep.ready)
                  const Text('Telegram ist angemeldet.'),
                if (step == TelegramStep.ready && pairingMessage != null)
                  Text(pairingMessage!),
                if (step == TelegramStep.ready && widget.telegram.paired) ...[
                  TextButton(
                    onPressed: busy ? null : testConnection,
                    child: const Text('Verbindung testen'),
                  ),
                  TextButton(
                    onPressed: busy ? null : disconnect,
                    child: const Text('Verbindung trennen'),
                  ),
                ],
                if (step == TelegramStep.ready)
                  TextButton(
                    onPressed: busy ? null : changeCredentials,
                    child: const Text('Telegram-Zugangsdaten ändern'),
                  ),
                if (widget.telegram.error case final String error) Text(error),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: Text(step == TelegramStep.ready ? 'Fertig' : 'Später'),
            ),
            if (step == TelegramStep.credentials || label.isNotEmpty)
              FilledButton(
                onPressed: busy ? null : submit,
                child: const Text('Weiter'),
              ),
            if (step == TelegramStep.ready)
              FilledButton(
                onPressed: busy ? null : pair,
                child: Text(
                  widget.telegram.paired
                      ? 'Erneut verbinden'
                      : 'Mit Rezeptgarten verbinden',
                ),
              ),
          ],
        );
      },
    );
  }
}
