from __future__ import annotations

import argparse
import sys
import unittest

from mcp_agent_wrapper import _client_config


class McpAgentWrapperConfigTest(unittest.TestCase):
    def test_server_python_uses_structured_process_arguments(self):
        config = _client_config(
            argparse.Namespace(
                server=None,
                server_python="C:/workspace/fake server.py",
                transport="local_stdio",
                endpoint=None,
                working_directory=None,
                protocol_version=None,
                timeout=20.0,
                stdio_framing="content_length",
                command_argv=(),
                process_environment={},
            )
        )

        self.assertEqual(config.command, "")
        self.assertEqual(config.command_argv, (sys.executable, "C:/workspace/fake server.py"))
        self.assertEqual(config.stdio_framing, "content_length")


if __name__ == "__main__":
    unittest.main()
