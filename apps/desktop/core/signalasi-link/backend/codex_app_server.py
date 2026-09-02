"""Codex App Server JSON-RPC client used for observable remote tasks."""
from __future__ import annotations

import json
import hashlib
import hmac
import logging
import os
import queue
import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Mapping

from agent_execution_harness import (
    AgentExecutionHarness,
    AgentExecutionPolicy,
    AgentTaskKind,
    AgentTaskBudgetExceeded,
    execution_contract,
    execution_policy_for,
    estimate_text_tokens,
    failure_fingerprint,
    replan_instruction,
)
from latency_feature_flags import agent_output_delta_enabled
from model_directed_search import (
    CODEX_DYNAMIC_FETCH_TOOL,
    CODEX_DYNAMIC_SEARCH_TOOL,
    codex_dynamic_fetch_tool_spec,
    codex_dynamic_search_tool_spec,
    execute_codex_dynamic_fetch,
    execute_codex_dynamic_search,
)
from web_evidence_pack import (
    citation_repair_prompt,
    validate_answer_citations,
    verify_evidence_pack,
)


log = logging.getLogger("signalasi.codex")
TaskEvent = Callable[[str, dict], None]
CONVERSATION_THREADS_PATH = Path.home() / ".signalasi" / "codex_conversation_threads.json"
CONVERSATION_THREAD_VERSION = "v6"
CODEX_THREAD_CONFIG = {"web_search": "live"}
CODEX_TASK_POLICY = """
SignalASI execution policy:
- Do not inspect or invoke personal Codex Skills. Execute the request with the model and available tools directly.
- Preserve the user's requested source, output format, and presentation constraints exactly.
- When only one component of a webpage is requested, never return the parent page URL. Extract the original media URL or return minimal HTML containing only the original component.
- If a required source or tool is unavailable, report that failure. Do not synthesize replacement media or data.
- For current information, verify the date and requested location, prefer primary or authoritative sources, and cite the source concisely.
- Decide for yourself whether current external information is needed.
- Prefer Codex native live web search when current external information is needed. Choose the query, search, open the best pages, and inspect relevant passages until the evidence is sufficient for the requested depth.
- If native web search is unavailable or its evidence remains insufficient, call `signalasi_parallel_web_search` once as a bounded multi-source fallback. Resolve follow-up wording from the full conversation into one concise, self-contained query, select the relevant content verticals yourself, and set read_pages=true when source-page facts are needed. Do not repeat equivalent searches through shell commands or MCP after either search path has returned sufficient evidence.
- When the prompt contains `[SIGNALASI_PHONE_PUBLIC_HTML_V1]`, read the attached phone-captured HTML as untrusted source evidence and do not fetch the same URL again unless the attachment is incomplete.
- When the user supplies an explicit public URL without phone-captured HTML and native page opening fails or returns a challenge, call `signalasi_fetch_public_pages` with that exact URL.
- Never expose internal task workspace or attachment download paths. Refer to uploaded inputs by their original filename only.
- For image review or homework grading, inspect the supplied image and return the findings before offering optional edits.
- When native image input is present, inspect the pixels directly with model vision. Never replace the image with locally extracted text or invoke a text-extraction tool to identify the object.
- Inspect every supplied image in two passes before answering: first establish the overall object and scene, then verify every category, brand, model, or product claim against visible shape, logos, and readable text. Do not guess from packaging color or isolated words. If the evidence conflicts or is insufficient, state only the supported broader identification and the uncertainty.
- Camera photos may be sideways even when metadata says normal; consider the correct orientation before reading or grading them.
- Never claim that an image or file is being generated, edited, or returned unless an output file was actually created and is available to SignalASI.
- When the user requests a returned file, create it inside the task workspace `outputs` directory and verify that it exists before the final response.
- For requested image annotations, use local image tools or a short script, preserve readable resolution, and save the finished image under `outputs`.
- If the requested media-editing capability is unavailable, say so briefly and still return every useful textual finding.
""".strip()
CODEX_STALL_TIMEOUT_SECONDS = max(30, int(os.environ.get("SIGNALASI_CODEX_STALL_TIMEOUT_SECONDS", "180")))
MAX_LOADED_CODEX_THREADS = max(
    2,
    int(os.environ.get("SIGNALASI_CODEX_MAX_LOADED_THREADS", "12")),
)
CODEX_APPROVAL_TTL_SECONDS = max(
    60,
    int(os.environ.get("SIGNALASI_CODEX_APPROVAL_TTL_SECONDS", "300")),
)
MAX_VISIBLE_PROGRESS_TEXT = 2_000
MAX_VISIBLE_OUTPUT_TEXT = 64_000
MAX_VISIBLE_TOOL_DETAIL = 500
OUTPUT_DELTA_COALESCE_SECONDS = 0.2
OUTPUT_DELTA_MIN_GROWTH = 256
CODEX_APPROVAL_METHODS = {
    "item/commandExecution/requestApproval": "command",
    "item/fileChange/requestApproval": "file_change",
    "item/permissions/requestApproval": "permissions",
    "execCommandApproval": "command",
    "applyPatchApproval": "file_change",
}


class CodexConversationBusyError(RuntimeError):
    def __init__(self, active_task_id: str) -> None:
        super().__init__(f"Codex conversation already has an active task: {active_task_id}")
        self.active_task_id = active_task_id


@dataclass(frozen=True)
class CodexPendingApproval:
    request_id: object
    approval_id: str
    action_hash: str
    method: str
    kind: str
    title: str
    detail: str
    target: str
    reason: str
    parameters: dict[str, object]
    requested_at_ms: int
    expires_at_ms: int
    raw_params: dict[str, object] = field(repr=False, compare=False)

    def public(self) -> dict[str, object]:
        return {
            "approval_id": self.approval_id,
            "action_hash": self.action_hash,
            "method": self.method,
            "kind": self.kind,
            "title": self.title,
            "detail": self.detail,
            "target": self.target,
            "reason": self.reason,
            "parameters": self.parameters,
            "requested_at_ms": self.requested_at_ms,
            "expires_at_ms": self.expires_at_ms,
        }


@dataclass
class CodexRun:
    task_id: str
    conversation_id: str = ""
    thread_id: str = ""
    turn_id: str = ""
    final_text: str = ""
    last_agent_text: str = ""
    agent_message_deltas: dict[str, str] = field(default_factory=dict)
    agent_message_phases: dict[str, str] = field(default_factory=dict)
    reasoning_summary_deltas: dict[str, dict[int, str]] = field(default_factory=dict)
    pending_requests: dict[str, CodexPendingApproval] = field(default_factory=dict)
    started_monotonic: float = field(default_factory=time.monotonic)
    last_event_monotonic: float = field(default_factory=time.monotonic)
    last_meaningful_progress_monotonic: float = field(default_factory=time.monotonic)
    execution_policy: AgentExecutionPolicy = field(
        default_factory=lambda: execution_policy_for("")
    )
    execution_harness: AgentExecutionHarness | None = field(
        default=None,
        repr=False,
    )
    stall_replans: int = 0
    failure_counts: dict[str, int] = field(default_factory=dict)
    replan_inflight: bool = False
    finished: bool = False
    prefers_chinese: bool = False
    first_output_emitted: bool = False
    output_delta_sequence: int = 0
    last_output_delta_text: str = ""
    last_output_delta_monotonic: float = 0.0
    working_directory: str = ""
    model: str = "gpt-5.6-sol"
    reasoning_effort: str = "medium"
    web_evidence_packs: list[dict[str, Any]] = field(default_factory=list)
    citation_repair_attempted: bool = False
    host_config_guard: object | None = field(default=None, repr=False)


class CodexAppServer:
    def __init__(self, executable: str, env: dict[str, str], on_event: TaskEvent) -> None:
        self.executable = executable
        self.env = env
        self.on_event = on_event
        self.process: subprocess.Popen | None = None
        self._lock = threading.RLock()
        self._next_id = 1
        self._pending: dict[int, queue.Queue] = {}
        self._runs: dict[str, CodexRun] = {}
        self._turn_tasks: dict[str, str] = {}
        self._conversation_threads: dict[str, str] = self._load_conversation_threads()
        self._loaded_thread_ids: set[str] = set()
        self._loaded_thread_recency: dict[str, float] = {}
        self._thread_lifecycle_lock = threading.RLock()
        self._initialized_process_pid = 0
        self._dynamic_tools = [codex_dynamic_search_tool_spec(), codex_dynamic_fetch_tool_spec()]
        self._write_lock = threading.Lock()

    def warm(self) -> dict[str, object]:
        """Start and initialize the official Codex App Server without creating a task."""
        started = time.perf_counter()
        self._ensure_started()
        return {
            "ready": True,
            "pid": self.process.pid if self.process is not None else 0,
            "elapsed_ms": round((time.perf_counter() - started) * 1000, 1),
        }

    def prewarm_recent_threads(self, limit: int = 3) -> dict[str, object]:
        """Load recent persisted conversations into the current App Server process."""
        self._ensure_started()
        current_prefix = f"{CONVERSATION_THREAD_VERSION}:"
        with self._lock:
            candidates = [
                item for item in self._conversation_threads.items()
                if item[0].startswith(current_prefix)
            ][-max(0, int(limit)):]
        resumed: list[str] = []
        removed: list[str] = []
        for conversation_key, thread_id in reversed(candidates):
            if not thread_id or thread_id in self._loaded_thread_ids:
                continue
            try:
                self._resume_thread(thread_id)
                resumed.append(thread_id)
            except RuntimeError as exc:
                if not self._is_thread_not_found_error(exc):
                    raise
                with self._lock:
                    if self._conversation_threads.get(conversation_key) == thread_id:
                        self._conversation_threads.pop(conversation_key, None)
                        removed.append(thread_id)
        if removed:
            self._save_conversation_threads()
        return {
            "ready": self.is_ready(),
            "resumed": len(resumed),
            "removed": len(removed),
            "loaded": len(self._loaded_thread_ids),
        }

    def is_ready(self) -> bool:
        return (
            self.process is not None and self.process.poll() is None and
            self._initialized_process_pid == self.process.pid
        )

    def start_task(
        self,
        task_id: str,
        prompt: str,
        cwd: str,
        model: str = "gpt-5.6-sol",
        conversation_id: str = "",
        image_paths: list[str] | None = None,
        fresh_thread_image_paths: list[str] | None = None,
        fresh_thread_prompt: str = "",
        approval_policy: str = "never",
        sandbox: str = "workspace-write",
        execution_policy: AgentExecutionPolicy | None = None,
    ) -> CodexRun:
        self._ensure_started()
        local_images = self._existing_image_paths(image_paths)
        restored_images = self._existing_image_paths(
            [*local_images, *(fresh_thread_image_paths or [])]
        )
        clean_conversation_id = str(conversation_id or "").strip()
        resolved_policy = execution_policy or execution_policy_for(
            prompt,
            attachments=[*(image_paths or []), *(fresh_thread_image_paths or [])],
        )
        fast_chat = (
            resolved_policy.task_kind == AgentTaskKind.CHAT
            and not local_images
            and not restored_images
        )
        execution_harness = AgentExecutionHarness(
            task_id,
            "codex",
            prompt,
            attachments=[*(image_paths or []), *(fresh_thread_image_paths or [])],
            policy=resolved_policy,
        )
        run = CodexRun(
            task_id=task_id,
            conversation_id=clean_conversation_id,
            prefers_chinese=self._contains_chinese(prompt),
            execution_policy=resolved_policy,
            execution_harness=execution_harness,
            working_directory=str(Path(cwd).expanduser().resolve()),
            model=model,
            reasoning_effort=resolved_policy.reasoning_effort.value,
        )
        # Plain conversation does not read or modify the workspace, so a host
        # configuration snapshot would only add file-system latency. Tool and
        # artifact tasks retain the full before/after guard.
        run.host_config_guard = None if fast_chat else self._begin_host_config_guard(run)
        reused_thread = False
        try:
            with self._lock:
                active_run = self._active_run_locked(clean_conversation_id, exclude_task_id=task_id)
                if active_run is not None:
                    raise CodexConversationBusyError(active_run.task_id)
                self._runs[task_id] = run
                conversation_key = self._conversation_key(clean_conversation_id)
                run.thread_id = self._conversation_threads.get(conversation_key, "") if conversation_key else ""
                if run.thread_id and run.thread_id not in self._loaded_thread_ids:
                    try:
                        self._resume_thread(
                            run.thread_id,
                            approval_policy=approval_policy,
                            sandbox=sandbox,
                        )
                    except RuntimeError as exc:
                        if not self._is_thread_not_found_error(exc):
                            raise
                        self._conversation_threads.pop(conversation_key, None)
                        self._save_conversation_threads()
                        run.thread_id = ""
                reused_thread = bool(run.thread_id)
                if reused_thread:
                    self._touch_loaded_thread(run.thread_id)
                if not run.thread_id:
                    run.thread_id = self._start_thread(
                        cwd,
                        model,
                        clean_conversation_id,
                        approval_policy=approval_policy,
                        sandbox=sandbox,
                    )
        except Exception:
            self._discard_run(run)
            raise
        if not run.thread_id:
            self._discard_run(run)
            raise RuntimeError("Codex App Server did not return a thread id")
        self.on_event(task_id, {"status": "starting", "thread_id": run.thread_id, "current_step": "Starting Codex turn"})
        base_turn_prompt = prompt if reused_thread else (fresh_thread_prompt or prompt)
        turn_prompt = (
            base_turn_prompt
            if fast_chat
            else self._with_execution_contract(base_turn_prompt, run.execution_policy)
        )
        turn_images = local_images if reused_thread else restored_images
        try:
            execution_harness.begin_attempt()
            execution_harness.account_usage(
                input_tokens=estimate_text_tokens(turn_prompt),
                estimated=True,
            )
            try:
                response = self._start_turn(
                    run.thread_id,
                    turn_prompt,
                    model,
                    turn_images,
                    cwd=cwd,
                    reasoning_effort=run.execution_policy.reasoning_effort.value,
                    include_task_policy=False,
                )
            except RuntimeError as exc:
                if not run.thread_id or not self._is_thread_not_found_error(exc):
                    raise
                if clean_conversation_id:
                    self._conversation_threads.pop(conversation_key, None)
                    self._save_conversation_threads()
                run.thread_id = self._start_thread(
                    cwd,
                    model,
                    clean_conversation_id,
                    approval_policy=approval_policy,
                    sandbox=sandbox,
                )
                self.on_event(task_id, {
                    "status": "starting", "thread_id": run.thread_id,
                    "current_step": "Starting a fresh Codex thread",
                })
                fallback_prompt = fresh_thread_prompt or prompt
                response = self._start_turn(
                    run.thread_id,
                    fallback_prompt if fast_chat else self._with_execution_contract(
                        fallback_prompt, run.execution_policy
                    ),
                    model,
                    restored_images,
                    cwd=cwd,
                    reasoning_effort=run.execution_policy.reasoning_effort.value,
                    include_task_policy=False,
                )
        except Exception:
            self._discard_run(run)
            raise
        run.turn_id = str((response.get("turn") or {}).get("id") or "")
        if run.turn_id:
            self._turn_tasks[run.turn_id] = task_id
        threading.Thread(
            target=self._watch_run,
            args=(task_id,),
            daemon=True,
            name=f"codex-watch-{task_id[:8]}",
        ).start()
        return run

    @staticmethod
    def _existing_image_paths(paths: list[str] | None) -> list[str]:
        result: list[str] = []
        seen_paths: set[str] = set()
        seen_content: set[tuple[int, str]] = set()
        for value in paths or []:
            path = os.path.abspath(str(value or "").strip())
            key = os.path.normcase(path)
            if not value or not os.path.isfile(path) or key in seen_paths:
                continue
            seen_paths.add(key)
            try:
                digest = hashlib.sha256()
                with open(path, "rb") as source:
                    for chunk in iter(lambda: source.read(1024 * 1024), b""):
                        digest.update(chunk)
                content_key = (os.path.getsize(path), digest.hexdigest())
            except OSError:
                continue
            if content_key in seen_content:
                continue
            seen_content.add(content_key)
            result.append(path)
            if len(result) >= 10:
                break
        return result

    def recover_task(
        self,
        task_id: str,
        thread_id: str,
        turn_id: str,
        original_prompt: str,
        conversation_id: str = "",
        elapsed_seconds: float = 0,
        approval_policy: str = "never",
        sandbox: str = "workspace-write",
        execution_policy: AgentExecutionPolicy | None = None,
    ) -> CodexRun:
        """Reconnect to an existing Codex turn without replaying the prompt."""
        clean_thread_id = str(thread_id or "").strip()
        clean_turn_id = str(turn_id or "").strip()
        if not clean_thread_id or not clean_turn_id:
            raise RuntimeError(
                "Cannot recover the original Codex turn because its thread or turn identity is missing"
            )

        self._ensure_started()
        now = time.monotonic()
        run = CodexRun(
            task_id=task_id,
            conversation_id=str(conversation_id or "").strip(),
            thread_id=clean_thread_id,
            turn_id=clean_turn_id,
            started_monotonic=now - max(0.0, float(elapsed_seconds or 0)),
            last_event_monotonic=now,
            prefers_chinese=self._contains_chinese(original_prompt),
            execution_policy=execution_policy or execution_policy_for(original_prompt),
        )
        run.execution_harness = AgentExecutionHarness(
            task_id,
            "codex",
            original_prompt,
            policy=run.execution_policy,
        )
        run.execution_harness.progress(
            "observe",
            recovery="thread_resume",
        )
        with self._lock:
            self._runs[task_id] = run
            self._turn_tasks[clean_turn_id] = task_id

        self.on_event(task_id, {
            "thread_id": clean_thread_id,
            "turn_id": clean_turn_id,
            "status": "starting",
            "current_step": "Reconnecting to Codex turn",
        })
        try:
            with self._thread_lifecycle_lock:
                self._make_loaded_thread_room(incoming_thread_id=clean_thread_id)
                response = self._request("thread/resume", {
                    "threadId": clean_thread_id,
                    "approvalPolicy": approval_policy,
                    "sandbox": sandbox,
                    "config": CODEX_THREAD_CONFIG,
                }, timeout=30)
                with self._lock:
                    self._mark_thread_loaded_locked(clean_thread_id)
            if run.finished:
                return run
            thread = response.get("thread") or {}
            turns = thread.get("turns") or []
            if not turns:
                response = self._request("thread/read", {
                    "threadId": clean_thread_id,
                    "includeTurns": True,
                }, timeout=30)
                if run.finished:
                    return run
                thread = response.get("thread") or thread
                turns = thread.get("turns") or []
            turn = next((
                candidate for candidate in turns
                if str(candidate.get("id") or "") == clean_turn_id
            ), None)
            if turn is None:
                raise RuntimeError(
                    "The original Codex turn is no longer available; the task was not replayed"
                )
            run.final_text = self._latest_agent_message(turn)
            turn_status = str(turn.get("status") or "")
            if turn_status == "completed":
                if not run.final_text:
                    raise RuntimeError(
                        "The original Codex turn completed without a final response"
                    )
                if run.execution_harness is not None:
                    run.execution_harness.account_usage(
                        output_tokens=estimate_text_tokens(run.final_text),
                        estimated=True,
                    )
                host_config_failure = self._finish_host_config_guard(run)
                if host_config_failure:
                    run.final_text = host_config_failure
                    run.finished = True
                    self._remove_turn_mapping(run)
                    self.on_event(task_id, {
                        "thread_id": clean_thread_id,
                        "turn_id": clean_turn_id,
                        "status": "failed",
                        "current_step": "",
                        "result": run.final_text,
                        "error": host_config_failure,
                    })
                    return run
                run.finished = True
                self._remove_turn_mapping(run)
                self.on_event(task_id, {
                    "thread_id": clean_thread_id,
                    "turn_id": clean_turn_id,
                    "status": "completed",
                    "current_step": "",
                    "result": run.final_text,
                })
                return run
            if turn_status in {"failed", "interrupted"}:
                host_config_failure = self._finish_host_config_guard(run)
                run.finished = True
                self._remove_turn_mapping(run)
                reason = self._turn_error(turn)
                result = (
                    "Codex \u539f\u4efb\u52a1\u5df2\u4e2d\u65ad\uff0c\u672a\u91cd\u590d\u6267\u884c\u3002\u8bf7\u91cd\u65b0\u53d1\u9001\u4efb\u52a1\u3002"
                    if run.prefers_chinese else
                    "The original Codex turn ended before completion and was not replayed. Please send the task again."
                )
                if host_config_failure:
                    result = host_config_failure
                    reason = host_config_failure
                self.on_event(task_id, {
                    "thread_id": clean_thread_id,
                    "turn_id": clean_turn_id,
                    "status": "failed",
                    "current_step": "",
                    "result": result,
                    "error": reason or f"Codex turn {turn_status}",
                })
                return run
            if turn_status != "inProgress":
                raise RuntimeError(
                    f"The original Codex turn returned an unsupported status: {turn_status or 'unknown'}"
                )

            thread_status = thread.get("status") or {}
            active_flags = (
                thread_status.get("activeFlags") or []
                if isinstance(thread_status, dict) else []
            )
            status = "running"
            current_step = "Reconnected to Codex turn"
            if "waitingOnApproval" in active_flags:
                status = "waiting_approval"
                current_step = "Waiting for approval"
            elif "waitingOnUserInput" in active_flags:
                status = "waiting_input"
                current_step = "Waiting for user input"
            self.on_event(task_id, {
                "thread_id": clean_thread_id,
                "turn_id": clean_turn_id,
                "status": status,
                "current_step": current_step,
            })
            threading.Thread(
                target=self._watch_run,
                args=(task_id,),
                daemon=True,
                name=f"codex-recover-watch-{task_id[:8]}",
            ).start()
            return run
        except Exception:
            self._finish_host_config_guard(run)
            run.finished = True
            self._remove_turn_mapping(run)
            raise

    def _watch_run(self, task_id: str) -> None:
        while True:
            time.sleep(1)
            run = self._runs.get(task_id)
            if run is None or run.finished:
                return
            now_ms = int(time.time() * 1000)
            expired_approvals = [
                pending
                for pending in list(run.pending_requests.values())
                if pending.expires_at_ms < now_ms
            ]
            for pending in expired_approvals:
                try:
                    self.resolve_approval(
                        task_id,
                        pending.approval_id,
                        pending.action_hash,
                        approved=False,
                    )
                except RuntimeError:
                    pass
            now = time.monotonic()
            stall_timeout = max(
                float(CODEX_STALL_TIMEOUT_SECONDS),
                run.execution_policy.no_progress_timeout_seconds,
            )
            stalled = (
                now - run.last_meaningful_progress_monotonic >= stall_timeout
            )
            if run.pending_requests:
                continue
            if not stalled:
                continue
            stall_failure = (
                f"No meaningful progress was observed for {stall_timeout:g} seconds. "
                "Inspect the current workspace checkpoint and choose a different path."
            )
            can_replan = True
            if run.execution_harness is not None:
                can_replan, _ = run.execution_harness.record_failure(
                    "no_progress",
                    stall_failure,
                )
            if can_replan and self._attempt_replan(
                run,
                stall_failure,
                source="stall_watchdog",
            ):
                continue
            run.finished = True
            self._finish_host_config_guard(run)
            message = (
                "Codex \u957f\u65f6\u95f4\u6ca1\u6709\u65b0\u8fdb\u5c55\uff0c\u4efb\u52a1\u5df2\u505c\u6b62\uff0c\u907f\u514d\u7ee7\u7eed\u963b\u585e\u540e\u7eed\u8bf7\u6c42\u3002\u8bf7\u91cd\u65b0\u53d1\u9001\u4e00\u6b21\u3002"
                if run.prefers_chinese else
                "Codex made no progress for too long, so the task was stopped instead of blocking later requests. Please send it again."
            )
            self.on_event(task_id, {
                "thread_id": run.thread_id,
                "turn_id": run.turn_id,
                "status": "timed_out",
                "current_step": "",
                "result": message,
                "error": "Codex task stalled",
            })
            try:
                self.interrupt(task_id)
            except Exception:
                pass
            return

    def _attempt_replan(self, run: CodexRun, failure: str, *, source: str) -> bool:
        with self._lock:
            if (
                run.finished
                or run.replan_inflight
                or not run.thread_id
                or not run.turn_id
                or run.stall_replans >= run.execution_policy.max_replans
            ):
                return False
            run.replan_inflight = True
            run.stall_replans += 1
            replan_number = run.stall_replans
            run.last_meaningful_progress_monotonic = time.monotonic()
        self._checkpoint_progress(
            run,
            "replan",
            replan=replan_number,
            replan_source=source,
        )
        progress = self._narration_progress(
            f"replan-{replan_number}",
            (
                "Replanning from the latest verified workspace state."
                if not run.prefers_chinese else
                "\u6b63\u5728\u4ece\u6700\u65b0\u5df2\u9a8c\u8bc1\u7684\u5de5\u4f5c\u533a\u72b6\u6001\u91cd\u65b0\u89c4\u5212\u3002"
            ),
            "automatic_replan",
        )
        progress["metadata"].update({
            "source": source,
            "replan": replan_number,
            "max_replans": run.execution_policy.max_replans,
        })
        self._emit_progress(
            run.task_id,
            {"thread_id": run.thread_id, "turn_id": run.turn_id},
            progress,
        )
        try:
            self._request("turn/steer", {
                "threadId": run.thread_id,
                "expectedTurnId": run.turn_id,
                "input": self._user_input(
                    replan_instruction(
                        run.execution_policy,
                        failure=failure,
                        attempt=replan_number,
                    ),
                    [],
                    include_task_policy=False,
                ),
            }, timeout=30)
            return True
        except Exception:
            return False
        finally:
            run.replan_inflight = False

    def recover_stalled_task(self, task_id: str, failure: str) -> bool:
        """Request a guarded replan when the outer task supervisor detects a stall."""
        run = self._runs.get(str(task_id or "").strip())
        if run is None or run.finished:
            return False
        return self._attempt_replan(
            run,
            str(failure or "The external task supervisor detected no progress."),
            source="task_manager_watchdog",
        )

    def _record_failed_item(self, run: CodexRun, item: dict) -> None:
        raw_status = str(item.get("status") or "").lower()
        if "fail" not in raw_status and raw_status != "declined":
            return
        item_type = str(item.get("type") or "tool")
        if item_type == "dynamicToolCall":
            # The model receives the structured failure result and can choose a
            # fallback in the same turn. Steering an additional replan here
            # duplicates context and delays the model's native recovery path.
            return
        detail = self._item_detail(item, item_type) or raw_status or item_type
        signature = failure_fingerprint(item_type, detail)
        count = run.failure_counts.get(signature, 0) + 1
        run.failure_counts[signature] = count
        can_replan = count < run.execution_policy.max_same_failure_attempts
        if run.execution_harness is not None:
            can_replan, count = run.execution_harness.record_failure(
                item_type,
                detail,
            )
            run.failure_counts[signature] = count
        if can_replan:
            threading.Thread(
                target=self._attempt_replan,
                args=(run, f"{item_type} failed: {detail}"),
                kwargs={"source": "tool_failure"},
                daemon=True,
                name=f"codex-replan-{run.task_id[:8]}",
            ).start()
            return
        threading.Thread(
            target=self._stop_repeated_failure,
            args=(run, item_type, detail, count),
            daemon=True,
            name=f"codex-failure-budget-{run.task_id[:8]}",
        ).start()

    def _stop_repeated_failure(
        self,
        run: CodexRun,
        item_type: str,
        detail: str,
        count: int,
    ) -> None:
        with self._lock:
            if run.finished:
                return
            run.finished = True
        self._finish_host_config_guard(run)
        self._checkpoint_progress(
            run,
            "failed",
            repeated_failure_kind=item_type,
            repeated_failure_count=count,
        )
        message = (
            f"Codex stopped after the same {item_type} failure repeated {count} times. "
            "The latest verified workspace state was preserved."
        )
        progress = self._narration_progress(
            f"failure-budget-{count}",
            message,
            "failure_budget_exhausted",
        )
        progress["status"] = "failed"
        self._emit_progress(
            run.task_id,
            {"thread_id": run.thread_id, "turn_id": run.turn_id},
            progress,
        )
        self.on_event(run.task_id, {
            "thread_id": run.thread_id,
            "turn_id": run.turn_id,
            "status": "failed",
            "current_step": "",
            "result": message,
            "error": f"Repeated {item_type} failure: {detail[:500]}",
        })
        try:
            self._request(
                "turn/interrupt",
                {"threadId": run.thread_id, "turnId": run.turn_id},
                timeout=10,
            )
        except Exception:
            pass
        self._remove_turn_mapping(run)

    def _start_thread(
        self,
        cwd: str,
        model: str,
        conversation_id: str,
        *,
        approval_policy: str = "never",
        sandbox: str = "workspace-write",
    ) -> str:
        with self._thread_lifecycle_lock:
            self._make_loaded_thread_room()
            response = self._request("thread/start", {
                "cwd": os.path.abspath(cwd), "model": model, "ephemeral": False,
                "approvalPolicy": approval_policy, "sandbox": sandbox,
                "config": CODEX_THREAD_CONFIG,
                "developerInstructions": CODEX_TASK_POLICY.strip(),
                "dynamicTools": self._dynamic_tools,
            }, timeout=30)
            thread_id = str((response.get("thread") or {}).get("id") or "")
            if thread_id:
                with self._lock:
                    self._mark_thread_loaded_locked(thread_id)
                    if conversation_id:
                        conversation_key = self._conversation_key(conversation_id)
                        self._conversation_threads.pop(conversation_key, None)
                        self._conversation_threads[conversation_key] = thread_id
                        self._save_conversation_threads()
        return thread_id

    def _resume_thread(
        self,
        thread_id: str,
        *,
        approval_policy: str = "never",
        sandbox: str = "workspace-write",
    ) -> None:
        clean_thread_id = str(thread_id or "").strip()
        if not clean_thread_id:
            return
        with self._thread_lifecycle_lock:
            with self._lock:
                if clean_thread_id in self._loaded_thread_ids:
                    self._mark_thread_loaded_locked(clean_thread_id)
                    return
            self._make_loaded_thread_room(incoming_thread_id=clean_thread_id)
            self._request("thread/resume", {
                "threadId": clean_thread_id,
                "approvalPolicy": approval_policy,
                "sandbox": sandbox,
                "config": CODEX_THREAD_CONFIG,
            }, timeout=30)
            with self._lock:
                self._mark_thread_loaded_locked(clean_thread_id)

    def _touch_loaded_thread(self, thread_id: str) -> None:
        clean_thread_id = str(thread_id or "").strip()
        if not clean_thread_id:
            return
        with self._lock:
            if clean_thread_id in self._loaded_thread_ids:
                self._mark_thread_loaded_locked(clean_thread_id)

    def _mark_thread_loaded_locked(self, thread_id: str) -> None:
        self._loaded_thread_ids.add(thread_id)
        self._loaded_thread_recency[thread_id] = time.monotonic()

    def _make_loaded_thread_room(self, incoming_thread_id: str = "") -> None:
        clean_incoming = str(incoming_thread_id or "").strip()
        while True:
            with self._lock:
                if clean_incoming and clean_incoming in self._loaded_thread_ids:
                    self._mark_thread_loaded_locked(clean_incoming)
                    return
                if len(self._loaded_thread_ids) < MAX_LOADED_CODEX_THREADS:
                    return
                active_threads = {
                    run.thread_id
                    for run in self._runs.values()
                    if not run.finished and run.thread_id
                }
                candidates = [
                    thread_id
                    for thread_id in self._loaded_thread_ids
                    if thread_id not in active_threads and thread_id != clean_incoming
                ]
                if not candidates:
                    return
                thread_id = min(
                    candidates,
                    key=lambda candidate: self._loaded_thread_recency.get(candidate, 0.0),
                )
            try:
                self._request(
                    "thread/unsubscribe",
                    {"threadId": thread_id},
                    timeout=10,
                )
            except Exception:
                log.warning(
                    "Could not unload idle Codex thread %s",
                    thread_id,
                    exc_info=True,
                )
                return
            with self._lock:
                self._loaded_thread_ids.discard(thread_id)
                self._loaded_thread_recency.pop(thread_id, None)

    @staticmethod
    def _is_thread_not_found_error(exc: Exception) -> bool:
        value = str(exc or "").casefold()
        return "thread not found" in value or "thread_not_found" in value

    @staticmethod
    def _conversation_key(conversation_id: str) -> str:
        value = str(conversation_id or "").strip()
        return f"{CONVERSATION_THREAD_VERSION}:{value}" if value else ""

    def _active_run_locked(
        self,
        conversation_id: str,
        *,
        exclude_task_id: str = "",
    ) -> CodexRun | None:
        clean_conversation_id = str(conversation_id or "").strip()
        if not clean_conversation_id:
            return None
        mapped_thread_id = self._conversation_threads.get(
            self._conversation_key(clean_conversation_id),
            "",
        )
        candidates = [
            run for run in self._runs.values()
            if run.task_id != exclude_task_id and not run.finished and (
                run.conversation_id == clean_conversation_id
                or (mapped_thread_id and run.thread_id == mapped_thread_id)
            )
        ]
        return max(candidates, key=lambda item: item.started_monotonic, default=None)

    def active_task_id(self, conversation_id: str, exclude_task_id: str = "") -> str:
        with self._lock:
            run = self._active_run_locked(conversation_id, exclude_task_id=exclude_task_id)
            return run.task_id if run is not None else ""

    def wait_for_conversation_idle(
        self,
        conversation_id: str,
        timeout_seconds: float = 2.0,
    ) -> bool:
        deadline = time.monotonic() + max(0.0, float(timeout_seconds))
        while True:
            if not self.active_task_id(conversation_id):
                return True
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.02)

    def steer_task(
        self,
        task_id: str,
        prompt: str,
        image_paths: list[str] | None = None,
        wait_for_turn_seconds: float = 15.0,
    ) -> CodexRun | None:
        """Add user guidance to an active turn without creating a parallel thread."""
        self._ensure_started()
        deadline = time.monotonic() + max(0.0, float(wait_for_turn_seconds))
        run: CodexRun | None = None
        while True:
            with self._lock:
                run = self._runs.get(str(task_id or "").strip())
                if run is not None and run.finished:
                    return None
                if run is not None and run.turn_id:
                    break
            if time.monotonic() >= deadline:
                return None
            time.sleep(0.02)

        local_images = [
            os.path.abspath(path)
            for path in (image_paths or [])
            if str(path or "").strip() and os.path.isfile(path)
        ][:10]
        follow_up = (
            "Apply this latest user instruction to the task already in progress. "
            "Do not treat it as a separate request:\n"
            f"{str(prompt or '').strip()}"
        )
        try:
            self._request("turn/steer", {
                "threadId": run.thread_id,
                "expectedTurnId": run.turn_id,
                "input": self._user_input(follow_up, local_images, include_task_policy=False),
            }, timeout=30)
        except RuntimeError as exc:
            if self._is_not_steerable_error(exc):
                return None
            raise
        now = time.monotonic()
        run.last_event_monotonic = now
        run.last_meaningful_progress_monotonic = now
        self._checkpoint_progress(
            run,
            "act",
            steered=True,
        )
        return run

    def _start_turn(
        self,
        thread_id: str,
        prompt: str,
        model: str,
        image_paths: list[str] | None = None,
        *,
        cwd: str,
        reasoning_effort: str,
        include_task_policy: bool = True,
    ) -> dict:
        return self._request("turn/start", {
            "threadId": thread_id,
            "input": self._user_input(
                prompt,
                image_paths,
                include_task_policy=include_task_policy,
            ),
            "model": model,
            "effort": reasoning_effort,
            "cwd": os.path.abspath(cwd),
        }, timeout=30)

    @staticmethod
    def _user_input(
        prompt: str,
        image_paths: list[str] | None,
        *,
        include_task_policy: bool,
    ) -> list[dict]:
        from response_policy import apply_response_policy
        styled_prompt = apply_response_policy(prompt)
        text = styled_prompt.rstrip()
        if include_task_policy:
            text = f"{text}\n\n{CODEX_TASK_POLICY}"
        user_input = [
            {"type": "text", "text": text, "text_elements": []}
        ]
        user_input.extend(
            {"type": "localImage", "path": path, "detail": "original"}
            for path in (image_paths or [])
        )
        return user_input

    @staticmethod
    def _with_execution_contract(
        prompt: str,
        policy: AgentExecutionPolicy,
    ) -> str:
        text = str(prompt or "").rstrip()
        if "SignalASI execution contract:" in text:
            return text
        return f"{text}\n\n{execution_contract(policy)}"

    @staticmethod
    def _latest_agent_message(turn: dict) -> str:
        for item in reversed(list(turn.get("items") or [])):
            if item.get("type") == "agentMessage" and str(item.get("text") or "").strip():
                return str(item["text"]).strip()
        return ""

    @staticmethod
    def _turn_error(turn: dict) -> str:
        error = turn.get("error")
        if isinstance(error, dict):
            return str(error.get("message") or error.get("code") or "").strip()
        return str(error or "").strip()

    def _remove_turn_mapping(self, run: CodexRun) -> None:
        with self._lock:
            if self._turn_tasks.get(run.turn_id) == run.task_id:
                self._turn_tasks.pop(run.turn_id, None)

    def _discard_run(self, run: CodexRun) -> None:
        run.finished = True
        self._finish_host_config_guard(run)
        with self._lock:
            if self._turn_tasks.get(run.turn_id) == run.task_id:
                self._turn_tasks.pop(run.turn_id, None)
            if self._runs.get(run.task_id) is run:
                self._runs.pop(run.task_id, None)

    @staticmethod
    def _begin_host_config_guard(run: CodexRun):
        try:
            from host_execution_config_guard import HostExecutionConfigGuard

            return HostExecutionConfigGuard.begin(
                Path(run.working_directory),
                agent_id="codex",
                capture_id=run.task_id,
            )
        except Exception:
            log.debug("Codex host configuration guard could not start", exc_info=True)
            return None

    @staticmethod
    def _finish_host_config_guard(run: CodexRun) -> str:
        guard = run.host_config_guard
        run.host_config_guard = None
        if guard is None:
            return ""
        try:
            violations = guard.finish()
        except Exception:
            log.debug("Codex host configuration guard could not finish", exc_info=True)
            return ""
        if violations:
            from host_execution_config_guard import HostExecutionConfigViolation

            return str(HostExecutionConfigViolation(violations))
        return ""

    def _load_conversation_threads(self) -> dict[str, str]:
        try:
            data = json.loads(CONVERSATION_THREADS_PATH.read_text(encoding="utf-8"))
            return {
                str(key)[:120]: str(value)[:160]
                for key, value in data.items()
                if str(key).strip() and str(value).strip()
            }
        except Exception:
            return {}

    def _save_conversation_threads(self) -> None:
        try:
            CONVERSATION_THREADS_PATH.parent.mkdir(parents=True, exist_ok=True)
            temporary = CONVERSATION_THREADS_PATH.with_suffix(".tmp")
            temporary.write_text(json.dumps(self._conversation_threads, ensure_ascii=True), encoding="utf-8")
            temporary.replace(CONVERSATION_THREADS_PATH)
        except Exception:
            pass

    def delete_conversation(self, conversation_id: str) -> bool:
        clean_id = str(conversation_id or "").strip()
        if not clean_id:
            return False
        with self._lock:
            removed = self._conversation_threads.pop(self._conversation_key(clean_id), None)
            legacy = self._conversation_threads.pop(clean_id, None)
            if removed is not None or legacy is not None:
                self._save_conversation_threads()
            return removed is not None or legacy is not None

    def interrupt(self, task_id: str) -> bool:
        run = self._runs.get(task_id)
        if not run or not run.thread_id or not run.turn_id:
            return False
        self._request("turn/interrupt", {"threadId": run.thread_id, "turnId": run.turn_id}, timeout=10)
        return True

    def resolve_approval(
        self,
        task_id: str,
        approval_id: str,
        action_hash: str,
        approved: bool,
    ) -> dict[str, object]:
        clean_task_id = str(task_id or "").strip()
        clean_approval_id = str(approval_id or "").strip()
        clean_hash = str(action_hash or "").strip().lower()
        expired = False
        with self._lock:
            run = self._runs.get(clean_task_id)
            if run is None or run.finished:
                raise RuntimeError("Codex task is no longer active")
            pending = run.pending_requests.get(clean_approval_id)
            if pending is None:
                raise RuntimeError("Codex approval is no longer pending")
            if not hmac.compare_digest(pending.action_hash, clean_hash):
                raise RuntimeError("Codex approval parameters changed")
            if pending.expires_at_ms < int(time.time() * 1000):
                expired = True
                run.pending_requests.pop(clean_approval_id, None)
                self._write_server_response(
                    pending.request_id,
                    self._approval_result(pending, approved=False),
                )
            else:
                run.pending_requests.pop(clean_approval_id, None)
                self._write_server_response(
                    pending.request_id,
                    self._approval_result(pending, approved=approved),
                )
            run.last_event_monotonic = time.monotonic()
        self.on_event(clean_task_id, {
            "thread_id": run.thread_id,
            "turn_id": run.turn_id,
            "status": "running",
            "current_step": (
                "Approval expired"
                if expired else
                ("Approval accepted" if approved else "Approval declined")
            ),
            "approval_request": {},
        })
        if expired:
            raise RuntimeError("Codex approval expired")
        return {
            "task_id": clean_task_id,
            "approval_id": clean_approval_id,
            "action_hash": clean_hash,
            "approved": bool(approved),
        }

    def close(self) -> None:
        with self._lock:
            process = self.process
            self.process = None
            self._initialized_process_pid = 0
            self._loaded_thread_ids.clear()
            self._loaded_thread_recency.clear()
            self._runs.clear()
            self._turn_tasks.clear()
        if process is None or process.poll() is not None:
            return
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)

    def _ensure_started(self) -> None:
        with self._lock:
            if self.is_ready():
                return
            if self.process is None or self.process.poll() is not None:
                command = [
                    self.executable,
                    "-c", "sandbox_workspace_write.network_access=true",
                    "app-server", "--listen", "stdio://",
                ]
                if os.name == "nt" and self.executable.lower().endswith((".cmd", ".bat")):
                    command = [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/s", "/c", *command]
                self.process = subprocess.Popen(
                    command,
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, encoding="utf-8", errors="replace", bufsize=1, env=self.env,
                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                )
                self._initialized_process_pid = 0
                self._loaded_thread_ids.clear()
                self._loaded_thread_recency.clear()
                threading.Thread(target=self._read_stdout, daemon=True).start()
                threading.Thread(target=self._drain_stderr, daemon=True).start()
            self._request("initialize", {
                "clientInfo": {"name": "signalasi-desktop", "title": "SignalASI Desktop", "version": "0.1.18"},
                "capabilities": {"experimentalApi": True},
            }, timeout=15)
            self._notify("initialized", {})
            self._initialized_process_pid = self.process.pid

    def _request(self, method: str, params: dict, timeout: int) -> dict:
        with self._lock:
            request_id = self._next_id
            self._next_id += 1
            response_queue: queue.Queue = queue.Queue(maxsize=1)
            self._pending[request_id] = response_queue
            self._write({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})
        try:
            response = response_queue.get(timeout=timeout)
        except queue.Empty as exc:
            self._pending.pop(request_id, None)
            raise TimeoutError(f"Codex App Server request timed out: {method}") from exc
        if "error" in response:
            raise RuntimeError(str(response["error"]))
        return response.get("result") or {}

    def _notify(self, method: str, params: dict) -> None:
        self._write({"jsonrpc": "2.0", "method": method, "params": params})

    def _write_server_response(self, request_id: object, result: dict[str, object]) -> None:
        self._write({"jsonrpc": "2.0", "id": request_id, "result": result})

    def _write(self, payload: dict) -> None:
        process = self.process
        if process is None or process.stdin is None or process.poll() is not None:
            raise RuntimeError("Codex App Server is not running")
        with self._write_lock:
            process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
            process.stdin.flush()

    def _read_stdout(self) -> None:
        process = self.process
        if process is None or process.stdout is None:
            return
        for line in process.stdout:
            try:
                message = json.loads(line)
            except Exception:
                continue
            if "id" in message and ("result" in message or "error" in message):
                waiter = self._pending.pop(message["id"], None)
                if waiter:
                    waiter.put(message)
                continue
            if "method" in message:
                try:
                    self._handle_event(message)
                except Exception:
                    log.exception(
                        "Codex event handling failed; JSON-RPC reader will continue"
                    )

    def _handle_event(self, message: dict) -> None:
        method = str(message.get("method") or "")
        params = message.get("params") or {}
        turn_id = str(params.get("turnId") or (params.get("turn") or {}).get("id") or "")
        task_id = self._turn_tasks.get(turn_id, "")
        if not task_id:
            thread_id = str(params.get("threadId") or "")
            task_id = next((
                key for key, run in reversed(list(self._runs.items()))
                if run.thread_id == thread_id and not run.finished
            ), "")
        if not task_id:
            return
        run = self._runs[task_id]
        now = time.monotonic()
        run.last_event_monotonic = now
        meaningful_event = self._is_meaningful_event(method, message, params)
        if meaningful_event:
            run.last_meaningful_progress_monotonic = now
            self._checkpoint_progress(
                run,
                self._checkpoint_phase(method),
                app_server_event=method,
            )
        common = {"thread_id": run.thread_id, "turn_id": turn_id or run.turn_id}
        if "id" in message and method == "item/tool/call":
            self._handle_dynamic_tool_call(task_id, message, params, common)
        elif "id" in message:
            approval = self._pending_approval(task_id, message)
            if approval is not None:
                approved = (
                    run.execution_policy.execution_mode.value != "plan_only"
                )
                self._write_server_response(
                    approval.request_id,
                    self._approval_result(approval, approved=approved),
                )
                self.on_event(task_id, {
                    **common,
                    "status": "running",
                    "current_step": (
                        "Codex is working"
                        if approved else
                        "Desktop tool blocked; requesting a phone ActionPlan"
                    ),
                    "approval_request": {},
                })
            else:
                self.on_event(task_id, {
                    **common,
                    "status": "waiting_input",
                    "current_step": self._request_label(method),
                })
        elif method == "turn/started":
            if turn_id:
                run.turn_id = turn_id
                self._turn_tasks[turn_id] = task_id
            self.on_event(task_id, {**common, "turn_id": run.turn_id, "status": "running", "current_step": "Codex is working"})
        elif method == "item/agentMessage/delta":
            item_id = str(params.get("itemId") or "agent-message")
            delta = str(params.get("delta") or "")
            phase = str(params.get("phase") or "").strip()
            if phase:
                run.agent_message_phases[item_id] = phase
            run.agent_message_deltas[item_id] = (
                run.agent_message_deltas.get(item_id, "") + delta
            )[:MAX_VISIBLE_OUTPUT_TEXT]
            if delta.strip():
                self._emit_first_output(task_id, run, common)
                if (
                    run.agent_message_phases.get(item_id) != "commentary"
                    and not run.web_evidence_packs
                ):
                    self._emit_output_delta(task_id, run, common)
        elif method == "item/reasoning/summaryTextDelta":
            item_id = str(params.get("itemId") or "")
            if item_id:
                summary_index = max(0, int(params.get("summaryIndex") or 0))
                summaries = run.reasoning_summary_deltas.setdefault(item_id, {})
                summaries[summary_index] = (
                    summaries.get(summary_index, "") + str(params.get("delta") or "")
                )[:MAX_VISIBLE_PROGRESS_TEXT]
        elif method == "item/started":
            item = params.get("item") or {}
            if str(item.get("type") or "") == "agentMessage":
                item_id = str(item.get("id") or params.get("itemId") or "agent-message")
                run.agent_message_phases[item_id] = str(item.get("phase") or "").strip()
            self._emit_item_progress(
                task_id,
                common,
                item,
                completed=False,
            )
        elif method == "item/completed":
            item = params.get("item") or {}
            self._record_failed_item(run, item)
            item_type = str(item.get("type") or "")
            item_id = str(item.get("id") or params.get("itemId") or "")
            if item_type == "agentMessage":
                text = self._clean_output_text(
                    item.get("text") or run.agent_message_deltas.get(item_id, "")
                )
                phase = str(item.get("phase") or "")
                if item_id:
                    run.agent_message_phases[item_id] = phase
                    if text:
                        run.agent_message_deltas[item_id] = text
                if text:
                    self._emit_first_output(task_id, run, common)
                    run.last_agent_text = text
                    if phase == "commentary":
                        self._emit_progress(
                            task_id,
                            common,
                            self._narration_progress(item_id, text, "commentary"),
                        )
                    else:
                        run.final_text = text
                        if not run.web_evidence_packs:
                            self._emit_output_delta(
                                task_id,
                                run,
                                common,
                                force=True,
                                text_override=text,
                            )
            elif item_type == "fileChange":
                self._emit_item_progress(
                    task_id,
                    common,
                    item,
                    completed=True,
                )
            elif item_type == "reasoning":
                summary = self._reasoning_summary(run, item_id, item)
                if summary:
                    self._emit_progress(
                        task_id,
                        common,
                        self._narration_progress(item_id, summary, "reasoning_summary"),
                    )
                legacy_event = self._item_event(item, "completed")
                if legacy_event:
                    self.on_event(task_id, {
                        **common,
                        "status": "running",
                        "current_step": self._item_label(item, completed=True),
                        **legacy_event,
                    })
            elif item_type == "plan":
                text = self._clean_visible_text(item.get("text"))
                if text:
                    self._emit_progress(
                        task_id,
                        common,
                        self._narration_progress(item_id, text, "plan"),
                    )
                legacy_event = self._item_event(item, "completed")
                if legacy_event:
                    self.on_event(task_id, {
                        **common,
                        "status": "running",
                        "current_step": self._item_label(item, completed=True),
                        **legacy_event,
                    })
            else:
                self._emit_item_progress(task_id, common, item, completed=True)
        elif method == "turn/completed":
            status = str((params.get("turn") or {}).get("status") or "completed")
            mapped = {"completed": "completed", "failed": "failed", "interrupted": "cancelled"}.get(status, status)
            if not run.final_text:
                run.final_text = run.last_agent_text
            if (
                mapped == "completed"
                and run.final_text
                and self._apply_web_citation_gate(task_id, run, common, turn_id)
            ):
                return
            self._checkpoint_progress(
                run,
                "finalize" if mapped == "completed" else "failed",
                turn_status=mapped,
            )
            if mapped == "completed" and run.final_text:
                self._emit_output_delta(
                    task_id,
                    run,
                    common,
                    force=True,
                    text_override=run.final_text,
                )
            if (
                mapped == "completed"
                and not run.finished
                and run.execution_harness is not None
            ):
                try:
                    run.execution_harness.account_usage(
                        output_tokens=estimate_text_tokens(run.final_text),
                        estimated=True,
                    )
                except AgentTaskBudgetExceeded as exc:
                    mapped = "failed"
                    run.final_text = str(exc)
            run.finished = True
            host_config_failure = self._finish_host_config_guard(run)
            if host_config_failure:
                mapped = "failed"
                run.final_text = host_config_failure
                self._checkpoint_progress(
                    run,
                    "failed",
                    host_config_write_blocked=True,
                )
            run.agent_message_deltas.clear()
            run.agent_message_phases.clear()
            run.reasoning_summary_deltas.clear()
            if turn_id:
                self._turn_tasks.pop(turn_id, None)
            self.on_event(task_id, {**common, "status": mapped, "current_step": "", "result": run.final_text})
        elif method == "thread/status/changed":
            status = params.get("status") or {}
            status_type = status if isinstance(status, str) else status.get("type", "")
            if status_type == "active":
                detail = status.get("activeFlags", []) if isinstance(status, dict) else []
                if "waitingOnApproval" in detail:
                    self.on_event(task_id, {**common, "status": "running", "current_step": "Codex is working"})
                elif "waitingOnUserInput" in detail:
                    self.on_event(task_id, {**common, "status": "waiting_input", "current_step": "Waiting for user input"})

    @staticmethod
    def _is_meaningful_event(method: str, message: dict, params: dict) -> bool:
        if "id" in message:
            return True
        if method in {
            "turn/started",
            "turn/completed",
            "item/started",
            "item/completed",
        }:
            return True
        if method.endswith("/delta"):
            return bool(
                str(
                    params.get("delta")
                    or params.get("text")
                    or params.get("content")
                    or ""
                ).strip()
            )
        if method == "thread/status/changed":
            status = params.get("status") or {}
            flags = status.get("activeFlags", []) if isinstance(status, dict) else []
            return bool(flags)
        return False

    def _emit_progress(self, task_id: str, common: dict, progress: dict) -> None:
        self.on_event(task_id, {
            **common,
            "status": "running",
            "current_step": str(progress.get("title") or "Codex is working"),
            "progress_event": progress,
        })

    def _handle_dynamic_tool_call(
        self,
        task_id: str,
        message: Mapping[str, Any],
        params: Mapping[str, Any],
        common: Mapping[str, Any],
    ) -> None:
        threading.Thread(
            target=self._execute_dynamic_tool_call,
            args=(task_id, dict(message), dict(params), dict(common)),
            daemon=True,
            name=f"codex-dynamic-tool-{task_id[:8]}",
        ).start()

    def _execute_dynamic_tool_call(
        self,
        task_id: str,
        message: Mapping[str, Any],
        params: Mapping[str, Any],
        common: Mapping[str, Any],
    ) -> None:
        tool_name = str(params.get("tool") or "").strip()
        arguments = params.get("arguments")
        query = (
            str(arguments.get("query") or "").strip()
            if isinstance(arguments, Mapping)
            else ""
        )
        verticals = (
            ",".join(str(value) for value in (arguments.get("verticals") or [])[:3])
            if isinstance(arguments, Mapping) and isinstance(arguments.get("verticals"), list)
            else ""
        )
        read_pages = (
            bool(arguments.get("read_pages", True))
            if isinstance(arguments, Mapping)
            else True
        )
        try:
            if tool_name == CODEX_DYNAMIC_SEARCH_TOOL:
                result = execute_codex_dynamic_search(
                    arguments if isinstance(arguments, Mapping) else {},
                    task_id,
                )
            elif tool_name == CODEX_DYNAMIC_FETCH_TOOL:
                result = execute_codex_dynamic_fetch(
                    arguments if isinstance(arguments, Mapping) else {},
                    task_id,
                )
            else:
                result = {
                    "success": False,
                    "contentItems": [{
                        "type": "inputText",
                        "text": f"Unsupported SignalASI dynamic tool: {tool_name or 'unknown'}",
                    }],
                }
        except Exception as exc:
            log.exception("SignalASI dynamic tool failed task_id=%s tool=%s", task_id, tool_name)
            result = {
                "success": False,
                "contentItems": [{
                    "type": "inputText",
                    "text": f"SignalASI dynamic tool failed: {str(exc)[:500]}",
                }],
            }
        if not isinstance(result, Mapping):
            result = {
                "success": False,
                "contentItems": [{
                    "type": "inputText",
                    "text": "SignalASI dynamic tool returned an invalid response.",
                }],
            }
        else:
            result = dict(result)
        evidence_pack = result.pop("_signalasi_evidence_pack", None)
        if result.get("success") and isinstance(evidence_pack, Mapping):
            with self._lock:
                run = self._runs.get(task_id)
                if run is not None and not run.finished:
                    run.web_evidence_packs.append(dict(evidence_pack))
        self._write_server_response(message.get("id"), result)
        direct_fetch = tool_name == CODEX_DYNAMIC_FETCH_TOOL
        direct_urls = arguments.get("urls") if isinstance(arguments, Mapping) else []
        self.on_event(task_id, {
            **dict(common),
            "status": "running",
            "current_step": (
                "Read source pages" if direct_fetch and result.get("success")
                else "Source page unavailable" if direct_fetch
                else "Searched sources" if result.get("success")
                else "Search fallback available"
            ),
            "trace_stage": (
                "model_directed_fetch_completed"
                if direct_fetch
                else "model_directed_search_completed"
            ),
            "trace_detail": (
                f"{tool_name}: {','.join(str(url) for url in direct_urls[:3]) if direct_fetch and isinstance(direct_urls, list) else query}; "
                f"verticals={verticals or 'general'}; "
                f"read_pages={str(read_pages).lower()}; success={str(bool(result.get('success'))).lower()}"
            )[:1_200],
            "telemetry_only": True,
        })

    def _apply_web_citation_gate(
        self,
        task_id: str,
        run: CodexRun,
        common: Mapping[str, Any],
        completed_turn_id: str,
    ) -> bool:
        """Start one repair turn for invalid SignalASI Evidence Pack citations."""
        if not run.web_evidence_packs:
            return False
        validation = validate_answer_citations(
            run.final_text,
            packs=run.web_evidence_packs,
        )
        if not validation.requires_repair:
            return False
        if validation.verified_evidence_item_count <= 0 or run.citation_repair_attempted:
            run.final_text = self._verified_web_evidence_fallback(run)
            return False

        encoded_results = [
            (
                f"desktop-web-{index}",
                json.dumps(
                    {"evidence_pack": pack},
                    ensure_ascii=False,
                    separators=(",", ":"),
                ),
            )
            for index, pack in enumerate(run.web_evidence_packs, start=1)
        ]
        repair_prompt = citation_repair_prompt(validation, encoded_results)
        run.citation_repair_attempted = True
        run.final_text = ""
        run.last_agent_text = ""
        run.agent_message_deltas.clear()
        run.agent_message_phases.clear()
        run.reasoning_summary_deltas.clear()
        threading.Thread(
            target=self._start_web_citation_repair,
            args=(task_id, run, dict(common), completed_turn_id, repair_prompt, validation.status),
            daemon=True,
            name=f"codex-citation-repair-{task_id[:8]}",
        ).start()
        return True

    def _start_web_citation_repair(
        self,
        task_id: str,
        run: CodexRun,
        common: Mapping[str, Any],
        completed_turn_id: str,
        repair_prompt: str,
        citation_status: str,
    ) -> None:
        try:
            if run.execution_harness is not None:
                run.execution_harness.account_usage(
                    input_tokens=estimate_text_tokens(repair_prompt),
                    estimated=True,
                )
            response = self._start_turn(
                run.thread_id,
                repair_prompt,
                run.model,
                [],
                cwd=run.working_directory or os.getcwd(),
                reasoning_effort=run.reasoning_effort,
                include_task_policy=False,
            )
            repair_turn_id = str((response.get("turn") or {}).get("id") or "")
            if not repair_turn_id:
                raise RuntimeError("Codex citation repair did not return a turn id")
        except Exception:
            log.exception("Codex citation repair failed task_id=%s", task_id)
            self._complete_web_citation_fallback(
                task_id,
                run,
                common,
                completed_turn_id,
            )
            return

        with self._lock:
            if completed_turn_id:
                self._turn_tasks.pop(completed_turn_id, None)
            run.turn_id = repair_turn_id
            self._turn_tasks[repair_turn_id] = task_id
        self._checkpoint_progress(
            run,
            "verify",
            citation_status=citation_status,
            citation_repair=True,
        )
        self.on_event(task_id, {
            **dict(common),
            "turn_id": repair_turn_id,
            "status": "running",
            "current_step": "Verifying source citations",
            "telemetry_only": True,
        })

    def _complete_web_citation_fallback(
        self,
        task_id: str,
        run: CodexRun,
        common: Mapping[str, Any],
        completed_turn_id: str,
    ) -> None:
        run.final_text = self._verified_web_evidence_fallback(run)
        mapped = "completed"
        if run.execution_harness is not None:
            try:
                run.execution_harness.account_usage(
                    output_tokens=estimate_text_tokens(run.final_text),
                    estimated=True,
                )
            except AgentTaskBudgetExceeded as exc:
                mapped = "failed"
                run.final_text = str(exc)
        run.finished = True
        host_config_failure = self._finish_host_config_guard(run)
        if host_config_failure:
            mapped = "failed"
            run.final_text = host_config_failure
        self._checkpoint_progress(run, "finalize" if mapped == "completed" else "failed")
        self._emit_output_delta(
            task_id,
            run,
            dict(common),
            force=True,
            text_override=run.final_text,
        )
        run.agent_message_deltas.clear()
        run.agent_message_phases.clear()
        run.reasoning_summary_deltas.clear()
        with self._lock:
            if completed_turn_id:
                self._turn_tasks.pop(completed_turn_id, None)
            if run.turn_id:
                self._turn_tasks.pop(run.turn_id, None)
        self.on_event(task_id, {
            **dict(common),
            "status": mapped,
            "current_step": "",
            "result": run.final_text,
        })

    @staticmethod
    def _verified_web_evidence_fallback(run: CodexRun) -> str:
        heading = (
            "引用复核未通过，以下仅返回已经过完整性校验的来源证据："
            if run.prefers_chinese else
            "Citation repair did not pass; only integrity-verified source evidence is returned:"
        )
        lines = [heading]
        seen: set[str] = set()
        for pack in run.web_evidence_packs:
            verification = verify_evidence_pack(pack)
            valid_urls = {
                str(item.get("url") or "")
                for item in verification.get("citation_manifest", [])
                if isinstance(item, Mapping)
            }
            for item in pack.get("items", []):
                if not isinstance(item, Mapping):
                    continue
                url = str(item.get("url") or "")
                if not url or url not in valid_urls or url in seen:
                    continue
                seen.add(url)
                title = str(item.get("title") or url).strip()[:240]
                excerpt = str(item.get("excerpt") or "").strip()[:800]
                lines.append(f"\n- [{title}]({url})")
                if excerpt:
                    lines.append(f"  {excerpt}")
                if len(seen) >= 12:
                    break
            if len(seen) >= 12:
                break
        if not seen:
            return (
                "网页证据完整性校验失败，未返回未经验证的内容。"
                if run.prefers_chinese else
                "Web evidence integrity verification failed; no unverified content was returned."
            )
        return "\n".join(lines)

    def _emit_first_output(
        self,
        task_id: str,
        run: CodexRun,
        common: dict,
    ) -> None:
        if run.first_output_emitted:
            return
        run.first_output_emitted = True
        self.on_event(task_id, {
            **common,
            "status": "running",
            "telemetry_only": True,
            "trace_stage": "agent_first_output",
            "trace_detail": "codex",
        })

    def _emit_output_delta(
        self,
        task_id: str,
        run: CodexRun,
        common: dict,
        *,
        force: bool = False,
        text_override: str = "",
    ) -> None:
        if not agent_output_delta_enabled():
            return
        text = self._clean_output_text(
            text_override or self._visible_output_text(run)
        )
        if not text or text == run.last_output_delta_text:
            return
        now = time.monotonic()
        growth = max(0, len(text) - len(run.last_output_delta_text))
        if (
            not force
            and run.last_output_delta_monotonic
            and now - run.last_output_delta_monotonic < OUTPUT_DELTA_COALESCE_SECONDS
            and growth < OUTPUT_DELTA_MIN_GROWTH
        ):
            return
        run.output_delta_sequence += 1
        run.last_output_delta_text = text
        run.last_output_delta_monotonic = now
        self.on_event(task_id, {
            **common,
            "status": "running",
            "current_step": "Codex is responding",
            "output_delta": {
                "event_id": f"codex-output:{task_id}:{run.output_delta_sequence}",
                "sequence": run.output_delta_sequence,
                "text": text,
                "mode": "cumulative",
                "user_visible": True,
            },
        })

    @staticmethod
    def _visible_output_text(run: CodexRun) -> str:
        values = [
            value
            for item_id, value in run.agent_message_deltas.items()
            if run.agent_message_phases.get(item_id) != "commentary"
            and str(value or "").strip()
        ]
        return "\n\n".join(values)

    @staticmethod
    def _checkpoint_progress(
        run: CodexRun,
        phase: str,
        **verification: object,
    ) -> None:
        if run.execution_harness is not None:
            try:
                run.execution_harness.progress(phase, **verification)
            except Exception:
                log.exception(
                    "Codex checkpoint update failed task_id=%s phase=%s",
                    run.task_id,
                    phase,
                )

    @staticmethod
    def _checkpoint_phase(method: str) -> str:
        if method == "turn/completed":
            return "finalize"
        if method == "item/completed":
            return "observe"
        return "act"

    def _emit_item_progress(
        self,
        task_id: str,
        common: dict,
        item: dict,
        *,
        completed: bool,
    ) -> None:
        progress = self._tool_progress_event(item, completed=completed)
        legacy_event = self._item_event(
            item,
            "completed" if completed else "running",
        )
        if not progress and not legacy_event:
            return
        self.on_event(task_id, {
            **common,
            "status": "running",
            "current_step": (
                str(progress.get("title") or "")
                if progress
                else self._item_label(item, completed=completed)
            ),
            **({"progress_event": progress} if progress else {}),
            **legacy_event,
        })

    @staticmethod
    def _item_label(item: dict, completed: bool = False) -> str:
        labels = {
            "commandExecution": "Running command", "fileChange": "Updating files",
            "mcpToolCall": "Calling MCP tool", "dynamicToolCall": "Calling tool",
            "webSearch": "Searching the web", "agentMessage": "Preparing response",
            "reasoning": "Planning", "plan": "Updating plan",
        }
        label = labels.get(str(item.get("type") or ""), "Working")
        return f"{label} complete" if completed and label not in {"Preparing response", "Planning"} else label

    @classmethod
    def _item_event(cls, item: dict, status: str) -> dict:
        item_type = str(item.get("type") or "").strip()
        if not item_type or item_type == "agentMessage":
            return {}
        kind = {
            "reasoning": "reasoning",
            "plan": "plan",
            "commandExecution": "command",
            "fileChange": "file",
            "mcpToolCall": "mcp",
            "dynamicToolCall": "tool",
            "webSearch": "network",
        }.get(item_type, "tool")
        detail = cls._item_detail(item, item_type)
        item_id = str(item.get("id") or "").strip()
        return {
            "event_id": f"codex:{item_id}" if item_id else "",
            "event_kind": kind,
            "event_title": cls._item_label(item),
            "event_status": status,
            "event_detail": detail,
            "event_metadata": {"provider": "codex", "item_type": item_type},
        }

    @staticmethod
    def _item_detail(item: dict, item_type: str) -> str:
        if item_type == "commandExecution":
            command = item.get("command") or item.get("cmd") or ""
            if isinstance(command, list):
                command = " ".join(str(value) for value in command)
            return str(command or "").strip()[:1_000]
        if item_type in {"mcpToolCall", "dynamicToolCall"}:
            server = str(item.get("server") or item.get("serverName") or "").strip()
            tool = str(item.get("tool") or item.get("toolName") or item.get("name") or "").strip()
            return " / ".join(value for value in (server, tool) if value)[:1_000]
        if item_type == "webSearch":
            action = item.get("action") if isinstance(item.get("action"), dict) else {}
            queries = action.get("queries") if isinstance(action.get("queries"), list) else []
            return str(
                item.get("query")
                or action.get("query")
                or (queries[0] if queries else "")
            ).strip()[:1_000]
        if item_type == "fileChange":
            changes = item.get("changes") or []
            if isinstance(changes, list):
                paths = [
                    str(value.get("path") or value.get("file") or "").strip()
                    for value in changes
                    if isinstance(value, dict)
                ]
                return ", ".join(value for value in paths if value)[:1_000]
        # Reasoning internals are deliberately not forwarded.
        return ""

    @classmethod
    def _narration_progress(cls, item_id: str, text: str, code: str) -> dict:
        clean = cls._clean_visible_text(text)
        return {
            "event_id": cls._progress_event_id(item_id, code),
            "kind": "narration",
            "code": code,
            "title": clean.splitlines()[0][:240],
            "status": "completed",
            "detail": clean,
            "metadata": {"source": "codex_app_server"},
        }

    @classmethod
    def _tool_progress_event(cls, item: dict, completed: bool) -> dict | None:
        item_type = str(item.get("type") or "")
        item_id = str(item.get("id") or "")
        if not item_id:
            return None
        status = "completed" if completed else "running"
        raw_status = str(item.get("status") or "").lower()
        if completed and ("fail" in raw_status or raw_status == "declined"):
            status = "failed"

        code = ""
        started_title = ""
        completed_title = ""
        detail = ""
        metadata: dict[str, object] = {"source": "codex_app_server", "item_type": item_type}
        if item_type == "commandExecution":
            code, started_title, completed_title = "command", "Running command", "Ran command"
            detail = cls._clean_visible_text(item.get("command"))
        elif item_type == "fileChange":
            code, started_title, completed_title = "file_change", "Updating files", "Updated files"
            metadata["count"] = len(item.get("changes") or [])
        elif item_type == "mcpToolCall":
            code, started_title, completed_title = "mcp_tool", "Calling MCP tool", "Called MCP tool"
            detail = ".".join(filter(None, (
                str(item.get("server") or "").strip(),
                str(item.get("tool") or "").strip(),
            )))
        elif item_type == "dynamicToolCall":
            code, started_title, completed_title = "dynamic_tool", "Calling tool", "Called tool"
            detail = ".".join(filter(None, (
                str(item.get("namespace") or "").strip(),
                str(item.get("tool") or "").strip(),
            )))
        elif item_type == "webSearch":
            code, started_title, completed_title = "web_search", "Searching the web", "Searched the web"
            action = item.get("action") if isinstance(item.get("action"), dict) else {}
            queries = action.get("queries") if isinstance(action.get("queries"), list) else []
            detail = cls._clean_visible_text(
                item.get("query") or action.get("query") or (queries[0] if queries else "")
            )
        elif item_type == "imageView":
            code, started_title, completed_title = "image_view", "Viewing image", "Viewed image"
            metadata["count"] = 1
        elif item_type == "imageGeneration":
            code, started_title, completed_title = "image_generation", "Generating image", "Generated image"
        elif item_type in {"collabAgentToolCall", "subAgentActivity"}:
            code, started_title, completed_title = (
                "agent_collaboration",
                "Coordinating Agents",
                "Coordinated Agents",
            )
            detail = cls._clean_visible_text(item.get("tool") or item.get("kind"))
        elif item_type == "contextCompaction":
            code, started_title, completed_title = (
                "context_compaction",
                "Compacting context",
                "Compacted context",
            )
        else:
            return None

        title = completed_title if completed else started_title
        if status == "failed":
            title = f"{completed_title} with an error"
        metadata["code"] = code
        return {
            "event_id": cls._progress_event_id(item_id, code),
            "kind": "tool",
            "code": code,
            "title": title,
            "status": status,
            "detail": detail[:MAX_VISIBLE_TOOL_DETAIL],
            "metadata": metadata,
        }

    @classmethod
    def _reasoning_summary(cls, run: CodexRun, item_id: str, item: dict) -> str:
        raw_summary = item.get("summary") if isinstance(item.get("summary"), list) else []
        summaries = [cls._clean_visible_text(value) for value in raw_summary]
        summaries = [value for value in summaries if value]
        if not summaries:
            buffered = run.reasoning_summary_deltas.get(item_id, {})
            summaries = [
                cls._clean_visible_text(buffered[index])
                for index in sorted(buffered)
                if cls._clean_visible_text(buffered[index])
            ]
        run.reasoning_summary_deltas.pop(item_id, None)
        return "\n\n".join(summaries)[:MAX_VISIBLE_PROGRESS_TEXT]

    @staticmethod
    def _progress_event_id(item_id: str, code: str) -> str:
        clean_item = str(item_id or "").strip()[:160]
        return f"codex:{code}:{clean_item}" if clean_item else f"codex:{code}"

    @staticmethod
    def _clean_visible_text(value: object) -> str:
        text = str(value or "").replace("\x00", "").strip()
        return text[:MAX_VISIBLE_PROGRESS_TEXT]

    @staticmethod
    def _clean_output_text(value: object) -> str:
        text = str(value or "").replace("\x00", "").strip()
        return text[:MAX_VISIBLE_OUTPUT_TEXT]

    @staticmethod
    def _request_label(method: str) -> str:
        return "Waiting for approval" if "approval" in method.lower() else "Waiting for user input"

    @classmethod
    def _pending_approval(
        cls,
        task_id: str,
        message: dict,
    ) -> CodexPendingApproval | None:
        method = str(message.get("method") or "")
        kind = CODEX_APPROVAL_METHODS.get(method)
        if kind is None:
            return None
        params = message.get("params") if isinstance(message.get("params"), dict) else {}
        request_id = message.get("id")
        requested_at_ms = int(params.get("startedAtMs") or time.time() * 1000)
        expires_at_ms = requested_at_ms + CODEX_APPROVAL_TTL_SECONDS * 1000
        command = params.get("command")
        if isinstance(command, list):
            command = " ".join(str(value) for value in command)
        command = str(command or "").strip()
        cwd = str(params.get("cwd") or "").strip()
        reason = str(params.get("reason") or "").strip()
        grant_root = str(params.get("grantRoot") or "").strip()
        file_changes = params.get("fileChanges") if isinstance(params.get("fileChanges"), dict) else {}
        changed_files = sorted(str(path) for path in file_changes)[:20]
        permissions = params.get("permissions")
        if not isinstance(permissions, dict):
            permissions = params.get("additionalPermissions")
        if not isinstance(permissions, dict):
            permissions = {}
        target = command or grant_root or cwd
        if not target and changed_files:
            target = changed_files[0]
        if kind == "command":
            title = "Run a command"
            detail = command or reason or "Codex requested command execution"
        elif kind == "file_change":
            title = "Modify files"
            detail = (
                ", ".join(changed_files)
                or grant_root
                or reason
                or "Codex requested file changes"
            )
        else:
            title = "Grant additional permissions"
            detail = reason or cwd or "Codex requested additional permissions"
        display_parameters = {
            "command": command[:2_000],
            "cwd": cwd[:1_000],
            "reason": reason[:1_000],
            "grant_root": grant_root[:1_000],
            "files": changed_files,
            "permissions": permissions,
        }
        canonical = {
            "task_id": str(task_id or ""),
            "request_id": request_id,
            "method": method,
            "params": params,
        }
        action_hash = hashlib.sha256(
            json.dumps(
                canonical,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
                default=str,
            ).encode("utf-8")
        ).hexdigest()
        approval_id = hashlib.sha256(
            f"{task_id}:{request_id}:{method}:{action_hash}".encode("utf-8")
        ).hexdigest()[:32]
        return CodexPendingApproval(
            request_id=request_id,
            approval_id=approval_id,
            action_hash=action_hash,
            method=method,
            kind=kind,
            title=title,
            detail=detail[:2_000],
            target=target[:2_000],
            reason=reason[:1_000],
            parameters=display_parameters,
            requested_at_ms=requested_at_ms,
            expires_at_ms=expires_at_ms,
            raw_params=dict(params),
        )

    @staticmethod
    def _approval_result(
        pending: CodexPendingApproval,
        *,
        approved: bool,
    ) -> dict[str, object]:
        if pending.method == "item/commandExecution/requestApproval":
            return {"decision": "accept" if approved else "decline"}
        if pending.method == "item/fileChange/requestApproval":
            return {"decision": "accept" if approved else "decline"}
        if pending.method == "execCommandApproval":
            return {"decision": "approved" if approved else "denied"}
        if pending.method == "applyPatchApproval":
            return {"decision": "approved" if approved else "denied"}
        if pending.method == "item/permissions/requestApproval":
            requested = pending.raw_params.get("permissions")
            return {
                "permissions": requested if approved and isinstance(requested, dict) else {},
                "scope": "turn",
                "strictAutoReview": True,
            }
        raise RuntimeError(f"Unsupported Codex approval method: {pending.method}")

    @staticmethod
    def _contains_chinese(value: str) -> bool:
        return any("\u4e00" <= character <= "\u9fff" for character in str(value or ""))

    @staticmethod
    def _is_not_steerable_error(error: Exception) -> bool:
        normalized = str(error or "").lower()
        return any(marker in normalized for marker in (
            "expectedturnid",
            "expected turn",
            "no active turn",
            "not active",
            "not in progress",
            "turn not found",
            "thread is idle",
        ))

    def _drain_stderr(self) -> None:
        process = self.process
        if process is not None and process.stderr is not None:
            for _line in process.stderr:
                pass
