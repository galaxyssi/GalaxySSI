package com.galaxyssi.chat

import android.os.Build
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Actual SQLite row cardinalities. Synthetic SQL vectors are NOT neural embeddings or complete memories. */
@RunWith(AndroidJUnit4::class)
class KnowledgeCountScaleDeviceTest {
    @Test fun millionVectorAndQueueRowsKeepStatsReadsBoundedAcrossMigrationAndRestart() {
        org.junit.Assume.assumeTrue("Explicit isolated SQL-scale test",
            InstrumentationRegistry.getArguments().getString("countScale") == "true")
        assertEquals("SM-T575", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val run = UUID.randomUUID().toString().replace("-", "")
        val resume = InstrumentationRegistry.getArguments().getString("countScaleResume").orEmpty()
        require(resume.isEmpty() || resume.matches(Regex("test-count-scale-[a-f0-9]{32}\\.db")))
        val name = resume.ifEmpty { "test-count-scale-$run.db" }
        val path = context.getDatabasePath(name)
        check(path.exists() == resume.isNotEmpty())
        val output = File(context.getExternalFilesDir(null), "embedding-test/count-scale-$run").apply { mkdirs() }
        fun open() = KnowledgeSqlite(path.path).apply {
            execSQL("PRAGMA foreign_keys=ON"); execSQL("PRAGMA recursive_triggers=ON")
            execSQL("PRAGMA journal_mode=WAL"); execSQL("PRAGMA synchronous=FULL")
        }
        var db = open()
        fun <T> transaction(block: () -> T): T {
            db.beginTransaction()
            try { return block().also { db.setTransactionSuccessful() } } finally { db.endTransaction() }
        }
        fun timed(block: () -> Unit): Double {
            val before = SystemClock.elapsedRealtimeNanos(); block()
            return (SystemClock.elapsedRealtimeNanos() - before) / 1_000_000.0
        }
        val model = "b".repeat(64)
        val first = "1".padStart(64, '0')
        fun actual(table: String): Long = db.rawQuery("SELECT count(*) FROM $table WHERE model_key=?", arrayOf(model)).use {
            check(it.moveToFirst()); it.getLong(0)
        }
        fun samples(name: String, values: List<Double>): JSONObject {
            File(output, "$name.csv").bufferedWriter().use { writer ->
                writer.appendLine("sample,elapsed_ms"); values.forEachIndexed { i, ms -> writer.appendLine("${i + 1},$ms") }
            }
            val sorted = values.sorted()
            fun p(q: Double) = sorted[(kotlin.math.ceil(sorted.size * q).toInt() - 1).coerceAtLeast(0)]
            return JSONObject().put("phase", name).put("n", sorted.size).put("p50_ms", p(.5))
                .put("p95_ms", p(.95)).put("p99_ms", p(.99)).put("max_ms", sorted.last())
                .put("over_200ms", values.count { it > 200 })
        }
        val report = JSONArray()
        try {
            val resumeState = if (resume.isNotEmpty()) transaction { KnowledgeCounts.snapshot(db, model) } else null
            if (resumeState != null) {
                assertEquals(1_000_000L, actual("knowledge_vectors"))
                assertEquals(1_000_000L, actual("knowledge_vector_queue"))
                assertFalse(resumeState.complete)
                assertTrue(resumeState.chunks in 1L..499_999L && resumeState.pending in 1L..499_999L)
                report.put(samples("old-count-1000000-resumed", (1..32).map {
                    timed { transaction { actual("knowledge_vectors"); actual("knowledge_vector_queue") } }
                }))
                println("KNOWLEDGE_COUNT_SCALE_RESUMED vectors=${resumeState.chunks} pending=${resumeState.pending}")
            } else {
            db.execSQL("CREATE TABLE knowledge_items(item_key TEXT PRIMARY KEY)")
            KnowledgeVectorLedger.create(db)
            db.execSQL("INSERT INTO knowledge_vector_models(model_key) VALUES('$model')")
            var rows = 0
            for (target in listOf(1024, 10240, 102400, 1_000_000)) {
                while (rows < target) {
                    val end = minOf(rows + 1024, target)
                    transaction {
                        val recursive = "WITH RECURSIVE ids(n) AS (VALUES(CAST(? AS INTEGER)) UNION ALL " +
                            "SELECT n+1 FROM ids WHERE n<CAST(? AS INTEGER)) "
                        val args = arrayOf((rows + 1).toString(), end.toString())
                        db.rawQuery(recursive + "INSERT INTO knowledge_items(item_key) SELECT printf('%064x',n) FROM ids", args).use { it.moveToNext() }
                        if (rows == 0) db.execSQL("INSERT INTO knowledge_vector_docs(item_key,model_key,revision,dimensions," +
                            "next_offset,chunk_count,complete,seal,content_length) VALUES('$first','$model','fixture',4,0,0,0,X'',1)")
                        db.rawQuery(recursive + "INSERT INTO knowledge_vectors(item_key,model_key,ordinal,ciphertext) " +
                            "SELECT '$first','$model',n-1,zeroblob(53) FROM ids", args).use { it.moveToNext() }
                    }
                    rows = end
                }
                assertEquals(target.toLong(), actual("knowledge_vectors"))
                assertEquals(target.toLong(), actual("knowledge_vector_queue"))
                val old = samples("old-count-$target", (1..32).map {
                    timed { transaction { actual("knowledge_vectors"); actual("knowledge_vector_queue") } }
                })
                report.put(old); println("KNOWLEDGE_COUNT_SCALE $old")
            }
            }
            val migration = if (resumeState == null) timed { transaction { KnowledgeCountSchema.create(db) } } else null
            if (resumeState == null) assertEquals(KnowledgeCountSnapshot(0, 0, false), KnowledgeCounts.snapshot(db, model))
            val pageSamples = mutableMapOf<KnowledgeCountSchema.Kind, MutableList<Double>>()
            KnowledgeCountSchema.Kind.entries.forEach { pageSamples[it] = ArrayList() }
            var iterations = 0
            var reopened = false
            while (KnowledgeCounts.pending(db)) {
                for (kind in KnowledgeCountSchema.Kind.entries) if (!KnowledgeCounts.position(db, kind).complete) {
                    requireNotNull(pageSamples[kind]) += timed { transaction { KnowledgeCounts.advance(db, kind) } }
                }
                iterations++
                if (!reopened && iterations == 7800) {
                    val before = transaction { KnowledgeCounts.snapshot(db, model) }
                    db.close(); db = open()
                    assertEquals(before, KnowledgeCounts.snapshot(db, model)); reopened = true
                    transaction {
                        db.execSQL("DELETE FROM knowledge_vectors WHERE ordinal IN (1,999900)")
                        db.execSQL("DELETE FROM knowledge_items WHERE item_key IN (printf('%064x',2),printf('%064x',999901))")
                    }
                }
                if (iterations % 1024 == 0) println("KNOWLEDGE_COUNT_SCALE_PROGRESS pages_per_table=$iterations")
            }
            pageSamples.forEach { (kind, values) -> report.put(samples("backfill-${kind.name.lowercase()}", values)) }
            assertTrue(reopened)
            assertEquals(KnowledgeCountSnapshot(999998, 999998, true), KnowledgeCounts.snapshot(db, model))
            db.close(); db = open()
            val firstRead = timed { transaction { assertTrue(KnowledgeCounts.snapshot(db, model).complete) } }
            report.put(samples("point-count-million", (1..256).map { timed { transaction { KnowledgeCounts.snapshot(db, model) } } }))
            report.put(samples("live-write-million", (1..128).map { offset -> timed {
                transaction {
                    db.execSQL("INSERT INTO knowledge_items(item_key) VALUES(printf('%064x',${1_000_000 + offset}))")
                    db.execSQL("INSERT INTO knowledge_vectors(item_key,model_key,ordinal,ciphertext) " +
                        "VALUES('$first','$model',${999999 + offset},zeroblob(53))")
                }
            } }))
            val measured = transaction { KnowledgeCounts.snapshot(db, model) }
            assertEquals(KnowledgeCountSnapshot(1000126, 1000126, true), measured)
            assertEquals(actual("knowledge_vectors"), measured.chunks)
            assertEquals(actual("knowledge_vector_queue"), measured.pending)
            for (kind in KnowledgeCountSchema.Kind.entries) db.rawQuery("SELECT 1 FROM ${kind.table} WHERE count_tracked!=1 LIMIT 1", null)
                .use { assertFalse(it.moveToFirst()) }
            db.execSQL("PRAGMA wal_checkpoint(TRUNCATE)")
            val result = JSONObject().put("device", Build.MODEL).put("version", BuildConfig.VERSION_NAME)
                .put("database", name).put("database_bytes", path.length()).put("migration_ms", migration)
                .put("resumed", resumeState != null)
                .put("resume_initial_vectors", resumeState?.chunks).put("resume_initial_pending", resumeState?.pending)
                .put("reopen_first_read_ms", firstRead).put("results", report)
                .put("final_vectors", measured.chunks).put("final_pending", measured.pending)
                .put("scope", "One million actual SQLite vector rows and queue rows, but no authentic vector ciphertext, source bodies, " +
                    "neural embedding, Keystore or UI. WAL/FULL transaction time includes commit/fsync. No OS cache drop. " +
                    "Baseline counts precede migration. Page samples exclude CSV writing, seeding and verification.")
            File(output, "summary.json").writeText(result.toString(2))
            println("KNOWLEDGE_COUNT_SCALE_RESULT $result")
            println("KNOWLEDGE_COUNT_SCALE_ARTIFACT directory=${output.path}")
        } finally { db.close() }
    }
}
