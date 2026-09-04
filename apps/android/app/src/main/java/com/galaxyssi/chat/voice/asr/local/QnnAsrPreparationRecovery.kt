package com.galaxyssi.chat.voice.asr.local

import java.io.File
import java.io.IOException
import java.util.Locale

enum class QnnAsrLoadFailureKind {
    MODEL_CORRUPT,
    RUNTIME_MISSING,
    RUNTIME_INCOMPATIBLE,
    CHIPSET_INCOMPATIBLE,
    OUT_OF_MEMORY,
    TRANSIENT_RUNTIME,
    UNKNOWN
}

data class QnnAsrLoadFailure(
    val kind: QnnAsrLoadFailureKind,
    val reasonCode: String,
    val detail: String,
    val retrySameModel: Boolean,
    val quarantineModel: Boolean
)

class QnnAsrLoadFailureClassifier {
    fun classify(error: Throwable): QnnAsrLoadFailure {
        val causes = generateSequence(error) { it.cause }.toList()
        val message = causes.joinToString(" ") { it.message.orEmpty() }.lowercase(Locale.ROOT)
        return when {
            causes.any { it is OutOfMemoryError } || MEMORY_MARKERS.any(message::contains) -> failure(
                QnnAsrLoadFailureKind.OUT_OF_MEMORY,
                "qnn_out_of_memory",
                error,
                retrySameModel = false
            )
            causes.any { it is UnsatisfiedLinkError || it is NoClassDefFoundError } ||
                RUNTIME_MISSING_MARKERS.any(message::contains) -> failure(
                    QnnAsrLoadFailureKind.RUNTIME_MISSING,
                    "qnn_runtime_missing",
                    error,
                    retrySameModel = false
                )
            RUNTIME_VERSION_MARKERS.any(message::contains) -> failure(
                QnnAsrLoadFailureKind.RUNTIME_INCOMPATIBLE,
                "qnn_runtime_incompatible",
                error,
                retrySameModel = false
            )
            CHIPSET_MARKERS.any(message::contains) -> failure(
                QnnAsrLoadFailureKind.CHIPSET_INCOMPATIBLE,
                "qnn_chipset_incompatible",
                error,
                retrySameModel = false
            )
            MODEL_MARKERS.any(message::contains) || causes.any { it is QnnContextModelInstallException } -> failure(
                QnnAsrLoadFailureKind.MODEL_CORRUPT,
                "qnn_model_corrupt",
                error,
                retrySameModel = false,
                quarantineModel = true
            )
            causes.any { it is IOException } || TRANSIENT_MARKERS.any(message::contains) -> failure(
                QnnAsrLoadFailureKind.TRANSIENT_RUNTIME,
                "qnn_runtime_transient",
                error,
                retrySameModel = true
            )
            else -> failure(
                QnnAsrLoadFailureKind.UNKNOWN,
                causes.filterIsInstance<QnnAsrPreparationException>().firstOrNull()
                    ?.let { "qnn_prepare_${it.stage.code}" }
                    ?: "qnn_prepare_unknown",
                error,
                retrySameModel = true
            )
        }
    }

    private fun failure(
        kind: QnnAsrLoadFailureKind,
        code: String,
        error: Throwable,
        retrySameModel: Boolean,
        quarantineModel: Boolean = false
    ) = QnnAsrLoadFailure(
        kind = kind,
        reasonCode = code,
        detail = error.message?.takeIf(String::isNotBlank) ?: code,
        retrySameModel = retrySameModel,
        quarantineModel = quarantineModel
    )

    private companion object {
        val MEMORY_MARKERS = setOf("out of memory", "not enough memory", "memory allocation", "failed to allocate")
        val RUNTIME_MISSING_MARKERS = setOf(
            "qnn htp execution provider is unavailable",
            "qnnexecutionprovider is unavailable",
            "cannot locate symbol",
            "couldn't find \"libqnn",
            "could not find libqnn",
            "dlopen failed"
        )
        val RUNTIME_VERSION_MARKERS = setOf(
            "qairt version",
            "qnn runtime version",
            "incompatible backend version",
            "backend version mismatch",
            "qnn sdk version mismatch"
        )
        val CHIPSET_MARKERS = setOf(
            "incompatible chipset",
            "unsupported soc",
            "soc model mismatch",
            "htp architecture mismatch",
            "context binary is not compatible with the device"
        )
        val MODEL_MARKERS = setOf(
            "model directory is unavailable",
            "model is missing",
            "model archive",
            "model checksum",
            "model context",
            "context binary is invalid",
            "context binary is corrupt",
            "invalid protobuf",
            "invalid model",
            "failed to load model",
            "wrapper verification failed",
            "install record is",
            "installed file verification failed",
            "tokenizer",
            "mel filter",
            "graph contains"
        )
        val TRANSIENT_MARKERS = setOf("temporarily unavailable", "resource busy", "try again", "timeout")
    }
}

data class QnnAsrModelSelection(
    val device: QnnAsrDeviceSnapshot,
    val decision: QnnAsrDeviceDecision,
    val model: QnnContextModelSnapshot
) {
    val signature: String = listOf(
        decision.reasonCode,
        model.directory?.canonicalPath.orEmpty(),
        model.record?.releaseVersion.orEmpty(),
        model.record?.archiveSha256.orEmpty(),
        device.qnnRuntimeVersion.orEmpty(),
        device.socModel
    ).joinToString("|")
}

interface QnnAsrModelSource {
    fun select(): QnnAsrModelSelection
    fun quarantineAndRollback(failure: QnnAsrLoadFailure): QnnContextModelRecoveryResult
}

enum class QnnAsrPreparationPhase {
    IDLE,
    PREPARING,
    READY,
    FALLBACK
}

data class QnnAsrPreparationStatus(
    val phase: QnnAsrPreparationPhase,
    val reasonCode: String,
    val detail: String = "",
    val attempts: Int = 0,
    val modelDirectory: String = "",
    val modelId: String = "",
    val modelReleaseVersion: String = "",
    val modelSha256: String = "",
    val modelTargetChipset: String = "",
    val qnnRuntimeVersion: String = "",
    val backend: String = "qnn_htp",
    val encoderContextLoaded: Boolean = false,
    val decoderContextLoaded: Boolean = false,
    val availableMemoryBytes: Long = 0L,
    val availableStorageBytes: Long = 0L,
    val advisories: Set<String> = emptySet(),
    val fallbackOrder: List<QnnAsrFallbackTarget> = emptyList(),
    val failureKind: QnnAsrLoadFailureKind? = null,
    val rolledBack: Boolean = false
) {
    companion object {
        val IDLE = QnnAsrPreparationStatus(QnnAsrPreparationPhase.IDLE, "idle")
    }
}

class QnnAsrPreparationCoordinator(
    private val source: QnnAsrModelSource,
    private val failureClassifier: QnnAsrLoadFailureClassifier = QnnAsrLoadFailureClassifier(),
    private val clock: () -> Long = System::currentTimeMillis,
    private val transientRetryCooldownMs: Long = 60_000L
) {
    private val lock = Any()
    private var suppressedSignature = ""
    private var retryAfterMillis = 0L
    private var suppressedStatus: QnnAsrPreparationStatus? = null

    init {
        require(transientRetryCooldownMs > 0L)
    }

    suspend fun prepare(engineProvider: () -> LocalAsrEngine): QnnAsrPreparationStatus {
        var selection = source.select()
        suppressed(selection)?.let { return it }
        if (selection.decision.eligibility != QnnAsrEligibility.READY) {
            return suppress(selection, unavailable(selection), permanent = true)
        }
        val initialDirectory = selection.model.directory?.canonicalFile
            ?: return suppress(selection, unavailable(selection), permanent = true)
        val engine = engineProvider()
        var attempts = 1
        val first = runCatching { engine.prepare(initialDirectory.path) }
        if (first.isSuccess && engine.state.value is LocalAsrState.Ready) {
            return clearSuppression(ready(selection, attempts, rolledBack = false))
        }

        var failure = failureClassifier.classify(
            first.exceptionOrNull() ?: IllegalStateException("QNN ASR preparation did not reach ready state")
        )
        var rolledBack = false
        var rollbackPendingForNextAttempt = false
        var retryDirectory: File? = null
        if (failure.quarantineModel) {
            val recovery = source.quarantineAndRollback(failure)
            rolledBack = recovery.rolledBack
            selection = source.select()
            if (recovery.rolledBack && selection.decision.eligibility == QnnAsrEligibility.READY) {
                retryDirectory = selection.model.directory?.canonicalFile
            }
        } else if (failure.retrySameModel) {
            retryDirectory = initialDirectory
        }

        if (retryDirectory != null) {
            attempts += 1
            val retried = runCatching { engine.prepare(requireNotNull(retryDirectory).path) }
            if (retried.isSuccess && engine.state.value is LocalAsrState.Ready) {
                return clearSuppression(ready(selection, attempts, rolledBack))
            }
            failure = failureClassifier.classify(
                retried.exceptionOrNull() ?: IllegalStateException("QNN ASR retry did not reach ready state")
            )
            if (failure.quarantineModel) {
                val recovery = source.quarantineAndRollback(failure)
                rolledBack = rolledBack || recovery.rolledBack
                rollbackPendingForNextAttempt = recovery.rolledBack
                selection = source.select()
            }
        }

        val status = fallback(selection, failure, attempts, rolledBack)
        if (rollbackPendingForNextAttempt) return clearSuppression(status)
        val permanent = failure.kind in setOf(
            QnnAsrLoadFailureKind.MODEL_CORRUPT,
            QnnAsrLoadFailureKind.RUNTIME_MISSING,
            QnnAsrLoadFailureKind.RUNTIME_INCOMPATIBLE,
            QnnAsrLoadFailureKind.CHIPSET_INCOMPATIBLE
        )
        return suppress(selection, status, permanent)
    }

    fun invalidate() = synchronized(lock) {
        suppressedSignature = ""
        retryAfterMillis = 0L
        suppressedStatus = null
    }

    private fun suppressed(selection: QnnAsrModelSelection): QnnAsrPreparationStatus? = synchronized(lock) {
        if (selection.signature != suppressedSignature || clock() >= retryAfterMillis) null else suppressedStatus
    }

    private fun suppress(
        selection: QnnAsrModelSelection,
        status: QnnAsrPreparationStatus,
        permanent: Boolean
    ): QnnAsrPreparationStatus = synchronized(lock) {
        suppressedSignature = selection.signature
        retryAfterMillis = if (permanent) Long.MAX_VALUE else safeAdd(clock(), transientRetryCooldownMs)
        suppressedStatus = status
        status
    }

    private fun clearSuppression(status: QnnAsrPreparationStatus): QnnAsrPreparationStatus = synchronized(lock) {
        suppressedSignature = ""
        retryAfterMillis = 0L
        suppressedStatus = null
        status
    }

    private fun unavailable(selection: QnnAsrModelSelection): QnnAsrPreparationStatus =
        base(selection).copy(
            phase = QnnAsrPreparationPhase.FALLBACK,
            reasonCode = selection.decision.reasonCode,
            detail = selection.decision.detail,
            fallbackOrder = selection.decision.fallbackOrder.ifEmpty { DEFAULT_FALLBACK_ORDER }
        )

    private fun ready(
        selection: QnnAsrModelSelection,
        attempts: Int,
        rolledBack: Boolean
    ): QnnAsrPreparationStatus = base(selection).copy(
        phase = QnnAsrPreparationPhase.READY,
        reasonCode = if (rolledBack) "qnn_ready_after_rollback" else "qnn_ready",
        attempts = attempts,
        encoderContextLoaded = true,
        decoderContextLoaded = true,
        rolledBack = rolledBack
    )

    private fun fallback(
        selection: QnnAsrModelSelection,
        failure: QnnAsrLoadFailure,
        attempts: Int,
        rolledBack: Boolean
    ): QnnAsrPreparationStatus = base(selection).copy(
        phase = QnnAsrPreparationPhase.FALLBACK,
        reasonCode = failure.reasonCode,
        detail = failure.detail,
        attempts = attempts,
        failureKind = failure.kind,
        fallbackOrder = DEFAULT_FALLBACK_ORDER,
        rolledBack = rolledBack
    )

    private fun base(selection: QnnAsrModelSelection): QnnAsrPreparationStatus {
        val record = selection.model.record
        return QnnAsrPreparationStatus(
            phase = QnnAsrPreparationPhase.PREPARING,
            reasonCode = "qnn_preparing",
            modelDirectory = selection.model.directory?.path.orEmpty(),
            modelId = record?.modelId.orEmpty(),
            modelReleaseVersion = record?.releaseVersion.orEmpty(),
            modelSha256 = record?.archiveSha256.orEmpty(),
            modelTargetChipset = record?.targetChipset.orEmpty(),
            qnnRuntimeVersion = selection.device.qnnRuntimeVersion.orEmpty(),
            availableMemoryBytes = selection.device.availableMemoryBytes,
            availableStorageBytes = selection.device.availableStorageBytes,
            advisories = selection.decision.advisories
        )
    }

    private fun safeAdd(left: Long, right: Long): Long =
        if (Long.MAX_VALUE - left < right) Long.MAX_VALUE else left + right

    private companion object {
        val DEFAULT_FALLBACK_ORDER = listOf(
            QnnAsrFallbackTarget.SMALL_OR_BASE_QNN,
            QnnAsrFallbackTarget.WHISPER_CPP,
            QnnAsrFallbackTarget.SYSTEM_ASR
        )
    }
}

class LargeTurboQnnModelSource(
    private val store: LargeTurboQnnModelStore,
    private val capabilityDetector: AndroidLargeTurboQnnDeviceCapabilityDetector,
    private val manifest: LargeTurboQnnModelManifest = LargeTurboQnnModelCatalog.s26Ultra,
    private val policy: LargeTurboQnnDevicePolicy = LargeTurboQnnDevicePolicy(manifest)
) : QnnAsrModelSource {
    override fun select(): QnnAsrModelSelection {
        val model = store.inspectActive(manifest)
        val device = capabilityDetector.snapshot(model.state)
        return QnnAsrModelSelection(device, policy.evaluate(device), model)
    }

    override fun quarantineAndRollback(failure: QnnAsrLoadFailure): QnnContextModelRecoveryResult =
        store.quarantineActiveAndRollback(manifest, failure.reasonCode, failure.detail)
}
