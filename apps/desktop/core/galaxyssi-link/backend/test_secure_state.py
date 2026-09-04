from __future__ import annotations

import base64
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from secure_state import (
    MASTER_KEY_ENV,
    PROTOCOL,
    SecureStateError,
    clear_cached_keys,
    decrypt_text,
    encrypt_text,
    read_secure_json,
    seal_identifier,
    unseal_identifier,
    write_secure_json,
)


class SecureStateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary.name) / "state.json"
        self.master_key = base64.urlsafe_b64encode(bytes(range(32))).decode("ascii")
        self.environment = patch.dict(
            os.environ,
            {MASTER_KEY_ENV: self.master_key},
        )
        self.environment.start()
        clear_cached_keys()

    def tearDown(self) -> None:
        clear_cached_keys()
        self.environment.stop()
        self.temporary.cleanup()

    def test_round_trip_hides_sensitive_values(self) -> None:
        value = {
            "client_route_id": "route-secret-value",
            "identity_fingerprint": "fingerprint-secret-value",
            "authorization": {"scope": "desktop.executor.full"},
        }

        write_secure_json(self.path, value, purpose="pairing-registry")

        raw = self.path.read_text(encoding="ascii")
        self.assertIn(PROTOCOL, raw)
        self.assertNotIn("route-secret-value", raw)
        self.assertNotIn("fingerprint-secret-value", raw)
        self.assertEqual(
            value,
            read_secure_json(
                self.path,
                purpose="pairing-registry",
            ).value,
        )

    def test_ciphertext_is_bound_to_store_purpose(self) -> None:
        write_secure_json(
            self.path,
            {"authorization_id": "private"},
            purpose="desktop-control",
        )

        with self.assertRaises(SecureStateError):
            read_secure_json(self.path, purpose="pairing-registry")

    def test_tampered_ciphertext_is_rejected(self) -> None:
        write_secure_json(self.path, {"route": "private"}, purpose="pairing-registry")
        envelope = json.loads(self.path.read_text(encoding="ascii"))
        ciphertext = envelope["ciphertext"]
        envelope["ciphertext"] = ("A" if ciphertext[0] != "A" else "B") + ciphertext[1:]
        self.path.write_text(json.dumps(envelope), encoding="ascii")

        with self.assertRaises(SecureStateError):
            read_secure_json(self.path, purpose="pairing-registry")

    def test_plaintext_requires_explicit_one_time_migration(self) -> None:
        self.path.write_text('{"server_route_id":"legacy"}', encoding="utf-8")

        with self.assertRaises(SecureStateError):
            read_secure_json(self.path, purpose="pairing-registry")

        migrated = read_secure_json(
            self.path,
            purpose="pairing-registry",
            allow_legacy_plaintext=True,
        )
        self.assertTrue(migrated.legacy_plaintext)
        self.assertEqual("legacy", migrated.value["server_route_id"])

    def test_device_key_is_created_and_recovered_without_plaintext_state(self) -> None:
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop(MASTER_KEY_ENV, None)
            clear_cached_keys()
            write_secure_json(
                self.path,
                {"identity_private_key": "never-plain"},
                purpose="signal-protocol-store",
            )
            clear_cached_keys()
            self.assertEqual(
                "never-plain",
                read_secure_json(
                    self.path,
                    purpose="signal-protocol-store",
                ).value["identity_private_key"],
            )

        self.assertNotIn("never-plain", self.path.read_text(encoding="ascii"))
        self.assertTrue((self.path.parent / ".galaxyssi-state-key").exists())

    def test_field_encryption_uses_randomized_ciphertext(self) -> None:
        first = encrypt_text(self.path, "private topic", purpose="link-delivery")
        second = encrypt_text(self.path, "private topic", purpose="link-delivery")

        self.assertNotEqual(first, second)
        self.assertNotIn("private topic", first)
        self.assertEqual(
            "private topic",
            decrypt_text(self.path, first, purpose="link-delivery"),
        )

    def test_identifier_encryption_is_queryable_and_authenticated(self) -> None:
        first = seal_identifier(
            self.path,
            "client-route-secret",
            purpose="link-delivery-route",
        )
        second = seal_identifier(
            self.path,
            "client-route-secret",
            purpose="link-delivery-route",
        )

        self.assertEqual(first, second)
        self.assertNotIn("client-route-secret", first)
        self.assertEqual(
            "client-route-secret",
            unseal_identifier(
                self.path,
                first,
                purpose="link-delivery-route",
            ),
        )


if __name__ == "__main__":
    unittest.main()
