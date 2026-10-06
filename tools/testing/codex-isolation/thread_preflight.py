"""Model-free validation of an ephemeral thread's experimental capability policy."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import queue
import subprocess
import time
import uuid

import preflight

FORMAT = "galaxyssi.codex-thread-isolation-preflight.v1"
DISABLED_FEATURES = (
    "apps", "plugins", "remote_plugin", "browser_use", "browser_use_external",
    "computer_use", "in_app_browser", "memories", "multi_agent", "multi_agent_v2",
    "hooks", "image_generation", "skill_search", "view_image", "goals",
)
CONFIG = {"web_search": "disabled", "project_doc_max_bytes": 0,
          "features.skip_host_skill_discovery": True,
          **{f"features.{name}": False for name in DISABLED_FEATURES}}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def overrides(values):
    return [key + "=" + json.dumps(value, ensure_ascii=True) for key, value in values.items()]


def config_value(config, dotted):
    current = config
    for part in dotted.split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current


def disabled_servers(response):
    config = response.get("config") if isinstance(response, dict) else None
    if not isinstance(config, dict):
        raise ValueError("effective_config_missing")
    servers = config.get("mcp_servers", {})
    if not isinstance(servers, dict):
        raise ValueError("mcp_config_not_object")
    # Serialize the whole override table: dotted server names are literal keys.
    if any(not isinstance(name, str) or not name or len(name) > 200 or any(ord(c) < 32 for c in name) for name in servers):
        raise ValueError("mcp_name_invalid")
    table = ", ".join(json.dumps(name) + "={enabled=false}" for name in sorted(servers))
    return "mcp_servers={" + table + "}", len(servers)


def skill_rows(response, workspace):
    rows = response.get("data") if isinstance(response, dict) else None
    if (not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict)
            or rows[0].get("cwd") != str(workspace) or rows[0].get("errors") != []
            or not isinstance(rows[0].get("skills"), list)):
        raise ValueError("skill_inventory_incomplete")
    skills = rows[0]["skills"]
    if any(not isinstance(skill, dict) or type(skill.get("enabled")) is not bool for skill in skills):
        raise ValueError("skill_inventory_incomplete")
    return skills


def disabled_skills(response, workspace):
    paths = set()
    for skill in skill_rows(response, workspace):
        value = skill.get("path")
        if (not isinstance(value, str) or not value or len(value) > 4096
                or any(ord(c) < 32 for c in value) or not Path(value).is_absolute()):
            raise ValueError("skill_path_invalid")
        # Match the runtime's reported path exactly. Some versions require
        # SKILL.md rather than the folder documented by the config reference.
        paths.add(value)
    entries = ", ".join("{path=" + json.dumps(path) + ",enabled=false}" for path in sorted(paths))
    return "skills.config=[" + entries + "]", len(paths)


class ThreadClient(preflight.Client):
    MAX_RESPONSE_CHARS = 16 * 1024 * 1024
    METHODS = frozenset({"initialize", "config/read", "thread/start", "thread/unsubscribe",
                         "skills/list", "mcpServerStatus/list", "command/exec"})

    def request(self, method, params, timeout=45):
        if method == "thread/start":
            allowed = {"model", "cwd", "permissions", "approvalPolicy", "config", "ephemeral",
                       "dynamicTools", "environments", "selectedCapabilityRoots", "runtimeWorkspaceRoots",
                       "allowProviderModelFallback"}
            if (not isinstance(params, dict) or set(params) != allowed or params.get("ephemeral") is not True
                    or params.get("approvalPolicy") != "never" or params.get("dynamicTools") != []
                    or params.get("environments") != [] or params.get("selectedCapabilityRoots") != []
                    or params.get("allowProviderModelFallback") is not False
                    or params.get("runtimeWorkspaceRoots") != []
                    or not str(params.get("permissions", "")).startswith("galaxyssi-thread-probe-")):
                raise ValueError("Only bounded ephemeral thread initialization is permitted")
        return super().request(method, params, timeout)


def initialize(client):
    client.request("initialize", {"clientInfo": {"name": "galaxyssi-thread-isolation-probe", "version": "1"},
                                  "capabilities": {"experimentalApi": True}})
    client.write({"jsonrpc": "2.0", "method": "initialized", "params": {}})


def summarize_config(response):
    config = response.get("config") if isinstance(response, dict) else None
    observed = {key: config_value(config, key) for key in CONFIG}
    # Only expected bool/int/enumerated values survive into the report.
    matches = {key: type(observed[key]) is type(expected) and observed[key] == expected for key, expected in CONFIG.items()}
    servers = config.get("mcp_servers", {}) if isinstance(config, dict) else None
    mcp_disabled = isinstance(servers, dict) and all(isinstance(value, dict) and value.get("enabled") is False
                                                   for value in servers.values())
    return {"requested_flags_match": matches, "all_requested_flags_match": all(matches.values()),
            "configured_mcp_count": len(servers) if isinstance(servers, dict) else None,
            "all_configured_mcp_disabled": mcp_disabled}


def start_summary(response, profile, workspace, model, effort):
    value = response if isinstance(response, dict) else {}
    thread = value.get("thread") or {}
    identifier = thread.get("id") if isinstance(thread, dict) else None
    if not isinstance(identifier, str) or not identifier or len(identifier) > 200:
        raise ValueError("ephemeral_thread_identity_missing")
    active = value.get("activePermissionProfile") or {}
    sources = value.get("instructionSources")
    roots = value.get("runtimeWorkspaceRoots")
    return identifier, {
        "thread_id_sha256": digest(identifier),
        "active_profile_matches": isinstance(active, dict) and active.get("id") == profile,
        "approval_policy_never": value.get("approvalPolicy") == "never",
        "requested_model_matches": value.get("model") == model,
        "requested_effort_matches": value.get("reasoningEffort") == effort,
        "no_additional_runtime_roots_reported": roots == [],
        "reported_runtime_root_count": len(roots) if isinstance(roots, list) else None,
        "reported_runtime_roots_sha256": digest(roots),
        "cwd_matches": value.get("cwd") == str(workspace),
        "instruction_source_count": len(sources) if isinstance(sources, list) else None,
        "no_instruction_sources_reported": sources == [],
        "disabled_plugin_ids_are_not_enforcement_evidence": True,
    }


def skill_summary(response, workspace):
    try:
        skills = skill_rows(response, workspace)
    except ValueError:
        return {"status": "unavailable", "reported_skill_count": None, "enabled_skill_count": None}
    return {"status": "observed", "reported_skill_count": len(skills),
            "enabled_skill_count": sum(skill["enabled"] for skill in skills)}


def mcp_summary(response):
    rows = response.get("data") if isinstance(response, dict) else None
    result = {"status": "incomplete", "server_count": len(rows) if isinstance(rows, list) else None,
              "disabled_server_count": None, "tool_count": None, "resource_count": None,
              "resource_template_count": None, "no_enabled_capabilities_reported": False}
    if (not isinstance(rows, list) or response.get("nextCursor") is not None
            or any(not isinstance(row, dict) or not isinstance(row.get("tools"), dict)
                   or not isinstance(row.get("resources"), list) or not isinstance(row.get("resourceTemplates"), list)
                   or row.get("toolsError") is not None for row in rows)):
        return result
    counts = {"disabled_server_count": sum(row.get("runtimeStatus") == "disabled" for row in rows),
              "tool_count": sum(len(row["tools"]) for row in rows),
              "resource_count": sum(len(row["resources"]) for row in rows),
              "resource_template_count": sum(len(row["resourceTemplates"]) for row in rows)}
    result.update(status="observed", **counts)
    result["no_enabled_capabilities_reported"] = (counts["disabled_server_count"] == len(rows)
        and counts["tool_count"] == counts["resource_count"] == counts["resource_template_count"] == 0)
    return result


def run(executable, directory, python, model, effort, *, client_factory=ThreadClient):
    if not isinstance(model, str) or not model.strip() or len(model) > 200 or effort not in {"low", "medium", "high", "xhigh"}:
        raise ValueError("Explicit model and supported effort required")
    executable, python = Path(executable).resolve(strict=True), Path(python).resolve(strict=True)
    if not executable.is_file() or not python.is_file():
        raise ValueError("Executable files required")
    directory = preflight.private_destination(directory)
    directory.mkdir(parents=True, exist_ok=False)
    workspace, sealed, unprotected = directory / "workspace", directory / "sealed", directory / "unprotected"
    workspace.mkdir()
    sealed.mkdir()
    unprotected.mkdir()
    marker = uuid.uuid4().hex
    profile = "galaxyssi-thread-probe-" + marker
    for root in (workspace, sealed, unprotected):
        (root / "canary.txt").write_text(marker, encoding="utf-8")
    flags = overrides({**CONFIG, "model_reasoning_effort": effort})
    policy = preflight.profile_config(profile, python, sealed, "denied-subtree")
    report = {"format": FORMAT, "model_calls": 0, "phone_dispatches": 0,
              "requested_model": model, "requested_effort": effort,
              "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
              "python_sha256": hashlib.sha256(python.read_bytes()).hexdigest(),
              "collector_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "shared_probe_sha256": hashlib.sha256(Path(preflight.__file__).read_bytes()).hexdigest(),
              "requested_flags": CONFIG, "command_boundary": "denied_subtree_not_workspace_only",
              "status": "running", "phase": "prepare", "cases": [], "failure_type": None,
              "ephemeral_thread_started": False, "unsubscribed": False, "cleanup_completed": False,
              "production_turn_isolation_verified": False, "ready_for_blind_efficacy_study": False,
              "started_at_ms": time.time_ns() // 1_000_000}
    client, identifier = None, None
    try:
        # Discover names only in a capability-disabled, model-free process. Never
        # persist config values, endpoint addresses, credentials or skill text.
        client = client_factory(executable, workspace, flags)
        report["phase"] = "discovery_initialize"
        initialize(client)
        report["phase"] = "discovery_config"
        server_override, count = disabled_servers(client.request("config/read", {"cwd": str(workspace), "includeLayers": False}))
        report["discovered_mcp_config_count"] = count
        report["phase"] = "discovery_skills"
        skill_override, count = disabled_skills(client.request("skills/list", {"cwds": [str(workspace)], "forceReload": True}), workspace)
        report["discovered_skill_path_count"] = count
        client.close()
        client = None
        client = client_factory(executable, workspace, [*flags, *policy, server_override, skill_override])
        report["phase"] = "restricted_initialize"
        initialize(client)
        report["phase"] = "restricted_config"
        report["effective_config"] = summarize_config(client.request("config/read", {"cwd": str(workspace), "includeLayers": False}))
        if not report["effective_config"]["all_requested_flags_match"] or not report["effective_config"]["all_configured_mcp_disabled"]:
            raise ValueError("effective_capability_flags_not_verified")
        report["phase"] = "ephemeral_thread_start"
        response = client.request("thread/start", {
            "model": model, "cwd": str(workspace), "permissions": profile, "approvalPolicy": "never",
            "config": {**CONFIG, "model_reasoning_effort": effort}, "ephemeral": True,
            "dynamicTools": [], "environments": [], "selectedCapabilityRoots": [],
            "runtimeWorkspaceRoots": [], "allowProviderModelFallback": False})
        identifier, report["thread"] = start_summary(response, profile, workspace, model, effort)
        report["ephemeral_thread_started"] = True
        required = ("active_profile_matches", "approval_policy_never", "requested_model_matches", "requested_effort_matches",
                    "no_additional_runtime_roots_reported", "cwd_matches", "no_instruction_sources_reported")
        if not all(report["thread"][field] for field in required):
            raise ValueError("thread_policy_not_verified")
        report["phase"] = "capability_inventory"
        report["skills"] = skill_summary(client.request("skills/list", {"cwds": [str(workspace)], "forceReload": True}), workspace)
        report["mcp"] = mcp_summary(client.request("mcpServerStatus/list", {"threadId": identifier}))
        for location, root in (("inside", workspace), ("sealed", sealed), ("unprotected", unprotected)):
            for operation in ("read", "write"):
                path = root / ("canary.txt" if operation == "read" else "write.txt")
                params = {"command": [str(python), "-c", preflight.PROGRAM, operation, str(path), marker],
                          "cwd": str(workspace), "permissionProfile": profile}
                row = {"case": f"{location}_{operation}"}
                report["phase"] = row["case"]
                try:
                    row["observation"] = preflight.classify(client.request("command/exec", params))
                except preflight.RpcError as error:
                    row["observation"] = {"outcome": "inconclusive", "rpc_code": error.code, "diagnostic": error.diagnostic}
                report["cases"].append(row)
        expected = {"inside_read": "allowed", "inside_write": "allowed", "sealed_read": "denied", "sealed_write": "denied",
                    "unprotected_read": "allowed", "unprotected_write": "denied"}
        commands = {row["case"]: row["observation"]["outcome"] for row in report["cases"]}
        report["command_checks_passed"] = commands == expected
        inventories = report["skills"].get("enabled_skill_count") == 0 and report["mcp"]["no_enabled_capabilities_reported"]
        report["no_enabled_capabilities_reported"] = inventories
        report["status"] = "preflight_passed_not_model_verified" if commands == expected and inventories else "incomplete"
        report["phase"] = "complete"
    except (OSError, RuntimeError, ValueError, TypeError, queue.Empty, TimeoutError) as error:
        report.update(status="failed", failure_type=type(error).__name__)
        if client is not None and getattr(client, "reader_failure", None):
            report["reader_failure"] = client.reader_failure
        if isinstance(error, ValueError):
            known = {"effective_capability_flags_not_verified", "thread_policy_not_verified", "ephemeral_thread_identity_missing",
                     "effective_config_missing", "mcp_config_not_object", "mcp_name_invalid",
                     "skill_inventory_incomplete", "skill_path_invalid"}
            report["failure_code"] = str(error) if str(error) in known else "invalid_probe_input"
        elif isinstance(error, preflight.RpcError):
            report["rpc_error_sha256"] = error.message_sha256
            report["rpc_diagnostic"] = error.diagnostic
    finally:
        if client is not None:
            if identifier:
                try:
                    client.request("thread/unsubscribe", {"threadId": identifier})
                    report["unsubscribed"] = True
                except (OSError, RuntimeError, ValueError, queue.Empty, TimeoutError):
                    report["status"] = "cleanup_incomplete"
            try:
                client.close()
                report["cleanup_completed"] = True
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                report["status"] = "cleanup_incomplete"
        else:
            report["cleanup_completed"] = True
        report["finished_at_ms"] = time.time_ns() // 1_000_000
        report["report_sha256"] = digest(report)
        with (directory / "report.json").open("x", encoding="utf-8", newline="\n") as stream:
            stream.write(json.dumps(report, indent=2, ensure_ascii=True, allow_nan=False) + "\n")
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex", type=Path, required=True)
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--effort", required=True)
    args = parser.parse_args(argv)
    try:
        result = run(args.codex, args.output, args.python, args.model, args.effort)
    except (OSError, ValueError, TypeError) as error:
        parser.exit(1, f"Thread preflight failed ({type(error).__name__}); no model invoked.\n")
    print(json.dumps({key: result[key] for key in ("status", "model_calls", "production_turn_isolation_verified")}))
    return 0 if result["status"] == "preflight_passed_not_model_verified" else 2


if __name__ == "__main__":
    raise SystemExit(main())
