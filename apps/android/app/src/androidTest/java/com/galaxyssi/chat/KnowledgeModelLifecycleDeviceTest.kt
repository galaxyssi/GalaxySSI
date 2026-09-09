package com.galaxyssi.chat

import android.content.Context
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkInfo
import androidx.work.WorkManager
import java.io.ByteArrayInputStream
import java.io.Closeable
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeModelLifecycleDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val fixture get() = File(context.getExternalFilesDir(null), "embedding-test/${KnowledgeEmbeddingModel.FILE}")

    @Test fun downloadImportAndCancelledRequestsNeverActivateUnverifiedFiles() = Fixture(context).use { test ->
        assertFalse(test.controller.state.enabled)
        assertFalse(test.controller.state.installed)
        assertNull(test.controller.searchSession())
        assertTrue(runCatching { test.controller.importModel { ByteArrayInputStream(byteArrayOf(1, 2, 3)) }.get() }.isFailure)
        assertFalse(test.controller.modelFile.exists())
        assertFalse(test.controller.state.enabled)
        assertTrue(runCatching { test.controller.setEnabled(true).get() }.isFailure)
        assertTrue(runCatching { test.controller.completeDownload("stale-request").get() }.isFailure)
        assertFalse(test.controller.state.enabled)
    }

    @Test fun cancelledQueuedDownloadDoesNotStartOrChangeTheSavedSetting() = Fixture(context).use { test ->
        repeat(20) {
            test.controller.download()
            test.controller.cancelDownload()
        }
        test.controller.setEnabled(false).get(40, TimeUnit.SECONDS)
        assertFalse(test.controller.state.enabled)
        assertFalse(test.controller.acceptsDownload("stale"))
        val config = AgentEncryptedPreferences(context, "knowledge-model-${test.namespace}").readString("configuration", "")
        assertEquals("", org.json.JSONObject(config).getString("download_request"))
    }

    @Test fun pinnedImportAutomaticallyIndexesNewContentAndNormalRagUsesTheModel() = Fixture(context).use { test ->
        requireFixture()
        test.controller.importModel { fixture.inputStream() }.get(60, TimeUnit.SECONDS)
        assertTrue(test.controller.state.installed)
        assertTrue(test.controller.state.enabled)
        val passages = listOf(
            "\u624b\u673a\u4e22\u5931\u540e\u53ef\u4ee5\u901a\u8fc7\u5b9a\u4f4d\u529f\u80fd\u67e5\u627e\u8bbe\u5907",
            "\u4fee\u6539\u767b\u5f55\u5bc6\u7801\u9700\u8981\u5728\u8d26\u53f7\u5b89\u5168\u9875\u9762\u8fdb\u884c",
            "\u6570\u636e\u5e93\u5efa\u7acb\u7d22\u5f15\u53ef\u4ee5\u52a0\u5feb\u67e5\u8be2\u901f\u5ea6")
        passages.forEachIndexed { id, content -> test.store.upsert(AgentKnowledgeItem("doc-$id", AgentKnowledgeKind.NOTE, "Document $id", content)) }
        await("automatic index: ${test.namespace}") {
            test.controller.refreshCounts()
            test.controller.state.pendingDocuments == 0L && test.controller.state.indexedChunks == 3L && test.idle()
        }
        KnowledgeSemanticSearch.resumeRuntime()
        val queries = listOf("\u6211\u7684\u7535\u8bdd\u627e\u4e0d\u5230\u4e86\u600e\u4e48\u529e",
            "\u600e\u6837\u66f4\u6362\u8d26\u6237\u53e3\u4ee4", "\u600e\u6837\u8ba9SQL\u68c0\u7d22\u66f4\u5feb")
        queries.forEachIndexed { id, query ->
            assertEquals("doc-$id", AgentKnowledgeRetriever.retrieve(test.store, query, "agent-knowledge-local", 1).citations.single().itemId)
        }
        assertTrue(test.controller.searchSession()!!.status.startsWith("ready:"))
        println("KNOWLEDGE_MODEL_LIFECYCLE automatic_index=3 native_rag_recall=3/3")
        test.store.close()
        test.store = SQLiteAgentKnowledgeStore(context, test.database, test.legacy) { _, _ -> }
        assertEquals("doc-0", test.store.search(queries[0], 1).single().id)
        test.controller.setEnabled(false).get()
        assertNull(test.controller.searchSession())
        assertEquals(3, test.store.list(10).size)
        assertTrue(test.controller.modelFile.isFile)
    }

    @Test fun failedReplacementPreservesTheInstalledModelAndEnabledState() = Fixture(context).use { test ->
        requireFixture()
        test.controller.importModel { fixture.inputStream() }.get(60, TimeUnit.SECONDS)
        await("empty index settles") { test.idle() }
        assertTrue(runCatching { test.controller.importModel { ByteArrayInputStream(ByteArray(64)) }.get() }.isFailure)
        test.controller.artifact.verifyInstalled()
        assertTrue(test.controller.state.enabled)
        test.controller.setEnabled(false).get()
        assertFalse(test.controller.state.enabled)
    }

    @Test fun startupReconcilesAPersistedDownloadWithoutAnEnqueuedWorker() = Fixture(context).use { test ->
        requireFixture()
        fixture.inputStream().use { test.controller.artifact.importFile(it) }
        AgentEncryptedPreferences(context, "knowledge-model-${test.namespace}").writeString("configuration",
            org.json.JSONObject().put("model", KnowledgeEmbeddingModel.ID).put("enabled", false)
                .put("download_request", "interrupted-before-enqueue").toString())
        test.reopen()
        await("installed download receipt reconciles") { test.controller.state.enabled && test.idle() }
        assertTrue(test.controller.state.installed)
        test.controller.artifact.verifyInstalled()
        assertFalse(test.controller.acceptsDownload("interrupted-before-enqueue"))
    }

    @Test fun savedModelChoiceAndPendingIndexResumeWhenControllerIsRecreated() = Fixture(context).use { test ->
        requireFixture()
        test.controller.importModel { fixture.inputStream() }.get(60, TimeUnit.SECONDS)
        // An empty WorkManager query can precede the controller's asynchronous enqueue.
        // Establish the registered model before testing its durable mutation queue.
        await("initial model registration and worker settle") {
            val key = test.controller.database().vectors(KnowledgeEmbeddingModel.spec).modelKey
            val registered = test.controller.database().access { db ->
                db.rawQuery("SELECT 1 FROM knowledge_vector_models WHERE model_key=?", arrayOf(key)).use { it.moveToFirst() }
            }
            registered && test.idle()
        }
        test.controller.setEnabled(false).get()
        test.store.upsert(AgentKnowledgeItem("pending", AgentKnowledgeKind.NOTE, "Pending", "\u624b\u673a\u4e22\u5931\u540e\u4f7f\u7528\u5b9a\u4f4d\u529f\u80fd"))
        test.controller.refreshCounts()
        assertEquals(1L, test.controller.state.pendingDocuments)
        test.reopen()
        assertTrue(test.controller.state.installed)
        assertFalse(test.controller.state.enabled)
        test.controller.setEnabled(true).get()
        await("durable queue resumes") {
            test.controller.refreshCounts()
            test.controller.state.indexedChunks == 1L && test.controller.state.pendingDocuments == 0L && test.idle()
        }
        assertEquals(1, test.store.list(10).size)
    }

    @Test fun burstMutationsCreateBoundedWorkAndAllDocumentsAreIndexed() = Fixture(context).use { test ->
        requireFixture()
        test.controller.importModel { fixture.inputStream() }.get(60, TimeUnit.SECONDS)
        repeat(40) { id ->
            test.store.upsert(AgentKnowledgeItem("burst-$id", AgentKnowledgeKind.NOTE, "Burst $id", "\u77e5\u8bc6\u7d22\u5f15\u6062\u590d\u6d4b\u8bd5 $id"))
            repeat(10) { test.controller.requestIndex() }
        }
        val pending = WorkManager.getInstance(context).getWorkInfosForUniqueWork("knowledge-index-v1-${test.namespace}").get()
            .count { it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.BLOCKED }
        assertTrue("Too many pending workers: $pending", pending <= 1)
        await("all 40 documents") {
            test.controller.refreshCounts()
            test.controller.state.indexedChunks == 40L && test.controller.state.pendingDocuments == 0L && test.idle()
        }
        println("KNOWLEDGE_MODEL_LIFECYCLE burst_documents=40 complete=40 pending_workers_max=1")
    }

    private fun requireFixture() = check(fixture.length() == KnowledgeEmbeddingModel.BYTES) { "Pinned BGE fixture is required, not skipped" }

    private class Fixture(val context: Context) : Closeable {
        val namespace = "test-model-${UUID.randomUUID()}"
        val database = "$namespace.db"
        val legacy = "legacy-$namespace"
        var controller = KnowledgeSemanticController(context, namespace, database, legacy)
        var store = SQLiteAgentKnowledgeStore(context, database, legacy) { _, _ -> }
        init { KnowledgeSemanticRuntime.registerTest(controller); controller.awaitReady() }
        fun idle(): Boolean = controller.runningWork.get() == 0 && WorkManager.getInstance(context)
            .getWorkInfosForUniqueWork("knowledge-index-v1-$namespace").get().all { it.state.isFinished }
        fun reopen() {
            await("before reopen") { idle() }
            KnowledgeSemanticRuntime.removeTest(namespace)
            store.close()
            controller = KnowledgeSemanticController(context, namespace, database, legacy)
            KnowledgeSemanticRuntime.registerTest(controller)
            controller.awaitReady()
            store = SQLiteAgentKnowledgeStore(context, database, legacy) { _, _ -> }
        }
        override fun close() {
            controller.setEnabled(false).get(40, TimeUnit.SECONDS)
            val manager = WorkManager.getInstance(context)
            manager.cancelUniqueWork("knowledge-index-v1-$namespace").result.get()
            manager.cancelUniqueWork("knowledge-model-v1-$namespace").result.get()
            await("workers release fixture") { controller.runningWork.get() == 0 }
            KnowledgeSemanticRuntime.removeTest(namespace)
            store.close()
            context.deleteDatabase(database)
            AgentEncryptedPreferences(context, legacy).clear()
            AgentEncryptedPreferences(context, "knowledge-model-$namespace").clear()
            check(controller.modelFile.parentFile!!.canonicalFile == File(context.filesDir, "knowledge-models/$namespace").canonicalFile)
            controller.modelFile.parentFile!!.listFiles()?.forEach { check(it.delete()) }
            check(controller.modelFile.parentFile!!.delete() || !controller.modelFile.parentFile!!.exists())
        }
    }
    companion object {
        private fun await(label: String, condition: () -> Boolean) {
            val deadline = SystemClock.elapsedRealtime() + 180_000
            while (!condition()) {
                check(SystemClock.elapsedRealtime() < deadline) { "Timed out: $label" }
                SystemClock.sleep(100)
            }
        }
    }
}
