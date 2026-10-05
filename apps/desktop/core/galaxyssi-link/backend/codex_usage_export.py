"""Local metadata-only audit export. Does not start Desktop, Codex or a model."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from agent_provider_usage import AgentProviderUsage
from agent_task_recovery_query import IDENTITY_FIELDS
from agent_tool_evidence import canonical, valid_identity
from codex_provider_usage import MAX_COUNTER


def collect(database: Path, scope: dict) -> dict:
    fields = {key: scope.get(key) for key in IDENTITY_FIELDS}
    generation = scope.get("execution_generation")
    if (not valid_identity(fields) or fields["agent_id"] != "codex" or type(generation) is not int
            or not 1 <= generation <= MAX_COUNTER):
        raise ValueError("An exact Codex task identity and execution_generation are required")
    archive = AgentProviderUsage(database)
    request = {**fields, "execution_generation": generation}
    first = archive.query(request, client_route_id=fields["client_route_id"])
    if first is None or first["status"] != "ready":
        raise ValueError("No usage journal is available for this exact execution")
    upper = first["observed_through_sequence"]
    page, entries = first, list(first["entries"])
    while page["has_more"]:
        page = archive.query({**request, "after_sequence": page["next_sequence"], "through_sequence": upper},
                             client_route_id=fields["client_route_id"])
        if page is None or page["status"] != "ready" or page["observed_through_sequence"] != upper:
            raise ValueError("Usage journal changed or became unavailable during export")
        entries.extend(page["entries"])
    if [item["sequence"] for item in entries] != list(range(1, upper + 1)):
        raise ValueError("Usage journal sequence is incomplete; export rejected")
    report = {key: value for key, value in first.items() if key not in {"entries", "has_more", "next_sequence"}}
    report.update(entries=entries, journal_entry_count=len(entries),
                  usage_snapshot_count=sum(item["observation"]["kind"] == "usage_snapshot" for item in entries),
                  entries_sha256=hashlib.sha256(canonical(entries)).hexdigest(),
                  limitations=["Notifications are not unique API response receipts or billing records.",
                               "Thread totals must not be summed or attributed wholly to this task.",
                               "Late, disconnected or unobserved provider events may be missing.",
                               "Requested model is not proof of the model actually served."])
    return report


def export(database: Path, scope: dict, output: Path) -> dict:
    output = Path(output).resolve()
    if any((parent / ".git").exists() for parent in (output.parent, *output.parents)):
        raise ValueError("Private audit exports must be outside Git repositories")
    if output.exists():
        raise FileExistsError("Refusing to overwrite an existing audit")
    report = collect(database, scope)
    encoded = json.dumps(report, ensure_ascii=True, indent=2, allow_nan=False) + "\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8", newline="\n") as destination:
        destination.write(encoded)
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--scope", type=Path, required=True, help="Private JSON containing the exact task identity")
    parser.add_argument("--output", type=Path, required=True, help="New JSON file outside all Git repositories")
    args = parser.parse_args(argv)
    try:
        scope = json.loads(args.scope.read_text(encoding="utf-8"))
        if not isinstance(scope, dict):
            raise ValueError("Scope must be a JSON object")
        report = export(args.database, scope, args.output)
    except Exception as exc:
        parser.exit(1, f"Export failed ({type(exc).__name__}); no model was invoked.\n")
    print(json.dumps({"status": "exported", "journal_entry_count": report["journal_entry_count"],
                      "usage_snapshot_count": report["usage_snapshot_count"],
                      "provider_history_complete": False, "request_count": None, "billed_cost": None}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
