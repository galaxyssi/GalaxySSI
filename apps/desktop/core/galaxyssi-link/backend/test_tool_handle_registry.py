import unittest

from tool_handle_registry import (
    ToolHandleError,
    ToolHandleRegistry,
    ToolHandleScope,
)


class ToolHandleRegistryTest(unittest.TestCase):
    def setUp(self):
        self.clock = [100.0]
        self.registry = ToolHandleRegistry(
            now=lambda: self.clock[0],
            max_handles=4,
        )
        self.scope = ToolHandleScope("phone-a", "conversation-a")

    def create(self, **kwargs):
        return self.registry.create(
            kind=kwargs.pop("kind", "browser"),
            resource_id=kwargs.pop("resource_id", "browser-resource"),
            scope=kwargs.pop("scope", self.scope),
            capabilities=kwargs.pop("capabilities", {"browser.navigate"}),
            **kwargs,
        )

    def test_create_resolve_and_reuse_opaque_handle(self):
        first = self.create(metadata={"mode": "isolated"})
        second = self.create(metadata={"mode": "isolated"})

        self.assertEqual(first["handle_id"], second["handle_id"])
        self.assertNotIn("browser-resource", first["handle_id"])
        resolved = self.registry.resolve(
            first["handle_id"],
            kind="browser",
            scope=self.scope,
            required_capability="browser.navigate",
        )
        self.assertEqual("browser-resource", resolved["resource_id"])
        self.assertEqual(1, resolved["use_count"])

    def test_owner_context_kind_and_capability_are_enforced(self):
        handle = self.create()

        cases = (
            (
                {"kind": "browser", "scope": ToolHandleScope("phone-b", "conversation-a")},
                "tool_handle_owner_mismatch",
            ),
            (
                {"kind": "browser", "scope": ToolHandleScope("phone-a", "conversation-b")},
                "tool_handle_context_mismatch",
            ),
            (
                {"kind": "desktop_session", "scope": self.scope},
                "tool_handle_kind_mismatch",
            ),
            (
                {
                    "kind": "browser",
                    "scope": self.scope,
                    "required_capability": "browser.download",
                },
                "tool_handle_capability_denied",
            ),
        )
        for arguments, code in cases:
            with self.subTest(code=code):
                with self.assertRaises(ToolHandleError) as raised:
                    self.registry.resolve(handle["handle_id"], **arguments)
                self.assertEqual(code, raised.exception.code)

    def test_expiry_is_explicit_and_retryable(self):
        handle = self.create(ttl_seconds=5)
        self.clock[0] += 6

        with self.assertRaises(ToolHandleError) as raised:
            self.registry.resolve(
                handle["handle_id"],
                kind="browser",
                scope=self.scope,
            )

        self.assertEqual("tool_handle_expired", raised.exception.code)
        self.assertTrue(raised.exception.retryable)
        self.assertEqual(1, self.registry.status()["metrics"]["expired"])

    def test_release_and_resource_revocation(self):
        first = self.create(resource_id="one")
        self.create(resource_id="two")

        self.assertTrue(self.registry.release(first["handle_id"], scope=self.scope))
        self.assertEqual(1, self.registry.revoke_resource("browser", "two"))
        self.assertEqual(0, self.registry.status()["active_count"])

    def test_capacity_evicts_least_recently_used_handle(self):
        handles = []
        for index in range(4):
            handles.append(self.create(resource_id=f"resource-{index}"))
            self.clock[0] += 1
        self.registry.resolve(
            handles[0]["handle_id"],
            kind="browser",
            scope=self.scope,
        )
        created = self.create(resource_id="resource-new")

        self.assertEqual(4, self.registry.status()["active_count"])
        self.assertTrue(created["handle_id"])
        with self.assertRaises(ToolHandleError):
            self.registry.resolve(
                handles[1]["handle_id"],
                kind="browser",
                scope=self.scope,
            )


if __name__ == "__main__":
    unittest.main()
