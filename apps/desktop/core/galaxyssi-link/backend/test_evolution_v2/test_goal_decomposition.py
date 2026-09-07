from __future__ import annotations

import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from agent_run_kernel import AgentRunEventLedger
from agent_task_dag import TaskDagError
from evolution_v2.campaigns import CampaignManager
from evolution_v2.campaign_planner import EvolutionCampaignPlanner
from evolution_v2.local_planning import LocalPlannerUnavailable
from evolution_v2.storage import EvolutionV2Store


class GoalDecompositionTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.store = EvolutionV2Store(self.root / "v2")
        self.tasks, self.starts = {}, []
        def ensure(proposal, campaign_id, task_id):
            return self.tasks.setdefault(task_id, SimpleNamespace(task_id=task_id, status="proposed", last_error=""))
        def start(task_id):
            self.starts.append(task_id)
            self.tasks[task_id].status = "running"
            return self.tasks[task_id]
        self.campaigns = CampaignManager(self.store, task_factory=None, task_ensurer=ensure,
            task_starter=start, task_getter=lambda key: self.tasks[key], run_ledger=AgentRunEventLedger(self.root / "runs.sqlite3"))
        self.manager = SimpleNamespace(v2_store=self.store, campaigns=self.campaigns, audit=Mock(),
            policy=SimpleNamespace(decide=lambda *args: SimpleNamespace(allowed=True)))
        self.config = {"enabled": True, "auto_start_tasks": True}
        proposal = {"title": "Document behavior", "problem": "Update reference documentation", "scope": ["docs"], "acceptance": ["Reference is accurate"]}
        self.plan = {"operation": "plan", "reason": "Update reference before examples", "nodes": [
            {"node_id": "reference", "depends_on": [], "proposal": proposal},
            {"node_id": "examples", "depends_on": ["reference"], "proposal": proposal}]}
        self.infer = Mock(return_value=json.dumps(self.plan))
        self.reopen()
        self.goal = self.goals.create("request-1", "Document feature", "Update reference and examples", auto_start=True)
        self.key = self.goal["campaign_id"]

    def reopen(self):
        self.planner = EvolutionCampaignPlanner(self.manager, lambda: self.config, self.infer)
        self.goals = self.planner.goal_decomposition.goals

    def graph(self):
        return self.campaigns.durable.graph_store.load(self.campaigns.durable.identity(self.key))

    def test_request_is_durable_idempotent_and_not_a_fake_empty_dag(self):
        self.assertIsNone(self.graph())
        self.reopen()
        self.assertEqual(self.goal, self.goals.create("request-1", "Document feature", "Update reference and examples", auto_start=True))
        with self.assertRaises(TaskDagError):
            self.goals.create("request-1", "Different", "Different")
        self.assertEqual(1, len(list(self.goals.pending())))

    def test_plan_creates_reserved_proposals_and_scheduler_dispatches_dependency_order(self):
        self.planner.tick()
        self.assertEqual("materialized", self.goals.load(self.key)["status"])
        self.assertEqual(self.goal["objective"], self.graph()["objective"])
        self.assertEqual(2, len(self.store.list_proposals()))
        self.assertTrue(all(item.status == "campaign_reserved" for item in self.store.list_proposals()))
        self.campaigns.tick(self.key)
        self.assertEqual(1, len(self.starts))
        self.assertEqual("pending", self.graph()["nodes"]["examples"]["status"])
        self.reopen()
        self.planner.tick()
        self.campaigns.tick(self.key)
        self.infer.assert_called_once()
        self.assertEqual(1, len(self.starts))

    def test_decision_saved_before_interruption_is_not_requested_again(self):
        with patch.object(self.planner.goal_decomposition, "materialize", side_effect=SystemExit(23)):
            with self.assertRaises(SystemExit):
                self.planner.tick()
        self.assertEqual("decided", self.goals.load(self.key)["status"])
        self.reopen()
        self.planner.tick()
        self.infer.assert_called_once()
        self.assertIsNotNone(self.graph())

    def test_crash_after_dag_commit_before_goal_projection_does_not_duplicate(self):
        original = self.goals._write
        def write(value, *args, **kwargs):
            if value["status"] == "materialized":
                raise SystemExit(23)
            return original(value, *args, **kwargs)
        with patch.object(self.goals, "_write", side_effect=write):
            with self.assertRaises(SystemExit):
                self.planner.tick()
        before = self.graph()
        self.reopen()
        self.planner.tick()
        self.assertEqual(before, self.graph())
        self.assertEqual(2, len(self.store.list_proposals()))
        self.infer.assert_called_once()

    def test_pause_and_cancel_during_inference_prevent_materialization(self):
        for operation in ("pause", "cancel"):
            if operation == "cancel":
                self.goals.control(self.key, "resume")
            def infer(messages):
                self.goals.control(self.key, operation)
                return json.dumps(self.plan)
            self.infer.side_effect = infer
            self.planner.tick()
            self.assertIsNone(self.graph())
            self.assertEqual("paused" if operation == "pause" else "cancelled", self.goals.load(self.key)["status"])

    def test_disable_during_inference_saves_decision_without_creating_dag(self):
        def infer(messages):
            self.config["enabled"] = False
            return json.dumps(self.plan)
        self.infer.side_effect = infer
        self.planner.tick()
        self.assertIsNone(self.graph())
        self.assertEqual("decided", self.goals.load(self.key)["status"])
        self.config["enabled"] = True
        self.planner.tick()
        self.infer.assert_called_once()
        self.assertIsNotNone(self.graph())

    def test_invalid_graph_does_not_leave_dispatchable_proposals(self):
        self.plan["nodes"][0]["depends_on"] = ["examples"]
        self.infer.return_value = json.dumps(self.plan)
        self.planner.tick()
        self.assertIsNone(self.graph())
        self.assertEqual([], self.store.list_proposals())
        self.assertIn("cycle", self.goals.load(self.key)["validation_feedback"]["detail"])

    def test_policy_rejection_is_an_observation_not_execution(self):
        self.manager.policy.decide = lambda *args: SimpleNamespace(allowed=False)
        self.planner.tick()
        self.assertIsNone(self.graph())
        self.assertEqual([], self.store.list_proposals())
        self.assertEqual("planning_error", self.goals.load(self.key)["status"])

    def test_wait_can_resume_with_user_context(self):
        self.infer.return_value = '{"operation":"wait","reason":"Need target document"}'
        self.planner.tick()
        self.planner.tick()
        self.infer.assert_called_once()
        self.goals.control(self.key, "resume", "The target is docs/reference.md")
        self.infer.return_value = json.dumps(self.plan)
        self.planner.tick()
        self.assertIn("docs/reference.md", self.infer.call_args.args[0][1]["content"])
        self.assertIsNotNone(self.graph())

    def test_missing_model_does_not_fallback_or_change_goal(self):
        self.infer.side_effect = LocalPlannerUnavailable("Not configured")
        self.planner.tick()
        self.assertEqual("local_model_unavailable", self.goals.load(self.key)["status"])
        self.assertIsNone(self.graph())
        self.assertEqual(self.goal["objective"], self.goals.load(self.key)["objective"])

    def test_disabled_evolution_never_infers_initial_goals(self):
        self.config["enabled"] = False
        self.planner.tick()
        self.infer.assert_not_called()
        self.assertEqual("requested", self.goals.load(self.key)["status"])

    def test_direct_planning_entry_also_respects_disabled_runtime(self):
        self.planner.goal_decomposition.plan(self.key, self.infer, lambda: False, self.planner._validate_proposal)
        self.infer.assert_not_called()
        self.assertIsNone(self.graph())

    def test_partial_proposal_write_recovers_same_plan_without_extra_proposals(self):
        from evolution_v2.common import now_millis
        original = self.store.save_proposal
        count = 0
        def save(proposal):
            nonlocal count
            count += 1
            if count == 2:
                raise OSError("Disk temporarily unavailable")
            return original(proposal)
        with patch.object(self.store, "save_proposal", side_effect=save):
            self.planner.tick()
        self.assertIsNone(self.graph())
        self.assertEqual(1, len(self.store.list_proposals()))
        self.assertIsNotNone(self.goals.load(self.key)["decision"])
        self.reopen()
        with patch("evolution_v2.goal_decomposition.now_millis", return_value=now_millis() + 61_000):
            self.planner.tick()
        self.infer.assert_called_once()
        self.assertIsNotNone(self.graph())
        self.assertEqual(2, len(self.store.list_proposals()))

    def test_public_projection_excludes_raw_decisions_and_feedback(self):
        self.infer.return_value = "not JSON"
        self.planner.tick()
        public = self.goals.public(self.goals.load(self.key))
        self.assertNotIn("validation_feedback", public)
        self.assertNotIn("decision", public)

    def test_two_planners_do_not_decompose_the_same_goal_concurrently(self):
        other = EvolutionCampaignPlanner(self.manager, lambda: self.config, self.infer)
        def infer(messages):
            self.assertEqual([], other.tick()["observations"])
            return json.dumps(self.plan)
        self.infer.side_effect = infer
        self.planner.tick()
        self.infer.assert_called_once()

    def test_goal_api_is_loopback_only_and_supports_idempotent_requests(self):
        from fastapi import FastAPI
        from fastapi.testclient import TestClient
        from evolution_v2 import api
        app = FastAPI()
        app.include_router(api.router)
        runtime = SimpleNamespace(campaign_planner=self.planner)
        body = {"request_id": "api-request", "name": "Document", "objective": "Update docs"}
        with patch.object(api, "evolution_v2_runtime", return_value=runtime):
            with TestClient(app) as client:
                created = client.post("/api/evolution/v2/goals", json=body)
                self.assertEqual(200, created.status_code)
                self.assertEqual(created.json(), client.post("/api/evolution/v2/goals", json=body).json())
                self.assertEqual(409, client.post("/api/evolution/v2/goals", json={**body, "objective": "Changed"}).status_code)
                key = created.json()["campaign_id"]
                self.assertEqual("requested", client.get(f"/api/evolution/v2/goals/{key}").json()["status"])
                self.assertEqual("paused", client.post(f"/api/evolution/v2/goals/{key}/control", json={"operation": "pause"}).json()["status"])
                first = client.get("/api/evolution/v2/goals?limit=1").json()
                second = client.get("/api/evolution/v2/goals", params={"limit": 1, **first["next_cursor"]}).json()
                self.assertNotEqual(first["goals"][0]["campaign_id"], second["goals"][0]["campaign_id"])
                self.assertEqual(400, client.get("/api/evolution/v2/goals?before_id=incomplete").status_code)
            with TestClient(app, client=("192.0.2.1", 12345)) as remote:
                self.assertEqual(403, remote.post("/api/evolution/v2/goals", json=body).status_code)

    def test_user_controls_cannot_cancel_a_goal_after_its_dag_has_started(self):
        self.planner.tick()
        before = self.graph()
        with self.assertRaises(TaskDagError):
            self.goals.control(self.key, "cancel")
        self.assertEqual(before, self.graph())


if __name__ == "__main__":
    unittest.main()
