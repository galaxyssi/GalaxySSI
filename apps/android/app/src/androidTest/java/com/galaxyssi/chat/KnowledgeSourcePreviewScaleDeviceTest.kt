package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Explicit full-corpus paired measurement; only derived fixture previews are reset. */
@RunWith(AndroidJUnit4::class)
class KnowledgeSourcePreviewScaleDeviceTest {
    @Test fun missingAndPersistedPreviewsCoverEveryRetainedSource() {
        val args = InstrumentationRegistry.getArguments()
        val name = args.getString("retainedKnowledgeFixture")
        assumeTrue("Explicit retained fixture and derived-preview reset required",
            name != null && args.getString("resetDerivedSourcePreviews") == "true")
        val fixtureName = requireNotNull(name)
        val before = KnowledgeSourceMigrationTestSupport.fingerprint(fixtureName)
        val count = KnowledgeSourceMigrationTestSupport.raw(fixtureName) { db ->
            db.rawQuery("SELECT count(*) FROM knowledge_items", null).use { check(it.moveToFirst()); it.getInt(0) }
        }
        require(count >= 10001)
        KnowledgeBackupTestFixture(fixtureName).apply { retain = true; observe = false }.use { f ->
            val output = File(requireNotNull(f.context.getExternalFilesDir("knowledge-source-preview-test")), f.name).apply { mkdirs() }
            // Reset only the explicitly authorized derived previews, never retained primary bodies.
            f.db.transaction { it.delete("knowledge_source_previews", null, null) }
            f.reopen()
            assertEquals(0, KnowledgeSourcePreviewFixtureSchema.count(f))
            KnowledgeSourceMigrationTestSupport.awaitReady(f)
            val passes = JSONArray()
            for ((index, label) in listOf("legacy_build", "ready_after_reopen", "ready_repeat").withIndex()) {
                f.reopen()
                val result = KnowledgeSourcePreviewScaleTraversal.run(f, count, label, output)
                assertEquals(count, KnowledgeSourcePreviewFixtureSchema.count(f))
                assertEquals(before, KnowledgeSourceMigrationTestSupport.fingerprint(f.name))
                assertEquals(if (index == 0) 0L else count.toLong(), result.getLong("preview_hits"))
                assertEquals(if (index == 0) count.toLong() else 0L, result.getLong("preview_misses"))
                passes.put(result)
                // Persist evidence before applying the latency gate, including any failing result.
                File(output, "summary.json").writeText(JSONObject().put("device", android.os.Build.MODEL)
                    .put("version", BuildConfig.VERSION_NAME).put("rows", count).put("ciphertext_sha256", before)
                    .put("passes", passes).put("scope", "Real encrypted sources; not 100M capacity, UI latency or cold legacy <200ms")
                    .toString(2))
                if (index > 0) assertTrue("Ready preview P95 exceeds 200ms: $result", result.getDouble("page_p95_ms") < 200)
            }
            assertEquals("not_configured", f.store.semanticSearchStatus)
        }
    }
}
