from __future__ import annotations

import json
import threading
import unittest
from unittest.mock import Mock, patch

import mqtt_bridge


class ConnectorPresenceTest(unittest.TestCase):
    def setUp(self) -> None:
        with mqtt_bridge.connector_status_state_lock:
            mqtt_bridge.connector_status_fingerprints.clear()
            mqtt_bridge.connector_status_last_publish_at.clear()

    def tearDown(self) -> None:
        with mqtt_bridge.connector_status_state_lock:
            mqtt_bridge.connector_status_fingerprints.clear()
            mqtt_bridge.connector_status_last_publish_at.clear()

    def test_mobile_agent_status_uses_epoch_milliseconds(self) -> None:
        diagnostics = {
            "agents": [
                {
                    "id": "codex",
                    "mobile_contact_id": "codex",
                    "name": "Codex",
                    "kind": "codex",
                    "status": "ready",
                    "invocation_profile": {
                        "default_model": "gpt-5.6-sol",
                        "models": [{"id": "gpt-5.6-sol", "display_name": "gpt-5.6-sol"}],
                        "reasoning_efforts": ["low", "medium", "high", "xhigh"],
                    },
                }
            ]
        }
        with (
            patch.object(mqtt_bridge, "connector_diagnostics", return_value=diagnostics),
            patch.object(mqtt_bridge, "desktop_id", return_value="desktop-test"),
            patch.object(mqtt_bridge, "desktop_name", return_value="Test PC"),
            patch.object(mqtt_bridge, "get_signal_bundle", return_value={"identityKeySha256": "abc"}),
            patch.object(mqtt_bridge, "get_client", return_value=None),
        ):
            agents = mqtt_bridge.mobile_connector_agents("a" * 22)

        self.assertEqual(1, len(agents))
        self.assertGreater(agents[0]["updated_at"], 1_000_000_000_000)
        self.assertEqual(
            "gpt-5.6-sol",
            agents[0]["invocation_profile"]["default_model"],
        )
        self.assertIn("xhigh", agents[0]["invocation_profile"]["reasoning_efforts"])

    def test_compact_mobile_agent_status_omits_heavy_routing_metadata(self) -> None:
        diagnostics = {
            "agents": [
                {
                    "id": "codex",
                    "mobile_contact_id": "codex",
                    "name": "Codex",
                    "kind": "codex",
                    "status": "ready",
                    "adapter": {
                        "capabilities": ["code"] * 200,
                        "protocols": ["acp"] * 200,
                        "metadata": "x" * 20_000,
                    },
                }
            ],
            "provider_profiles": {
                "profiles": [{"resource_id": "codex", "metadata": "y" * 20_000}]
            },
        }
        with (
            patch.object(mqtt_bridge, "connector_diagnostics", return_value=diagnostics),
            patch.object(mqtt_bridge, "desktop_id", return_value="desktop-test"),
            patch.object(mqtt_bridge, "desktop_name", return_value="Test PC"),
            patch.object(mqtt_bridge, "get_signal_bundle", return_value={"identityKeySha256": "abc"}),
        ):
            agents = mqtt_bridge.mobile_connector_agents("", detailed=False)

        self.assertEqual(1, len(agents))
        self.assertNotIn("adapter", agents[0])
        self.assertNotIn("capabilities", agents[0])
        self.assertNotIn("provider_profile", agents[0])
        self.assertNotIn("reputation", agents[0])
        self.assertLess(len(json.dumps(agents).encode("utf-8")), 2_048)

    def test_reconnect_requires_explicit_full_manifest_request(self) -> None:
        self.assertFalse(mqtt_bridge._capability_manifest_requested({}))
        self.assertFalse(
            mqtt_bridge._capability_manifest_requested(
                {"capability_manifest_version": 1}
            )
        )
        self.assertTrue(
            mqtt_bridge._capability_manifest_requested(
                {"request_capability_manifest": True}
            )
        )

    def test_full_manifest_has_one_canonical_agent_collection(self) -> None:
        control = Mock()
        control.status.return_value = {
            "contract_version": "1",
            "desktop_surface_contract": "1",
            "enabled": False,
            "require_unlocked": False,
            "allowed_tools": [],
            "authorizations": [],
        }
        native = Mock()
        native.manifest.return_value = {"tools": []}
        handles = Mock()
        handles.status.return_value = {"contract": "1"}
        marketplace = Mock()
        marketplace.catalog.return_value = {"items": []}
        whisper = Mock()
        whisper.capability.return_value = {"available": False}
        with (
            patch.object(mqtt_bridge, "connector_diagnostics", return_value={"provider_profiles": {"profiles": []}}),
            patch.object(mqtt_bridge, "get_client", return_value=None),
            patch.object(mqtt_bridge, "client_grant", return_value={"profile": "restricted", "scopes": []}),
            patch.object(mqtt_bridge, "has_full_executor", return_value=False),
            patch.object(mqtt_bridge, "mobile_connector_agents", return_value=[{"id": "desktop-test:codex"}]),
            patch.object(mqtt_bridge, "desktop_id", return_value="desktop-test"),
            patch.object(mqtt_bridge, "desktop_name", return_value="Test PC"),
            patch("desktop_control.desktop_control_manager", return_value=control),
            patch("desktop_native_tools.desktop_native_tool_registry", return_value=native),
            patch("provider_profiles.routable_model_profiles", return_value=[]),
            patch("remote_whisper_node.remote_whisper_node", return_value=whisper),
            patch("tool_handle_registry.tool_handle_registry", return_value=handles),
            patch("tool_marketplace.tool_marketplace", return_value=marketplace),
        ):
            manifest = mqtt_bridge.capability_manifest("route")

        self.assertEqual(mqtt_bridge.CAPABILITY_MANIFEST_VERSION, manifest["manifest_version"])
        self.assertNotIn("agents", manifest)
        self.assertEqual([{"id": "desktop-test:codex"}], manifest["connector_agents"])

    def test_lightweight_status_refresh_runs_off_the_message_worker(self) -> None:
        published = threading.Event()

        def publish_status(*_args, **_kwargs):
            published.set()
            return {"ok": True}

        with (
            patch.object(mqtt_bridge, "publish_connector_status", side_effect=publish_status),
            patch.object(mqtt_bridge, "publish_capability_manifest") as publish_manifest,
        ):
            scheduled = mqtt_bridge._schedule_requested_connector_state(
                Mock(),
                "route-test",
                include_capability_manifest=False,
            )
            self.assertTrue(scheduled)
            self.assertTrue(published.wait(1.0))
            publish_manifest.assert_not_called()

    def test_status_fingerprint_ignores_delivery_timestamp(self) -> None:
        with (
            patch.object(mqtt_bridge, "desktop_id", return_value="desktop-test"),
            patch.object(mqtt_bridge, "desktop_name", return_value="Test PC"),
            patch.object(mqtt_bridge, "get_signal_bundle", return_value={"identityKeySha256": "abc"}),
        ):
            first = mqtt_bridge._connector_status_fingerprint(
                [{"id": "desktop-test:codex", "status": "ready", "updated_at": 1}]
            )
            second = mqtt_bridge._connector_status_fingerprint(
                [{"id": "desktop-test:codex", "status": "ready", "updated_at": 999_999}]
            )

        self.assertEqual(first, second)

    def test_status_is_published_only_after_change_or_four_hour_refresh(self) -> None:
        route_id = "route-test"
        ready = [{"id": "desktop-test:codex", "status": "ready", "updated_at": 1}]
        busy = [{"id": "desktop-test:codex", "status": "busy", "updated_at": 2}]
        agents = ready

        def current_agents(*_args, **_kwargs):
            return agents

        with (
            patch.object(mqtt_bridge, "list_clients", return_value=[{"client_route_id": route_id}]),
            patch.object(mqtt_bridge, "mobile_connector_agents", side_effect=current_agents),
            patch.object(mqtt_bridge, "desktop_id", return_value="desktop-test"),
            patch.object(mqtt_bridge, "desktop_name", return_value="Test PC"),
            patch.object(mqtt_bridge, "get_signal_bundle", return_value={"identityKeySha256": "abc"}),
        ):
            mqtt_bridge._record_connector_status_publish(route_id, ready, published_at=100.0)
            self.assertEqual([], mqtt_bridge._due_connector_status_publications(now=160.0))

            agents = busy
            self.assertEqual(
                [(route_id, "state_changed")],
                mqtt_bridge._due_connector_status_publications(now=161.0),
            )

            mqtt_bridge._record_connector_status_publish(route_id, busy, published_at=200.0)
            self.assertEqual(
                [(route_id, "periodic_refresh")],
                mqtt_bridge._due_connector_status_publications(
                    now=200.0 + mqtt_bridge.CONNECTOR_STATUS_REFRESH_SECONDS
                ),
            )


if __name__ == "__main__":
    unittest.main()
