import os
import tempfile
import unittest
import zipfile
from unittest.mock import patch

from agent_execution_harness import execution_policy_for, finalize_task_artifacts
from installation_request_policy import installation_request
from task_workspace import task_workspace


class InstallationRequestPolicyTests(unittest.TestCase):
    def test_explicit_android_installations(self):
        for prompt in (
            "Install the Android APK and verify installation",
            "Build and install an Android APK on the phone",
            "Install app-debug.apk", "Install `C:\\build\\app-debug.apk`",
            "Reinstall the app on my Android phone", "deploy to phone",
            "Install the package onto the phone",
            "\u5b89\u88c5\u8fd9\u4e2aAPK", "\u5b89\u88dd\u9019\u500bAPK",
            "\u628a app.apk \u5b89\u88c5\u5230\u624b\u673a", "\u5b89\u88dd\u5230\u624b\u6a5f",
            "\u5b89\u88c5\u5b89\u5353\u5e94\u7528", "\u5b89\u88c5\u5e94\u7528\u5230\u624b\u673a",
        ):
            with self.subTest(prompt=prompt):
                self.assertEqual((True, True), installation_request(prompt))
                self.assertTrue(execution_policy_for(prompt).verify_installation)

    def test_generic_installations_do_not_require_apk(self):
        for prompt in (
            "Install numpy in the local Python environment.",
            "Install a crystal in the simulation. The Android App relays results.",
            "Install a crystal; the instructions are shown on the phone.",
            "Install the sensor on the phone.",
            "Install Firefox on the desktop.",
            "\u5b89\u88c5\u6676\u4f53\uff0c\u5b89\u5353\u5e94\u7528\u63d0\u4f9b\u663e\u793a\u3002",
        ):
            with self.subTest(prompt=prompt):
                self.assertEqual((True, False), installation_request(prompt))
                policy = execution_policy_for(prompt)
                self.assertFalse(policy.verify_installation)
                self.assertFalse(policy.requires_artifact)

    def test_negative_lists_and_launch_are_not_install_requests(self):
        for prompt in (
            "Study a simulation. Do not install software or modify the Android phone.",
            "Do not use the internet, install software, or call paid services.",
            "Never download, compile or install an Android APK.",
            "Do not install the APK, reinstall it or deploy to phone.",
            "Launch the app on the Android phone.",
            "Inspect the installed application.", "Uninstall the package.",
            '{"install": false, "apk": null}',
            "\u4e0d\u8981\u4e0b\u8f7d\u3001\u7f16\u8bd1\u6216\u5b89\u88c5APK",
            "\u7121\u9700\u5b89\u88ddAPK",
        ):
            with self.subTest(prompt=prompt):
                self.assertEqual((False, False), installation_request(prompt))
                self.assertFalse(execution_policy_for(prompt).verify_installation)

    def test_negative_scope_does_not_hide_separate_positive_request(self):
        for prompt in (
            "Do not install dependencies; install the Android APK.",
            "Do not search the web, but install the APK.",
            "Never launch the browser. Install the APK.",
            "\u4e0d\u8981\u5b89\u88c5\u4f9d\u8d56\uff0c\u4f46\u5b89\u88c5\u8fd9\u4e2aAPK",
        ):
            with self.subTest(prompt=prompt):
                self.assertTrue(execution_policy_for(prompt).verify_installation)

    def test_plan_and_screen_modes_still_suppress_installation(self):
        self.assertFalse(execution_policy_for("Plan only: install the APK").verify_installation)
        self.assertFalse(execution_policy_for("Install the APK", request_kind="screen_analysis").verify_installation)

    def test_generic_install_does_not_remove_explicit_build_deliverable(self):
        policy = execution_policy_for("Install numpy and build a data analysis program.")
        self.assertTrue(policy.requires_artifact)
        self.assertFalse(policy.verify_installation)

    def test_research_archive_is_not_failed_for_missing_apk(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}):
            root = task_workspace("research-contract", "codex")
            with zipfile.ZipFile(root / "observations.zip", "w") as bundle:
                bundle.writestr("observations.json", '{"observed": true}')
            result = finalize_task_artifacts(
                "research-contract",
                "Research the simulation, install the crystal, and return the file. The Android App displays results.",
                "codex",
            )
            self.assertEqual("passed", result.verification["status"])
            self.assertFalse(result.verification["installation"]["requested"])

    def test_explicit_android_install_still_fails_without_apk(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {"GALAXYSSI_WORKSPACE_ROOT": temporary}):
            root = task_workspace("missing-apk", "codex")
            (root / "notes.txt").write_text("Not an APK", encoding="utf-8")
            result = finalize_task_artifacts("missing-apk", "Install the Android APK", "codex")
            self.assertEqual("missing_apk", result.verification["installation"]["status"])
            self.assertNotEqual("passed", result.verification["status"])


if __name__ == "__main__":
    unittest.main()
