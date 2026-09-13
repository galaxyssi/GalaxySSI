import subprocess
import unittest
from unittest.mock import Mock

from native_smoke import Worker


class WorkerCleanupTests(unittest.TestCase):
    def worker(self):
        worker = Worker.__new__(Worker)
        worker.label = "owned"
        worker.process = Mock(returncode=0)
        worker.process.poll.return_value = None
        worker.reader = Mock()
        worker.log = Mock()
        worker._kill_tree = Mock()
        return worker

    def test_shutdown_timeout_closes_log_and_preserves_failure(self):
        worker = self.worker()
        worker.process.wait.side_effect = subprocess.TimeoutExpired("owned", 35)
        with self.assertRaisesRegex(AssertionError, "did not stop gracefully"):
            worker.stop()
        worker._kill_tree.assert_called_once_with()
        worker.reader.join.assert_called_once_with(5)
        worker.log.close.assert_called_once_with()

    def test_failed_exit_closes_log_and_preserves_failure(self):
        worker = self.worker()
        worker.process.returncode = 1
        with self.assertRaisesRegex(AssertionError, "cleanup failed"):
            worker.stop()
        worker.log.close.assert_called_once_with()

    def test_already_stopped_worker_does_not_kill_any_process(self):
        worker = self.worker()
        worker.process.poll.return_value = 0
        worker.stop()
        worker._kill_tree.assert_not_called()
        worker.process.stdin.write.assert_not_called()
        worker.log.close.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
