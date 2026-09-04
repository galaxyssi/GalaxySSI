package com.galaxyssi.chat.voice.asr.local

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import com.galaxyssi.chat.VoiceAssistantSettings
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

enum class LargeTurboQnnModelStatus {
    CHECKING,
    NOT_INSTALLED,
    DOWNLOADING,
    PAUSED,
    VERIFYING,
    INSTALLING,
    READY,
    FAILED
}

data class LargeTurboQnnModelState(
    val status: LargeTurboQnnModelStatus,
    val progress: Int = 0,
    val detail: String = "",
    val resumed: Boolean = false
)

enum class LargeTurboQnnModelAction {
    DOWNLOAD,
    RESUME,
    PAUSE,
    RETRY,
    USE,
    CURRENT,
    WAIT,
    UNSUPPORTED
}

internal fun largeTurboQnnModelAction(
    state: LargeTurboQnnModelState,
    selected: Boolean,
    supported: Boolean
): LargeTurboQnnModelAction = when {
    !supported -> LargeTurboQnnModelAction.UNSUPPORTED
    state.status == LargeTurboQnnModelStatus.CHECKING -> LargeTurboQnnModelAction.WAIT
    state.status == LargeTurboQnnModelStatus.DOWNLOADING -> LargeTurboQnnModelAction.PAUSE
    state.status == LargeTurboQnnModelStatus.VERIFYING ||
        state.status == LargeTurboQnnModelStatus.INSTALLING -> LargeTurboQnnModelAction.WAIT
    state.status == LargeTurboQnnModelStatus.PAUSED -> LargeTurboQnnModelAction.RESUME
    state.status == LargeTurboQnnModelStatus.FAILED -> LargeTurboQnnModelAction.RETRY
    state.status == LargeTurboQnnModelStatus.READY && selected -> LargeTurboQnnModelAction.CURRENT
    state.status == LargeTurboQnnModelStatus.READY -> LargeTurboQnnModelAction.USE
    else -> LargeTurboQnnModelAction.DOWNLOAD
}

object LargeTurboQnnModelManager {
    const val PROFILE_ID = "large_v3_turbo"

    val manifest: LargeTurboQnnModelManifest = LargeTurboQnnModelCatalog.s26Ultra

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "GalaxySSI-QNN-Large-Turbo").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val generation = AtomicLong(0L)
    private val initialized = AtomicBoolean(false)
    private val cancellation = AtomicBoolean(false)
    private val stateLock = Any()
    @Volatile private var applicationContext: Context? = null
    private var job: Future<*>? = null
    private var activeDownloader: LargeTurboQnnModelDownloader? = null
    private var currentState = LargeTurboQnnModelState(LargeTurboQnnModelStatus.CHECKING)

    fun sizeLabel(): String {
        val bytes = manifest.archive.sizeBytes + manifest.supportAssets.sumOf(QnnContextSupportAsset::downloadSizeBytes)
        return String.format(Locale.ROOT, "%.1f GB", bytes / 1_000_000_000.0)
    }

    fun state(context: Context, onChanged: () -> Unit = {}): LargeTurboQnnModelState {
        val application = context.applicationContext
        bindContext(application)
        ensureInitialized(application, onChanged)
        return synchronized(stateLock) { currentState }
    }

    fun hasActiveWork(): Boolean = synchronized(stateLock) {
        currentState.status in setOf(
            LargeTurboQnnModelStatus.CHECKING,
            LargeTurboQnnModelStatus.DOWNLOADING,
            LargeTurboQnnModelStatus.VERIFYING,
            LargeTurboQnnModelStatus.INSTALLING
        )
    }

    fun deviceDecision(context: Context): QnnAsrDeviceDecision {
        bindContext(context.applicationContext)
        val modelState = synchronized(stateLock) {
            when (currentState.status) {
                LargeTurboQnnModelStatus.READY -> QnnContextModelState.INSTALLED
                LargeTurboQnnModelStatus.FAILED -> QnnContextModelState.INVALID
                else -> QnnContextModelState.NOT_INSTALLED
            }
        }
        val store = LargeTurboQnnModelStore(context.applicationContext.filesDir)
        val detector = AndroidLargeTurboQnnDeviceCapabilityDetector(context.applicationContext, store, manifest)
        return LargeTurboQnnDevicePolicy(manifest).evaluate(detector.snapshot(modelState))
    }

    fun enqueue(
        context: Context,
        networkPolicy: QnnModelDownloadNetworkPolicy,
        onChanged: () -> Unit = {}
    ) {
        bindContext(context.applicationContext)
        LargeTurboQnnModelDownloadService.start(context.applicationContext, networkPolicy)
        notifyChanged(onChanged)
    }

    internal fun enqueueInProcess(
        context: Context,
        networkPolicy: QnnModelDownloadNetworkPolicy,
        onChanged: () -> Unit = {}
    ) {
        val application = context.applicationContext
        bindContext(application)
        synchronized(stateLock) {
            if (job?.isDone == false) return
            cancellation.set(false)
            currentState = LargeTurboQnnModelState(LargeTurboQnnModelStatus.DOWNLOADING)
        }
        LargeTurboQnnModelStateStore(application).write(snapshot())
        notifyChanged(onChanged)
        val runGeneration = generation.incrementAndGet()
        job = executor.submit {
            val store = LargeTurboQnnModelStore(application.filesDir)
            try {
                val selection = LargeTurboQnnModelSource(
                    store,
                    AndroidLargeTurboQnnDeviceCapabilityDetector(application, store, manifest),
                    manifest
                ).select()
                check(selection.decision.eligibility != QnnAsrEligibility.FALLBACK_REQUIRED) {
                    selection.decision.detail
                }
                check(store.hasEnoughSpace(manifest)) { "Not enough storage to install the QNN ASR model" }
                val downloader = LargeTurboQnnModelDownloader(
                    root = store.downloadDirectory(),
                    networkGate = androidNetworkGate(application)
                )
                synchronized(stateLock) { activeDownloader = downloader }
                var lastProgress = -1
                var resumed = false
                val downloaded = downloader.download(
                    manifest = manifest,
                    networkPolicy = networkPolicy,
                    cancellation = QnnModelDownloadCancellation {
                        cancellation.get() || generation.get() != runGeneration
                    }
                ) { progress ->
                    if (generation.get() != runGeneration) return@download
                    resumed = resumed || progress.resumed
                    val nextStatus = if (progress.phase == QnnModelDownloadPhase.VERIFYING) {
                        LargeTurboQnnModelStatus.VERIFYING
                    } else {
                        LargeTurboQnnModelStatus.DOWNLOADING
                    }
                    if (progress.percent != lastProgress || nextStatus != snapshot().status) {
                        lastProgress = progress.percent
                        update(
                            LargeTurboQnnModelState(
                                status = nextStatus,
                                progress = progress.percent,
                                detail = progress.assetName,
                                resumed = resumed
                            ),
                            onChanged
                        )
                    }
                }
                if (generation.get() != runGeneration || cancellation.get()) {
                    update(LargeTurboQnnModelState(LargeTurboQnnModelStatus.PAUSED, lastProgress.coerceAtLeast(0)), onChanged)
                    return@submit
                }
                update(
                    LargeTurboQnnModelState(
                        LargeTurboQnnModelStatus.INSTALLING,
                        progress = 100,
                        resumed = downloaded.resumed
                    ),
                    onChanged
                )
                store.install(
                    manifest = manifest,
                    archive = downloaded.archive,
                    archiveSha256 = downloaded.archiveSha256,
                    supportAssets = downloaded.supportAssets
                )
                VoiceAssistantSettings.setAsrModel(application, PROFILE_ID)
                VoiceAssistantSettings.setAsrAcceleration(
                    application,
                    VoiceAssistantSettings.ASR_ACCELERATION_QNN
                )
                update(
                    LargeTurboQnnModelState(
                        LargeTurboQnnModelStatus.READY,
                        progress = 100,
                        resumed = downloaded.resumed
                    ),
                    onChanged
                )
            } catch (_: QnnModelDownloadCancelledException) {
                if (generation.get() == runGeneration) {
                    update(LargeTurboQnnModelState(LargeTurboQnnModelStatus.PAUSED), onChanged)
                }
            } catch (error: Throwable) {
                if (generation.get() == runGeneration) {
                    val paused = cancellation.get() || Thread.currentThread().isInterrupted
                    update(
                        LargeTurboQnnModelState(
                            status = if (paused) LargeTurboQnnModelStatus.PAUSED else LargeTurboQnnModelStatus.FAILED,
                            detail = if (paused) "" else error.message.orEmpty()
                        ),
                        onChanged
                    )
                }
            } finally {
                synchronized(stateLock) {
                    if (generation.get() == runGeneration) {
                        job = null
                        activeDownloader = null
                    }
                }
            }
        }
    }

    fun pause(context: Context, onChanged: () -> Unit = {}) {
        bindContext(context.applicationContext)
        LargeTurboQnnModelDownloadService.pause(context.applicationContext)
        notifyChanged(onChanged)
    }

    internal fun pauseInProcess(onChanged: () -> Unit = {}) {
        cancellation.set(true)
        val downloader = synchronized(stateLock) {
            job?.cancel(true)
            job = null
            currentState = currentState.copy(status = LargeTurboQnnModelStatus.PAUSED)
            activeDownloader.also { activeDownloader = null }
        }
        downloader?.cancelActiveDownload()
        applicationContext?.let { LargeTurboQnnModelStateStore(it).write(snapshot()) }
        notifyChanged(onChanged)
    }

    fun select(context: Context) {
        bindContext(context.applicationContext)
        if (snapshot().status != LargeTurboQnnModelStatus.READY) return
        VoiceAssistantSettings.setAsrModel(context.applicationContext, PROFILE_ID)
        VoiceAssistantSettings.setAsrAcceleration(
            context.applicationContext,
            VoiceAssistantSettings.ASR_ACCELERATION_QNN
        )
    }

    fun delete(context: Context, onChanged: () -> Unit = {}) {
        bindContext(context.applicationContext)
        pauseInProcess()
        generation.incrementAndGet()
        LargeTurboQnnModelStore(context.applicationContext.filesDir).deleteAll()
        if (VoiceAssistantSettings.get(context).asrAcceleration == VoiceAssistantSettings.ASR_ACCELERATION_QNN &&
            VoiceAssistantSettings.get(context).asrModel == PROFILE_ID
        ) {
            VoiceAssistantSettings.setAsrAcceleration(
                context.applicationContext,
                VoiceAssistantSettings.ASR_ACCELERATION_GGML
            )
        }
        initialized.set(true)
        update(LargeTurboQnnModelState(LargeTurboQnnModelStatus.NOT_INSTALLED), onChanged)
    }

    private fun ensureInitialized(context: Context, onChanged: () -> Unit) {
        if (!initialized.compareAndSet(false, true)) return
        executor.execute {
            val inspected = runCatching {
                LargeTurboQnnModelStore(context.filesDir).inspectActive(manifest)
            }.getOrElse { error ->
                update(
                    LargeTurboQnnModelState(LargeTurboQnnModelStatus.FAILED, detail = error.message.orEmpty()),
                    onChanged
                )
                return@execute
            }
            val state = when (inspected.state) {
                QnnContextModelState.INSTALLED -> LargeTurboQnnModelState(
                    LargeTurboQnnModelStatus.READY,
                    progress = 100
                )
                QnnContextModelState.NOT_INSTALLED -> LargeTurboQnnModelState(
                    LargeTurboQnnModelStatus.NOT_INSTALLED
                )
                QnnContextModelState.INVALID -> LargeTurboQnnModelState(
                    LargeTurboQnnModelStatus.FAILED,
                    detail = inspected.detail
                )
            }
            update(state, onChanged)
        }
    }

    private fun snapshot(): LargeTurboQnnModelState = synchronized(stateLock) { currentState }

    private fun update(state: LargeTurboQnnModelState, callback: () -> Unit) {
        synchronized(stateLock) { currentState = state }
        applicationContext?.let { LargeTurboQnnModelStateStore(it).write(state) }
        notifyChanged(callback)
    }

    private fun notifyChanged(callback: () -> Unit) {
        mainHandler.post(callback)
    }

    private fun bindContext(context: Context) {
        val application = context.applicationContext
        applicationContext = application
        val store = LargeTurboQnnModelStateStore(application)
        val persisted = store.read() ?: return
        val stale = persisted.state.status.isPersistedActiveState() &&
            !LargeTurboQnnModelDownloadService.running &&
            System.currentTimeMillis() - persisted.updatedAtMillis > STALE_ACTIVE_STATE_MS
        val restored = if (stale) {
            persisted.state.copy(status = LargeTurboQnnModelStatus.PAUSED).also(store::write)
        } else {
            persisted.state
        }
        synchronized(stateLock) { currentState = restored }
        if (restored.status == LargeTurboQnnModelStatus.PAUSED || restored.status.isPersistedActiveState()) {
            initialized.set(true)
        }
    }

    private fun LargeTurboQnnModelStatus.isPersistedActiveState(): Boolean = this in setOf(
        LargeTurboQnnModelStatus.DOWNLOADING,
        LargeTurboQnnModelStatus.VERIFYING,
        LargeTurboQnnModelStatus.INSTALLING
    )

    private fun androidNetworkGate(context: Context) = QnnModelDownloadNetworkGate { policy ->
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return@QnnModelDownloadNetworkGate false
        val network = manager.activeNetwork ?: return@QnnModelDownloadNetworkGate false
        val capabilities = manager.getNetworkCapabilities(network)
            ?: return@QnnModelDownloadNetworkGate false
        val validated = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        validated && (policy == QnnModelDownloadNetworkPolicy.ANY_VALIDATED_NETWORK ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI))
    }

    private const val STALE_ACTIVE_STATE_MS = 30_000L
}
