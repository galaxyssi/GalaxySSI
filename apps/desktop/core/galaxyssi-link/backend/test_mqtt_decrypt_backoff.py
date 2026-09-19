import json
import unittest
from galaxyssi_client import SignalSidecarError
from mqtt_decrypt_backoff import DecryptBackoff


class DecryptBackoffTest(unittest.TestCase):
    def setUp(self):
        self.now = 0
        self.gate = DecryptBackoff(capacity=2, clock=lambda: self.now)
        self.error = SignalSidecarError(400, json.dumps({
            "error": "InvalidMessageException", "message": "No valid sessions. private data"}))

    def test_duplicate_failure_defers_but_eventually_retries(self):
        self.gate.failed(('peer', 'key', 'cipher'), self.error)
        self.assertTrue(self.gate.defer(('peer', 'key', 'cipher')))
        self.now = 2
        self.assertFalse(self.gate.defer(('peer', 'key', 'cipher')))
        self.gate.failed(('peer', 'key', 'cipher'), self.error)
        self.now = 5
        self.assertTrue(self.gate.defer(('peer', 'key', 'cipher')))
        self.now = 6
        self.assertFalse(self.gate.defer(('peer', 'key', 'cipher')))

    def test_scope_pairing_and_cipher_changes_are_independent(self):
        self.gate.failed(('a', 'k1', 'c1'), self.error)
        for key in [('b', 'k1', 'c1'), ('a', 'k2', 'c1'), ('a', 'k1', 'c2')]:
            self.assertFalse(self.gate.defer(key))

    def test_bounded_and_success_clears_only_matching_entry(self):
        for key in ('a', 'b', 'c'):
            self.gate.failed(key, self.error)
        self.assertEqual(2, self.gate.snapshot()['tracked'])
        self.assertFalse(self.gate.defer('a'))
        self.gate.succeeded('b')
        self.assertFalse(self.gate.defer('b'))
        self.assertTrue(self.gate.defer('c'))
        self.assertNotIn('private data', str(self.gate.snapshot()))

    def test_infrastructure_errors_do_not_poison_ciphertext(self):
        self.gate.failed('a', TimeoutError('private data'))
        self.assertFalse(self.gate.defer('a'))
        self.assertEqual(0, self.gate.snapshot()['tracked'])
