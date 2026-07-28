from __future__ import annotations

import unittest
from unittest.mock import patch

from fastapi import HTTPException
from pydantic import ValidationError
from starlette.requests import Request

from evolution_v2.api import (
    CampaignReq,
    IssueIngestReq,
    MaterializeReq,
    ResearchReq,
    RoadmapReq,
    _runtime,
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
        )
        for build in invalid:
            with self.subTest(build=build):
                with self.assertRaises(ValidationError):
                    build()


if __name__ == "__main__":
    unittest.main()
