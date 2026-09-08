"""Direct final-review evidence, excluding generated criteria and historical acceptance claims."""
from .evidence_scope import publication_fields


def pointer(value):
    return str(value).replace("~", "~0").replace("/", "~1")


def original_goal_catalog(evidence):
    catalog = publication_fields(evidence["publications"])
    for node_id, candidate in evidence["candidates"].items():
        prefix = "/candidates/" + pointer(node_id)
        for field in ("base_commit", "candidate_commit", "changed_paths"):
            if field in candidate:
                catalog[prefix + "/" + field] = {"node_id": node_id, "source": "immutable_git",
                    "field": field, "value": candidate[field], "label": field,
                    "description": "Observed immutable Git identity or changed-path list, not proof of file contents."}
        for path, contents in candidate["files"].items():
            for field in ("before", "after"):
                catalog[prefix + "/files/" + pointer(path) + "/" + field] = {
                    "node_id": node_id, "source": "immutable_git", "field": field, "value": contents[field],
                    "label": path + " " + field,
                    "description": "Complete actual " + field + " text at " + path +
                        ". Null means the file does not exist at this revision. Compare before and after for preservation."}
    for node_id, integration in evidence["current_integrations"].items():
        for field in ("ci", "retention_fingerprint", "integration_commit"):
            if field in integration:
                catalog["/integrations/" + pointer(node_id) + "/" + field] = {
                    "node_id": node_id, "source": "current_host_integration", "field": field,
                    "value": integration[field], "label": "Current integration " + field,
                    "description": "Fresh host-verified integration evidence, not PR title/body or source semantics."}
    return catalog
