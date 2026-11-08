import unittest
from unittest.mock import Mock, patch

from codex_proxy import codex_proxy_environment


class CodexProxyTest(unittest.TestCase):
    def test_windows_proxy_is_used_without_assuming_a_port(self):
        check = Mock(return_value=False)
        original = {"NO_PROXY": "internal.example"}
        with patch("codex_proxy.system_proxies", return_value={"http": "http://127.0.0.1:8765", "https": "http://127.0.0.1:8765"}):
            env = codex_proxy_environment(original, check)
        self.assertEqual("http://127.0.0.1:8765", env["HTTPS_PROXY"])
        self.assertEqual(env["https_proxy"], env["HTTPS_PROXY"])
        self.assertIn("internal.example", env["NO_PROXY"])
        self.assertIn("127.0.0.1", env["NO_PROXY"])
        self.assertEqual("system", env["GALAXYSSI_CODEX_PROXY_SOURCE"])
        self.assertEqual({"NO_PROXY": "internal.example"}, original)
        check.assert_not_called()

    def test_explicit_override_has_priority(self):
        with patch("codex_proxy.system_proxies") as discover:
            env = codex_proxy_environment({"GALAXYSSI_CODEX_PROXY": "http://explicit:1234", "HTTPS_PROXY": "http://old:1"}, Mock())
        self.assertEqual("http://explicit:1234", env["HTTPS_PROXY"])
        self.assertEqual("explicit", env["GALAXYSSI_CODEX_PROXY_SOURCE"])
        discover.assert_not_called()

    def test_existing_environment_is_not_overwritten(self):
        for key in ("HTTPS_PROXY", "https_proxy", "ALL_PROXY"):
            with self.subTest(key=key), patch("codex_proxy.system_proxies") as discover:
                env = codex_proxy_environment({key: "http://chosen:1234", "no_proxy": "private.example"}, Mock())
                self.assertEqual("http://chosen:1234", env[key])
                self.assertIn("private.example", env["NO_PROXY"])
                discover.assert_not_called()

    def test_direct_network_does_not_invent_a_proxy(self):
        with patch("codex_proxy.system_proxies", return_value={}):
            env = codex_proxy_environment({}, Mock(return_value=False))
        self.assertNotIn("HTTPS_PROXY", env)
        self.assertEqual("direct", env["GALAXYSSI_CODEX_PROXY_SOURCE"])

    def test_legacy_local_fallback_is_retained(self):
        with patch("codex_proxy.system_proxies", return_value={}):
            env = codex_proxy_environment({}, Mock(return_value=True))
        self.assertEqual("http://127.0.0.1:7890", env["HTTPS_PROXY"])

    def test_system_scheme_and_bypass_are_preserved(self):
        with patch("codex_proxy.system_proxies", return_value={"http": "http://one:1", "https": "http://two:2", "no": "*.example"}):
            env = codex_proxy_environment({}, Mock())
        self.assertEqual("http://one:1", env["HTTP_PROXY"])
        self.assertEqual("http://two:2", env["HTTPS_PROXY"])
        self.assertIn("*.example", env["NO_PROXY"])


if __name__ == "__main__":
    unittest.main()
