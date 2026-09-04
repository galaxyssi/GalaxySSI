# Headless Swarm

GalaxySSI Desktop can run durable repository work without an open chat window.
The feature is an action in the proactive task runtime, so scheduled and manual
runs share the same persistence, retry, cancellation, recovery, delivery, and
event history.

## Workflows

| Workflow | Repository access | Result |
| --- | --- | --- |
| `pr_review` | Read-only detached worktree | One review from the coordinator |
| `test_repair` | Scoped disposable worktree | Checked local candidate branch |
| `documentation_update` | Documentation-only disposable worktree | Checked local candidate branch |

The active checkout is never used as an Agent working directory. Planning,
specialist investigation, and verification each use detached observer
worktrees. A mutating run has one writer: the coordinator in the candidate
worktree.

## Lifecycle

1. Resolve the configured base and review commits.
2. Create a managed Git worktree outside the source checkout.
3. Ask the coordinator for a bounded plan.
4. Run configured specialists in parallel read-only worktrees.
5. For review, produce one final report and reject any attempted mutation.
6. For repair or documentation work, let only the coordinator edit.
7. Enforce path scope and the changed-file budget.
8. Run `git diff --check` and configured argv-based validation checks.
9. Commit a local candidate branch.
10. Run optional read-only verifiers and produce one final status.

Every phase is recorded in the proactive run event stream. A Desktop restart
requeues incomplete runs. Cancellation is checked between phases and before
host commands.

## Safety

- Validation commands use argv arrays with no shell.
- Only a bounded executable allowlist is accepted.
- Git references and repository-relative paths are validated.
- Protected repository paths cannot be declared as writable scope.
- Documentation runs reject changes outside documentation paths.
- Review runs reset and fail closed if an Agent writes a file.
- Candidates are local-only. The swarm never pushes, opens, or merges a pull
  request by itself.
- Agent conversations are isolated by proactive task, run, and Agent ID.

## Example Action

```json
{
  "kind": "headless_swarm",
  "target_id": "test_repair",
  "prompt": "Repair the failing parser regression and preserve public behavior.",
  "arguments": {
    "repository_root": "C:/work/project",
    "base_ref": "HEAD",
    "scope": ["src", "tests"],
    "acceptance": ["The parser regression test passes."],
    "checks": [
      {
        "argv": ["python", "-m", "unittest", "tests.test_parser"],
        "timeout_seconds": 600
      }
    ]
  },
  "team": [
    {"agent_id": "codex", "role": "coordinator"},
    {"agent_id": "hermes", "role": "specialist"},
    {"agent_id": "claude", "role": "verifier"}
  ]
}
```

