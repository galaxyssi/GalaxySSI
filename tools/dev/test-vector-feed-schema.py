"""Execute emitted production Kotlin SQL against actual SQLite; no App files or keys."""
import argparse
import base64
import sqlite3
import time
from pathlib import Path


def verify(schema, count):
    with sqlite3.connect(":memory:") as db:
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("CREATE TABLE knowledge_vector_models(model_key TEXT PRIMARY KEY)")
        db.execute("CREATE TABLE knowledge_items(item_key TEXT PRIMARY KEY)")
        db.execute("CREATE TABLE knowledge_vector_docs(item_key TEXT REFERENCES knowledge_items(item_key) ON DELETE CASCADE,"
                   "model_key TEXT REFERENCES knowledge_vector_models(model_key) ON DELETE CASCADE,revision TEXT,"
                   "chunk_count INTEGER,complete INTEGER,PRIMARY KEY(item_key,model_key))")
        model = "a" * 64
        db.execute("INSERT INTO knowledge_vector_models VALUES(?)", (model,))
        db.executemany("INSERT INTO knowledge_items VALUES(?)", ((f"{i:064x}",) for i in range(count)))
        db.executemany("INSERT INTO knowledge_vector_docs VALUES(?,?,?,1,1)",
                       ((f"{i:064x}", model, "b" * 64) for i in range(count)))
        db.commit()
        callbacks = 0

        def progress():
            nonlocal callbacks
            callbacks += 1
            return 0

        db.set_progress_handler(progress, 100)
        start = time.perf_counter()
        db.execute("BEGIN IMMEDIATE")
        for statement in schema:
            db.execute(statement)
        db.commit()
        elapsed = (time.perf_counter() - start) * 1000
        db.set_progress_handler(None, 0)
        # 100K source rows must not turn this metadata migration into a corpus scan.
        assert callbacks * 100 < 20_000, (count, callbacks)
        assert db.execute("SELECT count(*) FROM knowledge_vector_changes").fetchone()[0] == 0
        assert db.execute("SELECT head,completed_chunks,bootstrap_complete FROM knowledge_vector_feed_state").fetchone() == (0, 0, 0)
        assert db.execute("SELECT count(*) FROM knowledge_vector_docs").fetchone()[0] == count
        print(f"rows={count} schema_ms={elapsed:.3f} vm_steps_approx={callbacks * 100} sqlite={sqlite3.sqlite_version}", flush=True)

        keys = [row[0] for row in db.execute("SELECT item_key FROM knowledge_vector_docs ORDER BY item_key LIMIT 3")]
        for key in keys:
            db.execute("UPDATE knowledge_vector_docs SET feed_tracked=1 WHERE item_key=?", (key,))
        assert db.execute("SELECT completed_chunks FROM knowledge_vector_feed_state").fetchone()[0] == 3
        db.commit()
        db.execute("BEGIN")
        db.execute("DELETE FROM knowledge_items WHERE item_key=?", (keys[0],))
        assert db.execute("SELECT completed_chunks FROM knowledge_vector_feed_state").fetchone()[0] == 2
        db.rollback()
        assert db.execute("SELECT completed_chunks FROM knowledge_vector_feed_state").fetchone()[0] == 3
        db.execute("DELETE FROM knowledge_items WHERE item_key=?", (keys[0],))
        events = list(db.execute("SELECT sequence,previous,operation FROM knowledge_vector_changes ORDER BY sequence"))
        assert [row[2] for row in events] == [1, 1, 1, 0]
        assert [row[1] for row in events] == [0] + [row[0] for row in events[:-1]]
        db.execute("DELETE FROM knowledge_vector_models WHERE model_key=?", (model,))
        assert db.execute("SELECT count(*) FROM knowledge_vector_changes").fetchone()[0] == 0
        assert db.execute("SELECT count(*) FROM knowledge_vector_feed_state").fetchone()[0] == 0
        assert list(db.execute("PRAGMA foreign_key_check")) == []


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("schema", type=Path)
    args = parser.parse_args()
    # This is compiler-emitted protocol data, not a parser for Kotlin source text.
    schema = [base64.b64decode(line, validate=True).decode("utf-8")
              for line in args.schema.read_text(encoding="utf-8-sig").splitlines() if line]
    assert len(schema) >= 10
    for count in (100, 10_000, 100_000):
        verify(schema, count)
    print("Production schema migration and feed invariants passed at all three cardinalities.")


if __name__ == "__main__":
    main()
