"""Local JVM/Python contract fixture. No model or network access."""
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from collaboration_text_artifact import execute


def main():
    mode, directory = sys.argv[1:3]
    if mode in {"publish", "confirm"}:
        arguments = {"mode": "publish", "path": "outputs/candidate.py", "milestone_id": "fixture-v1", "title": "Executable fixture"}
        def publish(request):
            if mode == "confirm":
                if request["mode"] != "receipt":
                    raise AssertionError("Recovering committed text must not republish it")
                return json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
            return {"success": True, "captured_request": request}
        result = execute("fixture-author", directory, arguments, publish=publish,
                         recall=lambda _: None, active=lambda: True)
    elif mode == "materialize":
        fixture = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
        def recall(arguments):
            return fixture["pages"][str(arguments["offset"])]
        result = execute("fixture-reader", directory, fixture["arguments"],
                         publish=lambda _: None, recall=recall, active=lambda: True)
    else:
        raise ValueError("Unknown fixture operation")
    print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    main()
