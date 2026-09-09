package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.io.InputStream
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import java.util.UUID
import java.util.concurrent.CancellationException
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicInteger

internal data class KnowledgeModelState(val loaded: Boolean = false, val installed: Boolean = false,
    val enabled: Boolean = false, val phase: String = "loading", val downloaded: Long = 0,
    val indexedChunks: Long = 0, val pendingDocuments: Long = 0, val error: String = "")

/** One model/session owner per database, not one model load for each ephemeral store facade. */
internal class KnowledgeSemanticController(
    context: Context, val namespace: String, val databaseName: String, val legacyName: String
) : Closeable {
    val context = context.applicationContext
    private val preferences = AgentEncryptedPreferences(this.context, "knowledge-model-$namespace")
    val modelFile = File(this.context.filesDir, "knowledge-models/$namespace/${KnowledgeEmbeddingModel.FILE}")
    val artifact = VerifiedKnowledgeModelFile(modelFile, KnowledgeEmbeddingModel.BYTES, KnowledgeEmbeddingModel.SHA256)
    private val executor = Executors.newSingleThreadExecutor { task -> Thread(task, "knowledge-model-$namespace").apply { isDaemon = true } }
    private val listeners = CopyOnWriteArraySet<(KnowledgeModelState) -> Unit>()
    private val ready = CompletableFuture<Unit>()
    private val transferEpoch = AtomicLong()
    private val transferLock = Any()
    private val indexRequested = AtomicBoolean()
    internal val runningWork = AtomicInteger()
    @Volatile private var closed = false
    @Volatile private var downloadRequest = ""
    @Volatile var state = KnowledgeModelState()
        private set
    val indexingEnabled: Boolean get() = !closed && state.enabled && state.installed
    val downloadPending: Boolean get() = !closed && downloadRequest.isNotBlank()
    private var retrieval: KnowledgeSemanticSearch? = null
    init {
        require(namespace.matches(Regex("[a-z0-9-]+")))
        executor.execute {
            try {
                val raw = preferences.readString("configuration", "")
                val config = if (raw.isBlank()) JSONObject() else JSONObject(raw)
                require(config.optString("model", KnowledgeEmbeddingModel.ID) == KnowledgeEmbeddingModel.ID)
                val enabled = config.optBoolean("enabled", false)
                downloadRequest = config.optString("download_request", "")
                val installed = artifact.installed()
                update { it.copy(loaded = true, installed = installed, enabled = enabled,
                    phase = if (installed) "ready" else "not_installed", downloaded = artifact.partialBytes()) }
                ready.complete(Unit)
                if (installed) refreshCounts()
                if (downloadRequest.isNotBlank()) KnowledgeModelWork.download(this.context, namespace, downloadRequest, recover = true)
                if (enabled && installed) requestIndex()
            } catch (error: Exception) {
                update { it.copy(loaded = true, phase = "error", error = error.javaClass.simpleName) }
                ready.completeExceptionally(error)
            }
        }
    }
    fun awaitReady() { ready.get() }
    fun observe(listener: (KnowledgeModelState) -> Unit): Closeable {
        listeners.add(listener); listener(state)
        return Closeable { listeners.remove(listener) }
    }
    @Synchronized fun update(change: (KnowledgeModelState) -> KnowledgeModelState) {
        if (closed) return
        state = change(state)
        listeners.forEach { listener -> runCatching { listener(state) } }
    }
    @Synchronized fun searchSession(): KnowledgeSemanticSearch? {
        if (closed || !state.loaded || !state.enabled || !state.installed) return null
        return retrieval ?: KnowledgeSemanticSearch(database(), KnowledgeEmbeddingModel.spec, {
            LlamaKnowledgeVectorEncoder.open(context, modelFile, KnowledgeEmbeddingModel.spec)
        }).also { retrieval = it }
    }
    fun database() = AgentKnowledgeDatabase.shared(context, databaseName, legacyName)
    fun setEnabled(enabled: Boolean): CompletableFuture<Unit> {
        if (!enabled) cancelDownload()
        return submit {
            awaitReady()
            if (enabled) artifact.verifyInstalled()
            if (!enabled) downloadRequest = ""
            persist(enabled)
            invalidateSession()
            update { it.copy(enabled = enabled, installed = artifact.installed(), phase = if (enabled) "ready" else "disabled", error = "") }
            if (enabled) requestIndex() else KnowledgeModelWork.cancelIndex(context, namespace)
        }
    }
    fun importModel(input: () -> InputStream): CompletableFuture<Unit> {
        val epoch = transferEpoch.incrementAndGet()
        downloadRequest = ""
        return submit {
            awaitReady()
            downloadRequest = ""
            KnowledgeModelWork.cancelDownload(context, namespace)
            update { it.copy(phase = "importing", error = "") }
            synchronized(artifact) { input().use { artifact.importFile(it, { closed || transferEpoch.get() != epoch }) { n -> update { state -> state.copy(downloaded = n) } } } }
            enableInstalled(epoch)
        }
    }
    private fun enableInstalled(epoch: Long) {
        artifact.verifyInstalled { closed || transferEpoch.get() != epoch }
        synchronized(transferLock) {
            if (closed || transferEpoch.get() != epoch) throw CancellationException("Superseded model activation")
            downloadRequest = ""
            persist(true)
            invalidateSession()
            update { it.copy(installed = true, enabled = true, phase = "ready", downloaded = KnowledgeEmbeddingModel.BYTES, error = "") }
        }
        requestIndex()
    }
    fun download(): CompletableFuture<Unit> {
        val epoch = transferEpoch.incrementAndGet()
        return submit {
            awaitReady()
            val request = synchronized(transferLock) {
                if (transferEpoch.get() != epoch) throw CancellationException("Superseded model download")
                downloadRequest = UUID.randomUUID().toString()
                persist(state.enabled)
                update { it.copy(phase = "downloading", error = "") }
                downloadRequest
            }
            KnowledgeModelWork.download(context, namespace, request)
        }
    }
    fun cancelDownload() {
        synchronized(transferLock) { transferEpoch.incrementAndGet(); downloadRequest = "" }
        KnowledgeModelWork.cancelDownload(context, namespace)
        update { it.copy(phase = if (it.installed) "ready" else "not_installed") }
        submit { persist(state.enabled) }
    }
    fun acceptsDownload(request: String): Boolean = !closed && request.isNotBlank() && request == downloadRequest
    fun completeDownload(request: String): CompletableFuture<Unit> = submit {
        val epoch = transferEpoch.get()
        if (!acceptsDownload(request)) throw CancellationException("Superseded model download")
        enableInstalled(epoch)
    }
    fun failDownload(request: String, error: Exception): CompletableFuture<Unit> = submit {
        if (acceptsDownload(request)) {
            downloadRequest = ""
            persist(state.enabled)
            update { it.copy(phase = "error", error = error.message.orEmpty().take(180)) }
        }
    }
    private fun persist(enabled: Boolean) = synchronized(transferLock) {
        if (closed) throw CancellationException("Knowledge model controller is closed")
        preferences.writeString("configuration", JSONObject().put("model", KnowledgeEmbeddingModel.ID)
            .put("enabled", enabled).put("download_request", downloadRequest).toString())
    }
    fun requestIndex() {
        if (closed || !indexRequested.compareAndSet(false, true)) return
        submit {
            indexRequested.set(false)
            if (indexingEnabled) KnowledgeModelWork.requestIndex(context, namespace)
        }.whenComplete { _, error -> if (error != null) indexRequested.set(false) }
    }
    fun refreshCounts() {
        if (closed) return
        val ledger = database().vectors(KnowledgeEmbeddingModel.spec)
        val counts = database().access { db ->
            val chunks = db.rawQuery("SELECT count(*) FROM knowledge_vectors WHERE model_key=?", arrayOf(ledger.modelKey)).use {
                check(it.moveToFirst()); it.getLong(0)
            }
            val pending = db.rawQuery("SELECT count(*) FROM knowledge_vector_queue WHERE model_key=?", arrayOf(ledger.modelKey)).use {
                check(it.moveToFirst()); it.getLong(0)
            }
            chunks to pending
        }
        update { it.copy(indexedChunks = counts.first, pendingDocuments = counts.second) }
    }
    private fun submit(action: () -> Unit): CompletableFuture<Unit> {
        val result = CompletableFuture<Unit>()
        try { executor.execute {
            try { check(!closed); action(); result.complete(Unit) }
            catch (error: Exception) {
                if (error !is CancellationException) update { it.copy(phase = "error", error = error.message.orEmpty().take(180)) }
                result.completeExceptionally(error)
            }
        } } catch (error: RejectedExecutionException) { result.completeExceptionally(error) }
        return result
    }
    @Synchronized fun invalidateSession() { retrieval?.close(); retrieval = null }
    override fun close() {
        synchronized(transferLock) { closed = true; transferEpoch.incrementAndGet(); downloadRequest = "" }
        invalidateSession()
        listeners.clear(); executor.shutdown()
    }
}

internal object KnowledgeSemanticRuntime {
    const val DATABASE = "galaxyssi_knowledge_v2.db"
    const val LEGACY = "galaxyssi_agent_knowledge"
    private val controllers = ConcurrentHashMap<String, KnowledgeSemanticController>()
    fun production(context: Context): KnowledgeSemanticController = controllers.computeIfAbsent("production") {
        KnowledgeSemanticController(context, "production", DATABASE, LEGACY)
    }
    fun forStore(context: Context, name: String): KnowledgeSemanticController? =
        if (name == DATABASE) production(context) else controllers.values.firstOrNull { it.databaseName == name }
    fun forWorker(context: Context, namespace: String): KnowledgeSemanticController =
        if (namespace == "production") production(context) else requireNotNull(controllers[namespace]) { "Test model namespace is not registered" }
    internal fun registerTest(controller: KnowledgeSemanticController) {
        require(controller.namespace.startsWith("test-")); check(controllers.putIfAbsent(controller.namespace, controller) == null)
    }
    internal fun removeTest(namespace: String) { require(namespace.startsWith("test-")); controllers.remove(namespace)?.close() }
    fun invalidateDatabase(name: String) { controllers.values.filter { it.databaseName == name }.forEach { it.invalidateSession() } }
    fun closeForPrivateDataReset() {
        controllers.values.forEach { controller ->
            controller.close()
            KnowledgeModelWork.cancelIndex(controller.context, controller.namespace)
            KnowledgeModelWork.cancelDownload(controller.context, controller.namespace)
        }
        controllers.clear()
    }
}
