"""Publish one reviewed feature PR while injecting a lost local create response.

Explicit --allow-publish is required. This tests the post-validation publication
component, not the complete candidate build/review pipeline.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--body-file", type=Path, required=True)
    parser.add_argument("--allow-publish", action="store_true")
    args = parser.parse_args()
    if not args.allow_publish:
        parser.error("--allow-publish is required for this live GitHub test")
    source, state = args.source.resolve(), args.state.resolve()
    production = Path(os.environ.get("APPDATA", Path.home() / ".local/share")) / "GalaxySSI"
    if (state in {source, Path.home().resolve(), production.resolve()}
            or production.resolve() in state.parents):
        parser.error("Use an isolated acceptance state directory")
    os.environ["GALAXYSSI_STATE_DIR"] = str(state)
    sys.path.insert(0, str(source / "apps/desktop/core/galaxyssi-link/backend"))
    from evolution_v2 import legacy
    from evolution_v2.common import atomic_write_json
    from evolution_v2.github_client import GitHubClient
    from evolution_v2.publication import publish_candidate
    from evolution_v2.storage import EvolutionV2Store

    def git(*argv):
        return subprocess.run(["git", *argv], cwd=source, check=True, capture_output=True,
                              text=True, timeout=30).stdout.strip()

    if git("branch", "--show-current") != args.branch or git("status", "--porcelain"):
        parser.error("The reviewed source must be clean and checked out on --branch")
    github = GitHubClient(source)
    if github.current_repository() != args.repository:
        parser.error("The configured origin does not match --repository")
    head = git("rev-parse", "HEAD")
    task = legacy.EvolutionTask("publication-acceptance-" + head[:20], args.title, [], [], [], "low", 1,
                               status="publishing", candidate_branch=args.branch, candidate_commit=head)
    body = args.body_file.read_text(encoding="utf-8")

    class LostResponseRunner(legacy.EvolutionCommandRunner):
        creates = 0
        injected = False

        def run(self, argv, cwd, **kwargs):
            result = super().run(argv, cwd, **kwargs)
            if tuple(argv[:3]) == ("gh", "pr", "create"):
                self.creates += 1
                if result.returncode == 0:
                    self.injected = True
                    raise subprocess.TimeoutExpired(argv[:3], kwargs.get("timeout_seconds", 300))
            return result

    runner = LostResponseRunner()
    manager = SimpleNamespace(github=github, runner=runner,
        v2_store=EvolutionV2Store(state / "evolution/v2"),
        _pull_request_title=lambda task: args.title,
        _pull_request_body=lambda task, attempt: body)
    url = publish_candidate(manager, task, None, source, "main")
    count = runner.creates
    repeated = publish_candidate(manager, task, None, source, "main")
    if repeated != url or runner.creates != count:
        raise RuntimeError("Publication replay did not reuse the same PR")
    evidence = {"head_sha": head, "branch": args.branch, "url": url,
                "create_calls": count, "lost_response_injected": runner.injected,
                "same_pr_reused": True, "component_only": True}
    atomic_write_json(state / "publication-acceptance.json", evidence)
    print(json.dumps(evidence, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
