"""Local JVM/Python contract fixture; no model, MQTT or external service."""
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from collaboration_file_artifact import execute


def main():
    mode, directory = sys.argv[1:3]
    root = Path(directory)
    scope = {"desktop_id": "fixture-desktop", "client_route_id": "fixture-route", "contact_id": "fixture-contact",
             "peer_fingerprint": "fixture-phone-key", "local_fingerprint": "fixture-desktop-key",
             "task_id": "fixture-author", "conversation_id": "fixture-group", "turn_id": "fixture-turn",
             "source_message_id": "fixture-message", "agent_id": "codex", "execution_generation": 1}
    if mode in {"publish", "confirm"}:
        args = {"mode": "publish", "path": "outputs/evidence.bin", "milestone_id": "fixture-file-v1", "title": "Complete file fixture"}
        def publish(request):
            if mode == "confirm":
                if request["mode"] != "receipt":
                    raise AssertionError("Recovering a committed file must not republish it")
                return json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
            return {"success": False, "status": "captured_only", "captured_request": request}
        result = execute(root / "store", str(root / "author"), scope, args,
                         publish=publish, recall=lambda _: None, active=lambda: True)
    elif mode == "materialize":
        fixture = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
        result = execute(root / "store", str(root / "peer"), {**scope, "task_id": "fixture-reader"}, fixture["arguments"],
                         publish=lambda _: None, recall=lambda args: fixture["pages"][str(args["offset"])], active=lambda: True)
    else:
        raise ValueError("Unknown fixture operation")
    print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    main()
