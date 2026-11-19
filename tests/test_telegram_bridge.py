import unittest
from app.telegram_pairs import bridge_config
from scripts.telegram_bridge import pairing_request, reply_for, same_pair


class TelegramBridgeTests(unittest.TestCase):
    def test_legacy_bots_are_never_authorized(self):
        raw = {'token': 'fixture', 'client_id': 111, 'cart_key': 'old',
               'android_pair': {'client_id': 222},
               'android_user_pair': {'client_id': 333, 'cart_key': 'user', 'cart_owner': 'owner'}}
        before = bridge_config(raw)
        self.assertEqual(set(before['clients']), {'333'})
        self.assertNotIn('user', str(before))
        self.assertFalse(same_pair(before, bridge_config({**raw, 'android_user_pair': {**raw['android_user_pair'], 'cart_key': 'new'}}), 333))
        nonce = 'a' * 32
        message = {'from': {'id': 333, 'is_bot': False}, 'chat': {'id': 333, 'type': 'private'}, 'date': 1000, 'text': 'rezeptgarten-cart ' + nonce}
        self.assertEqual(reply_for({'message': message}, 333, 1000), 'rezeptgarten-cart ' + nonce)
        self.assertIsNone(reply_for({'message': {**message, 'from': {'id': 333, 'is_bot': True}}}, 333, 1000))
        self.assertIsNone(reply_for({'message': message}, 333, 1121))

    def test_user_pairing_requires_fresh_private_user_message(self):
        challenge = 'a' * 64
        message = {'from': {'id': 123, 'is_bot': False}, 'chat': {'id': 123, 'type': 'private'},
                   'date': 1000, 'text': 'rezeptgarten-pair ' + challenge}
        self.assertEqual(pairing_request({'message': message}, 1000), (123, challenge))
        self.assertIsNone(pairing_request({'message': message}, 1121))
        self.assertIsNone(pairing_request({'message': {**message, 'from': {'id': 123, 'is_bot': True}}}, 1000))
        self.assertIsNone(pairing_request({'message': {**message, 'chat': {'id': 123, 'type': 'group'}}}, 1000))
        user = {**message, 'text': 'rezeptgarten-ping ' + 'b' * 32}
        self.assertIsNotNone(reply_for({'message': user}, 123, 1000))


if __name__ == '__main__':
    unittest.main()
