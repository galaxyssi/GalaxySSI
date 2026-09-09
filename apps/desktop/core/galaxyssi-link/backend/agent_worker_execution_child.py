"""Private single-job Codex adapter, launched only by WorkerProcessExecutor."""
import base64
import hashlib
import io
import json
from pathlib import Path
import sys
import threading


def policy_for_job(job):
    from dataclasses import replace
    from agent_execution_harness import AgentExecutionMode, AgentReasoningEffort, AgentTaskNetworkPolicy, execution_policy_for
    options = job["options"]
    if not isinstance(options, dict) or not isinstance(options.get("task_budget", {}), dict):
        raise ValueError("worker_options_invalid")
    if options.get("task_budget", {}).get("network_policy") is not None:
        AgentTaskNetworkPolicy(options["task_budget"]["network_policy"])
    mode = AgentExecutionMode(options.get("execution_mode") or "auto_complete")
    attachments = options.get("attachments") or []
    if not isinstance(attachments, list) or any(not isinstance(item, dict) for item in attachments):
        raise ValueError("worker_input_invalid")
    policy = execution_policy_for(job["prompt"], attachments=[item.get("name", "image") for item in attachments],
        requested_execution_mode=mode, requested_task_budget=options.get("task_budget"))
    invocation = options.get("agent_invocation") or {}
    if not isinstance(invocation, dict):
        raise ValueError("worker_invocation_invalid")
    if invocation.get("reasoning_effort"):
        policy = replace(policy, reasoning_effort=AgentReasoningEffort(invocation["reasoning_effort"]))
    if (not policy.task_budget.allow_cloud or not policy.task_budget.allow_paid_providers
            or policy.task_budget.network_policy != AgentTaskNetworkPolicy.ANY):
        raise ValueError("worker_provider_budget_denied")
    if policy.requires_artifact:
        raise ValueError("worker_artifact_return_not_implemented")
    return policy


def prepare_images(options, workspace):
    from PIL import Image
    attachments = options.get("attachments", [])
    if not isinstance(attachments, list) or len(attachments) > 12:
        raise ValueError("worker_input_invalid")
    paths = []
    for index, attachment in enumerate(attachments):
        if not isinstance(attachment, dict) or not str(attachment.get("mime_type", "")).startswith("image/"):
            raise ValueError("worker_input_type_not_implemented")
        encoded = attachment.get("data_b64")
        if not isinstance(encoded, str) or len(encoded) > 512 * 1024:
            raise ValueError("worker_input_bytes_required")
        data = base64.b64decode(encoded, validate=True)
        if not data or hashlib.sha256(data).hexdigest() != attachment.get("sha256"):
            raise ValueError("worker_input_digest_mismatch")
        with Image.open(io.BytesIO(data)) as image:
            if image.width * image.height > 16_000_000:
                raise ValueError("worker_input_dimensions_exceeded")
            suffix = {"PNG": ".png", "JPEG": ".jpg", "WEBP": ".webp", "GIF": ".gif"}.get(image.format)
            if suffix is None:
                raise ValueError("worker_input_format_not_implemented")
            image.verify()
        path = workspace / f"input-{index}{suffix}"
        with path.open("xb") as stream:
            stream.write(data)
        paths.append(str(path))
    return paths


def execute(request):
    import codex_app_server
    from agent_execution_harness import AgentExecutionMode
    from agent_gateway import BASE_AGENTS, _agent_env, _find_codex_desktop_cli
    from response_policy import apply_response_policy
    workspace = Path(request["workspace"]).resolve()
    options = request["options"]
    policy = policy_for_job(request)
    language = options.get("response_language_preference") or options.get("response_language") or ""
    prompt = apply_response_policy(request["prompt"], language) if language else request["prompt"]
    # This process owns only one grant; it never reads Desktop conversation IDs.
    codex_app_server.CONVERSATION_THREADS_PATH = workspace / "worker-codex-threads.json"
    images = prepare_images(options, workspace)
    invocation = options.get("agent_invocation") or {}
    model = invocation.get("model_id") or "gpt-5.6-sol"
    if not isinstance(model, str) or len(model) > 128:
        raise ValueError("worker_model_invalid")
    done = threading.Event()
    terminal = {}
    execution_id = request["execution_id"]
    def event(task_id, value):
        if task_id != execution_id:
            return
        if value.get("status") in {"completed", "failed", "cancelled", "timed_out"}:
            terminal.update(value)
            done.set()
    executable = _find_codex_desktop_cli() or "codex"
    server = codex_app_server.CodexAppServer(executable,
        _agent_env(BASE_AGENTS["codex"], restricted_workspace=True), event)
    try:
        server.start_task(execution_id, prompt, str(workspace), model=model,
            conversation_id="worker-" + execution_id, image_paths=images,
            approval_policy="never", sandbox="read-only" if policy.execution_mode == AgentExecutionMode.PLAN_ONLY else request["sandbox"],
            execution_policy=policy)
        while not done.wait(0.1):
            if server.process is None or server.process.poll() is not None:
                raise RuntimeError("worker_provider_exited")
        status = terminal["status"]
        text = str(terminal.get("result") or "") if status == "completed" else ""
        if status == "completed" and (not text.strip() or len(text.encode("utf-8")) > 8192):
            raise ValueError("worker_result_empty_or_too_large")
        return dict(status=status, text=text, error="" if status == "completed" else "worker_provider_failed", current_step="")
    finally:
        server.close()


def main():
    try:
        path = Path(sys.argv[1])
        if path.stat().st_size > 512 * 1024 + 4096:
            raise ValueError("worker_request_too_large")
        request = json.loads(path.read_text(encoding="utf-8"))
        report = execute(request)
    except Exception as error:
        # Do not leak provider stderr, paths or credentials into remote receipts.
        code = str(error) if isinstance(error, ValueError) and str(error).startswith("worker_") else "worker_provider_execution_failed"
        report = dict(status="failed", text="", error=code[:256], current_step="")
    sys.stdout.write(json.dumps(report, ensure_ascii=False, allow_nan=False))
    sys.stdout.flush()


if __name__ == "__main__":
    main()
