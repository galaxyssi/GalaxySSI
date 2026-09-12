package com.galaxyssi.chat

import android.os.SystemClock
import org.json.JSONObject
import org.junit.Assert.*
import java.io.File

internal object KnowledgeSourcePreviewScaleTraversal {
    fun run(f: KnowledgeBackupTestFixture, count: Int, label: String, output: File): JSONObject {
        val openAt = SystemClock.elapsedRealtime()
        f.db.access { KnowledgeSourceDirectory.state(it).requireReady() }
        val openMs = SystemClock.elapsedRealtime() - openAt
        val seen = BooleanArray(count + 1)
        var cursor: AgentKnowledgeSourceCursor? = null
        val times = mutableListOf<Double>()
        var groups = 0
        var bodies = 0L
        var hits = 0L
        var misses = 0L
        var midReopenMs = 0L
        File(output, "$label.csv").bufferedWriter().use { csv ->
            csv.write("page,groups,elapsed_ms,preview_hits,preview_misses,body_reads\n")
            do {
                val beforeBodies = f.db.decryptedItemReads
                val beforeHits = f.db.sourcePreviewHits
                val beforeMisses = f.db.sourcePreviewMisses
                val start = System.nanoTime()
                val page = f.store.sourcePage(cursor, 50)
                val ms = (System.nanoTime() - start) / 1_000_000.0
                val pageBodies = f.db.decryptedItemReads - beforeBodies
                val pageHits = f.db.sourcePreviewHits - beforeHits
                val pageMisses = f.db.sourcePreviewMisses - beforeMisses
                times.add(ms); bodies += pageBodies; hits += pageHits; misses += pageMisses
                csv.write("${times.size},${page.groups.size},$ms,$pageHits,$pageMisses,$pageBodies\n")
                assertFalse(f.db.hasActivePreviewKey)
                assertEquals(count, page.total)
                assertEquals(page.groups.size.toLong(), pageHits + pageMisses)
                page.groups.forEach { group ->
                    val index = group.source.removePrefix("fixture-").toInt()
                    assertTrue(index in 1..count); assertFalse(seen[index]); seen[index] = true
                    assertEquals(count - groups, index)
                    KnowledgeSourceMigrationTestSupport.assertGroup(group, index); groups++
                }
                cursor = page.next
                if (times.size == 100) {
                    val at = SystemClock.elapsedRealtime(); f.reopen()
                    f.db.access { KnowledgeSourceDirectory.state(it).requireReady() }
                    midReopenMs = SystemClock.elapsedRealtime() - at
                }
            } while (cursor != null)
        }
        assertEquals(count, groups); assertEquals((count + 49) / 50, times.size)
        assertEquals(0L, bodies); assertTrue((1..count).all { seen[it] })
        val ordered = times.sorted()
        fun percentile(p: Double) = ordered[(kotlin.math.ceil(p * ordered.size).toInt() - 1).coerceAtLeast(0)]
        return JSONObject().put("label", label).put("open_ms", openMs).put("mid_reopen_ms", midReopenMs)
            .put("pages", times.size).put("groups", groups).put("first_page_ms", times.first())
            .put("page_p50_ms", percentile(.50)).put("page_p95_ms", percentile(.95))
            .put("page_p99_ms", percentile(.99)).put("page_max_ms", ordered.last())
            .put("preview_hits", hits).put("preview_misses", misses).put("body_reads", bodies)
            .also { println("KNOWLEDGE_SOURCE_PREVIEW_SCALE $it") }
    }
}
