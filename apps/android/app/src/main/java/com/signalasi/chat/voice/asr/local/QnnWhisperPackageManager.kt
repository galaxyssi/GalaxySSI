package com.signalasi.chat.voice.asr.local

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.signalasi.chat.VoiceAssistantSettings
import kotlinx.coroutines.runBlocking
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicLong

data class QnnWhisperPackage(
    val id: String,
    val profileId: String,
    val displayName: String,
    val variant: String,
    val sizeBytes: Long
) {
    val sizeLabel: String
        get() = String.format("%.0f MB", sizeBytes / 1_000_000.0)
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
    val packages = listOf(
        QnnWhisperPackage(
            id = "tiny_qnn",
            profileId = "tiny",
            displayName = "Tiny QNN",
            variant = "whisperkit-litert/openai_whisper-tiny",
            sizeBytes = 155_232_685L
        ),
        QnnWhisperPackage(
            id = "base_qnn",
            profileId = "base",
            displayName = "Base QNN",
            variant = "whisperkit-litert/openai_whisper-base",
            sizeBytes = 294_735_793L
        )
    )

    private val downloader = QnnWhisperModelDownloader()
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "SignalASI-QNN-Models").apply { isDaemon = true }
    }
    private val states = ConcurrentHashMap<String, QnnWhisperPackageState>()
    private val jobs = ConcurrentHashMap<String, Future<*>>()
    private val generations = ConcurrentHashMap<String, AtomicLong>()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun supportedPackages(context: Context): List<QnnWhisperPackage> =
        if (WhisperQnnSupport.canInstall(context.applicationContext)) packages else emptyList()

    fun packageForProfile(profileId: String): QnnWhisperPackage? = packages.firstOrNull { it.profileId == profileId }

    fun modelRoot(context: Context, model: QnnWhisperPackage): File = File(
        context.applicationContext.filesDir,
        "argmaxinc/models/${model.variant.substringAfterLast('/')}"
    )

    fun isInstalled(context: Context, model: QnnWhisperPackage): Boolean =
        downloader.isInstalled(model.variant, modelRoot(context, model))

    fun state(context: Context, model: QnnWhisperPackage): QnnWhisperPackageState {
        states[model.id]?.let { return it }
        return if (isInstalled(context, model)) {
            QnnWhisperPackageState(QnnWhisperPackageStatus.READY, 100)
        } else {
            QnnWhisperPackageState(QnnWhisperPackageStatus.NOT_INSTALLED)
        }
    }

    fun hasActiveDownload(): Boolean = states.values.any {
        it.status == QnnWhisperPackageStatus.DOWNLOADING ||
            it.status == QnnWhisperPackageStatus.VERIFYING
    }

    fun enqueue(context: Context, model: QnnWhisperPackage, onChanged: () -> Unit = {}) {
        if (jobs[model.id]?.isDone == false) return
        val appContext = context.applicationContext
        val generation = generations.getOrPut(model.id, ::AtomicLong).incrementAndGet()
        states[model.id] = QnnWhisperPackageState(QnnWhisperPackageStatus.DOWNLOADING)
        notifyChanged(onChanged)
        jobs[model.id] = executor.submit {
            try {
                runBlocking {
                    downloader.install(model.variant, modelRoot(appContext, model)) { progress ->
                        if (isCurrent(model.id, generation)) {
                            states[model.id] = QnnWhisperPackageState(
                                status = if (progress >= 100) {
                                    QnnWhisperPackageStatus.VERIFYING
                                } else {
                                    QnnWhisperPackageStatus.DOWNLOADING
                                },
                                progress = progress
                            )
                            notifyChanged(onChanged)
                        }
                    }
                }
                if (!isCurrent(model.id, generation)) return@submit
                VoiceAssistantSettings.setAsrModel(appContext, model.profileId)
                VoiceAssistantSettings.setAsrAcceleration(
                    appContext,
                    VoiceAssistantSettings.ASR_ACCELERATION_QNN
                )
                states[model.id] = QnnWhisperPackageState(QnnWhisperPackageStatus.READY, 100)
            } catch (error: Throwable) {
                if (isCurrent(model.id, generation)) {
                    states[model.id] = QnnWhisperPackageState(
                        QnnWhisperPackageStatus.FAILED,
                        detail = error.message.orEmpty()
                    )
                }
            } finally {
                if (isCurrent(model.id, generation)) {
                    jobs.remove(model.id)
                    notifyChanged(onChanged)
                }
            }
        }
    }

    fun cancel(context: Context, model: QnnWhisperPackage) {
        generations.getOrPut(model.id, ::AtomicLong).incrementAndGet()
        jobs.remove(model.id)?.cancel(true)
        modelRoot(context, model).listFiles()
            .orEmpty()
            .filter { it.name.startsWith(".") && it.name.endsWith(".part") }
            .forEach(File::delete)
        states[model.id] = QnnWhisperPackageState(QnnWhisperPackageStatus.NOT_INSTALLED)
    }

    fun delete(context: Context, model: QnnWhisperPackage) {
        cancel(context, model)
        modelRoot(context, model).deleteRecursively()
        states.remove(model.id)
        if (VoiceAssistantSettings.get(context).asrAcceleration == VoiceAssistantSettings.ASR_ACCELERATION_QNN &&
            VoiceAssistantSettings.get(context).asrModel == model.profileId
        ) {
            VoiceAssistantSettings.setAsrAcceleration(context, VoiceAssistantSettings.ASR_ACCELERATION_GGML)
        }
    }

    private fun notifyChanged(callback: () -> Unit) {
        mainHandler.post(callback)
    }

    private fun isCurrent(modelId: String, generation: Long): Boolean =
        generations[modelId]?.get() == generation
}
