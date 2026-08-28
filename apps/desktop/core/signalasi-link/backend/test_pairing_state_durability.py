from __future__ import annotations

import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

import pairing_state
from link_protocol import new_link_secret, new_route_id
from secure_state import PROTOCOL, read_secure_json, write_secure_json


class PairingStateDurabilityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.registry = Path(self.temp.name) / "registry.json"
        self.patches = [
            patch.object(pairing_state, "STATE_PATH", self.registry),
            patch.object(pairing_state, "_last_good_state", None),
            patch.object(pairing_state, "_last_good_path", ""),
        ]
        for item in self.patches:
            item.start()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.temp.cleanup()

    def _pair_client(self, route_id: str | None = None) -> dict:
        return pairing_state.record_pairing_success(
            "a" * 64,
            "signalasi:test",
            client_route_id=route_id or new_route_id(),
            display_name="Test phone",
            platform="android",
            link_secret=new_link_secret(),
            local_identity_fingerprint="d" * 64,
        )

    def _simulate_restart(self) -> None:
        pairing_state._last_good_state = None
        pairing_state._last_good_path = ""

    def _persisted_state(self) -> dict:
        return read_secure_json(
            self.registry,
            purpose=pairing_state.STATE_PURPOSE,
        ).value

    def test_registry_and_clients_survive_process_restart(self):
        paired = self._pair_client()

        self._simulate_restart()

        self.assertEqual(paired["client_route_id"], pairing_state.list_clients()[0]["client_route_id"])
        self.assertEqual(4, pairing_state._read_state()["schema"])

    def test_corrupt_primary_recovers_from_backup_without_changing_identity(self):
        paired = self._pair_client()
        self.registry.write_text("{partial", encoding="utf-8")
        self._simulate_restart()

        recovered = pairing_state._read_state()

        self.assertIn(paired["client_route_id"], recovered["clients"])
        self.assertEqual(4, self._persisted_state()["schema"])

    def test_missing_primary_recovers_from_backup(self):
        paired = self._pair_client()
        self.registry.unlink()
        self._simulate_restart()

        recovered = pairing_state._read_state()

        self.assertIn(paired["client_route_id"], recovered["clients"])
        self.assertTrue(self.registry.exists())

    def test_corrupt_registry_without_recovery_is_not_replaced(self):
        self.registry.write_text("{broken", encoding="utf-8")
        pairing_state._backup_path().write_text("{also-broken", encoding="utf-8")

        with self.assertRaises(pairing_state.PairingRegistryError):
            pairing_state._read_state()

        self.assertEqual("{broken", self.registry.read_text(encoding="utf-8"))

    def test_unsupported_registry_schema_is_discarded_without_migration(self):
        write_secure_json(
            self.registry,
            {"schema": 3, "server_route_id": new_route_id(), "clients": {}},
            purpose=pairing_state.STATE_PURPOSE,
        )
        write_secure_json(
            pairing_state._backup_path(),
            {"schema": 3, "server_route_id": new_route_id(), "clients": {}},
            purpose=pairing_state.STATE_PURPOSE,
        )
        self._simulate_restart()

        state = pairing_state._read_state()

        self.assertEqual(4, state["schema"])
        self.assertEqual({}, state["clients"])
        self.assertNotIn("server_route_id", state)

    def test_concurrent_updates_do_not_drop_clients_or_corrupt_json(self):
        pairing_state._read_state()
        routes = [new_route_id() for _ in range(32)]

        with ThreadPoolExecutor(max_workers=8) as executor:
            list(executor.map(self._pair_client, routes))

        self._simulate_restart()
        state = pairing_state._read_state()

        self.assertEqual(set(routes), set(state["clients"]))
        self.assertEqual(32, len(self._persisted_state()["clients"]))
        self.assertFalse(list(self.registry.parent.glob(f".{self.registry.name}.*.tmp")))

    def test_registry_hides_route_fingerprint_and_authorization_at_rest(self):
        paired = self._pair_client()

        raw = self.registry.read_text(encoding="ascii")

        self.assertIn(PROTOCOL, raw)
        self.assertNotIn(paired["client_route_id"], raw)
        self.assertNotIn("a" * 64, raw)
        self.assertNotIn("desktop.executor.full", raw)

    def test_device_metadata_and_user_alias_are_persisted(self):
        paired = pairing_state.record_pairing_success(
            "b" * 64,
            "signalasi:device",
            client_route_id=new_route_id(),
            display_name="S26 Ultra · 4F2A",
            platform="android",
            device_id="phone-stable-id",
            device_name="S26 Ultra",
            device_manufacturer="Samsung",
            device_model="SM-S9480",
            platform_version="17",
            profile_name="Me",
            link_secret=new_link_secret(),
            local_identity_fingerprint="d" * 64,
        )

        renamed = pairing_state.rename_client(paired["client_route_id"], "My primary phone")
        self._simulate_restart()
        restored = pairing_state.get_client(paired["client_route_id"])

        self.assertEqual("phone-stable-id", restored["device_id"])
        self.assertEqual("SM-S9480", restored["device_model"])
        self.assertEqual("My primary phone", renamed["display_name"])
        self.assertTrue(restored["user_renamed"])

    def test_automatic_device_name_collapses_duplicate_segments(self):
        paired = pairing_state.record_pairing_success(
            "c" * 64,
            "signalasi:device",
            client_route_id=new_route_id(),
            display_name="Galaxy S20 Ultra 5G · Galaxy S20 Ultra 5G · 9CC8",
            device_name="Galaxy S20 Ultra 5G",
            profile_name="Galaxy S20 Ultra 5G · 9CC8",
            link_secret=new_link_secret(),
            local_identity_fingerprint="d" * 64,
        )

        self.assertEqual("Galaxy S20 Ultra 5G · 9CC8", paired["display_name"])
        self.assertEqual(
            "Galaxy S20 Ultra 5G · 9CC8",
            self._persisted_state()["clients"][paired["client_route_id"]]["display_name"],
        )

    def test_existing_duplicate_name_is_normalized_without_overwriting_user_alias(self):
        paired = self._pair_client()
        state = pairing_state._read_state()
        state["clients"][paired["client_route_id"]]["display_name"] = "Phone · Phone · A1B2"
        pairing_state._write_state(state)

        self.assertEqual("Phone · A1B2", pairing_state.list_clients()[0]["display_name"])
        renamed = pairing_state.rename_client(paired["client_route_id"], "Phone · Phone")
        self.assertEqual("Phone · Phone", renamed["display_name"])


if __name__ == "__main__":
    unittest.main()
