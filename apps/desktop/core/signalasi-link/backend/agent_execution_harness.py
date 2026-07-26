"""Shared execution policy, recovery budget, checkpoints, and artifact finalization."""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import time
import zipfile
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Iterable


class AgentTaskKind(str, Enum):
    CHAT = "chat"
    RESEARCH = "research"
    ARTIFACT = "artifact"
    BUILD = "build"
    INSTALL = "install"
    DEVICE = "device"


class AgentReasoningEffort(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


@dataclass(frozen=True)
class AgentExecutionPolicy:
    task_kind: AgentTaskKind
    reasoning_effort: AgentReasoningEffort
    no_progress_timeout_seconds: float
    max_replans: int
    max_same_failure_attempts: int
    requires_artifact: bool = False
    target_platform: str = ""
    verify_installation: bool = False

    def public(self) -> dict:
        return {
            "task_kind": self.task_kind.value,
            "reasoning_effort": self.reasoning_effort.value,
            "no_progress_timeout_seconds": self.no_progress_timeout_seconds,
            "max_replans": self.max_replans,
            "max_same_failure_attempts": self.max_same_failure_attempts,
            "requires_artifact": self.requires_artifact,
            "target_platform": self.target_platform,
            "verify_installation": self.verify_installation,
            "absolute_timeout_seconds": None,
        }

    @classmethod
    def from_public(cls, value: dict | None) -> "AgentExecutionPolicy":
        value = value or {}
        try:
            task_kind = AgentTaskKind(str(value.get("task_kind") or "chat"))
        except ValueError:
            task_kind = AgentTaskKind.CHAT
        try:
            effort = AgentReasoningEffort(str(value.get("reasoning_effort") or "low"))
        except ValueError:
            effort = AgentReasoningEffort.LOW
        return cls(
            task_kind=task_kind,
            reasoning_effort=effort,
            no_progress_timeout_seconds=max(
                30.0,
                float(value.get("no_progress_timeout_seconds") or 180.0),
            ),
            max_replans=max(0, int(value.get("max_replans") or 0)),
            max_same_failure_attempts=max(
                1,
                int(value.get("max_same_failure_attempts") or 2),
            ),
            requires_artifact=bool(value.get("requires_artifact")),
            target_platform=str(value.get("target_platform") or ""),
            verify_installation=bool(value.get("verify_installation")),
        )


_BUILD_TERMS = (
    "build", "compile", "implement", "develop", "create an app", "create a game",
    "write a program", "make an app", "make a game", "fix bug", "run tests",
    "\u7f16\u8bd1", "\u6784\u5efa", "\u5f00\u53d1", "\u5b9e\u73b0",
    "\u5199\u4e00\u4e2a\u7a0b\u5e8f", "\u505a\u4e00\u4e2a\u6e38\u620f",
    "\u751f\u6210\u7a0b\u5e8f", "\u4fee\u590d bug", "\u8fd0\u884c\u6d4b\u8bd5",
)
_INSTALL_TERMS = (
    "install", "install and open", "install apk", "deploy to phone", "launch the app",
    "\u5b89\u88c5", "\u5b89\u88c5\u5e76\u6253\u5f00", "\u5b89\u88c5 apk",
    "\u5b89\u88c5\u5230\u624b\u673a", "\u7f16\u8bd1\u5e76\u5b89\u88c5",
)
_ARTIFACT_TERMS = (
    "return the file", "send the file", "export", "generate image", "create file",
    "downloadable", "zip project", "apk",
    "\u53d1\u56de\u6587\u4ef6", "\u8fd4\u56de\u6587\u4ef6", "\u5bfc\u51fa",
    "\u751f\u6210\u56fe\u7247", "\u6253\u5305", "\u538b\u7f29\u5305",
)
_RESEARCH_TERMS = (
    "latest", "today", "news", "weather", "research", "search the web",
    "\u6700\u65b0", "\u4eca\u5929", "\u65b0\u95fb", "\u5929\u6c14",
    "\u8c03\u67e5", "\u641c\u7d22", "\u8054\u7f51",
)
_DEVICE_TERMS = (
    "battery", "flashlight", "camera", "alarm", "timer", "phone setting",
    "\u7535\u91cf", "\u624b\u7535\u7b52", "\u6444\u50cf\u5934", "\u62cd\u7167",
    "\u95f9\u949f", "\u8ba1\u65f6\u5668", "\u624b\u673a\u8bbe\u7f6e",
)
_ANDROID_TERMS = (
    "android", "apk", "mobile app", "phone game", "on the phone",
    "\u5b89\u5353", "\u624b\u673a app", "\u624b\u673a\u4e0a\u73a9",
    "\u624b\u673a\u6e38\u620f", "\u5b89\u88c5\u5230\u624b\u673a",
)


def execution_policy_for(
    prompt: str,
    *,
    attachments: Iterable[str] = (),
) -> AgentExecutionPolicy:
    normalized = " ".join(str(prompt or "").lower().split())
    has_attachment_context = bool(tuple(attachments))
    has_install = _contains_any(normalized, _INSTALL_TERMS)
    has_build = _contains_any(normalized, _BUILD_TERMS)
    has_artifact_request = _contains_any(normalized, _ARTIFACT_TERMS)
    has_research = _contains_any(normalized, _RESEARCH_TERMS)
    has_device = _contains_any(normalized, _DEVICE_TERMS)
    target_platform = "android" if _contains_any(normalized, _ANDROID_TERMS) else ""

    if has_install:
        kind = AgentTaskKind.INSTALL
    elif has_build:
        kind = AgentTaskKind.BUILD
    elif has_artifact_request or has_attachment_context:
        kind = AgentTaskKind.ARTIFACT
    elif has_research:
        kind = AgentTaskKind.RESEARCH
    elif has_device:
        kind = AgentTaskKind.DEVICE
    else:
        kind = AgentTaskKind.CHAT

    complex_task = kind in {
        AgentTaskKind.RESEARCH,
        AgentTaskKind.ARTIFACT,
        AgentTaskKind.BUILD,
        AgentTaskKind.INSTALL,
    }
    no_progress_timeout = {
        AgentTaskKind.CHAT: 180.0,
        AgentTaskKind.DEVICE: 120.0,
        AgentTaskKind.RESEARCH: 300.0,
        AgentTaskKind.ARTIFACT: 360.0,
        AgentTaskKind.BUILD: 420.0,
        AgentTaskKind.INSTALL: 420.0,
    }[kind]
    return AgentExecutionPolicy(
        task_kind=kind,
        reasoning_effort=(
            AgentReasoningEffort.MEDIUM if complex_task else AgentReasoningEffort.LOW
        ),
        no_progress_timeout_seconds=no_progress_timeout,
        max_replans=3 if complex_task else 2,
        max_same_failure_attempts=2,
        requires_artifact=(
            has_artifact_request
            or kind in {AgentTaskKind.BUILD, AgentTaskKind.INSTALL}
        ),
        target_platform=target_platform,
        verify_installation=kind == AgentTaskKind.INSTALL,
    )


def execution_contract(policy: AgentExecutionPolicy) -> str:
    target = policy.target_platform or "the requested platform"
    artifact_line = (
        "- Put every final deliverable in the task workspace outputs directory. "
        "A single deliverable stays as its native file; a directory or multi-file project must be packaged as ZIP."
        if policy.requires_artifact else
        "- Only create files when they are useful to the requested result."
    )
    install_line = (
        f"- The target is {target}. Build the native installable artifact, verify its format, "
        "and only claim installation or launch after an execution receipt confirms it."
        if policy.verify_installation else
        "- Verify the requested result before reporting success."
    )
    return "\n".join((
        "SignalASI execution contract:",
        f"- Task class: {policy.task_kind.value}; reasoning effort: {policy.reasoning_effort.value}.",
        "- Work through Plan -> Act -> Observe -> Replan -> Verify -> Finalize.",
        "- Preserve useful work in the task workspace before risky or long-running steps.",
        "- Do not repeat the same failed approach. Diagnose the observed failure and choose a materially different path.",
        artifact_line,
        install_line,
        "- Keep user-facing progress concise, but preserve readable reasoning summaries and concrete tool progress.",
    ))


def replan_instruction(
    policy: AgentExecutionPolicy,
    *,
    failure: str,
    attempt: int,
) -> str:
    return "\n\n".join((
        "The previous execution path did not complete.",
        f"Observed failure class (attempt {attempt}/{policy.max_same_failure_attempts}): {failure[:1_000]}",
        "Inspect the current workspace checkpoint. Preserve valid work, choose a materially different approach, "
        "and continue from the latest verified state. Do not restart the same failing command unchanged.",
        execution_contract(policy),
    ))


def failure_fingerprint(kind: str, message: str) -> str:
    normalized = re.sub(r"\b\d+(?:\.\d+)?\b", "#", str(message or "").lower())
    normalized = re.sub(r"[a-f0-9]{16,}", "<id>", normalized)
    normalized = re.sub(r"\s+", " ", normalized).strip()[:500]
    return hashlib.sha256(f"{kind.strip().lower()}\0{normalized}".encode("utf-8")).hexdigest()[:24]


@dataclass
class AgentExecutionCheckpoint:
    task_id: str
    agent_id: str
    policy: AgentExecutionPolicy
    phase: str = "plan"
    last_progress_at: float = field(default_factory=time.time)
    replans: int = 0
    attempts: int = 0
    failure_counts: dict[str, int] = field(default_factory=dict)
    last_failure: str = ""
    verification: dict = field(default_factory=dict)

    def public(self) -> dict:
        return {
            "version": 1,
            "task_id": self.task_id,
            "agent_id": self.agent_id,
            "policy": self.policy.public(),
            "phase": self.phase,
            "last_progress_at": self.last_progress_at,
            "replans": self.replans,
            "attempts": self.attempts,
            "failure_counts": dict(self.failure_counts),
            "last_failure": self.last_failure,
            "verification": dict(self.verification),
        }


class AgentExecutionHarness:
    def __init__(
        self,
        task_id: str,
        agent_id: str,
        prompt: str,
        *,
        attachments: Iterable[str] = (),
        policy: AgentExecutionPolicy | None = None,
    ) -> None:
        self.policy = policy or execution_policy_for(prompt, attachments=attachments)
        initial = AgentExecutionCheckpoint(
            task_id=str(task_id or "").strip(),
            agent_id=str(agent_id or "").strip(),
            policy=self.policy,
        )
        self.checkpoint = initial
        self.checkpoint = self._load(initial) or initial
        self.checkpoint.policy = self.policy
        self._save()

    def progress(self, phase: str, **verification: object) -> None:
        self.checkpoint.phase = str(phase or "act")
        self.checkpoint.last_progress_at = time.time()
        if verification:
            self.checkpoint.verification.update(verification)
        self._save()

    def begin_attempt(self) -> int:
        self.checkpoint.attempts += 1
        self.progress("act")
        return self.checkpoint.attempts

    def record_failure(self, kind: str, message: str) -> tuple[bool, int]:
        signature = failure_fingerprint(kind, message)
        count = self.checkpoint.failure_counts.get(signature, 0) + 1
        self.checkpoint.failure_counts[signature] = count
        self.checkpoint.last_failure = str(message or "")[:2_000]
        can_replan = (
            count < self.policy.max_same_failure_attempts
            and self.checkpoint.replans < self.policy.max_replans
        )
        if can_replan:
            self.checkpoint.replans += 1
            self.progress("replan")
        else:
            self.progress("failed")
        return can_replan, count

    def _save(self) -> None:
        if not self.checkpoint.task_id:
            return
        encoded = json.dumps(
            self.checkpoint.public(),
            ensure_ascii=False,
            separators=(",", ":"),
        )
        for target in self._checkpoint_paths():
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_suffix(f"{target.suffix}.tmp")
            temporary.write_text(encoded, encoding="utf-8")
            os.replace(temporary, target)

    def _load(
        self,
        initial: AgentExecutionCheckpoint,
    ) -> AgentExecutionCheckpoint | None:
        for target in reversed(self._checkpoint_paths()):
            try:
                value = json.loads(target.read_text(encoding="utf-8"))
            except (OSError, ValueError, TypeError):
                continue
            if (
                str(value.get("task_id") or "") != initial.task_id
                or str(value.get("agent_id") or "") != initial.agent_id
            ):
                continue
            return AgentExecutionCheckpoint(
                task_id=initial.task_id,
                agent_id=initial.agent_id,
                policy=self.policy,
                phase=str(value.get("phase") or "plan"),
                last_progress_at=float(value.get("last_progress_at") or time.time()),
                replans=max(0, int(value.get("replans") or 0)),
                attempts=max(0, int(value.get("attempts") or 0)),
                failure_counts={
                    str(key): max(0, int(count))
                    for key, count in dict(value.get("failure_counts") or {}).items()
                },
                last_failure=str(value.get("last_failure") or "")[:2_000],
                verification=dict(value.get("verification") or {}),
            )
        return None

    def _checkpoint_paths(self) -> tuple[Path, Path]:
        from task_workspace import task_workspace

        root = task_workspace(self.checkpoint.task_id, self.checkpoint.agent_id)
        common = root / ".signalasi" / "execution-checkpoint.json"
        clean_agent = re.sub(
            r"[^A-Za-z0-9._-]+",
            "-",
            self.checkpoint.agent_id,
        ).strip(".-")[:48] or "agent"
        digest = hashlib.sha256(
            self.checkpoint.agent_id.encode("utf-8")
        ).hexdigest()[:8]
        actor = (
            root
            / ".signalasi"
            / "execution-checkpoints"
            / f"{clean_agent}-{digest}.json"
        )
        return common, actor


@dataclass(frozen=True)
class ArtifactFinalization:
    output_files: tuple[dict, ...]
    verification: dict
    packaged: bool = False


def finalize_task_artifacts(
    task_id: str,
    prompt: str,
    agent_id: str,
    *,
    allow_device_install: bool = False,
) -> ArtifactFinalization:
    from task_workspace import task_artifacts, task_workspace

    policy = execution_policy_for(prompt)
    root = task_workspace(task_id, agent_id)
    output_root = root / "outputs"
    output_root.mkdir(parents=True, exist_ok=True)
    packaged = False

    current = task_artifacts(task_id)
    if policy.requires_artifact:
        candidates = _workspace_candidates(root)
        selected_apk = _newest_file(candidates, ".apk")
        if selected_apk is not None:
            delivered = _copy_to_outputs(selected_apk, output_root)
            current = [_artifact_descriptor(root, delivered)]
        else:
            existing_archive = _newest_artifact(current, {".zip", ".apk"})
            if existing_archive is not None:
                current = [existing_archive]
            elif len(candidates) == 1 and candidates[0].is_file():
                delivered = _copy_to_outputs(candidates[0], output_root)
                current = [_artifact_descriptor(root, delivered)]
            elif candidates:
                archive_name = _safe_archive_name(prompt, policy)
                archive = output_root / archive_name
                _package_candidates(root, candidates, archive)
                current = [_artifact_descriptor(root, archive)]
                packaged = True
            elif (
                policy.task_kind in {AgentTaskKind.BUILD, AgentTaskKind.INSTALL}
                and len(current) > 1
            ):
                archive_name = _safe_archive_name(prompt, policy)
                archive = output_root / archive_name
                _package_artifacts(root, current, archive)
                current = [_artifact_descriptor(root, archive)]
                packaged = True

    verification = _verify_outputs(
        root,
        current,
        policy,
        allow_device_install=allow_device_install,
    )
    return ArtifactFinalization(tuple(current), verification, packaged)


def looks_failed_reply(value: str) -> bool:
    text = str(value or "").strip()
    if not text:
        return True
    if not text.startswith("["):
        return False
    normalized = text.lower()
    return any(marker in normalized for marker in (
        "failed", "failure", "timeout", "timed out", "no response",
        "not configured", "not detected", "unavailable",
        "\u5931\u8d25", "\u8d85\u65f6", "\u65e0\u54cd\u5e94",
        "\u672a\u914d\u7f6e", "\u672a\u68c0\u6d4b", "\u4e0d\u53ef\u7528",
    ))


def _contains_any(value: str, terms: Iterable[str]) -> bool:
    return any(term in value for term in terms)


def _workspace_candidates(root: Path) -> list[Path]:
    excluded_parts = {
        ".git", ".gradle", ".idea", ".signalasi", "__pycache__", "node_modules",
        "downloads", "outputs", "temp", "build", "dist",
    }
    candidates: list[Path] = []
    for item in root.iterdir():
        if item.name in {"downloads", "outputs", "temp", "logs", "screenshots", ".signalasi"}:
            continue
        if item.is_file() and not item.name.startswith("."):
            candidates.append(item)
            continue
        if (
            item.is_dir()
            and item.name not in excluded_parts
            and any(source.is_file() and not source.is_symlink() for source in item.rglob("*"))
        ):
            candidates.append(item)
    # Build outputs may contain the requested APK even though caches stay excluded.
    for apk in root.rglob("*.apk"):
        if apk.is_file() and not any(part in {".gradle", ".git"} for part in apk.parts):
            candidates.append(apk)
    unique = {str(item.resolve()).casefold(): item for item in candidates}
    return sorted(unique.values(), key=lambda item: str(item).casefold())


def _newest_file(candidates: Iterable[Path], suffix: str) -> Path | None:
    files = [
        item for item in candidates
        if item.is_file() and item.suffix.lower() == suffix.lower()
    ]
    return max(files, key=lambda item: item.stat().st_mtime, default=None)


def _copy_to_outputs(source: Path, output_root: Path) -> Path:
    target = output_root / source.name
    if source.resolve() != target.resolve():
        shutil.copy2(source, target)
    return target


def _artifact_descriptor(root: Path, source: Path) -> dict:
    return {
        "name": source.name,
        "relative_path": source.relative_to(root).as_posix(),
        "category": source.relative_to(root).parts[0],
        "size": source.stat().st_size,
    }


def _newest_artifact(
    artifacts: Iterable[dict],
    suffixes: set[str],
) -> dict | None:
    matches = [
        dict(item)
        for item in artifacts
        if Path(str(item.get("name") or "")).suffix.lower() in suffixes
    ]
    return max(matches, key=lambda item: int(item.get("size") or 0), default=None)


def _safe_archive_name(prompt: str, policy: AgentExecutionPolicy) -> str:
    target = "android-project" if policy.target_platform == "android" else "project"
    digest = hashlib.sha256(str(prompt or "").encode("utf-8")).hexdigest()[:8]
    return f"{target}-{digest}.zip"


def _package_candidates(root: Path, candidates: list[Path], archive: Path) -> None:
    temporary = archive.with_suffix(".tmp")
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for candidate in candidates:
            if candidate.is_file():
                bundle.write(candidate, candidate.relative_to(root).as_posix())
                continue
            for source in candidate.rglob("*"):
                if not source.is_file() or source.is_symlink():
                    continue
                relative = source.relative_to(root)
                if any(part in {
                    ".git", ".gradle", ".idea", ".signalasi", "__pycache__",
                    "node_modules", "outputs", "temp",
                } for part in relative.parts):
                    continue
                bundle.write(source, relative.as_posix())
    os.replace(temporary, archive)


def _package_artifacts(root: Path, artifacts: Iterable[dict], archive: Path) -> None:
    temporary = archive.with_suffix(".tmp")
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for item in artifacts:
            relative = str(item.get("relative_path") or "").replace("\\", "/")
            source = (root / relative).resolve()
            if source == archive.resolve() or not source.is_file() or source.is_symlink():
                continue
            bundle.write(source, Path(relative).as_posix())
    os.replace(temporary, archive)


def _verify_outputs(
    root: Path,
    output_files: list[dict],
    policy: AgentExecutionPolicy,
    *,
    allow_device_install: bool,
) -> dict:
    results: list[dict] = []
    all_valid = True
    for item in output_files:
        relative = str(item.get("relative_path") or "")
        source = (root / relative).resolve()
        valid = source.is_file() and source.stat().st_size > 0
        detail = "non-empty file"
        if valid and source.suffix.lower() in {".zip", ".apk", ".docx", ".xlsx", ".pptx"}:
            try:
                with zipfile.ZipFile(source) as bundle:
                    invalid_member = bundle.testzip()
                    valid = invalid_member is None
                    detail = "archive integrity passed" if valid else f"damaged member: {invalid_member}"
                    if valid and source.suffix.lower() == ".apk":
                        valid = "AndroidManifest.xml" in bundle.namelist()
                        detail = "APK structure passed" if valid else "AndroidManifest.xml is missing"
            except (OSError, zipfile.BadZipFile) as exc:
                valid = False
                detail = str(exc)[:200]
        all_valid = all_valid and valid
        results.append({
            "relative_path": relative,
            "valid": valid,
            "detail": detail,
            "sha256": _sha256(source) if valid else "",
        })

    installation = {"requested": policy.verify_installation, "status": "not_requested"}
    apk = next((
        (root / str(item.get("relative_path") or "")).resolve()
        for item in output_files
        if str(item.get("relative_path") or "").lower().endswith(".apk")
    ), None)
    if policy.verify_installation:
        if apk is None or not apk.is_file():
            installation = {"requested": True, "status": "missing_apk"}
            all_valid = False
        elif not allow_device_install:
            installation = {"requested": True, "status": "phone_handoff_required"}
        else:
            installation = _verify_android_install(apk)
            all_valid = all_valid and installation["status"] in {
                "installed",
                "phone_handoff_required",
            }

    return {
        "status": "passed" if all_valid and (output_files or not policy.requires_artifact) else "failed",
        "required_artifact": policy.requires_artifact,
        "outputs": results,
        "installation": installation,
    }


def _verify_android_install(apk: Path) -> dict:
    adb = shutil.which("adb")
    if not adb:
        return {"requested": True, "status": "phone_handoff_required", "detail": "adb unavailable"}
    try:
        devices = subprocess.run(
            [adb, "devices"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        connected = [
            line.split()[0]
            for line in devices.stdout.splitlines()[1:]
            if line.strip().endswith("\tdevice")
        ]
        if not connected:
            return {
                "requested": True,
                "status": "phone_handoff_required",
                "detail": "no authorized Android device",
            }
        installed = subprocess.run(
            [adb, "-s", connected[0], "install", "-r", str(apk)],
            capture_output=True,
            text=True,
            timeout=180,
            check=False,
        )
        output = "\n".join((installed.stdout, installed.stderr)).strip()
        return {
            "requested": True,
            "status": "installed" if installed.returncode == 0 and "Success" in output else "install_failed",
            "device": connected[0],
            "detail": output[-500:],
        }
    except Exception as exc:
        return {"requested": True, "status": "install_failed", "detail": str(exc)[:300]}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
