package com.galaxyssi.chat

import android.provider.Settings
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeVectorNeuralDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val spec = KnowledgeVectorSpec("5a88d266870fbd27c6f329df60de80e2d4cf3bbd5e6f080bd5c1b2e5abb12039", 512, 64)
    private fun model(): File = File(context.getExternalFilesDir(null), "embedding-test/bge-small-zh-v1.5-q8_0.gguf").also {
        assumeTrue("Install the pinned real-model fixture", it.isFile)
    }
    private fun store(name: String) = SQLiteAgentKnowledgeStore(context, name, "legacy-$name") { _, _ -> }
    private fun db(name: String) = AgentKnowledgeDatabase.shared(context, name, "legacy-$name")
    private fun clean(name: String) {
        AgentKnowledgeDatabase.release(context, name)
        context.deleteDatabase(name)
        AgentEncryptedPreferences(context, "legacy-$name").clear()
        AgentEncryptedPreferences(context, "$name-proof").clear()
    }

    @Test fun realVectorsRetainTheirSemanticOrderingAfterEncryptionAndReopen() {
        val model = model()
        val name = "test-real-vectors-${UUID.randomUUID()}.db"
        try {
            val store = store(name)
            val passages = listOf(
                "\u624b\u673a\u4e22\u5931\u540e\u53ef\u4ee5\u901a\u8fc7\u5b9a\u4f4d\u529f\u80fd\u67e5\u627e\u8bbe\u5907",
                "\u4fee\u6539\u767b\u5f55\u5bc6\u7801\u9700\u8981\u5728\u8d26\u53f7\u5b89\u5168\u9875\u9762\u8fdb\u884c",
                "\u6570\u636e\u5e93\u5efa\u7acb\u7d22\u5f15\u53ef\u4ee5\u52a0\u5feb\u67e5\u8be2\u901f\u5ea6"
            )
            passages.forEachIndexed { index, content -> store.upsert(AgentKnowledgeItem(
                "doc-$index", AgentKnowledgeKind.NOTE, "Document $index", content)) }
            LlamaKnowledgeVectorEncoder.open(context, model, spec).use { encoder ->
                assertFalse(store.indexVectorChunks(encoder, 8).pending)
            }
            AgentKnowledgeDatabase.release(context, name)
            val ledger = db(name).vectors(spec)
            val pages = passages.indices.map { requireNotNull(ledger.page("doc-$it")) }
            try {
                LlamaKnowledgeVectorEncoder.open(context, model, spec).use { encoder ->
                    val queries = listOf("\u6211\u7684\u7535\u8bdd\u627e\u4e0d\u5230\u4e86\u600e\u4e48\u529e",
                        "\u600e\u6837\u66f4\u6362\u8d26\u6237\u53e3\u4ee4", "\u600e\u6837\u8ba9SQL\u68c0\u7d22\u66f4\u5feb")
                    queries.forEachIndexed { expected, query ->
                        val vector = encoder.embed(query)
                        try {
                            val scores = pages.map { page -> page.rows.single().values.indices.sumOf {
                                page.rows.single().values[it].toDouble() * vector[it]
                            } }
                            assertEquals(expected, scores.indices.maxBy { scores[it] })
                        } finally { vector.fill(0f) }
                    }
                    println("KNOWLEDGE_VECTOR_PERSISTED recall_at_1=3/3 dimensions=512")
                }
            } finally { pages.forEach { it.close() } }
        } finally { clean(name) }
    }

    @Test fun wrongModelHashFailsBeforeIndexing() {
        assertThrows(IllegalStateException::class.java) {
            LlamaKnowledgeVectorEncoder.open(context, model(), spec.copy(modelSha256 = "0".repeat(64)))
        }
    }

    @Test fun stagedCheckpointSurvivesARealDeviceReboot() {
        val args = InstrumentationRegistry.getArguments()
        val phase = args.getString("vector_phase")
        assumeTrue("Explicit two-phase reboot harness required", phase == "prepare" || phase == "verify")
        val name = requireNotNull(args.getString("vector_fixture"))
        require(name.matches(Regex("test-vector-reboot-[a-z0-9-]+\\.db")))
        val proof = AgentEncryptedPreferences(context, "$name-proof")
        val boot = Settings.Global.getInt(context.contentResolver, "boot_count", -1)
        check(boot >= 0) { "Device boot count unavailable" }
        val model = model()
        val content = "\u8bbe\u5907\u91cd\u542f\u4ee5\u540e\u4ece\u5df2\u7ecf\u5b8c\u6210\u7684\u5411\u91cf\u5206\u5757\u7ee7\u7eed\uff0c\u4e0d\u91cd\u590d\u63d0\u4ea4\u65e7\u5757\u3002".repeat(80)
        if (phase == "prepare") {
            check(store(name).stats().itemCount == 0L) { "Use a fresh named reboot fixture" }
            store(name).upsert(AgentKnowledgeItem("reboot-doc", AgentKnowledgeKind.DOCUMENT, "Reboot fixture", content))
            LlamaKnowledgeVectorEncoder.open(context, model, spec).use { encoder ->
                assertEquals(1, store(name).indexVectorChunks(encoder, 1).committedChunks)
            }
            assertEquals(1, requireNotNull(db(name).vectors(spec).nextJob()).count)
            assertNull(db(name).vectors(spec).page("reboot-doc"))
            proof.writeString("boot", boot.toString())
            proof.writeString("first_chunk_hash", firstCiphertextHash(name))
            println("KNOWLEDGE_VECTOR_REBOOT prepared boot=$boot committed_chunks=1")
        } else {
            check(boot > proof.readString("boot", "-1").toInt()) { "Device has not rebooted since preparation" }
            assertEquals(1, requireNotNull(db(name).vectors(spec).nextJob()).count)
            val originalHash = proof.readString("first_chunk_hash", "")
            assertEquals(originalHash, firstCiphertextHash(name))
            var generated = 0
            var pending = true
            LlamaKnowledgeVectorEncoder.open(context, model, spec).use { encoder ->
                repeat(1000) {
                    if (pending) store(name).indexVectorChunks(encoder).also {
                        generated += it.committedChunks; assertEquals(0, it.staleResults); pending = it.pending
                    }
                }
            }
            assertFalse(pending)
            requireNotNull(db(name).vectors(spec).page("reboot-doc", limit = 1)).use {
                assertEquals(generated + 1, it.total)
                println("KNOWLEDGE_VECTOR_REBOOT verified boot=$boot total_chunks=${it.total} new_chunks=$generated")
            }
            assertEquals(originalHash, firstCiphertextHash(name))
            assertEquals(content, store(name).findByIds(setOf("reboot-doc")).single().content)
            clean(name)
        }
    }

    private fun firstCiphertextHash(name: String): String = db(name).access { sql ->
        sql.rawQuery("SELECT ciphertext FROM knowledge_vectors WHERE ordinal=0", null).use {
            check(it.moveToFirst())
            val bytes = it.getBlob(0)
            try { MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { byte -> "%02x".format(byte) } }
            finally { bytes.fill(0) }
        }
    }
}
