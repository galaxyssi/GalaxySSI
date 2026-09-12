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
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Real metadata cardinality and durable counters, not a million encrypted bodies or vector embeddings. */
@RunWith(AndroidJUnit4::class)
class KnowledgeIndexedStatsScaleDeviceTest {
    @Test fun compareAggregateAndPointStatsThroughOneMillionRows() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue("Explicit SQL-scale fixture required", args.getString("indexedStatsScale") == "true")
        assertEquals("SM-T575", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val resume = args.getString("indexedStatsResume").orEmpty()
        require(resume.isEmpty() || resume.matches(Regex("test-indexed-stats-scale-[a-f0-9]{32}\\.db")))
        val name = resume.ifEmpty { "test-indexed-stats-scale-${UUID.randomUUID().toString().replace("-", "")}.db" }
        val path = context.getDatabasePath(name)
        check(path.exists() == resume.isNotEmpty())
        val output = File(context.getExternalFilesDir(null), "knowledge-stats-scale/${name.removeSuffix(".db")}").apply { mkdirs() }
        fun open() = KnowledgeSqlite(path.absolutePath).apply {
            execSQL("PRAGMA foreign_keys=ON"); execSQL("PRAGMA recursive_triggers=ON")
            execSQL("PRAGMA journal_mode=WAL"); execSQL("PRAGMA synchronous=FULL")
        }
        var db = open()
        fun <T> transaction(block: () -> T): T {
            db.beginTransaction()
            try { return block().also { db.setTransactionSuccessful() } } finally { db.endTransaction() }
        }
        fun timed(block: () -> Unit): Double {
            val at = SystemClock.elapsedRealtimeNanos(); block()
            return (SystemClock.elapsedRealtimeNanos() - at) / 1_000_000.0
        }
        val reports = JSONArray()
        try {
            if (resume.isEmpty()) transaction {
                db.execSQL("CREATE TABLE knowledge_items(item_key TEXT PRIMARY KEY,source_key TEXT NOT NULL,updated INTEGER NOT NULL)")
                db.execSQL("CREATE INDEX knowledge_updated ON knowledge_items(updated DESC,item_key)")
                db.execSQL("CREATE TABLE stats_scale_state(id INTEGER PRIMARY KEY CHECK(id=1),seeded INTEGER NOT NULL)")
                db.execSQL("INSERT INTO stats_scale_state VALUES(1,0)")
                KnowledgeSourceDirectorySchema.create(db)
            }
            var seeded = db.rawQuery("SELECT seeded FROM stats_scale_state WHERE id=1", null).use { check(it.moveToFirst()); it.getLong(0) }
            require(seeded in 0L..1_000_000L)
            println("KNOWLEDGE_INDEXED_STATS_FIXTURE name=$name seeded=$seeded")
            File(output, "samples.csv").bufferedWriter().use { csv ->
                csv.appendLine("rows,phase,sample,elapsed_ms")
                for (target in listOf(1024L, 10240L, 102400L, 1_000_000L)) {
                    if (target < seeded) continue
                    while (seeded < target) {
                        val end = minOf(seeded + 2048, target)
                        transaction {
                            db.rawQuery("WITH RECURSIVE ids(n) AS (VALUES(CAST(? AS INTEGER)) UNION ALL SELECT n+1 FROM ids WHERE n<CAST(? AS INTEGER)) " +
                                "INSERT INTO knowledge_items SELECT printf('%064x',n),CASE WHEN n%4=0 THEN '' ELSE printf('%064x',n/4) END,n FROM ids",
                                arrayOf((seeded + 1).toString(), end.toString())).use { it.moveToNext() }
                            db.rawQuery("UPDATE stats_scale_state SET seeded=? WHERE id=1", arrayOf(end.toString())).use { it.moveToNext() }
                        }
                        seeded = end
                        if (seeded % 102400L == 0L || seeded == target) println("KNOWLEDGE_INDEXED_STATS_SEEDED $seeded")
                    }
                    val expected = AgentKnowledgeStats(target, target / 4, target)
                    fun aggregate(): AgentKnowledgeStats = db.rawQuery("SELECT count(*),count(DISTINCT NULLIF(source_key,'')),COALESCE(max(updated),0) FROM knowledge_items", null).use {
                        check(it.moveToFirst()); AgentKnowledgeStats(it.getLong(0), it.getLong(1), it.getLong(2))
                    }
                    assertEquals(expected, transaction { aggregate() })
                    for (phase in listOf("old-aggregate", "indexed")) {
                        val samples = (1..if (phase == "indexed") 64 else 8).map { sample ->
                            timed { assertEquals(expected, transaction { if (phase == "indexed") KnowledgeIndexedStats.read(db) else aggregate() }) }
                                .also { csv.appendLine("$target,$phase,$sample,$it") }
                        }
                        val sorted = samples.sorted()
                        fun p(fraction: Double) = sorted[(kotlin.math.ceil(sorted.size * fraction).toInt() - 1).coerceAtLeast(0)]
                        val report = JSONObject().put("rows", target).put("phase", phase).put("samples", samples.size)
                            .put("p50_ms", p(.50)).put("p95_ms", p(.95)).put("p99_ms", p(.99)).put("max_ms", sorted.last())
                            .put("over_200ms", samples.count { it > 200 })
                        reports.put(report); println("KNOWLEDGE_INDEXED_STATS $report")
                    }
                    db.close(); db = open()
                    assertEquals(expected, transaction { KnowledgeIndexedStats.read(db) })
                }
            }
            assertEquals(1_000_000L, seeded)
            val summary = JSONObject().put("device", Build.MODEL).put("version", BuildConfig.VERSION_NAME)
                .put("database", name).put("database_bytes", path.length()).put("results", reports)
                .put("scope", "Actual SQL metadata and transactional directory counts; no real body encryption, model inference, UI or OS cache drop. Seeding excluded from query timings. Original aggregate is compared on the same indexed fixture. Not 100M capacity or universal latency acceptance.")
            File(output, "summary.json").writeText(summary.toString(2))
            println("KNOWLEDGE_INDEXED_STATS_COMPLETE $summary output=${output.absolutePath}")
        } finally { db.close() }
    }
}
