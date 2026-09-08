"""Tool-free planning inference confined to a literal loopback connection."""
from __future__ import annotations

import http.client
import ipaddress
import json
from urllib.parse import urlsplit

from .local_planning_stream import PlanningStreamError, RESPONSE_LIMIT, read_decision_stream


class LocalPlannerUnavailable(RuntimeError):
    pass


class LocalPlannerContextExceeded(LocalPlannerUnavailable):
    def __init__(self, requested_tokens=None, context_tokens=None):
        self.requested_tokens = requested_tokens if type(requested_tokens) is int and requested_tokens > 0 else None
        self.context_tokens = context_tokens if type(context_tokens) is int and context_tokens > 0 else None
        super().__init__("Local planning context window exceeded; retain the goal and latest observation while compacting older history")


def response_error(response):
    if response.status in {400, 413}:
        try:
            body = response.read(65537)
            if len(body) > 65536:
                return LocalPlannerUnavailable(f"Local planning endpoint returned HTTP {response.status}")
            payload = json.loads(body)
            error = payload.get("error") if isinstance(payload, dict) else None
            if isinstance(error, dict) and (error.get("type") == "exceed_context_size_error"
                    or error.get("code") == "context_length_exceeded"):
                return LocalPlannerContextExceeded(error.get("n_prompt_tokens"), error.get("n_ctx"))
        except (ValueError, TypeError):
            pass
    return LocalPlannerUnavailable(f"Local planning endpoint returned HTTP {response.status}")


def messages_with_response_schema(messages, schema):
    if schema is None:
        return messages
    instruction = ("\n\nReturn a JSON value matching the following response schema. "
                   "This schema defines response structure, not additional task requirements.\n"
                   + json.dumps(schema, ensure_ascii=False, separators=(",", ":")))
    # Grammar-constrained decoding does not make the schema visible to the model.
    result = [dict(message) for message in messages]
    for message in result:
        if message.get("role") == "system" and isinstance(message.get("content"), str):
            message["content"] += instruction
            break
    else:
        result.insert(0, {"role": "system", "content": instruction.lstrip()})
    return result


def local_plan_endpoint(config=None):
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
    return config, url, host, path


def infer_local_plan(messages: list[dict], *, config=None, response_schema=None) -> str:
    config, url, host, path = local_plan_endpoint(config)
    request = {"model": config["model"], "messages": messages_with_response_schema(messages, response_schema), "stream": True}
    if response_schema is not None:
        request["response_format"] = {"type": "json_schema", "json_schema": {
            "name": "local_file_action", "schema": response_schema}}
    payload = json.dumps(request, ensure_ascii=False).encode("utf-8")
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
            raise response_error(response)
        if response.getheader("Content-Type", "").split(";", 1)[0].strip().lower() == "text/event-stream":
            return read_decision_stream(response)
        body = response.read(RESPONSE_LIMIT + 1)
        if len(body) > RESPONSE_LIMIT:
            raise LocalPlannerUnavailable("Local planning response exceeded the response envelope")
        data = json.loads(body)
        message = data["choices"][0]["message"]
        if message.get("tool_calls") or message.get("function_call") or not isinstance(message.get("content"), str):
            raise LocalPlannerUnavailable("Local planner did not return a tool-free decision")
        return message["content"]
    except PlanningStreamError as error:
        raise LocalPlannerUnavailable(str(error)) from error
    except (OSError, http.client.HTTPException) as error:
        raise LocalPlannerUnavailable("Local planning endpoint is unavailable") from error
    finally:
        connection.close()
