package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Explicit retained synthetic corpus: all 10,001 encrypted items belong to one source. */
@RunWith(AndroidJUnit4::class)
class KnowledgeSourceRevisionScaleDeviceTest {
    @Test fun retainedSingleSourceRevisionAndStreamingSnapshot() {
        val name = InstrumentationRegistry.getArguments().getString("sourceRevisionScaleFixture").orEmpty()
        assumeTrue("Explicit isolated scale fixture required", name.isNotBlank())
        require(name.matches(Regex("test-knowledge-backup-source-revision-[a-f0-9]{24}\\.db")))
        KnowledgeBackupTestFixture(name).apply { retain = true; observe = false }.use { f ->
            val output = File(requireNotNull(f.context.getExternalFilesDir("knowledge-source-revision-test")), name).apply { mkdirs() }
            f.db.transaction { it.delete("knowledge_items", "item_key=?", arrayOf(f.db.key("id", "backup-20000"))) }
            val rows = f.db.access { db -> db.rawQuery("SELECT count(*) FROM knowledge_items", null).use {
                check(it.moveToFirst()); it.getInt(0)
            } }
            require(rows in 0..10001)
            // Sequential committed batches make interrupted seeding resumable without rewriting earlier ciphertext.
            for (start in (rows + 1)..10001 step 64) {
                f.db.transaction { db -> (start..minOf(start + 63, 10001)).forEach { i ->
                    f.db.write(db, f.item(i).copy(source = "\u5355\u6765\u6e90\u538b\u529b\u6d4b\u8bd5", chunkIndex = 10001 - i, chunkCount = 10001))
                } }
                if (start % 1024 == 1) println("SOURCE_REVISION_SEED committed=${minOf(start + 63, 10001)}")
            }
            val hash = KnowledgeSourceMigrationTestSupport.fingerprint(name)
            val reference = AgentKnowledgeSourceReference("\u5355\u6765\u6e90\u538b\u529b\u6d4b\u8bd5")
            val migrationStarted = System.nanoTime()
            KnowledgeSourceRevisionFixtureSchema.versionNine(f)
            val baseline = f.store.sourceExport(reference)
            val migrationMs = (System.nanoTime() - migrationStarted) / 1e6
            assertTrue(baseline.revision.endsWith(":0"))
            assertEquals(0L, f.db.decryptedItemReads); assertEquals(0L, f.db.decryptedSourceSummaryReads)
            val legacyTimes = ArrayList<Double>()
            var legacyToken: String? = null
            File(output, "legacy-digest-ms.csv").bufferedWriter().use { writer ->
                writer.appendLine("sample,legacy_digest_ms")
                repeat(20) { i ->
                    val start = System.nanoTime()
                    val token = KnowledgeSourceLegacyDigestFixture.run(f, reference)
                    val elapsed = (System.nanoTime() - start) / 1e6
                    if (legacyToken != null) assertEquals(legacyToken, token)
                    legacyToken = token; legacyTimes.add(elapsed); writer.appendLine("$i,$elapsed")
                }
            }
            val csv = File(output, "revision-and-write-ms.csv")
            val revisionTimes = ArrayList<Double>()
            val writeTimes = ArrayList<Double>()
            csv.bufferedWriter().use { writer ->
                writer.appendLine("sample,revision_ms,write_ms")
                repeat(200) { i ->
                    val start = System.nanoTime()
                    assertEquals(baseline.revision, f.store.sourceExport(reference).revision)
                    val queryMs = (System.nanoTime() - start) / 1e6
                    // Independent, real encrypted writes also prove unrelated updates do not invalidate this source.
                    val writeStart = System.nanoTime()
                    f.store.upsert(f.item(20000, "\u5e76\u884c\u5199\u5165-$i").copy(source = "other"))
                    val writeMs = (System.nanoTime() - writeStart) / 1e6
                    revisionTimes.add(queryMs); writeTimes.add(writeMs)
                    writer.appendLine("$i,$queryMs,$writeMs")
                }
            }
            f.db.transaction { it.delete("knowledge_items", "item_key=?", arrayOf(f.db.key("id", "backup-20000"))) }
            assertEquals(hash, KnowledgeSourceMigrationTestSupport.fingerprint(name))
            val started = System.nanoTime()
            val bodyReads = f.db.decryptedItemReads
            var count = 0
            var largestPage = 0
            baseline.snapshot().use { snapshot ->
                snapshot.items().forEach { item ->
                    val expected = 10001 - count
                    assertEquals("backup-$expected", item.id)
                    assertEquals(f.item(expected).content, item.content)
                    assertEquals(reference.source, item.source)
                    count++
                }
                assertEquals(10001L, snapshot.loadedKeys); largestPage = snapshot.largestKeyPage
            }
            val traversalMs = (System.nanoTime() - started) / 1e6
            assertEquals(10001, count); assertEquals(64, largestPage)
            assertEquals(10001L, f.db.decryptedItemReads - bodyReads)
            assertEquals(hash, KnowledgeSourceMigrationTestSupport.fingerprint(name))
            f.reopen(); assertEquals(baseline.revision, f.store.sourceExport(reference).revision)
            fun percentile(values: List<Double>, fraction: Double) = values.sorted()[kotlin.math.ceil(values.size * fraction).toInt() - 1]
            val result = JSONObject().put("device", android.os.Build.MODEL).put("version", BuildConfig.VERSION_NAME)
                .put("rows", count).put("source_count", 1).put("ciphertext_sha256", hash)
                .put("migration_and_first_token_ms", migrationMs).put("query_p95_ms", percentile(revisionTimes, .95))
                .put("legacy_digest_p95_ms", percentile(legacyTimes, .95)).put("legacy_digest_p99_ms", percentile(legacyTimes, .99))
                .put("query_p99_ms", percentile(revisionTimes, .99)).put("query_max_ms", revisionTimes.max())
                .put("write_p95_ms", percentile(writeTimes, .95)).put("write_p99_ms", percentile(writeTimes, .99))
                .put("write_max_ms", writeTimes.max()).put("snapshot_rows", count).put("largest_key_page", largestPage)
                .put("full_source_traversal_ms", traversalMs)
                .put("scope", "10,001 real encrypted members in one synthetic source; not 100M capacity, UI latency or a <200ms full export")
            File(output, "summary.json").writeText(result.toString(2)); println("SOURCE_REVISION_SCALE $result")
            assertTrue("Indexed query P95 exceeds 200ms: $result", result.getDouble("query_p95_ms") < 200)
            assertTrue("Write P95 exceeds 200ms: $result", result.getDouble("write_p95_ms") < 200)
        }
    }
}
