package com.galaxyssi.chat

import android.os.Debug
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Explicit real encrypted-source scale run; metadata-only million-row fixtures are not used. */
@RunWith(AndroidJUnit4::class)
class KnowledgeBackupScaleDeviceTest {
    @Test fun encryptedSourcesRoundTripWithoutCorpusArrays() {
        val raw = InstrumentationRegistry.getArguments().getString("knowledgeBackupRows")
        assumeTrue("Explicit source count required for the retained scale run", raw != null)
        val count = requireNotNull(raw).toInt()
        require(count > 1000)
        KnowledgeBackupTestFixture().use { f ->
            f.observe = false
            f.retain = true
            val output = File(requireNotNull(f.context.getExternalFilesDir("knowledge-backup-test")), f.name).apply { mkdirs() }
            val start = SystemClock.elapsedRealtime()
            for (first in 1..count step 64) f.db.transaction { sql ->
                for (index in first..minOf(first + 63, count)) f.db.write(sql, f.item(index))
            }
            println("KNOWLEDGE_BACKUP_SCALE seed=$count elapsed_ms=${SystemClock.elapsedRealtime() - start}")
            val seeded = SystemClock.elapsedRealtime()
            assertEquals(count.toLong() + 2, f.export())
            val exported = SystemClock.elapsedRealtime()
            println("KNOWLEDGE_BACKUP_SCALE export=$count elapsed_ms=${exported - seeded} bytes=${f.file.length()}")
            f.db.transaction { it.delete("knowledge_items", null, null); f.db.write(it, f.item(count + 1)) }
            val stageStarted = SystemClock.elapsedRealtime()
            val stageSamples = File(output, "stage-row-ms.csv").bufferedWriter()
            stageSamples.write("sample,elapsed_ms\n")
            var accepted = 0L
            var maxObservedHeap = 0L
            fun sampleHeap() {
                val runtime = Runtime.getRuntime()
                maxObservedHeap = maxOf(maxObservedHeap, runtime.totalMemory() - runtime.freeMemory())
            }
            var stageMillis = 0L
            var restoreMillis = 0L
            var writeSamples = 0L
            try { KnowledgeBackupStaging(f.context).use { stage ->
                StreamingBackupArchive.read(f.file, f.password) { section, key, input ->
                    val at = System.nanoTime()
                    stage.accept(section, key, input)
                    if (section == "knowledge-row") {
                        accepted++
                        stageSamples.write("$accepted,${(System.nanoTime() - at) / 1_000_000.0}\n")
                        if (accepted % 1024L == 0L) {
                            sampleHeap(); println("KNOWLEDGE_BACKUP_SCALE staged=$accepted")
                        }
                    }
                }
                stage.validateArchive(); stageMillis = SystemClock.elapsedRealtime() - stageStarted
                assertEquals(count.toLong(), accepted)
                val restoreAt = SystemClock.elapsedRealtime()
                f.store.restoreRecords(stage) { restored ->
                    writeSamples = restored
                    if (restored % 1024L == 0L) { sampleHeap(); println("KNOWLEDGE_BACKUP_SCALE restored=$restored") }
                }
                restoreMillis = SystemClock.elapsedRealtime() - restoreAt
            } } finally { stageSamples.close() }
            f.reopen()
            assertEquals(count.toLong(), f.store.stats().itemCount)
            assertEquals(count.toLong(), writeSamples)
            val verifyAt = SystemClock.elapsedRealtime()
            f.db.backupSnapshot().use { snapshot ->
                var verified = 0L
                for (item in snapshot.items()) {
                    val index = item.id.removePrefix("backup-").toInt()
                    assertTrue(index in 1..count); assertEquals(f.item(index), item); verified++
                }
                assertEquals(count.toLong(), verified)
            }
            val verifyMillis = SystemClock.elapsedRealtime() - verifyAt
            val summary = JSONObject().put("device", android.os.Build.MODEL).put("version", BuildConfig.VERSION_NAME)
                .put("rows", count).put("archive_bytes", f.file.length()).put("seed_ms", seeded - start)
                .put("export_ms", exported - seeded).put("stage_ms", stageMillis).put("restore_ms", restoreMillis)
                .put("verify_ms", verifyMillis).put("sampled_java_heap_max_bytes", maxObservedHeap)
                .put("native_heap_at_end_bytes", Debug.getNativeHeapAllocatedSize())
                .put("scope", "Real encrypted sources and FTS, not semantic vectors or 100M capacity; heap samples are not a peak bound")
            File(output, "summary.json").writeText(summary.toString(2))
            // Keep the portable archive and original encrypted source fixture for later same-scale checks.
            f.file.copyTo(File(output, "sources.hcbak"))
            f.retain = true
            println("KNOWLEDGE_BACKUP_SCALE complete=$count summary=$summary output=${output.absolutePath}")
        }
    }
}
