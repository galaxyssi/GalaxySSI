from __future__ import annotations

import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from fastapi import HTTPException
from pydantic import ValidationError
from starlette.requests import Request

from evolution_v2.api import (
    CampaignReq,
    IssueIngestReq,
    MaterializeReq,
    ResearchReq,
    RoadmapReq,
    SchedulerConfigReq,
    _runtime,
    scheduler_config,
    scheduler_tick,
)


def request_from(host: str) -> Request:
    return Request({
        "type": "http",
        "http_version": "1.1",
        "method": "GET",
        "scheme": "http",
        "path": "/api/evolution/v2/health",
        "raw_path": b"/api/evolution/v2/health",
        "query_string": b"",
        "headers": [],
        "client": (host, 49152),
        "server": ("127.0.0.1", 8765),
    })


class ApiBoundaryTests(unittest.TestCase):
    def test_materialize_defaults_to_automatic_agent_selection(self):
        self.assertEqual("auto", MaterializeReq().agent_id)

    def test_loopback_request_reaches_runtime(self):
        expected = object()
        with patch("evolution_v2.api.evolution_v2_runtime", return_value=expected):
            self.assertIs(expected, _runtime(request_from("127.0.0.1")))

    def test_non_loopback_request_is_rejected_before_runtime_creation(self):
        with patch("evolution_v2.api.evolution_v2_runtime") as runtime:
            with self.assertRaises(HTTPException) as raised:
                _runtime(request_from("203.0.113.8"))
        runtime.assert_not_called()
        self.assertEqual(403, raised.exception.status_code)
        self.assertEqual(
            "loopback_required",
            raised.exception.detail["error"]["code"],
        )

    def test_all_ipv4_and_ipv6_loopback_addresses_are_accepted(self):
        expected = object()
        with patch("evolution_v2.api.evolution_v2_runtime", return_value=expected):
            self.assertIs(expected, _runtime(request_from("127.0.0.2")))
            self.assertIs(expected, _runtime(request_from("::ffff:127.0.0.1")))

    def test_request_models_reject_oversized_or_unknown_input(self):
        invalid = (
            lambda: ResearchReq(limit=0),
            lambda: ResearchReq(query="x" * 1_001),
            lambda: RoadmapReq(goal=""),
            lambda: MaterializeReq(agent_id="../shell"),
            lambda: MaterializeReq(max_attempts=11),
            lambda: IssueIngestReq(text=""),
            lambda: CampaignReq(name="test", unexpected=True),
            lambda: SchedulerConfigReq(
                enabled=True,
                evolutions_per_day=0,
                execution_mode="serial",
                max_parallel_evolutions=2,
            ),
            lambda: SchedulerConfigReq(
                enabled=True,
                evolutions_per_day=24,
                execution_mode="automatic",
                max_parallel_evolutions=2,
            ),
            lambda: SchedulerConfigReq(
                enabled=True,
                evolutions_per_day=24,
                execution_mode="parallel",
                max_parallel_evolutions=5,
            ),
        )
        for build in invalid:
            with self.subTest(build=build):
                with self.assertRaises(ValidationError):
                    build()

    def test_scheduler_config_accepts_bounded_serial_and_parallel_modes(self):
        serial = SchedulerConfigReq(
            enabled=False,
            evolutions_per_day=1,
            execution_mode="serial",
            max_parallel_evolutions=2,
        )
        parallel = SchedulerConfigReq(
            enabled=True,
            evolutions_per_day=96,
            execution_mode="parallel",
            max_parallel_evolutions=4,
        )

        self.assertFalse(serial.enabled)
        self.assertEqual("parallel", parallel.execution_mode)

    def test_scheduler_config_is_forwarded_to_the_persistent_scheduler(self):
        scheduler = SimpleNamespace(update_config=Mock(return_value={"running": True}))
        runtime = SimpleNamespace(scheduler=scheduler)
        request = request_from("127.0.0.1")
        payload = SchedulerConfigReq(
            enabled=True,
            evolutions_per_day=24,
            execution_mode="parallel",
            max_parallel_evolutions=3,
        )

        with patch("evolution_v2.api._runtime", return_value=runtime):
            result = scheduler_config(request, payload)

        self.assertTrue(result["running"])
        scheduler.update_config.assert_called_once_with(payload.model_dump())

    def test_scheduler_tick_forwards_the_evolution_only_mode(self):
        scheduler = SimpleNamespace(run_due=Mock(return_value={"evolution": {"status": "started"}}))
        runtime = SimpleNamespace(scheduler=scheduler)

        with patch("evolution_v2.api._runtime", return_value=runtime):
            result = scheduler_tick(
                request_from("127.0.0.1"),
                force=False,
                evolution_only=True,
            )

        self.assertEqual("started", result["evolution"]["status"])
        scheduler.run_due.assert_called_once_with(
            force=False,
            evolution_only=True,
        )


if __name__ == "__main__":
    unittest.main()
