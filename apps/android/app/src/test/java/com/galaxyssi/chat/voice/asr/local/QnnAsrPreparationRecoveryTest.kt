package com.galaxyssi.chat.voice.asr.local

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.file.Files

class QnnAsrPreparationRecoveryTest {
    private val classifier = QnnAsrLoadFailureClassifier()

    @Test
    fun `classifier distinguishes model runtime chipset memory and transient failures`() {
        assertEquals(
            QnnAsrLoadFailureKind.MODEL_CORRUPT,
            classifier.classify(IllegalArgumentException("QNN ASR model is missing encoder.bin")).kind
        )
        assertEquals(
            QnnAsrLoadFailureKind.RUNTIME_MISSING,
            classifier.classify(UnsatisfiedLinkError("dlopen failed for libQnnHtp.so")).kind
        )
        assertEquals(
            QnnAsrLoadFailureKind.RUNTIME_INCOMPATIBLE,
            classifier.classify(IllegalStateException("QNN SDK version mismatch")).kind
        )
        assertEquals(
            QnnAsrLoadFailureKind.CHIPSET_INCOMPATIBLE,
            classifier.classify(IllegalStateException("unsupported SoC SM8750")).kind
        )
        assertEquals(
            QnnAsrLoadFailureKind.OUT_OF_MEMORY,
            classifier.classify(OutOfMemoryError("failed to allocate tensor arena")).kind
        )
        assertEquals(
            QnnAsrLoadFailureKind.TRANSIENT_RUNTIME,
            classifier.classify(IOException("resource busy, try again")).kind
        )
    }

    @Test
    fun `incompatible device never constructs the QNN runtime`() = runBlocking {
        val source = FakeSource(selection("active", eligibility = QnnAsrEligibility.FALLBACK_REQUIRED))
        val coordinator = QnnAsrPreparationCoordinator(source)
        var engineFactories = 0

        val status = coordinator.prepare {
            engineFactories += 1
            FakeEngine()
        }

        assertEquals(QnnAsrPreparationPhase.FALLBACK, status.phase)
        assertEquals(0, engineFactories)
        assertEquals(0, source.recoveries)
    }

    @Test
    fun `transient preparation failure retries the same persistent engine once`() = runBlocking {
        val source = FakeSource(selection("active"))
        val engine = FakeEngine(mutableListOf(IOException("resource busy"), null))
        val coordinator = QnnAsrPreparationCoordinator(source)

        val status = coordinator.prepare { engine }

        assertEquals(QnnAsrPreparationPhase.READY, status.phase)
        assertEquals(2, status.attempts)
        assertEquals(2, engine.prepareCalls)
        assertEquals(0, source.recoveries)
    }

    @Test
    fun `corrupt active model is quarantined and verified previous release is loaded once`() = runBlocking {
        val active = selection("active", release = "0.60.0")
        val previous = selection("previous", release = "0.59.0")
        val source = FakeSource(active, previous)
        val engine = FakeEngine(mutableListOf(
            IllegalArgumentException("context binary is corrupt"),
            null
        ))
        val coordinator = QnnAsrPreparationCoordinator(source)

        val status = coordinator.prepare { engine }

        assertEquals(QnnAsrPreparationPhase.READY, status.phase)
        assertTrue(status.rolledBack)
        assertEquals("0.59.0", status.modelReleaseVersion)
        assertEquals(2, status.attempts)
        assertEquals(1, source.recoveries)
        assertEquals(
            listOf(active.model.directory?.canonicalFile, previous.model.directory?.canonicalFile),
            engine.preparedDirectories.map(File::getCanonicalFile)
        )
    }

    @Test
    fun `memory failure does not spin retries and exposes ordered fallback`() = runBlocking {
        val source = FakeSource(selection("active"))
        val engine = FakeEngine(mutableListOf(OutOfMemoryError("tensor allocation failed")))
        var now = 10_000L
        val coordinator = QnnAsrPreparationCoordinator(source, clock = { now })

        val first = coordinator.prepare { engine }
        val suppressed = coordinator.prepare { engine }

        assertEquals(QnnAsrPreparationPhase.FALLBACK, first.phase)
        assertEquals(QnnAsrLoadFailureKind.OUT_OF_MEMORY, first.failureKind)
        assertEquals(QnnAsrFallbackTarget.SMALL_OR_BASE_QNN, first.fallbackOrder.first())
        assertEquals(1, engine.prepareCalls)
        assertEquals(first, suppressed)
        now += 60_001L
        engine.outcomes += OutOfMemoryError("tensor allocation failed")
        coordinator.prepare { engine }
        assertEquals(2, engine.prepareCalls)
    }

    @Test
    fun `permanent runtime mismatch remains suppressed until capability signature changes`() = runBlocking {
        val initial = selection("active")
        val source = FakeSource(initial)
        val engine = FakeEngine(mutableListOf(IllegalStateException("backend version mismatch")))
        val coordinator = QnnAsrPreparationCoordinator(source)

        val failed = coordinator.prepare { engine }
        coordinator.prepare { engine }
        assertEquals(QnnAsrLoadFailureKind.RUNTIME_INCOMPATIBLE, failed.failureKind)
        assertEquals(1, engine.prepareCalls)

        source.current = initial.copy(
            device = initial.device.copy(qnnRuntimeVersion = "2.45.1"),
            decision = initial.decision.copy(reasonCode = "large_turbo_qnn_ready_after_update")
        )
        engine.outcomes.add(null)
        val recovered = coordinator.prepare { engine }
        assertEquals(QnnAsrPreparationPhase.READY, recovered.phase)
        assertEquals(2, engine.prepareCalls)
    }

    private fun selection(
        directoryName: String,
        release: String = "0.59.0",
        eligibility: QnnAsrEligibility = QnnAsrEligibility.READY
    ): QnnAsrModelSelection {
        val directory = Files.createTempDirectory("galaxyssi-qnn-$directoryName-").toFile().apply { deleteOnExit() }
        val record = QnnContextModelInstallRecord(
            modelId = LargeTurboQnnModelCatalog.MODEL_ID,
            releaseVersion = release,
            qairtVersion = "2.45.0.260326154327",
            targetChipset = "qualcomm-snapdragon-8-elite-gen5-for-galaxy",
            htpVersion = 81,
            archiveSha256 = "a".repeat(64),
            installedAtMillis = 1L,
            files = emptyList()
        )
        val device = QnnAsrDeviceSnapshot(
            androidApiLevel = 36,
            supportedAbis = setOf("arm64-v8a"),
            manufacturer = "Samsung",
            brand = "Samsung",
            hardware = "qcom",
            socManufacturer = "Qualcomm",
            socModel = "SM8850-AD",
            nativeLibraries = setOf("libQnnSystem.so", "libQnnHtp.so", "libQnnHtpV81Stub.so"),
            qnnRuntimeVersion = "2.45.0",
            availableMemoryBytes = 6L * 1024L * 1024L * 1024L,
            availableStorageBytes = 12L * 1024L * 1024L * 1024L,
            activeModelState = QnnContextModelState.INSTALLED
        )
        val decision = QnnAsrDeviceDecision(
            eligibility = eligibility,
            reasonCode = if (eligibility == QnnAsrEligibility.READY) "large_turbo_qnn_ready" else "chipset_mismatch",
            detail = "test",
            fallbackOrder = if (eligibility == QnnAsrEligibility.READY) emptyList() else listOf(
                QnnAsrFallbackTarget.WHISPER_CPP,
                QnnAsrFallbackTarget.SYSTEM_ASR
            )
        )
        return QnnAsrModelSelection(
            device,
            decision,
            QnnContextModelSnapshot(QnnContextModelState.INSTALLED, directory, record)
        )
    }

    private class FakeSource(
        var current: QnnAsrModelSelection,
        private val rollback: QnnAsrModelSelection? = null
    ) : QnnAsrModelSource {
        var recoveries = 0

        override fun select(): QnnAsrModelSelection = current

        override fun quarantineAndRollback(failure: QnnAsrLoadFailure): QnnContextModelRecoveryResult {
            recoveries += 1
            val previous = rollback
            return if (previous != null) {
                current = previous
                QnnContextModelRecoveryResult(previous.model, File("active"), true, failure.reasonCode)
            } else {
                current = current.copy(
                    device = current.device.copy(activeModelState = QnnContextModelState.INVALID),
                    decision = current.decision.copy(
                        eligibility = QnnAsrEligibility.MODEL_DOWNLOAD_REQUIRED,
                        reasonCode = "large_turbo_model_required"
                    ),
                    model = current.model.copy(state = QnnContextModelState.INVALID)
                )
                QnnContextModelRecoveryResult(current.model, current.model.directory, false, failure.reasonCode)
            }
        }
    }

    private class FakeEngine(
        val outcomes: MutableList<Throwable?> = mutableListOf(null)
    ) : LocalAsrEngine {
        private val mutableState = MutableStateFlow<LocalAsrState>(LocalAsrState.Unprepared)
        private val mutableEvents = MutableSharedFlow<AsrEvent>(extraBufferCapacity = 4)
        var prepareCalls = 0
        val preparedDirectories = mutableListOf<File>()

        override val state: StateFlow<LocalAsrState> = mutableState.asStateFlow()
        override val events: Flow<AsrEvent> = mutableEvents.asSharedFlow()

        override suspend fun prepare(modelDirectory: String) {
            prepareCalls += 1
            preparedDirectories += File(modelDirectory)
            val outcome = if (outcomes.isEmpty()) null else outcomes.removeAt(0)
            if (outcome != null) {
                mutableState.value = LocalAsrState.Failed("qnn_prepare_failed", outcome.message.orEmpty(), true)
                throw outcome
            }
            mutableState.value = LocalAsrState.Ready(modelDirectory, 1L)
        }

        override fun start(config: AsrConfig) = Unit
        override fun pushPcm(pcm: ByteBuffer, sampleCount: Int): Boolean = false
        override fun stop() = Unit
        override fun cancel() = Unit
        override fun pause(reason: LocalAsrPauseReason) = Unit
        override fun resume(reason: LocalAsrPauseReason) = Unit
        override fun close() {
            mutableState.value = LocalAsrState.Closed
        }
    }
}
