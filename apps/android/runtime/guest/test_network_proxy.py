import base64
import socket
import unittest
from unittest import mock

import galaxyssi_network_proxy as proxy


class NetworkProxyPolicyTest(unittest.TestCase):
    def test_allowlist_accepts_exact_and_subdomains_only(self):
        allowed = ("maven.google.com", "repo1.maven.org")
        self.assertTrue(proxy.domain_allowed("maven.google.com", allowed))
        self.assertTrue(proxy.domain_allowed("dl.maven.google.com", allowed))
        self.assertFalse(proxy.domain_allowed("maven.google.com.example.org", allowed))
        self.assertFalse(proxy.domain_allowed("example.org", allowed))
        with self.assertRaisesRegex(ValueError, "invalid"):
            proxy.normalize_domain("invalid_domain.example")

    def test_resolver_rejects_direct_and_resolved_private_addresses(self):
        with self.assertRaisesRegex(ValueError, "Direct IP"):
            proxy.resolve_public_address("127.0.0.1", 443)
        answer = [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("10.0.0.4", 443))]
        with mock.patch.object(proxy.socket, "getaddrinfo", return_value=answer) as resolver:
            with self.assertRaisesRegex(ValueError, "public address"):
                proxy.resolve_public_address("example.org", 443)
        self.assertEqual(socket.AF_INET, resolver.call_args.kwargs["family"])

    def test_proxy_requires_per_task_basic_authentication(self):
        instance = proxy.AllowlistedHttpProxy(["example.org"], "test-token", 1024)
        try:
            expected = base64.b64encode(b"galaxyssi:test-token").decode("ascii")
            self.assertTrue(instance.authorize(f"Basic {expected}"))
            self.assertFalse(instance.authorize("Basic wrong"))
        finally:
            instance._server.server_close()

    def test_proxy_environment_configures_common_clients_and_gradle(self):
        instance = proxy.AllowlistedHttpProxy(["example.org"], "test-token", 1024)
        environment = instance.start().values
        try:
            self.assertIn("galaxyssi:test-token@127.0.0.1:", environment["HTTPS_PROXY"])
            self.assertIn("-Dhttps.proxyHost=127.0.0.1", environment["GRADLE_OPTS"])
            self.assertIn("-Djdk.http.auth.tunneling.disabledSchemes=", environment["GRADLE_OPTS"])
        finally:
            instance.close()


if __name__ == "__main__":
    unittest.main()
