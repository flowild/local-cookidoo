import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rezeptgarten/telegram_service.dart';

void main() {
  test('accepts only complete matching response parts', () async {
    const nonce = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const other = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final parts = TelegramSnapshotParts('cart', nonce);
    parts.accept('rezeptgarten-cart-part $other 1/2 AAA');
    parts.accept('rezeptgarten-week-part $nonce 1/2 AAA');
    parts.accept('rezeptgarten-cart-part $nonce 2/2 BBB');
    expect(parts.result.isCompleted, isFalse);
    parts.accept('rezeptgarten-cart-part $nonce 1/2 AAA');
    expect(await parts.result.future, 'AAABBB');

    final conflict = TelegramSnapshotParts('cart', nonce);
    final failure = expectLater(conflict.result.future, throwsFormatException);
    conflict.accept('rezeptgarten-cart-part $nonce 1/2 AAA');
    conflict.accept('rezeptgarten-cart-part $nonce 1/2 CCC');
    await failure;
  });

  test('decrypts the server AES-GCM and zlib format and authenticates the request', () async {
    const encoded =
        'AAECAwQFBgcICQoLP559TQ/Ji9agFyUBH7+yJk+b0oaicRZRFjZPCLBsADOxGeIYwXFI6sNBa17ArUIQVRIR';
    const key = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
    const nonce = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final result = await decodeTelegramSnapshot(encoded, key, nonce);
    expect(result['items'], [
      {'name': 'Test'},
    ]);
    await expectLater(
      decodeTelegramSnapshot(encoded, key, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
      throwsA(isA<Exception>()),
    );
    final damaged = base64Decode(encoded);
    damaged[15] ^= 1;
    await expectLater(
      decodeTelegramSnapshot(base64Encode(damaged), key, nonce),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      decodeTelegramSnapshot(base64Encode(damaged.sublist(0, 20)), key, nonce),
      throwsFormatException,
    );
  });
}
