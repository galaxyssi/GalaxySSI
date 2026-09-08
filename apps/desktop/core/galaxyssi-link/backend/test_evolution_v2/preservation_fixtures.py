"""Explicit unrestricted source compiler for tests of other acceptance stages."""
import json


def unrestricted(messages, **kwargs):
    source = json.loads(messages[-1]["content"])
    requirement = source["requirements"][0]
    return json.dumps({"files": {path: {"preservation": "none",
        "source_requirement_id": requirement["id"], "source_quote": requirement["text"],
        "reason": "Controlled compiler fixture; source classification is tested separately"}
        for path in source["paths"]}})
