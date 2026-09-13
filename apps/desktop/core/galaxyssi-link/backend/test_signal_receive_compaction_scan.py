"""Query-work regression, not a model/transport timing benchmark."""
from contextlib import closing
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import link_delivery as delivery
import signal_receive_compaction as compaction


class CompactionScanTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="galaxyssi-compaction-query-")
        self.addCleanup(temp.cleanup)
        override = patch.object(delivery, "DB_PATH", Path(temp.name) / "delivery.db")
        override.start()
        self.addCleanup(override.stop)

    def test_small_completed_history_does_not_get_scanned_on_each_new_message(self):
        with closing(delivery._connect()) as db:
            # These are schema-only rows, not fabricated native acceptance proof.
            # Their bodies are deliberately unreadable; none qualifies for compaction.
            db.executemany("INSERT INTO inbound_signal_bodies VALUES(?,?,?,?,?,?)",
                (("peer", f"m-{i}", "a" * 64, "not-a-receive-body", 1000, i) for i in range(10000)))
            db.executemany("""INSERT INTO inbound_messages
                (client_route_id,message_id,received_at,status,dispatch_state) VALUES(?,?,?,'RX_STORED','dispatched')""",
                (("peer", f"m-{i}", i) for i in range(10000)))
            db.commit()
            traced = Mock(wraps=db)
            with patch.object(compaction, "compact_in_transaction") as compact:
                compaction.compact_backlog(traced, "peer")
                compact.assert_not_called()
            sql, args = traced.execute.call_args.args
            plan = " ".join(row[-1] for row in db.execute("EXPLAIN QUERY PLAN " + sql, args))
            operations = [0]
            def count_steps():
                operations[0] += 100
                return 0
            db.set_progress_handler(count_steps, 100)
            try:
                self.assertEqual([], db.execute(sql, args).fetchall())
            finally:
                db.set_progress_handler(None, 0)
            print(f"COMPACTION_QUERY_VM_STEPS={operations[0]} PLAN={plan}", flush=True)
            self.assertLess(operations[0], 1000, "Small completed history was scanned")
            self.assertIn("signal_large_body_candidates", plan)
            self.assertNotIn("TEMP B-TREE", plan)

    def test_large_candidates_keep_peer_scope_order_and_page_bound(self):
        with closing(delivery._connect()) as db:
            for peer, mid, size, created, state in (
                ("peer", "newer", compaction.MIN_BODY_BYTES + 1, 4, "dispatched"),
                ("peer", "older", compaction.MIN_BODY_BYTES, 2, "dispatched"),
                ("peer", "next", compaction.MIN_BODY_BYTES, 5, "dispatched"),
                ("peer", "tiny", compaction.MIN_BODY_BYTES - 1, 0, "dispatched"),
                ("peer", "running", compaction.MIN_BODY_BYTES, 0, "running"),
                ("other", "private", compaction.MIN_BODY_BYTES, 0, "dispatched"),
            ):
                db.execute("INSERT INTO inbound_signal_bodies VALUES(?,?,?,?,?,?)", (peer, mid, "a" * 64, "schema fixture", size, created))
                db.execute("""INSERT INTO inbound_messages
                    (client_route_id,message_id,received_at,status,dispatch_state) VALUES(?,?,?,'RX_STORED',?)""",
                    (peer, mid, created, state))
            with patch.object(compaction, "compact_in_transaction") as compact:
                compaction.compact_backlog(db, "peer", limit=2)
            self.assertEqual(["older", "newer"], [call.args[2] for call in compact.call_args_list])
            self.assertTrue(all(call.args[1] == "peer" for call in compact.call_args_list))

    def test_existing_database_gets_index_without_erasing_rows(self):
        with closing(delivery._connect()) as db:
            db.execute("DROP INDEX signal_large_body_candidates")
            db.execute("INSERT INTO inbound_signal_bodies VALUES('peer','id','hash','body',100,1)")
            db.commit()
        with closing(delivery._connect()) as db:
            self.assertIsNotNone(db.execute("SELECT name FROM sqlite_master WHERE name='signal_large_body_candidates'").fetchone())
            self.assertEqual(1, db.execute("SELECT count(*) FROM inbound_signal_bodies").fetchone()[0])


if __name__ == "__main__":
    unittest.main()
