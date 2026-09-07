"""Tool-free planning inference confined to a literal loopback connection."""
from __future__ import annotations

import http.client
import ipaddress
import json
from urllib.parse import urlsplit


class LocalPlannerUnavailable(RuntimeError):
    pass


def infer_local_plan(messages: list[dict], *, config=None) -> str:
    if config is None:
        from agent_config import local_model_config
        config = local_model_config()
    url = urlsplit(config.get("url") or "")
    host = "127.0.0.1" if url.hostname == "localhost" else url.hostname
    try:
        local = ipaddress.ip_address(host or "").is_loopback
    except ValueError:
        local = False
    if (not local or url.scheme not in {"http", "https"} or url.username or url.password
            or url.query or url.fragment or not config.get("model")):
        raise LocalPlannerUnavailable("Configure a loopback local model for private campaign planning")
    path = url.path.rstrip("/")
    if path.endswith(("/api/generate", "/api/chat")):
        path = path.rsplit("/api/", 1)[0] + "/v1/chat/completions"
    if not path.endswith("/chat/completions"):
        raise LocalPlannerUnavailable("Local planner requires a chat-completions endpoint")
    payload = json.dumps({"model": config["model"], "messages": messages, "stream": False},
                         ensure_ascii=False).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if config.get("api_key"):
        headers["Authorization"] = "Bearer " + config["api_key"]
    # Direct sockets bypass proxy environment variables and never follow redirects.
    connection_type = http.client.HTTPSConnection if url.scheme == "https" else http.client.HTTPConnection
    connection = connection_type(host, url.port, timeout=60)
    try:
        connection.request("POST", path, body=payload, headers=headers)
        response = connection.getresponse()
        if response.status != 200:
            raise LocalPlannerUnavailable(f"Local planning endpoint returned HTTP {response.status}")
        body = response.read(2 * 1024 * 1024 + 1)
        if len(body) > 2 * 1024 * 1024:
            raise LocalPlannerUnavailable("Local planning response exceeded the response envelope")
        data = json.loads(body)
        message = data["choices"][0]["message"]
        if message.get("tool_calls") or not isinstance(message.get("content"), str):
            raise LocalPlannerUnavailable("Local planner did not return a tool-free decision")
        return message["content"]
    except (OSError, http.client.HTTPException) as error:
        raise LocalPlannerUnavailable("Local planning endpoint is unavailable") from error
    finally:
        connection.close()
