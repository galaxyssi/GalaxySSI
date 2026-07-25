from __future__ import annotations

import json
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

import pairing_state
from link_protocol import new_route_id


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
        )

    def _simulate_restart(self) -> None:
        pairing_state._last_good_state = None
        pairing_state._last_good_path = ""

    def test_registry_and_clients_survive_process_restart(self):
        server_route = pairing_state.server_route_id()
        paired = self._pair_client()

        self._simulate_restart()

        self.assertEqual(server_route, pairing_state.server_route_id())
        self.assertEqual(paired["client_route_id"], pairing_state.list_clients()[0]["client_route_id"])

    def test_corrupt_primary_recovers_from_backup_without_changing_identity(self):
        server_route = pairing_state.server_route_id()
        paired = self._pair_client()
        self.registry.write_text("{partial", encoding="utf-8")
        self._simulate_restart()

        recovered = pairing_state._read_state()

        self.assertEqual(server_route, recovered["server_route_id"])
        self.assertIn(paired["client_route_id"], recovered["clients"])
        self.assertEqual(server_route, json.loads(self.registry.read_text())["server_route_id"])

    def test_missing_primary_recovers_from_backup(self):
        server_route = pairing_state.server_route_id()
        paired = self._pair_client()
        self.registry.unlink()
        self._simulate_restart()

        recovered = pairing_state._read_state()

        self.assertEqual(server_route, recovered["server_route_id"])
        self.assertIn(paired["client_route_id"], recovered["clients"])
        self.assertTrue(self.registry.exists())

    def test_corrupt_registry_without_recovery_is_not_replaced(self):
        self.registry.write_text("{broken", encoding="utf-8")
        pairing_state._backup_path().write_text("{also-broken", encoding="utf-8")

        with self.assertRaises(pairing_state.PairingRegistryError):
            pairing_state._read_state()

        self.assertEqual("{broken", self.registry.read_text(encoding="utf-8"))

    def test_concurrent_updates_do_not_drop_clients_or_corrupt_json(self):
        pairing_state.server_route_id()
        routes = [new_route_id() for _ in range(32)]

        with ThreadPoolExecutor(max_workers=8) as executor:
            list(executor.map(self._pair_client, routes))

        self._simulate_restart()
        state = pairing_state._read_state()

        self.assertEqual(set(routes), set(state["clients"]))
        self.assertEqual(32, len(json.loads(self.registry.read_text())["clients"]))
        self.assertFalse(list(self.registry.parent.glob(f".{self.registry.name}.*.tmp")))


if __name__ == "__main__":
    unittest.main()
