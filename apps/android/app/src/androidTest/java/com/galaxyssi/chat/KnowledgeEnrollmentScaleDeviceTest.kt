package com.galaxyssi.chat

import android.content.ContentValues
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

/** Real SQLite directory cardinalities, not a full-memory/embedding capacity benchmark. */
@RunWith(AndroidJUnit4::class)
class KnowledgeEnrollmentScaleDeviceTest {
    @Test fun millionKeyDirectoryHasBoundedRestartableRegistration() {
        org.junit.Assume.assumeTrue("Explicit large isolated catalog test",
            InstrumentationRegistry.getArguments().getString("enrollmentScale") == "true")
        assertEquals("SM-T575", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val run = UUID.randomUUID().toString().replace("-", "")
        val name = "test-enrollment-scale-$run.db"
        val path = context.getDatabasePath(name)
        val output = File(context.getExternalFilesDir(null), "embedding-test/enrollment-scale-$run").apply { mkdirs() }
        fun open() = KnowledgeSqlite(path.path).apply {
            execSQL("PRAGMA foreign_keys=ON"); execSQL("PRAGMA journal_mode=WAL"); execSQL("PRAGMA synchronous=FULL")
        }
        var db = open()
        fun <T> transaction(block: () -> T): T {
            db.beginTransaction()
            try { return block().also { db.setTransactionSuccessful() } } finally { db.endTransaction() }
        }
        fun count(table: String, model: String? = null): Long = db.rawQuery("SELECT count(*) FROM $table" +
            if (model == null) "" else " WHERE model_key=?", model?.let { arrayOf(it) }).use { check(it.moveToFirst()); it.getLong(0) }
        fun register(model: String) = transaction {
            db.insertOrThrow("knowledge_vector_models", null, ContentValues().apply { put("model_key", model) })
        }
        fun elapsed(block: () -> Unit): Double {
            val start = SystemClock.elapsedRealtimeNanos(); block()
            return (SystemClock.elapsedRealtimeNanos() - start) / 1_000_000.0
        }
        val summary = JSONArray()
        try {
            db.execSQL("CREATE TABLE knowledge_items(item_key TEXT PRIMARY KEY)")
            KnowledgeVectorLedger.create(db)
            KnowledgeVectorEnrollment.create(db)
            var rows = 0
            for (target in listOf(1024, 10240, 102400, 1_000_000)) {
                while (rows < target) {
                    val end = minOf(rows + 1024, target)
                    transaction {
                        db.rawQuery("WITH RECURSIVE ids(n) AS (VALUES(CAST(? AS INTEGER)) UNION ALL " +
                            "SELECT n+1 FROM ids WHERE n<CAST(? AS INTEGER)) " +
                            "INSERT INTO knowledge_items(item_key) SELECT printf('%064x',n) FROM ids",
                            arrayOf((rows + 1).toString(), end.toString())).use { it.moveToNext() }
                    }
                    rows = end
                }
                assertEquals(target.toLong(), count("knowledge_items"))
                val old = "a".repeat(64)
                val eagerMs = elapsed {
                    transaction {
                        db.insertOrThrow("knowledge_vector_models", null, ContentValues().apply { put("model_key", old) })
                        db.rawQuery("INSERT INTO knowledge_vector_queue(model_key,item_key) SELECT ?,item_key FROM knowledge_items",
                            arrayOf(old)).use { it.moveToNext() }
                    }
                }
                assertEquals(target.toLong(), count("knowledge_vector_queue", old))
                transaction { db.delete("knowledge_vector_models", "model_key=?", arrayOf(old)) }
                val model = "b".repeat(64)
                val registerMs = elapsed { register(model) }
                assertEquals(0L, count("knowledge_vector_queue", model))
                val samples = ArrayList<Double>()
                var checkpoint = KnowledgeVectorEnrollment.state(db, model)
                var reopened = false
                File(output, "$target.csv").bufferedWriter().use { writer ->
                    writer.appendLine("page,elapsed_ms,complete")
                    while (!checkpoint.complete) {
                        val ms = elapsed { checkpoint = transaction { KnowledgeVectorEnrollment.refill(db, model) } }
                        samples += ms
                        writer.appendLine("${samples.size},$ms,${checkpoint.complete}")
                        if (!reopened && samples.size >= target / (64 * 2)) {
                            db.close(); db = open()
                            assertEquals(checkpoint, KnowledgeVectorEnrollment.state(db, model))
                            reopened = true
                        }
                    }
                }
                val total = count("knowledge_vector_queue", model)
                assertEquals(target.toLong(), total)
                db.rawQuery("SELECT item_key FROM knowledge_vector_queue WHERE model_key=? ORDER BY item_key", arrayOf(model)).use { cursor ->
                    var expected = 1
                    while (cursor.moveToNext()) {
                        assertEquals(expected.toString(16).padStart(64, '0'), cursor.getString(0)); expected++
                    }
                    assertEquals(target + 1, expected)
                }
                val sorted = samples.sorted()
                fun percentile(p: Double) = sorted[(kotlin.math.ceil(sorted.size * p).toInt() - 1).coerceAtLeast(0)]
                val measured = JSONObject().put("rows", target).put("eager_ms", eagerMs).put("register_ms", registerMs)
                    .put("pages", samples.size).put("p50_ms", percentile(0.5)).put("p95_ms", percentile(0.95))
                    .put("p99_ms", percentile(0.99)).put("max_ms", sorted.last()).put("over_200ms", samples.count { it > 200 })
                    .put("complete_keys_verified", total).put("reopened", reopened)
                summary.put(measured)
                println("KNOWLEDGE_ENROLLMENT_SCALE $measured")
                if (target < 1_000_000) transaction { db.delete("knowledge_vector_models", "model_key=?", arrayOf(model)) }
            }
            db.close(); db = open()
            assertEquals(1_000_000L, count("knowledge_vector_queue", "b".repeat(64)))
            assertTrue(KnowledgeVectorEnrollment.state(db, "b".repeat(64)).complete)
            db.execSQL("PRAGMA wal_checkpoint(TRUNCATE)")
            val report = JSONObject().put("device", Build.MODEL).put("version", BuildConfig.VERSION_NAME)
                .put("database", name).put("database_bytes", path.length()).put("measurements", summary)
                .put("scope", "Synthetic opaque source keys and actual durable queues, not encrypted source bodies or vectors. " +
                    "No OS cache drop. Page timings include transaction/fsync but exclude CSV writing, registration, seeding and verification. " +
                    "Model key derivation, Keystore and whole-App UI are outside this SQL-only benchmark.")
            File(output, "summary.json").writeText(report.toString(2))
            println("KNOWLEDGE_ENROLLMENT_ARTIFACT directory=${output.path} database=$name bytes=${path.length()}")
        } finally { db.close() }
    }
}
