"""Runtime/log signal ingestion and deterministic repair proposal generation."""
from __future__ import annotations

import re
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from .common import now_millis, sha256_text, state_root
from .models import EvolutionProposal, IssueSignal
from .storage import EvolutionV2Store


@dataclass(frozen=True)
class IssueRule:
    rule_id: str
    pattern: re.Pattern[str]
    title: str
    severity: str
    scope: tuple[str, ...]
    acceptance: tuple[str, ...]


RULES = (
    IssueRule(
        "processing-stuck",
        re.compile(
            r"(?i)(stuck|timeout|timed out).{0,80}"
            r"(processing|\u5904\u7406\u4e2d)|processing.{0,80}(stuck|timeout)"
        ),
        "App processing state does not reach a terminal state",
        "high",
        (
            "apps/android/app/src/main/java/com/galaxyssi/chat",
            "apps/desktop/core/galaxyssi-link/backend/mqtt_bridge.py",
        ),
        (
            "Every visible processing state reaches success, failure, cancellation or timeout.",
            "A duplicate/replayed result cannot keep the UI in processing.",
            "Add a regression test for the exact timeout or replay sequence.",
        ),
    ),
    IssueRule(
        "mqtt-duplicate",
        re.compile(r"(?i)(duplicate|replay|already seen).{0,100}(mqtt|cipher|message)|mqtt.{0,100}(duplicate|replay)"),
        "Duplicate MQTT delivery or replay affected task state",
        "high",
        (
            "apps/android/app/src/main/java/com/galaxyssi/chat",
            "apps/desktop/core/galaxyssi-link/backend/mqtt_bridge.py",
        ),
        (
            "Duplicate envelopes are deduplicated by route and message identity before side effects.",
            "Decryption failures are terminal and do not create repeated visible errors.",
            "Delivery, receive and display acknowledgements remain idempotent.",
        ),
    ),
    IssueRule(
        "route-leak",
        re.compile(r"(?i)(route|client_route_id).{0,100}(mismatch|leak|wrong|missing)"),
        "Message or result crossed a client route boundary",
        "critical",
        (
            "apps/desktop/core/galaxyssi-link/backend/mqtt_bridge.py",
            "apps/android/app/src/main/java/com/galaxyssi/chat",
        ),
        (
            "Every delivery and acknowledgement is scoped by client_route_id, message_id, task_id and conversation_id.",
            "Messages for another route are rejected before UI state mutation.",
            "Add adversarial route-isolation tests.",
        ),
    ),
    IssueRule(
        "android-crash",
        re.compile(r"(?i)(FATAL EXCEPTION|Process: com\.galaxyssi\.chat|ANR in com\.galaxyssi\.chat)"),
        "Android candidate or production App crashed",
        "high",
        ("apps/android/app/src/main", "apps/android/app/src/test", "apps/android/app/src/androidTest"),
        (
            "The captured crash sequence no longer produces a fatal exception or ANR.",
            "A focused unit or instrumentation regression test is included.",
            "Candidate installation test restores the previously installed stable APK.",
        ),
    ),
    IssueRule(
        "desktop-crash",
        re.compile(r"(?i)(uncaught exception|backend exited|renderer process gone|ECONNREFUSED).{0,150}(8765|GalaxySSI|backend)?"),
        "Desktop renderer or backend became unavailable",
        "high",
        ("apps/desktop/src", "apps/desktop/core/galaxyssi-link/backend", "apps/desktop/scripts"),
        (
            "Desktop backend starts in an isolated state directory and /health responds.",
            "Unexpected backend exit is reported and recovered without spawning duplicate processes.",
            "Add a smoke or unit regression test for the triggering failure.",
        ),
    ),
)


class IssueSignalScanner:
    def __init__(self, store: EvolutionV2Store, log_roots: Iterable[Path] = ()) -> None:
        self.store = store
        supplied = [Path(path) for path in log_roots]
        self.log_roots = supplied or [state_root() / "logs", state_root() / "evolution" / "logs"]

    def scan(self, *, max_files: int = 200, max_bytes_per_file: int = 2 * 1024 * 1024) -> list[IssueSignal]:
        discovered: list[IssueSignal] = []
        paths: list[Path] = []
        for root in self.log_roots:
            if root.is_file():
                paths.append(root)
            elif root.is_dir():
                paths.extend(path for path in root.rglob("*") if path.is_file())
        paths.sort(key=lambda path: path.stat().st_mtime if path.exists() else 0, reverse=True)
        for path in paths[:max_files]:
            try:
                size = path.stat().st_size
                with path.open("rb") as stream:
                    if size > max_bytes_per_file:
                        stream.seek(max(0, size - max_bytes_per_file))
                    text = stream.read(max_bytes_per_file).decode("utf-8", errors="replace")
            except OSError:
                continue
            discovered.extend(self.ingest_text(text, source=str(path)))
        return discovered

    def ingest_text(self, text: str, *, source: str = "runtime") -> list[IssueSignal]:
        rows: list[IssueSignal] = []
        for rule in RULES:
            match = rule.pattern.search(str(text or ""))
            if not match:
                continue
            start = max(0, match.start() - 400)
            end = min(len(text), match.end() + 800)
            evidence = " ".join(text[start:end].split())[:2_000]
            fingerprint = sha256_text(f"{rule.rule_id}\n{evidence.casefold()}")[:32]
            existing = next((item for item in self.store.list_issues(500) if item.fingerprint == fingerprint), None)
            if existing:
                existing.last_seen_millis = now_millis()
                existing.occurrences += 1
                existing.evidence = evidence
                self.store.save_issue(existing)
                rows.append(existing)
                continue
            signal = IssueSignal(
                signal_id=f"issue-{uuid.uuid4().hex[:20]}",
                kind=rule.rule_id,
                title=rule.title,
                evidence=evidence,
                severity=rule.severity,
                fingerprint=fingerprint,
                suggested_scope=list(rule.scope),
                suggested_acceptance=list(rule.acceptance),
                source=str(source)[:1_000],
            )
            self.store.save_issue(signal)
            rows.append(signal)
        return rows

    def proposal(self, signal: IssueSignal) -> EvolutionProposal:
        proposal = EvolutionProposal(
            proposal_id=f"proposal-{uuid.uuid4().hex[:20]}",
            title=f"Repair: {signal.title}",
            problem=f"{signal.title}. Evidence: {signal.evidence}",
            scope=signal.suggested_scope,
            acceptance=signal.suggested_acceptance,
            reproduction_steps=[f"Replay or reproduce evidence fingerprint {signal.fingerprint}."],
            risk_level=signal.severity if signal.severity in {"low", "medium", "high", "critical"} else "medium",
            objective="repair",
            origin="diagnostics",
            issue_signal_ids=[signal.signal_id],
        )
        self.store.save_proposal(proposal)
        signal.status = "proposed"
        self.store.save_issue(signal)
        return proposal
