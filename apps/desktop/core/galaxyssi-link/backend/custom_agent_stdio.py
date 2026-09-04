"""Minimal Custom Agent example for GalaxySSI Desktop.

Use this command in Desktop:

    python custom_agent_stdio.py -

GalaxySSI passes the phone message through stdin when the command ends with
``-``. Replace this file with your own logic, or use it as a smoke-testable
starting point for shell scripts and local tools.
"""
from __future__ import annotations

import os
import json
import sys


def read_prompt() -> str:
    args = sys.argv[1:]
    if not args or args[-1] == "-":
        return sys.stdin.read().strip()
    return " ".join(args).strip()


def _reply(prompt: str) -> str:
    name = os.environ.get("GALAXYSSI_CUSTOM_AGENT_NAME", "Custom Agent").strip() or "Custom Agent"
    if not prompt:
        return f"[{name}] Ready. Send me a message from GalaxySSI."
    return f"[{name}] Request received. Custom Agent is connected."


def serve_jsonl() -> int:
    """Serve GalaxySSI's persistent CLI protocol without closing stdin."""
    for line in sys.stdin:
        value = line.strip()
        if not value:
            continue
        try:
            request = json.loads(value)
        except json.JSONDecodeError:
            continue
        if not isinstance(request, dict):
            continue
        request_id = str(request.get("id") or "")
        method = str(request.get("method") or "")
        if method == "agent/shutdown":
            print(json.dumps({"id": request_id, "result": {"stopped": True}}), flush=True)
            return 0
        if method != "agent/run":
            print(json.dumps({
                "id": request_id,
                "error": {"code": "method_not_found", "message": f"Unsupported method: {method}"},
            }), flush=True)
            continue
        params = request.get("params") if isinstance(request.get("params"), dict) else {}
        prompt = str(params.get("prompt") or "")
        print(json.dumps({
            "protocol": "galaxyssi.agent-cli/1.0",
            "id": request_id,
            "result": {"reply": _reply(prompt)},
        }), flush=True)
    return 0


def main() -> int:
    if "--serve-jsonl" in sys.argv[1:]:
        return serve_jsonl()
    prompt = read_prompt()
    print(_reply(prompt))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
