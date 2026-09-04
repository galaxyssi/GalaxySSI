"""Signed, append-only reputation evidence for Desktop Agent executions."""
from __future__ import annotations

import hashlib
import json
import math
import os
import threading
import time
from pathlib import Path
from typing import Any, Callable

from galaxyssi_client import (
    desktop_id,
    get_signal_bundle,
    sign_signal_identity,
    verify_signal_identity,
)


TERMINAL_STATES = frozenset({"completed", "failed", "cancelled", "timed_out"})
CAPABILITY_MAP = {
    "conversation": "CHAT",
    "chat": "CHAT",
    "reasoning": "REASONING",
    "web": "LIVE_DATA",
    "live_data": "LIVE_DATA",
    "tools": "TOOL_USE",
    "terminal": "TOOL_USE",
    "mcp": "MCP",
    "skill": "SKILL",
    "skills": "SKILL",
    "local_inference": "LOCAL_INFERENCE",
    "research": "RESEARCH",
    "code": "CODE",
    "tasks": "TASK_EXECUTION",
    "task_execution": "TASK_EXECUTION",
    "automation": "TASK_EXECUTION",
    "files": "TASK_EXECUTION",
    "custom_tools": "TASK_EXECUTION",
    "smart_home": "SMART_HOME",
    "device_control": "DEVICE_CONTROL",
    "knowledge_search": "KNOWLEDGE_SEARCH",
}
OUTCOME_MAP = {
    "completed": "SUCCEEDED",
    "failed": "FAILED",
    "cancelled": "CANCELLED",
    "timed_out": "TIMED_OUT",
}

IdentityProvider = Callable[[], dict[str, str]]
Signer = Callable[[bytes], dict[str, str]]
Verifier = Callable[[bytes, str], bool]


def _canonical_json(value: dict[str, Any]) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def _sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _state_root() -> Path:
    configured = os.environ.get("GALAXYSSI_STATE_DIR", "").strip()
    return Path(configured) if configured else Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI"


def _default_identity() -> dict[str, str]:
    bundle = get_signal_bundle()
    return {
        "signer_id": desktop_id(),
        "signature_key_id": str(bundle.get("identityKeySha256") or "").lower(),
    }


class AgentReputationLedger:
    """Persists verifiable host observations and computes bounded route evidence."""

    def __init__(
        self,
        ledger_path: Path | None = None,
        head_path: Path | None = None,
        *,
        identity_provider: IdentityProvider = _default_identity,
        signer: Signer = sign_signal_identity,
        verifier: Verifier = verify_signal_identity,
        clock: Callable[[], int] = lambda: int(time.time() * 1000),
    ) -> None:
        root = _state_root()
        self._ledger_path = ledger_path or root / "agent-reputation-ledger.jsonl"
        self._head_path = head_path or root / "agent-reputation-head.json"
        self._identity_provider = identity_provider
        self._signer = signer
        self._verifier = verifier
        self._clock = clock
        self._lock = threading.RLock()
        self._records: list[dict[str, Any]] = []
        self._receipts_by_id: dict[str, dict[str, Any]] = {}
        self._receipts_by_task: dict[str, dict[str, Any]] = {}
        self._integrity_ok = True
        self._integrity_reason = "empty"
        self._load()

    def record_task(self, task: dict[str, Any]) -> dict[str, Any] | None:
        status = str(task.get("status") or "").lower()
        if status not in TERMINAL_STATES:
            return None
        task_id = str(task.get("task_id") or "").strip()
        if not task_id:
            return None
        with self._lock:
            existing = self._receipts_by_task.get(task_id)
            if existing is not None:
                return dict(existing)
            if not self._integrity_ok:
                raise RuntimeError(f"Agent reputation ledger integrity failure: {self._integrity_reason}")

            identity = self._identity_provider()
            signer_id = str(identity.get("signer_id") or "").strip()
            signature_key_id = str(identity.get("signature_key_id") or "").lower()
            if not signer_id or len(signature_key_id) != 64:
                raise RuntimeError("Desktop signing identity is unavailable")

            started_at = max(
                1,
                int(task.get("started_at") or task.get("created_at") or self._clock()),
            )
            completed_at = max(started_at, int(task.get("completed_at") or self._clock()))
            raw_agent_id = str(task.get("agent_id") or "desktop-agent").strip()
            contact_id = str(task.get("contact_id") or "").strip()
            subject_agent_id = (
                contact_id
                if contact_id.startswith("desktop_") and ":" in contact_id
                else f"{signer_id}:{raw_agent_id}"
            )
            output_hash = _sha256(str(task.get("result") or "").encode("utf-8")) \
                if str(task.get("result") or "") else ""
            evidence = self._evidence(task)
            evidence_hash = _sha256(_canonical_json(evidence)) if evidence else ""
            run_id = str(task.get("retry_of") or task_id).strip() or task_id
            receipt_id = _sha256(_canonical_json({
                "run_id": run_id,
                "task_id": task_id,
                "agent_id": subject_agent_id,
                "outcome": OUTCOME_MAP[status],
                "completed_at_millis": completed_at,
                "output_hash": output_hash,
                "evidence_hash": evidence_hash,
                "attempt": max(1, int(task.get("attempt") or 1)),
            }))
            receipt = {
                "version": 1,
                "receipt_id": receipt_id,
                "run_id": run_id,
                "task_id_hash": _sha256(task_id.encode("utf-8")),
                "agent_id": subject_agent_id,
                "installation_id": signer_id,
                "executor_failure_domain": signer_id,
                "capabilities": self._capabilities(raw_agent_id),
                "outcome": OUTCOME_MAP[status],
                "provenance": "HOST_OBSERVED",
                "started_at_millis": started_at,
                "completed_at_millis": completed_at,
                "deadline_at_millis": 0,
                "estimated_cost_units": 0,
                "actual_cost_units": 0,
                "output_hash": output_hash,
                "evidence_hash": evidence_hash,
                "signer_id": signer_id,
                "signature_key_id": signature_key_id,
            }
            signed = self._signer(_canonical_json(receipt))
            if (
                str(signed.get("signer_id") or "") != signer_id
                or str(signed.get("signature_key_id") or "").lower() != signature_key_id
                or not str(signed.get("signature") or "")
            ):
                raise RuntimeError("Desktop signing identity changed while recording execution")
            receipt["signature"] = str(signed["signature"])
            self._append(task_id, receipt)
            return dict(receipt)

    def receipt_for_task(self, task_id: str) -> dict[str, Any] | None:
        with self._lock:
            receipt = self._receipts_by_task.get(str(task_id or ""))
            return dict(receipt) if receipt is not None else None

    def snapshot(
        self,
        agent_id: str,
        capabilities: list[str] | tuple[str, ...] | set[str] = (),
        now_millis: int | None = None,
    ) -> dict[str, Any]:
        requested = {
            CAPABILITY_MAP.get(str(value).lower(), str(value).upper())
            for value in capabilities
            if str(value).strip()
        }
        with self._lock:
            latest_by_run: dict[str, dict[str, Any]] = {}
            for receipt in self._receipts_by_id.values():
                if receipt.get("agent_id") != agent_id:
                    continue
                if requested and not requested.intersection(receipt.get("capabilities") or []):
                    continue
                previous = latest_by_run.get(str(receipt.get("run_id") or ""))
                if previous is None or int(receipt["completed_at_millis"]) >= int(previous["completed_at_millis"]):
                    latest_by_run[str(receipt["run_id"])] = receipt
            receipts = list(latest_by_run.values())
            integrity_ok = self._integrity_ok
            integrity_reason = self._integrity_reason
        if not receipts:
            return self._neutral_snapshot(agent_id, integrity_ok, integrity_reason)

        now = int(now_millis or self._clock())
        success_total = 0.0
        evidence_total = 0.0
        latency_total = 0.0
        timeout_runs = 0
        failed_runs = 0
        last_evidence_at = 0
        for receipt in receipts:
            completed_at = int(receipt["completed_at_millis"])
            age = max(0, now - completed_at)
            recency = math.exp(-math.log(2.0) * age / (30 * 24 * 60 * 60 * 1000))
            outcome = str(receipt["outcome"])
            reliability = {
                "SUCCEEDED": 1.0,
                "PARTIAL": 0.6,
                "CANCELLED": 0.5,
                "FAILED": 0.0,
                "TIMED_OUT": 0.0,
                "REJECTED": 0.0,
            }.get(outcome, 0.0)
            outcome_weight = 0.2 if outcome == "CANCELLED" else 1.0
            weight = recency * 0.6 * outcome_weight
            success_total += reliability * weight
            evidence_total += weight
            latency_total += max(
                0,
                completed_at - int(receipt["started_at_millis"]),
            ) * weight
            timeout_runs += int(outcome == "TIMED_OUT")
            failed_runs += int(outcome in {"FAILED", "TIMED_OUT", "REJECTED"})
            last_evidence_at = max(last_evidence_at, completed_at)
        reliability = round((1.4 + success_total) / (2.0 + evidence_total) * 100)
        confidence = round((1.0 - math.exp(-evidence_total / 4.0)) * 100)
        score = max(0, min(100, reliability))
        routing_adjustment = 0 if confidence < 35 else max(
            -12,
            min(12, round((score - 70) * confidence / 100 * 0.45)),
        )
        return {
            "agent_id": agent_id,
            "score": score,
            "confidence": max(0, min(100, confidence)),
            "reliability": score,
            "evaluated_runs": len(receipts),
            "failed_runs": failed_runs,
            "timeout_runs": timeout_runs,
            "average_latency_ms": round(latency_total / evidence_total) if evidence_total else 0,
            "last_evidence_at_millis": last_evidence_at,
            "routing_adjustment": routing_adjustment,
            "ledger_integrity": "verified" if integrity_ok else "invalid",
            "ledger_integrity_reason": integrity_reason,
        }

    def integrity(self) -> dict[str, Any]:
        with self._lock:
            return {
                "ok": self._integrity_ok,
                "reason": self._integrity_reason,
                "records": len(self._records),
                "head": self._records[-1]["record_hash"] if self._records else "",
            }

    def _append(self, task_id: str, receipt: dict[str, Any]) -> None:
        previous_hash = self._records[-1]["record_hash"] if self._records else ""
        record = {
            "version": 1,
            "sequence": len(self._records) + 1,
            "previous_record_hash": previous_hash,
            "task_id": task_id,
            "receipt": receipt,
        }
        record["record_hash"] = _sha256(_canonical_json(record))
        head = self._signed_head(record)
        self._ledger_path.parent.mkdir(parents=True, exist_ok=True)
        with self._ledger_path.open("ab") as handle:
            handle.write(_canonical_json(record) + b"\n")
            handle.flush()
            os.fsync(handle.fileno())
        self._write_head(head)
        self._records.append(record)
        self._receipts_by_id[str(receipt["receipt_id"])] = receipt
        self._receipts_by_task[task_id] = receipt
        self._integrity_ok = True
        self._integrity_reason = "verified"

    def _signed_head(self, record: dict[str, Any]) -> dict[str, Any]:
        identity = self._identity_provider()
        unsigned = {
            "version": 1,
            "sequence": int(record["sequence"]),
            "record_hash": str(record["record_hash"]),
            "updated_at_millis": self._clock(),
            "signer_id": str(identity["signer_id"]),
            "signature_key_id": str(identity["signature_key_id"]).lower(),
        }
        signed = self._signer(_canonical_json(unsigned))
        if (
            str(signed.get("signer_id") or "") != unsigned["signer_id"]
            or str(signed.get("signature_key_id") or "").lower() != unsigned["signature_key_id"]
        ):
            raise RuntimeError("Desktop signing identity changed while committing ledger head")
        return {**unsigned, "signature": str(signed["signature"])}

    def _write_head(self, head: dict[str, Any]) -> None:
        self._head_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self._head_path.with_suffix(self._head_path.suffix + ".tmp")
        with temporary.open("wb") as handle:
            handle.write(_canonical_json(head))
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(self._head_path)

    def _load(self) -> None:
        with self._lock:
            try:
                records = self._read_records()
                self._validate_chain(records)
                self._validate_or_recover_head(records)
            except Exception as exc:
                self._records = []
                self._receipts_by_id = {}
                self._receipts_by_task = {}
                self._integrity_ok = False
                self._integrity_reason = str(exc)[:240] or "validation_failed"
                return
            self._records = records
            self._receipts_by_id = {
                str(record["receipt"]["receipt_id"]): record["receipt"]
                for record in records
            }
            self._receipts_by_task = {
                str(record["task_id"]): record["receipt"]
                for record in records
            }
            self._integrity_ok = True
            self._integrity_reason = "verified" if records else "empty"

    def _read_records(self) -> list[dict[str, Any]]:
        if not self._ledger_path.exists():
            return []
        records: list[dict[str, Any]] = []
        with self._ledger_path.open("rb") as handle:
            for line_number, raw in enumerate(handle, start=1):
                if not raw.strip():
                    continue
                try:
                    value = json.loads(raw)
                except json.JSONDecodeError as exc:
                    raise RuntimeError(f"invalid_record_json:{line_number}") from exc
                if not isinstance(value, dict):
                    raise RuntimeError(f"invalid_record_type:{line_number}")
                records.append(value)
        return records

    @staticmethod
    def _validate_chain(records: list[dict[str, Any]]) -> None:
        previous_hash = ""
        receipt_ids: set[str] = set()
        task_ids: set[str] = set()
        for index, record in enumerate(records, start=1):
            if int(record.get("sequence") or 0) != index:
                raise RuntimeError(f"sequence_mismatch:{index}")
            if str(record.get("previous_record_hash") or "") != previous_hash:
                raise RuntimeError(f"chain_mismatch:{index}")
            expected = dict(record)
            claimed_hash = str(expected.pop("record_hash", ""))
            calculated = _sha256(_canonical_json(expected))
            if claimed_hash != calculated:
                raise RuntimeError(f"record_hash_mismatch:{index}")
            receipt = record.get("receipt")
            if not isinstance(receipt, dict) or not receipt.get("signature"):
                raise RuntimeError(f"receipt_missing:{index}")
            task_id = str(record.get("task_id") or "")
            receipt_id = str(receipt.get("receipt_id") or "")
            if not task_id or str(receipt.get("task_id_hash") or "") != _sha256(task_id.encode("utf-8")):
                raise RuntimeError(f"task_binding_mismatch:{index}")
            if not receipt_id or receipt_id in receipt_ids:
                raise RuntimeError(f"receipt_replay:{index}")
            if task_id in task_ids:
                raise RuntimeError(f"task_replay:{index}")
            receipt_ids.add(receipt_id)
            task_ids.add(task_id)
            previous_hash = claimed_hash

    def _validate_or_recover_head(self, records: list[dict[str, Any]]) -> None:
        if not records:
            if self._head_path.exists():
                raise RuntimeError("head_without_ledger")
            return
        if not self._head_path.exists():
            self._verify_receipt_range(records)
            self._write_head(self._signed_head(records[-1]))
            return
        try:
            head = json.loads(self._head_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            raise RuntimeError("invalid_head") from exc
        if not isinstance(head, dict):
            raise RuntimeError("invalid_head")
        unsigned = {key: head.get(key) for key in (
            "version",
            "sequence",
            "record_hash",
            "updated_at_millis",
            "signer_id",
            "signature_key_id",
        )}
        if not self._verifier(_canonical_json(unsigned), str(head.get("signature") or "")):
            raise RuntimeError("head_signature_invalid")
        head_sequence = int(head.get("sequence") or 0)
        if head_sequence <= 0 or head_sequence > len(records):
            raise RuntimeError("ledger_truncated")
        if str(records[head_sequence - 1]["record_hash"]) != str(head.get("record_hash") or ""):
            raise RuntimeError("head_chain_mismatch")
        if head_sequence < len(records):
            self._verify_receipt_range(records[head_sequence:])
            self._write_head(self._signed_head(records[-1]))

    def _verify_receipt_range(self, records: list[dict[str, Any]]) -> None:
        identity = self._identity_provider()
        key_id = str(identity.get("signature_key_id") or "").lower()
        signer_id = str(identity.get("signer_id") or "")
        for record in records:
            receipt = dict(record["receipt"])
            signature = str(receipt.pop("signature", ""))
            if (
                receipt.get("signer_id") != signer_id
                or str(receipt.get("signature_key_id") or "").lower() != key_id
                or not self._verifier(_canonical_json(receipt), signature)
            ):
                raise RuntimeError(f"receipt_signature_invalid:{record.get('sequence')}")

    @staticmethod
    def _evidence(task: dict[str, Any]) -> dict[str, Any]:
        evidence = {
            "status": str(task.get("status") or ""),
            "error": str(task.get("error") or "")[:4_000],
            "exit_code": task.get("exit_code"),
            "artifacts": [
                {
                    "name": str(item.get("name") or ""),
                    "size": int(item.get("size") or 0),
                    "sha256": str(item.get("sha256") or ""),
                }
                for item in list(task.get("output_files") or [])[:100]
                if isinstance(item, dict)
            ],
        }
        return evidence if evidence["error"] or evidence["exit_code"] is not None or evidence["artifacts"] else {}

    @staticmethod
    def _capabilities(agent_id: str) -> list[str]:
        try:
            from agent_gateway import all_agent_specs

            spec = all_agent_specs().get(agent_id)
            raw = tuple(spec.capabilities) if spec is not None else ()
        except Exception:
            raw = ()
        mapped = {
            CAPABILITY_MAP[value.lower()]
            for value in raw
            if value.lower() in CAPABILITY_MAP
        }
        return sorted(mapped or {"CHAT", "TASK_EXECUTION"})

    @staticmethod
    def _neutral_snapshot(agent_id: str, integrity_ok: bool, reason: str) -> dict[str, Any]:
        return {
            "agent_id": agent_id,
            "score": 70,
            "confidence": 0,
            "reliability": 70,
            "evaluated_runs": 0,
            "failed_runs": 0,
            "timeout_runs": 0,
            "average_latency_ms": 0,
            "last_evidence_at_millis": 0,
            "routing_adjustment": 0,
            "ledger_integrity": "verified" if integrity_ok else "invalid",
            "ledger_integrity_reason": reason,
        }


_process_ledger: AgentReputationLedger | None = None
_process_ledger_lock = threading.Lock()


def agent_reputation_ledger() -> AgentReputationLedger:
    global _process_ledger
    if _process_ledger is not None:
        return _process_ledger
    with _process_ledger_lock:
        if _process_ledger is None:
            _process_ledger = AgentReputationLedger()
        return _process_ledger
