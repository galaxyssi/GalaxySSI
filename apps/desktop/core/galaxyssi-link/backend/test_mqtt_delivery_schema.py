"""Local schema initialization must not recreate historical business effects."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import time
import unittest
from unittest.mock import patch

import link_delivery


class DeliverySchemaTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="galaxyssi-delivery-schema-")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "delivery.db"
        patched = patch.object(link_delivery, "DB_PATH", self.path)
        patched.start()
        self.addCleanup(patched.stop)

    def old_database(self, partial=False):
        with closing(sqlite3.connect(self.path)) as db:
            db.execute("""CREATE TABLE inbound_messages (
                client_route_id TEXT NOT NULL, message_id TEXT NOT NULL, received_at REAL NOT NULL,
                status TEXT NOT NULL, acknowledgement TEXT NOT NULL DEFAULT '{}',
                PRIMARY KEY(client_route_id,message_id))""")
            db.execute("INSERT INTO inbound_messages VALUES('old-pair','old-id',?,'accepted','unchanged')", (time.time(),))
            db.execute("CREATE TABLE delivery_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            db.execute("INSERT INTO delivery_metadata VALUES('secure_storage_version',?)", (link_delivery.SECURE_STORAGE_VERSION,))
            if partial:
                db.execute("ALTER TABLE inbound_messages ADD COLUMN dispatch_state TEXT NOT NULL DEFAULT 'stored'")
                db.execute("UPDATE inbound_messages SET dispatch_state='dispatched'")
            db.commit()

    def test_ack_only_rows_are_preserved_but_never_scheduled_as_new_work(self):
        self.old_database()
        for _ in range(2):
            with closing(link_delivery._connect()) as db:
                self.assertEqual(('accepted', 'unchanged', 'uncertain', 'legacy_record_without_dispatch_proof'),
                    db.execute("SELECT status,acknowledgement,dispatch_state,dispatch_error FROM inbound_messages").fetchone())
                self.assertEqual(0, db.execute("SELECT count(*) FROM inbound_messages WHERE dispatch_state IN ('stored','retry','running')").fetchone()[0])
                self.assertIsNotNone(db.execute("SELECT name FROM sqlite_master WHERE name='inbound_dispatch_pending'").fetchone())

    def test_new_receives_after_upgrade_keep_stored_default(self):
        self.old_database()
        with closing(link_delivery._connect()) as db:
            db.execute("INSERT INTO inbound_messages(client_route_id,message_id,received_at,status) VALUES('new-pair','new-id',2,'RX_STORED')")
            db.commit()
            self.assertEqual(('stored', ''), db.execute("SELECT dispatch_state,dispatch_error FROM inbound_messages WHERE message_id='new-id'").fetchone())

    def test_partial_schema_does_not_erase_existing_dispatch_proof(self):
        self.old_database(partial=True)
        with closing(link_delivery._connect()) as db:
            self.assertEqual(('dispatched', 0, ''), db.execute("SELECT dispatch_state,dispatch_retry_at,dispatch_error FROM inbound_messages").fetchone())

    def test_concurrent_openers_create_one_schema_without_replaying_old_rows(self):
        self.old_database()
        def open_database(_):
            with closing(link_delivery._connect()) as db:
                return db.execute("SELECT dispatch_state FROM inbound_messages").fetchone()[0]
        with ThreadPoolExecutor(max_workers=4) as workers:
            self.assertEqual(['uncertain'] * 8, list(workers.map(open_database, range(8))))


if __name__ == '__main__':
    unittest.main()
