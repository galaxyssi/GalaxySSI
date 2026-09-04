"""SLSA-inspired candidate provenance and optional Sigstore/Cosign signing."""
from __future__ import annotations

import json
import os
import platform
import subprocess
from pathlib import Path
from typing import Any

from .common import atomic_write_json, now_millis, sha256_file, stable_json
from .runner import SafeRunner


class ProvenanceWriter:
    def __init__(self, root: Path, runner: SafeRunner | None = None) -> None:
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)
        self.runner = runner or SafeRunner()

    def write(
        self,
        *,
        task: Any,
        attempt: Any,
        candidate_commit: str,
        source_root: Path,
    ) -> Path:
        subject = {
            "name": "GalaxySSI evolution candidate",
            "digest": {"gitCommit": candidate_commit},
        }
        gates = [
            {
                "id": gate.id,
                "status": gate.status,
                "exit_code": gate.exit_code,
                "duration_millis": gate.duration_millis,
                "evidence_sha256": getattr(gate, "evidence_sha256", ""),
                "evidence_manifest_sha256": getattr(
                    gate,
                    "evidence_manifest_sha256",
                    "",
                ),
            }
            for gate in attempt.gates
        ]
        statement = {
            "_type": "https://in-toto.io/Statement/v1",
            "subject": [subject],
            "predicateType": "https://slsa.dev/provenance/v1",
            "predicate": {
                "buildDefinition": {
                    "buildType": "https://galaxyssi.org/evolution/worktree/v2",
                    "externalParameters": {
                        "task_id": task.task_id,
                        "risk_level": task.risk_level,
                        "scope": task.scope,
                        "acceptance": task.acceptance,
                    },
                    "resolvedDependencies": [
                        {"uri": "git+origin", "digest": {"gitCommit": task.base_commit}},
                    ],
                },
                "runDetails": {
                    "builder": {"id": "GalaxySSI Desktop Self-Evolution V2"},
                    "metadata": {
                        "invocationId": f"{task.task_id}/attempt-{attempt.number}",
                        "startedOnMillis": attempt.started_at_millis,
                        "finishedOnMillis": attempt.completed_at_millis or now_millis(),
                    },
                    "byproducts": [
                        {"name": "quality-gates", "content": gates},
                        {"name": "changed-files", "content": attempt.changed_files},
                    ],
                },
            },
            "galaxyssi": {
                "protocol": "galaxyssi.evolution-provenance.v2",
                "host": {
                    "platform": platform.platform(),
                    "python": platform.python_version(),
                },
                "approval_hash": getattr(task, "approval_hash", ""),
            },
        }
        target = self.root / f"{task.task_id}-{candidate_commit[:12]}.intoto.json"
        atomic_write_json(target, statement)
        digest_path = target.with_suffix(target.suffix + ".sha256")
        digest_path.write_text(f"{sha256_file(target)}  {target.name}\n", encoding="utf-8")
        return target

    def sign_blob_keyless(self, path: Path, *, enabled: bool = False) -> dict[str, Any]:
        if not enabled:
            return {"signed": False, "reason": "Keyless signing is disabled by policy."}
        if not self.runner.which("cosign"):
            return {"signed": False, "reason": "cosign is not installed."}
        bundle = Path(path).with_suffix(Path(path).suffix + ".sigstore.json")
        result = self.runner.run(
            ("cosign", "sign-blob", "--yes", "--bundle", str(bundle), str(path)),
            Path(path).parent,
            timeout_seconds=300,
        )
        return {
            "signed": result.ok,
            "bundle": str(bundle) if result.ok else "",
            "summary": result.stdout[-2_000:],
        }
