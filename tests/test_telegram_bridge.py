import unittest
from scripts.telegram_bridge import reply_for


class TelegramBridgeTests(unittest.TestCase):
    def test_only_fresh_private_ping_from_paired_bot_receives_reply(self):
        nonce = 'a' * 32
        message = {'from': {'id': 123, 'is_bot': True}, 'chat': {'id': 123, 'type': 'private'},
                   'date': 1000, 'text': 'rezeptgarten-ping ' + nonce}
        self.assertEqual(reply_for({'message': message}, 123, 1000), 'rezeptgarten-pong ' + nonce)
        cart = {**message, 'text': 'rezeptgarten-cart ' + nonce}
        self.assertEqual(reply_for({'message': cart}, 123, 1000), 'rezeptgarten-cart ' + nonce)
        compressed = {**message, 'text': 'rezeptgarten-cartz ' + nonce}
        self.assertEqual(reply_for({'message': compressed}, 123, 1000), 'rezeptgarten-cartz ' + nonce)
        week = {**message, 'text': 'rezeptgarten-weekz ' + nonce + ' 2026-01-05'}
        self.assertEqual(reply_for({'message': week}, 123, 1000), 'rezeptgarten-weekz ' + nonce + ' 2026-01-05')
        self.assertIsNone(reply_for({'message': {**week, 'text': 'rezeptgarten-weekz ' + nonce + ' 2026-01-06'}}, 123, 1000))
        self.assertIsNone(reply_for({'message': message}, 456, 1000))
        self.assertIsNone(reply_for({'message': message}, 123, 1121))
        for key, value in [('text', 'rezeptgarten-pong ' + nonce), ('chat', {'id': 123, 'type': 'group'}),
                           ('from', {'id': 123, 'is_bot': False})]:
            self.assertIsNone(reply_for({'message': {**message, key: value}}, 123, 1000))


if __name__ == '__main__':
    unittest.main()
