package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Reuses the full encrypted corpus from the backup test, without deleting or replacing any rows. */
@RunWith(AndroidJUnit4::class)
class KnowledgeSourceDirectoryScaleDeviceTest {
    @Test fun retainedEncryptedCorpusMigratesAndEveryPageSurvivesReopen() {
        val name = InstrumentationRegistry.getArguments().getString("retainedKnowledgeFixture")
        assumeTrue("Explicit retained source fixture required", name != null)
        val fixtureName = requireNotNull(name)
        val before = KnowledgeSourceMigrationTestSupport.fingerprint(fixtureName)
        val count = KnowledgeSourceMigrationTestSupport.raw(fixtureName) { db ->
            db.rawQuery("SELECT count(*) FROM knowledge_items", null).use { check(it.moveToFirst()); it.getInt(0) }
        }
        require(count >= 10001)
        KnowledgeBackupTestFixture(fixtureName).apply { retain = true; observe = false }.use { f ->
            val output = File(requireNotNull(f.context.getExternalFilesDir("knowledge-source-directory-test")), f.name).apply { mkdirs() }
            val start = SystemClock.elapsedRealtime()
            val initial = f.db.access { KnowledgeSourceDirectory.state(it) }
            val opened = SystemClock.elapsedRealtime()
            KnowledgeSourceMigrationTestSupport.awaitReady(f)
            val migrated = SystemClock.elapsedRealtime()
            println("KNOWLEDGE_SOURCE_SCALE ready=$count open_ms=${opened - start} migration_ms=${migrated - opened}")
            assertEquals(count, f.store.sourceCount())
            val seen = BooleanArray(count + 1)
            var cursor: AgentKnowledgeSourceCursor? = null
            val times = mutableListOf<Double>()
            var groups = 0
            var bodyReads = 0L
            var headerReads = 0L
            var reopenMs = 0L
            File(output, "pages-ms.csv").bufferedWriter().use { csv ->
                csv.write("page,groups,elapsed_ms\n")
                do {
                    val bodiesBefore = f.db.decryptedItemReads
                    val headersBefore = f.db.decryptedSourceSummaryReads
                    val at = System.nanoTime()
                    val page = f.store.sourcePage(cursor, 50)
                    val ms = (System.nanoTime() - at) / 1_000_000.0
                    times.add(ms); csv.write("${times.size},${page.groups.size},$ms\n")
                    assertEquals(count, page.total)
                    page.groups.forEach { group ->
                        val index = group.source.removePrefix("fixture-").toInt()
                        assertTrue(index in 1..count); assertFalse(seen[index]); seen[index] = true
                        assertEquals(count - groups, index)
                        KnowledgeSourceMigrationTestSupport.assertGroup(group, index); groups++
                    }
                    bodyReads += f.db.decryptedItemReads - bodiesBefore
                    headerReads += f.db.decryptedSourceSummaryReads - headersBefore
                    cursor = page.next
                    if (times.size == 100) {
                        val closeAt = SystemClock.elapsedRealtime(); f.reopen()
                        f.db.access { KnowledgeSourceDirectory.state(it).requireReady() }
                        reopenMs = SystemClock.elapsedRealtime() - closeAt
                    }
                    if (times.size % 25 == 0) println("KNOWLEDGE_SOURCE_SCALE pages=${times.size} groups=$groups")
                } while (cursor != null)
            }
            assertEquals(count, groups); assertEquals((count + 49) / 50, times.size)
            assertEquals(0L, bodyReads); assertEquals(count.toLong(), headerReads)
            assertTrue((1..count).all { seen[it] })
            assertEquals(before, KnowledgeSourceMigrationTestSupport.fingerprint(f.name))
            assertEquals("not_configured", f.store.semanticSearchStatus)
            val ordered = times.sorted()
            fun percentile(p: Double) = ordered[(kotlin.math.ceil(p * ordered.size).toInt() - 1).coerceAtLeast(0)]
            val summary = JSONObject().put("device", android.os.Build.MODEL).put("version", BuildConfig.VERSION_NAME)
                .put("rows", count).put("initial_complete", initial.complete).put("open_ms", opened - start)
                .put("migration_ms", migrated - opened).put("reopen_ms", reopenMs).put("pages", times.size)
                .put("first_page_ms", times.first()).put("page_p50_ms", percentile(.50)).put("page_p95_ms", percentile(.95))
                .put("page_p99_ms", percentile(.99)).put("page_max_ms", ordered.last()).put("body_reads", bodyReads)
                .put("header_reads", headerReads).put("ciphertext_sha256", before)
                .put("scope", "Retained real encrypted corpus, not 100M capacity or UI latency; includes per-page authentication")
            File(output, "summary.json").writeText(summary.toString(2))
            println("KNOWLEDGE_SOURCE_SCALE complete=$count summary=$summary output=${output.absolutePath}")
        }
    }
}
