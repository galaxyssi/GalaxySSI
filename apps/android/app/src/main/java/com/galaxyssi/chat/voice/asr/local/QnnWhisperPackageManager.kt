package com.galaxyssi.chat.voice.asr.local

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import com.galaxyssi.chat.VoiceAssistantSettings
import java.io.File
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class QnnWhisperPackage internal constructor(
    val id: String,
    val profileId: String,
    val displayName: String,
    val sizeBytes: Long,
    internal val modelRootName: String,
    internal val manifest: LargeTurboQnnModelManifest
) {
    val sizeLabel: String
        get() = String.format(Locale.ROOT, "%.1f MB", sizeBytes / 1_048_576.0)
}

enum class QnnWhisperPackageStatus {
    NOT_INSTALLED,
    DOWNLOADING,
    VERIFYING,
    READY,
    FAILED
}

data class QnnWhisperPackageState(
    val status: QnnWhisperPackageStatus,
    val progress: Int = 0,
    val detail: String = ""
)

object QnnWhisperPackageManager {
    val packages = CompactWhisperQnnModelCatalog.all.map { compact ->
        QnnWhisperPackage(
            id = compact.manifest.modelId,
            profileId = compact.profileId,
            displayName = compact.manifest.displayName,
            sizeBytes = compact.manifest.archive.sizeBytes,
            modelRootName = compact.modelRootName,
            manifest = compact.manifest
        )
    }

    private val executor = Executors.newFixedThreadPool(2) { runnable ->
        Thread(runnable, "GalaxySSI-QNN-Models").apply { isDaemon = true }
    }
    private val states = ConcurrentHashMap<String, QnnWhisperPackageState>()
    private val jobs = ConcurrentHashMap<String, Future<*>>()
    private val generations = ConcurrentHashMap<String, AtomicLong>()
    private val cancellations = ConcurrentHashMap<String, AtomicBoolean>()
    private val downloaders = ConcurrentHashMap<String, LargeTurboQnnModelDownloader>()
    private val initialized = ConcurrentHashMap.newKeySet<String>()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun supportedPackages(context: Context): List<QnnWhisperPackage> =
        if (WhisperQnnSupport.canInstall(context.applicationContext)) packages else emptyList()

    fun packageById(id: String): QnnWhisperPackage? = packages.firstOrNull { it.id == id }

    fun selectedPackage(context: Context): QnnWhisperPackage? {
        val config = VoiceAssistantSettings.get(context.applicationContext)
        return packageById(config.asrQnnPackage)
            ?: packages.firstOrNull { it.profileId == config.asrModel }
    }

    fun packageForProfile(profileId: String): QnnWhisperPackage? =
        packages.firstOrNull { it.profileId == profileId }

    fun modelRoot(context: Context, model: QnnWhisperPackage): File =
        store(context, model).inspectActive(model.manifest).directory
            ?: File(context.applicationContext.filesDir, "models/asr/${model.modelRootName}/s26u")

    fun isInstalled(context: Context, model: QnnWhisperPackage): Boolean {
        states[model.id]?.let { return it.status == QnnWhisperPackageStatus.READY }
        val installed = runCatching {
            store(context, model).inspectActive(model.manifest).state == QnnContextModelState.INSTALLED
        }.getOrDefault(false)
        if (installed) {
            initialized += model.id
            states[model.id] = QnnWhisperPackageState(QnnWhisperPackageStatus.READY, 100)
        }
        return installed
    }

    fun state(context: Context, model: QnnWhisperPackage): QnnWhisperPackageState {
        states[model.id]?.let { return it }
        if (initialized.add(model.id)) {
            states[model.id] = QnnWhisperPackageState(QnnWhisperPackageStatus.VERIFYING)
            executor.execute {
                val snapshot = runCatching { store(context, model).inspectActive(model.manifest) }
                    .getOrElse { error ->
                        states[model.id] = QnnWhisperPackageState(
                            QnnWhisperPackageStatus.FAILED,
                            detail = error.message.orEmpty()
                        )
                        return@execute
                    }
                states[model.id] = when (snapshot.state) {
                    QnnContextModelState.INSTALLED -> QnnWhisperPackageState(QnnWhisperPackageStatus.READY, 100)
                    QnnContextModelState.NOT_INSTALLED -> QnnWhisperPackageState(QnnWhisperPackageStatus.NOT_INSTALLED)
                    QnnContextModelState.INVALID -> QnnWhisperPackageState(
                        QnnWhisperPackageStatus.FAILED,
                        detail = snapshot.detail
                    )
                }
            }
        }
        return states[model.id] ?: QnnWhisperPackageState(QnnWhisperPackageStatus.VERIFYING)
    }

    fun hasActiveDownload(): Boolean = states.values.any {
        it.status == QnnWhisperPackageStatus.DOWNLOADING ||
            it.status == QnnWhisperPackageStatus.VERIFYING
    }

    fun enqueue(context: Context, model: QnnWhisperPackage, onChanged: () -> Unit = {}) {
        if (jobs[model.id]?.isDone == false) return
        val appContext = context.applicationContext
        val generation = generations.getOrPut(model.id, ::AtomicLong).incrementAndGet()
        val cancellation = cancellations.getOrPut(model.id, ::AtomicBoolean).also { it.set(false) }
        states[model.id] = QnnWhisperPackageState(QnnWhisperPackageStatus.DOWNLOADING)
        notifyChanged(onChanged)
        jobs[model.id] = executor.submit {
            val store = store(appContext, model)
            try {
                check(store.hasEnoughSpace(model.manifest)) { "Not enough storage to install the QNN ASR model" }
                val downloader = LargeTurboQnnModelDownloader(
                    root = store.downloadDirectory(),
                    networkGate = networkGate(appContext)
                )
                downloaders[model.id] = downloader
                val downloaded = downloader.download(
                    manifest = model.manifest,
                    networkPolicy = QnnModelDownloadNetworkPolicy.ANY_VALIDATED_NETWORK,
                    cancellation = QnnModelDownloadCancellation {
                        cancellation.get() || generations[model.id]?.get() != generation
                    }
                ) { progress ->
                    if (generations[model.id]?.get() != generation) return@download
                    states[model.id] = QnnWhisperPackageState(
                        status = if (progress.phase == QnnModelDownloadPhase.VERIFYING) {
                            QnnWhisperPackageStatus.VERIFYING
                        } else {
                            QnnWhisperPackageStatus.DOWNLOADING
                        },
                        progress = progress.percent,
                        detail = progress.assetName
                    )
                    notifyChanged(onChanged)
                }
                if (cancellation.get() || generations[model.id]?.get() != generation) return@submit
                store.install(
                    manifest = model.manifest,
                    archive = downloaded.archive,
                    archiveSha256 = downloaded.archiveSha256,
                    supportAssets = downloaded.supportAssets
                )
                VoiceAssistantSettings.setAsrQnnPackage(appContext, model.id, model.profileId)
                states[model.id] = QnnWhisperPackageState(QnnWhisperPackageStatus.READY, 100)
            } catch (_: QnnModelDownloadCancelledException) {
                if (generations[model.id]?.get() == generation) {
                    states[model.id] = QnnWhisperPackageState(QnnWhisperPackageStatus.NOT_INSTALLED)
                }
            } catch (error: Throwable) {
                if (generations[model.id]?.get() == generation) {
                    states[model.id] = QnnWhisperPackageState(
                        QnnWhisperPackageStatus.FAILED,
                        detail = error.message.orEmpty()
                    )
                }
            } finally {
                if (generations[model.id]?.get() == generation) {
                    jobs.remove(model.id)
                    downloaders.remove(model.id)
                    notifyChanged(onChanged)
                }
            }
        }
    }

    fun select(context: Context, model: QnnWhisperPackage) {
        if (state(context, model).status != QnnWhisperPackageStatus.READY) return
        VoiceAssistantSettings.setAsrQnnPackage(context.applicationContext, model.id, model.profileId)
    }

    fun cancel(context: Context, model: QnnWhisperPackage) {
        generations.getOrPut(model.id, ::AtomicLong).incrementAndGet()
        cancellations.getOrPut(model.id, ::AtomicBoolean).set(true)
        downloaders.remove(model.id)?.cancelActiveDownload()
        jobs.remove(model.id)?.cancel(true)
        states[model.id] = if (store(context, model).inspectActive(model.manifest).state ==
            QnnContextModelState.INSTALLED
        ) {
            QnnWhisperPackageState(QnnWhisperPackageStatus.READY, 100)
        } else {
            QnnWhisperPackageState(QnnWhisperPackageStatus.NOT_INSTALLED)
        }
    }

    fun delete(context: Context, model: QnnWhisperPackage) {
        cancel(context, model)
        store(context, model).deleteAll()
        states[model.id] = QnnWhisperPackageState(QnnWhisperPackageStatus.NOT_INSTALLED)
        val settings = VoiceAssistantSettings.get(context.applicationContext)
        if (settings.asrAcceleration == VoiceAssistantSettings.ASR_ACCELERATION_QNN &&
            settings.asrQnnPackage == model.id
        ) {
            VoiceAssistantSettings.setAsrAcceleration(
                context.applicationContext,
                VoiceAssistantSettings.ASR_ACCELERATION_GGML
            )
        }
    }

    private fun store(context: Context, model: QnnWhisperPackage) = LargeTurboQnnModelStore(
        filesDirectory = context.applicationContext.filesDir,
        modelRootName = model.modelRootName,
        deviceRootName = CompactWhisperQnnModelCatalog.DEVICE_ROOT_NAME
    )

    private fun networkGate(context: Context) = QnnModelDownloadNetworkGate {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return@QnnModelDownloadNetworkGate false
        val network = manager.activeNetwork ?: return@QnnModelDownloadNetworkGate false
        val capabilities = manager.getNetworkCapabilities(network)
            ?: return@QnnModelDownloadNetworkGate false
        capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    private fun notifyChanged(callback: () -> Unit) {
        mainHandler.post(callback)
    }
}
