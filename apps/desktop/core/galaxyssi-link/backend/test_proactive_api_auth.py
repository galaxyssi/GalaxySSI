import os
import unittest
from unittest.mock import patch

from fastapi import HTTPException
from starlette.requests import Request

import main


def request_for(host: str, token: str = "") -> Request:
    headers = []
    if token:
        headers.append((b"x-galaxyssi-token", token.encode("ascii")))
    return Request(
        {
            "type": "http",
            "client": (host, 43210),
            "headers": headers,
        }
    )


class ProactiveApiAuthorizationTests(unittest.TestCase):
    def test_loopback_request_requires_matching_process_token(self):
        with patch.dict(
            os.environ,
            {"GALAXYSSI_DESKTOP_TASK_STREAM_TOKEN": "desktop-process-token"},
        ):
            main.require_desktop_api_token(
                request_for("127.0.0.1", "desktop-process-token")
            )
            with self.assertRaises(HTTPException) as captured:
                main.require_desktop_api_token(request_for("127.0.0.1"))

        self.assertEqual(401, captured.exception.status_code)

    def test_remote_request_is_rejected_even_with_token(self):
        with patch.dict(
            os.environ,
            {"GALAXYSSI_DESKTOP_TASK_STREAM_TOKEN": "desktop-process-token"},
        ):
            with self.assertRaises(HTTPException) as captured:
                main.require_desktop_api_token(
                    request_for("192.0.2.10", "desktop-process-token")
                )

        self.assertEqual(403, captured.exception.status_code)


if __name__ == "__main__":
    unittest.main()
