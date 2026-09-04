"""Prompts that separate implementer, reviewer and research evidence roles."""
from __future__ import annotations

from pathlib import Path

from .common import state_root
from .storage import EvolutionV2Store


def default_evolution_patch_agent(task, attempt, worktree: Path, previous_failure: str) -> str:
    """Invoke the configured CLI coding Agent inside the disposable worktree."""
    from agent_gateway import ask_evolution_agent

    store = EvolutionV2Store(state_root() / "evolution" / "v2")
    metadata = store.get_task_metadata(task.task_id)
    evidence: list[str] = []
    if metadata is not None:
        for run_id in metadata.research_run_ids[:5]:
            run = store.get_research(run_id)
            if run is None:
                continue
            for item in run.items[:8]:
                evidence.append(
                    f"- {item.repository}: score={item.total_score}, recommendation={item.recommendation}, "
                    f"targets={', '.join(item.integration_targets)}; risks={'; '.join(item.risks) or 'none recorded'}"
                )
    prior_logs: list[str] = []
    prior_attempts = [row for row in task.attempts if row.number < attempt.number]
    if prior_attempts:
        prior = prior_attempts[-1]
        for gate in prior.gates[-4:]:
            if not gate.log_path:
                continue
            try:
                text = Path(gate.log_path).read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            prior_logs.append(f"[{gate.id}]\n{text[-6_000:]}")
    scope = "\n".join(f"- {value}" for value in task.scope)
    acceptance = "\n".join(f"- {value}" for value in task.acceptance)
    reproduction = "\n".join(f"- {value}" for value in task.reproduction_steps) or "- Not supplied"
    retry = ""
    if previous_failure or prior_logs:
        retry = (
            "\nPrevious isolated attempt failed. Diagnose the actual root cause and do not repeat it:\n"
            f"{previous_failure[:6_000]}\n"
            + "\n\n".join(prior_logs)[:16_000]
        )
    dossier = "\n".join(evidence) or "- No technology-radar evidence is attached."
    objective = metadata.objective if metadata else "repair"
    origin = metadata.origin if metadata else "manual"
    prompt = f"""
You are the implementation Agent for GalaxySSI Self-Evolution V2 inside a disposable Git worktree.
The independent host, not you, owns Git publishing, immutable gates, review, approval and rollback.

Objective: {objective}
Origin: {origin}
Problem:
{task.problem}

Reproduction:
{reproduction}

Allowed source scope (modify nothing else):
{scope}

Acceptance criteria:
{acceptance}

Attached technology-radar evidence (metadata only; do not clone or execute discovered repositories):
{dossier}
{retry}

Required workflow:
1. Inspect the existing implementation and tests before editing.
2. Write a concise internal repair/implementation plan.
3. Make the smallest coherent change within the declared scope.
4. Add focused regression tests for behavior, failure and rollback paths.
5. Run only focused local checks. Do not use network commands.
6. Leave source changes uncommitted for the host quality-gate suite.

Forbidden:
- Do not push, open a PR, merge, alter Git configuration, edit .git, change workflow files, access credentials,
  weaken authentication/TLS, download binaries, install dependencies, or touch the active production checkout.
- Do not silently import third-party code because it is popular. Reimplement interoperable concepts only after
  checking license, attack surface and fit with current GalaxySSI abstractions.

Finish with a concise summary of files changed, tests added, residual risks and rollback behavior.
""".strip()
    return ask_evolution_agent(
        attempt.agent_id or task.agent_id,
        prompt,
        task_id=f"{task.task_id}-a{attempt.number}",
        working_directory=worktree,
    )
