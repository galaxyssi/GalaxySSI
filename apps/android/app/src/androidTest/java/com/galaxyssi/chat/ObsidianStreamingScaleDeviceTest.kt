package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.OutputStream
import java.security.DigestOutputStream
import java.security.MessageDigest
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Reuses the retained encrypted corpus without reseeding or rewriting its contents. */
@RunWith(AndroidJUnit4::class)
class ObsidianStreamingScaleDeviceTest {
    @Test fun retained10001MemberSourceStreamsCompleteNoteAndSurvivesReopen() {
        val name = InstrumentationRegistry.getArguments().getString("streamingProjectionFixture").orEmpty()
        assumeTrue("Explicit retained synthetic fixture required", name.isNotBlank())
        require(name.matches(Regex("test-knowledge-backup-source-revision-[a-f0-9]{24}\\.db")))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        require(context.getDatabasePath(name).isFile) { "Retained fixture is missing; never silently reseed" }
        KnowledgeBackupTestFixture(name).apply { retain = true; observe = false }.use { f ->
            assertEquals(10001L, f.db.access { sql -> sql.rawQuery("SELECT count(*) FROM knowledge_items", null).use {
                check(it.moveToFirst()); it.getLong(0)
            } })
            val fingerprint = KnowledgeSourceMigrationTestSupport.fingerprint(name)
            val source = "\u5355\u6765\u6e90\u538b\u529b\u6d4b\u8bd5"
            val reference = AgentKnowledgeSourceReference(source)
            val export = f.store.sourceExport(reference)
            val key = ObsidianKnowledgeIdentity.sourceKey(reference)
            val beforeReads = f.db.decryptedItemReads
            val bodyDigest = MessageDigest.getInstance("SHA-256")
            val discard = object : OutputStream() { override fun write(value: Int) = Unit
                override fun write(bytes: ByteArray, offset: Int, length: Int) = Unit }
            DigestOutputStream(discard, bodyDigest).writer().use { writer ->
                for (i in 10001 downTo 1) {
                    if (i != 10001) writer.write("\n\n")
                    writer.write(f.item(i).content)
                }
            }
            val expectedHeader = ObsidianAndroidBridge.noteHeader(key, "knowledge", f.item(10001).title,
                source, 10002, emptyList(), ObsidianContentHash.hex(bodyDigest.digest()))
            val expectedHash = ObsidianContentHash.write(discard) { target ->
                target.write(expectedHeader.toByteArray())
                for (i in 10001 downTo 1) {
                    if (i != 10001) target.write("\n\n".toByteArray())
                    target.write(f.item(i).content.toByteArray())
                }
                target.write('\n'.code)
            }
            val file = File.createTempFile("test-streamed-note-", ".md", f.context.cacheDir)
            try {
                val start = System.nanoTime()
                var preparationMs = 0.0
                val actualHash = ObsidianStreamingKnowledge.prepare(export, key, "knowledge", source).use { content ->
                    preparationMs = (System.nanoTime() - start) / 1e6
                    file.outputStream().use(content::writeTo)
                }
                val totalMs = (System.nanoTime() - start) / 1e6
                assertEquals(expectedHash, actualHash)
                file.inputStream().use { assertEquals(actualHash, ObsidianBoundedTextScan.read(it, 0).hash) }
                assertEquals(20002L, f.db.decryptedItemReads - beforeReads)
                assertEquals(fingerprint, KnowledgeSourceMigrationTestSupport.fingerprint(name))
                f.reopen()
                assertEquals(export.revision, f.store.sourceExport(reference).revision)
                val result = JSONObject().put("device", android.os.Build.MODEL).put("version", BuildConfig.VERSION_NAME)
                    .put("rows", 10001).put("ciphertext_sha256", fingerprint).put("output_sha256", actualHash)
                    .put("output_bytes", file.length()).put("preparation_ms", preparationMs).put("full_export_ms", totalMs)
                    .put("decrypted_item_reads", 20002).put("sort_budget_bytes", 524288).put("merge_fan_in", 16)
                    .put("scope", "Retained 10,001-member source, not 100M capacity or sub-200ms full export")
                val output = File(requireNotNull(f.context.getExternalFilesDir("knowledge-streaming-projection-test")), name).apply { mkdirs() }
                File(output, "summary.json").writeText(result.toString(2))
                println("STREAMING_PROJECTION_SCALE $result")
            } finally { check(file.delete()) }
        }
    }
}
