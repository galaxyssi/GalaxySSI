from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

from agent_run_storage import open_run_database_keepalive


class RunDatabaseKeepaliveTest(unittest.TestCase):
    def test_idle_connection_does_not_hold_transaction_or_block_workers(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "runs.sqlite3"
            keeper = open_run_database_keepalive(path)
            try:
                self.assertFalse(keeper.in_transaction)
                keeper.execute("CREATE TABLE sample (id INTEGER PRIMARY KEY)")
                def write(value):
                    connection = sqlite3.connect(path, timeout=5)
                    try:
                        with connection:
                            connection.execute("INSERT INTO sample VALUES (?)", (value,))
                    finally:
                        connection.close()
                with ThreadPoolExecutor(max_workers=2) as pool:
                    list(pool.map(write, range(10)))
                self.assertEqual(10, keeper.execute("SELECT count(*) FROM sample").fetchone()[0])
                self.assertFalse(keeper.in_transaction)
                connection = sqlite3.connect(path)
                try:
                    with self.assertRaises(ValueError), connection:
                        connection.execute("INSERT INTO sample VALUES (99)")
                        raise ValueError("rollback")
                finally:
                    connection.close()
                self.assertEqual(10, keeper.execute("SELECT count(*) FROM sample").fetchone()[0])
            finally:
                keeper.close()
            connection = sqlite3.connect(path)
            try:
                self.assertEqual(10, connection.execute("SELECT count(*) FROM sample").fetchone()[0])
                self.assertEqual("ok", connection.execute("PRAGMA integrity_check").fetchone()[0])
            finally:
                connection.close()

    def test_committed_data_recovers_after_process_exit_without_close(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "runs.sqlite3"
            script = (
                "import os,sqlite3; from pathlib import Path; "
                "from agent_run_storage import open_run_database_keepalive; "
                f"k=open_run_database_keepalive(Path({str(path)!r})); "
                "k.execute('CREATE TABLE sample (id INTEGER)'); "
                f"w=sqlite3.connect({str(path)!r}); "
                "w.execute('INSERT INTO sample VALUES (1)'); w.commit(); os._exit(0)"
            )
            subprocess.run([sys.executable, "-c", script], cwd=Path(__file__).parent, check=True, timeout=10)
            connection = sqlite3.connect(path)
            try:
                self.assertEqual([(1,)], connection.execute("SELECT * FROM sample").fetchall())
                self.assertEqual("ok", connection.execute("PRAGMA integrity_check").fetchone()[0])
            finally:
                connection.close()
