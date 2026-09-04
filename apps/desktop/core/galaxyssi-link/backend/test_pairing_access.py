from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from pairing_access import (
    DESKTOP_CONTROL,
    DESKTOP_EXECUTOR,
    DESKTOP_EXTERNAL_FILES,
    DESKTOP_NATIVE_TOOLS,
    EXECUTOR_FULL,
    RESTRICTED,
    apply_restricted_agent_boundary,
    grant_binding,
    grant_for_executor,
    normalize_grant,
)


class PairingAccessTests(unittest.TestCase):
    def test_full_executor_grant_contains_every_desktop_scope(self) -> None:
        grant = grant_for_executor(True, issued_at_millis=100)

        self.assertEqual(DESKTOP_EXECUTOR, grant["profile"])
        self.assertTrue(grant["desktop_executor"])
        self.assertIn(EXECUTOR_FULL, grant["scopes"])
        self.assertIn(DESKTOP_CONTROL, grant["scopes"])
        self.assertIn(DESKTOP_NATIVE_TOOLS, grant["scopes"])
        self.assertIn(DESKTOP_EXTERNAL_FILES, grant["scopes"])
        self.assertNotIn("desktop.approval.bypass", grant["scopes"])

    def test_partial_or_self_asserted_executor_grant_fails_closed(self) -> None:
        grant = normalize_grant({
            "profile": DESKTOP_EXECUTOR,
            "desktop_executor": True,
            "scopes": ["agent.chat", "agent.attachments.explicit", EXECUTOR_FULL],
        })

        self.assertEqual(RESTRICTED, grant["profile"])
        self.assertFalse(grant["desktop_executor"])
        self.assertNotIn(EXECUTOR_FULL, grant["scopes"])

    def test_grant_binding_changes_when_the_pairing_consent_changes(self) -> None:
        first = {"access": grant_for_executor(True, issued_at_millis=100)}
        same = {"access": grant_for_executor(True, issued_at_millis=100)}
        replacement = {"access": grant_for_executor(True, issued_at_millis=101)}

        self.assertEqual(grant_binding(first), grant_binding(same))
        self.assertNotEqual(grant_binding(first), grant_binding(replacement))

    def test_restricted_prompt_removes_external_paths_but_keeps_task_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory).resolve()
            allowed = workspace / "downloads" / "input" / "brief.txt"
            prompt = (
                f'Use "{allowed}" and read '
                '"C:\\Users\\agent\\Documents\\private.txt".'
            )

            bounded = apply_restricted_agent_boundary(prompt, workspace)

        self.assertIn(str(allowed), bounded)
        self.assertNotIn("private.txt", bounded)
        self.assertIn("[blocked external Desktop path]", bounded)
        self.assertIn("External Desktop path references removed from this request: 1", bounded)


if __name__ == "__main__":
    unittest.main()
