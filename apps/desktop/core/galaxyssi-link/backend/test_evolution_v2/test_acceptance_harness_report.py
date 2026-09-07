"""Live-harness success must not depend on stale manifest milestones."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest


PATH = Path(__file__).resolve().parents[6] / "tools/testing/campaign_acceptance_report.py"
SPEC = importlib.util.spec_from_file_location("campaign_acceptance_report", PATH)
report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(report)


def task(key="current", status="running", url=""):
    value = SimpleNamespace(task_id=key, status=status, pull_request_url=url)
    value.public = lambda: {"task_id": value.task_id, "status": value.status,
                            "pull_request_url": value.pull_request_url}
    return value


def graph(status="active", node_status="running", key="current"):
    return {"status": status, "nodes": {"node": {"status": node_status,
             "action": {"task_id": key}}}, "retired_ids": ["old-node"]}


class AcceptanceHarnessReportTest(unittest.TestCase):
    def observe(self, current=None, dag=None, workers=0, goal_status="materialized", planning=None, outcome=None):
        current = current or task()
        return report.snapshot({"status": goal_status}, dag or graph(),
                               lambda key: current if key == current.task_id else None,
                               workers, planning or {}, lambda _: outcome or {})

    def test_restart_invalidates_stale_ready_and_observation_flags(self):
        record = {"candidate_ready": True, "needs_observation": True, "full_campaign_complete": True,
                  "published": [{"task_id": "retired", "url": "old-pr"}]}
        report.invalidate_cached_milestones(record)
        self.assertFalse(record["candidate_ready"])
        self.assertFalse(record["needs_observation"])
        self.assertFalse(record["full_campaign_complete"])
        self.assertEqual("observing", record["acceptance_stage"])
        self.assertEqual("retired", record["published"][0]["task_id"])

    def test_old_publication_never_terminates_running_replacement(self):
        record = {"published": [{"task_id": "retired", "url": "old-pr"}], "candidate_ready": True}
        record.update(self.observe(workers=1))
        self.assertIsNone(record["exit_code"])
        self.assertFalse(record["candidate_ready"])
        self.assertEqual([], record["current_published_task_ids"])

    def test_current_candidate_is_a_non_success_milestone(self):
        value = self.observe(task(status="waiting_approval"))
        self.assertTrue(value["candidate_ready"])
        self.assertEqual(["current"], value["ready_task_ids"])
        self.assertEqual(2, value["exit_code"])
        self.assertFalse(value["full_campaign_complete"])

    def test_candidate_does_not_stop_other_active_worker(self):
        value = self.observe(task(status="waiting_approval"), workers=1)
        self.assertIsNone(value["exit_code"])

    def test_retired_task_cannot_be_current_candidate(self):
        value = self.observe(task(key="retired", status="waiting_approval"))
        self.assertFalse(value["candidate_ready"])
        self.assertEqual(["current"], value["missing_task_ids"])

    def test_failed_node_does_not_advertise_obsolete_candidate(self):
        value = self.observe(task(status="waiting_approval"), dag=graph(node_status="failed"))
        self.assertFalse(value["candidate_ready"])

    def test_current_published_pr_is_not_completion(self):
        value = self.observe(task(status="published", url="pr"))
        self.assertEqual(3, value["exit_code"])
        self.assertEqual("awaiting_integration", value["acceptance_stage"])
        self.assertFalse(value["full_campaign_complete"])

    def test_publication_does_not_skip_other_running_task(self):
        dag = graph()
        dag["nodes"]["other"] = {"status": "running", "action": {"task_id": "other"}}
        tasks = {"current": task(status="published", url="pr"), "other": task("other")}
        value = report.snapshot({"status": "materialized"}, dag, tasks.get, 0, {}, lambda _: {})
        self.assertIsNone(value["exit_code"])

    def test_waiting_observation_is_recomputed(self):
        value = self.observe(planning={"observations": [{"status": "waiting"}]})
        self.assertEqual(4, value["exit_code"])
        self.assertTrue(value["needs_observation"])
        value.update(self.observe())
        self.assertFalse(value["needs_observation"])
        self.assertIsNone(value["exit_code"])

    def test_unavailable_model_is_not_success(self):
        value = self.observe(goal_status="local_model_unavailable")
        self.assertEqual(4, value["exit_code"])

    def test_completion_requires_current_integrated_outcome(self):
        current = task(status="published", url="pr")
        dag = graph(status="completed", node_status="completed")
        for outcome in ({}, {"stage": "awaiting_integration"},
                        {"stage": "completed", "task_id": "retired", "integration_commit": "a" * 40},
                        {"stage": "completed", "task_id": "current"}):
            with self.subTest(outcome=outcome):
                value = self.observe(current, dag, outcome=outcome)
                self.assertFalse(value["full_campaign_complete"])
                self.assertEqual(1, value["exit_code"])
        outcome = {"stage": "completed", "task_id": "current", "integration_commit": "a" * 40,
                   "pull_request_url": "pr"}
        value = self.observe(current, dag, outcome=outcome)
        self.assertTrue(value["full_campaign_complete"])
        self.assertEqual(0, value["exit_code"])

    def test_integration_requires_matching_url_and_commit_identity(self):
        outcome = {"stage": "completed", "task_id": "current", "integration_commit": "a" * 40,
                   "pull_request_url": "pr"}
        for field, wrong in (("pull_request_url", "old-pr"), ("integration_commit", "main"),
                             ("integration_commit", None)):
            with self.subTest(field=field, wrong=wrong):
                value = self.observe(task(status="published", url="pr"), graph("completed", "completed"),
                                     outcome={**outcome, field: wrong})
                self.assertFalse(value["full_campaign_complete"])

    def test_changed_child_status_invalidates_completed_projection(self):
        value = self.observe(task(status="failed", url="pr"), graph("completed", "completed"),
                             outcome={"stage": "completed", "task_id": "current",
                                      "integration_commit": "a" * 40, "pull_request_url": "pr"})
        self.assertFalse(value["full_campaign_complete"])

    def test_paused_or_cancelled_goal_is_not_a_live_success(self):
        for state in ("paused", "cancelled"):
            with self.subTest(state=state):
                value = self.observe(task(status="published", url="pr"), graph("completed", "completed"),
                                     goal_status=state, outcome={"stage": "completed", "task_id": "current",
                                      "integration_commit": "a" * 40, "pull_request_url": "pr"})
                self.assertFalse(value["full_campaign_complete"])

    def test_completed_graph_without_publication_is_not_publication_acceptance(self):
        value = self.observe(task(status="completed"), graph(status="completed", node_status="completed"))
        self.assertFalse(value["full_campaign_complete"])

    def test_missing_current_task_prevents_completion(self):
        value = self.observe(task(key="retired"), graph(status="completed", node_status="completed"))
        self.assertEqual(1, value["exit_code"])

    def test_empty_completed_graph_does_not_pass(self):
        value = self.observe(dag={"status": "completed", "nodes": {}})
        self.assertEqual(1, value["exit_code"])

    def test_active_worker_prevents_completion(self):
        value = self.observe(task(status="published", url="pr"), graph("completed", "completed"), workers=1,
                             outcome={"stage": "completed", "task_id": "current", "integration_commit": "a" * 40})
        self.assertFalse(value["full_campaign_complete"])
        self.assertIsNone(value["exit_code"])


if __name__ == "__main__":
    unittest.main()
