from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from evolution_v2.research import TechnologyRadar
from evolution_v2.storage import EvolutionV2Store


class FakeGitHub:
    def repository(self, name):
        return metadata(name, stars=10000 if name.startswith("openai/") else 3000)

    def search_repositories(self, query, limit=20):
        return [metadata("unknown/fast-agent", stars=50000), metadata("openai/codex", stars=10000)]


def metadata(name, stars):
    owner, repo = name.split("/", 1)
    return {
        "full_name": name,
        "name": repo,
        "description": "Multi-agent coding agent with MCP, skills, evaluation and durable workflow",
        "html_url": f"https://github.com/{name}",
        "license": {"spdx_id": "Apache-2.0"},
        "stargazers_count": stars,
        "forks_count": max(10, stars // 10),
        "open_issues_count": 20,
        "pushed_at": "2026-07-20T00:00:00Z",
        "archived": False,
        "topics": ["ai-agents", "mcp", "coding-agent"],
    }


class ResearchTests(unittest.TestCase):
    def test_trusted_run_excludes_unknown_owners_and_does_not_execute(self):
        with tempfile.TemporaryDirectory() as root:
            repo = Path(root) / "repo"
            repo.mkdir()
            config = repo / "sources.json"
            config.write_text(
                '{"known_repositories":["openai/codex"],"trusted_organizations":["openai"],"discovery_queries":["agent"]}',
                encoding="utf-8",
            )
            store = EvolutionV2Store(Path(root) / "state")
            radar = TechnologyRadar(repo, store, github=FakeGitHub(), config_path=config)
            run = radar.run(trusted_only=True, limit=10)
            self.assertEqual("completed", run.status)
            self.assertTrue(run.items)
            self.assertTrue(all(item.repository.startswith("openai/") for item in run.items))
            self.assertIn(run.items[0].recommendation, {"adopt", "evaluate", "watch"})
            proposals = radar.proposals(run)
            for proposal in proposals:
                self.assertIn("Do not vendor, install or execute", " ".join(proposal.acceptance))


if __name__ == "__main__":
    unittest.main()
