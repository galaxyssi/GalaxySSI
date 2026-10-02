"""Generate a local Android contract fixture through the actual Desktop archive (no network/model)."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import tempfile
import uuid

BACKEND = Path(__file__).resolve().parents[2] / "apps/desktop/core/galaxyssi-link/backend"
sys.path.insert(0, str(BACKEND))
from agent_task_store import AgentTaskStore
from agent_tool_evidence import AgentToolEvidence, completed_tool_observation, task_identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    group = "remote-evidence-cross-language-" + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="galaxyssi-evidence-fixture-") as temporary:
        path = Path(temporary) / "run.db"
        task = dict(task_id="fixture-task", client_route_id="fixture-phone", client_conversation_id=group,
                    client_turn_id="turn", source_message_id="1234", contact_id="fixture-contact", agent_id="codex",
                    conversation_id="fixture-backend", status="running", execution_generation=2, status_seq=1)
        AgentTaskStore(path).upsert(task)
        archive = AgentToolEvidence(path)
        for index, code in enumerate([0, 7]):
            archive.record(task, completed_tool_observation(
                {"type": "commandExecution", "id": f"fixture-{index}", "command": "fixture-only-not-executed",
                 "exitCode": code, "aggregatedOutput": ("Original \u8bc1\u636e\n" * 3000)},
                thread_id="fixture-provider-thread", turn_id="fixture-provider-turn"))
        fields = {**task_identity(task), "execution_generation": 2}

        def query(**selection):
            return archive.query({**fields, "request_id": "fixture-nonce", **selection}, client_route_id="fixture-phone")

        index = query(mode="index", after_sequence=0)
        pages = [query(mode="page", evidence_id=item["evidence_id"], sha256=item["sha256"], page_index=page)
                 for item in index["entries"] for page in range(item["page_count"])]
        output = {"fields": fields, "index": index, "empty_index": query(mode="index", after_sequence=2), "pages": pages}
        args.output.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Wrote {len(index['entries'])} observations / {len(pages)} pages to {args.output}")


if __name__ == "__main__":
    main()
