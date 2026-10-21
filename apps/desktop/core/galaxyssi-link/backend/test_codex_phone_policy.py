import unittest
from codex_phone_policy import PHONE_REASONING_POLICY, thread_policy, thread_tools


class PhonePolicyTests(unittest.TestCase):
    def test_phone_research_has_native_tools_without_desktop_mutation_contract(self):
        policy = thread_policy("phone-planner-v1:goal", "Desktop project policy")
        self.assertEqual(PHONE_REASONING_POLICY, policy)
        self.assertIn("directly in this model turn", policy)
        self.assertIn("Do not run Desktop commands", policy)
        self.assertIn("phone-only network access", policy)
        self.assertIn("actual final answer", policy)
        self.assertNotIn("Desktop project policy", policy)

    def test_phone_tool_inventory_excludes_host_mutations(self):
        tools = [{"name": name} for name in (
            "galaxyssi_parallel_web_search", "galaxyssi_fetch_public_pages",
            "research_audit", "office_preview", "collaboration_publish")]
        self.assertEqual(tools[:3], thread_tools("phone-planner-v1:goal", tools))
        self.assertIs(tools, thread_tools("ordinary-desktop-task", tools))
        self.assertEqual("Desktop project policy",
            thread_policy("ordinary-desktop-task", "Desktop project policy"))
