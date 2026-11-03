import unittest
from codex_phone_policy import PHONE_REASONING_POLICY, permits_host_tool, thread_config, thread_policy, thread_sandbox, thread_tools


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

    def test_unmarked_mobile_chat_cannot_inherit_desktop_execution(self):
        scope = "client:identity:phone:conversation"
        self.assertEqual(PHONE_REASONING_POLICY, thread_policy(scope, "Desktop project policy"))
        self.assertIn("Never substitute a web timer", thread_policy(scope, "Desktop project policy"))
        self.assertEqual([], thread_tools(scope, [{"name": "collaboration_publish"}]))

    def test_phone_disables_host_commands_and_apps_but_preserves_native_search(self):
        base = {"web_search": "live"}
        for scope in ("phone-planner-v1:goal", "client:identity:phone:conversation"):
            config = thread_config(scope, base)
            self.assertFalse(config["features.shell_tool"])
            self.assertFalse(config["features.apps"])
            self.assertEqual("live", config["web_search"])
            self.assertEqual("read-only", thread_sandbox(scope, "danger-full-access"))
        self.assertEqual({"web_search": "live"}, base)
        self.assertIs(base, thread_config("desktop-local", base))
        self.assertEqual("workspace-write", thread_sandbox("desktop-local", "workspace-write"))

    def test_host_dispatch_rejects_unadvertised_side_effects(self):
        for scope in ("phone-planner-v1:goal", "client:identity:phone:conversation"):
            self.assertFalse(permits_host_tool(scope, "collaboration_publish"))
            self.assertFalse(permits_host_tool(scope, "office_preview"))
            self.assertTrue(permits_host_tool(scope, "galaxyssi_parallel_web_search"))
        self.assertTrue(permits_host_tool("desktop-local", "collaboration_publish"))
