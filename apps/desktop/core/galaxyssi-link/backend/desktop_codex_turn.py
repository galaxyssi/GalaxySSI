"""Desktop chat turns on the shared, prewarmed Codex app-server."""
from __future__ import annotations

import threading
import time
import uuid


def managed_chat_scope(task, conversation_id: str) -> bool:
    """Keep phone-native turns on their existing recovery/tool-aware adapter."""
    if task is None:
        return False
    route = str(getattr(task, "client_route_id", "") or "")
    if not route:
        return str(getattr(task, "source_message_id", "")).startswith("desktop:")
    valid_scope = (
        getattr(task, "agent_id", "") == "desktop"
        and bool(getattr(task, "source_message_id", ""))
        and bool(getattr(task, "client_conversation_id", ""))
        and bool(getattr(task, "client_turn_id", ""))
        and bool(conversation_id)
        and conversation_id == getattr(task, "conversation_id", "")
    )
    if not valid_scope:
        return False
    from pairing_access import has_full_executor
    from pairing_state import get_client
    return has_full_executor(get_client(route))


def native_chat_model(command: list[str]) -> str:
    """Only migrate the built-in exec profile; custom flags keep their semantics."""
    if len(command) < 2 or command[1] != "exec":
        return ""
    model = ""
    index = 2
    while index < len(command):
        value = command[index]
        if value in {"--skip-git-repo-check", "--ephemeral", "-"}:
            index += 1
        elif value in {"--model", "-m"} and index + 1 < len(command):
            model = command[index + 1]
            index += 2
        elif value == "-c" and index + 1 < len(command) and command[index + 1].startswith("model_reasoning_effort="):
            index += 2
        else:
            return ""
    return model


def run_chat_turn(*, server, register, unregister, prompt: str, fresh_prompt: str,
                  conversation_id: str, cwd: str, model: str, policy,
                  on_event, cancelled, timeout: float | None = None) -> str:
    # Unique attempt identity fences late provider notifications after cancellation.
    run_id = "desktop-chat-" + uuid.uuid4().hex
    completed = threading.Event()
    closed = threading.Event()
    terminal = {}
    started = time.monotonic()

    def receive(event_task_id, event):
        if closed.is_set() or event_task_id != run_id:
            return
        status = str(event.get("status") or "")
        if status in {"completed", "failed", "cancelled", "timed_out"}:
            terminal.update(event)
            completed.set()
        else:
            on_event(event)

    register(run_id, receive)
    try:
        if cancelled():
            raise RuntimeError("Desktop task cancelled before Codex dispatch")
        server.start_task(
            run_id, prompt, cwd, model=model,
            conversation_id="desktop-chat-v1:" + conversation_id if conversation_id else "",
            fresh_thread_prompt=fresh_prompt, execution_policy=policy,
        )
        on_event({"status": "running", "current_step": "Waiting for Codex response",
                  "desktop_stage": "model_started", "elapsed_ms": round((time.monotonic() - started) * 1000)})
        while True:
            if cancelled():
                server.interrupt(run_id)
                raise RuntimeError("Desktop task cancelled")
            if completed.wait(0.05):
                break
            if timeout is not None and time.monotonic() - started >= timeout:
                server.interrupt(run_id)
                raise TimeoutError("Codex turn timed out")
        if cancelled():
            raise RuntimeError("Desktop task cancelled")
        on_event({"status": "running", "current_step": "Codex generation completed; checking response",
                  "desktop_stage": "model_completed", "elapsed_ms": round((time.monotonic() - started) * 1000)})
        if terminal.get("status") != "completed":
            raise RuntimeError(str(terminal.get("error") or terminal.get("result") or terminal.get("status")))
        reply = str(terminal.get("result") or "").strip()
        if not reply:
            raise RuntimeError("Codex completed without a response")
        return reply
    finally:
        closed.set()
        unregister(run_id, receive)
