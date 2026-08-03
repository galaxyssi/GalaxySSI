package com.signalasi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.BlockingQueue
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class WhisperQnnStreamingNativeApiTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun partialAndFinalFlowThroughSeparateWorkersWhileRuntimeStaysResident() {
        val runtime = FakeRuntime("hello", "hello world")
        val frontendFactory = FakeFrontendFactory()
        val callback = RecordingCallback()
        val api = AndroidWhisperQnnAsrApi(WhisperQnnTranscriberRuntimeFactory { runtime }, frontendFactory)
        val handle = api.create(
            temporaryFolder.newFolder("model").path,
            temporaryFolder.newFolder("runtime").path,
            callback
        )

        assertTrue(api.start(handle, 7L, AsrConfig()))
        val frontend = frontendFactory.latest()
        frontend.emit(window(NativeFeatureWindowKind.PARTIAL, 0L, 16_000L))
        assertTrue(callback.partialLatch.await(2, TimeUnit.SECONDS))
        frontend.emit(window(NativeFeatureWindowKind.FINAL, 0L, 24_000L))
        assertTrue(callback.finalLatch.await(2, TimeUnit.SECONDS))

        assertEquals(listOf("hello world"), callback.finals)
        assertEquals(2, runtime.calls.get())
        assertFalse(runtime.closed.get())
        assertTrue(callback.diagnostics.isNotEmpty())
        assertEquals(0, callback.diagnostics.last().encoderNpuLayers)
        assertEquals(0, callback.diagnostics.last().decoderNpuLayers)
        assertEquals(null, callback.diagnostics.last().qnnExecution)

        api.destroy(handle)
        assertTrue(runtime.closed.get())
        assertTrue(frontend.closed.get())
    }

    @Test
    fun explicitNoSpeechFinalDoesNotInvokeQnn() {
        val runtime = FakeRuntime("unused")
        val frontendFactory = FakeFrontendFactory()
        val callback = RecordingCallback()
        val api = AndroidWhisperQnnAsrApi(WhisperQnnTranscriberRuntimeFactory { runtime }, frontendFactory)
        val handle = api.create(
            temporaryFolder.newFolder("model-empty").path,
            temporaryFolder.newFolder("runtime-empty").path,
            callback
        )

        assertTrue(api.start(handle, 8L, AsrConfig()))
        frontendFactory.latest().emit(window(NativeFeatureWindowKind.NO_SPEECH_FINAL, 0L, 2_000L))
        assertTrue(callback.finalLatch.await(2, TimeUnit.SECONDS))

        assertEquals(listOf(""), callback.finals)
        assertEquals(0, runtime.calls.get())
        api.destroy(handle)
    }

    @Test
    fun verifiedFailClosedQnnExecutionPublishesReferenceCoverageSeparately() {
        val runtime = FakeRuntime("verified result").apply {
            qnnExecution = QnnExecutionAttestation(
                executionProvider = "QNNExecutionProvider",
                backendType = "htp",
                verification = QnnExecutionVerification.ENCODER_AND_DECODER_EXECUTED,
                cpuFallbackDisabled = true,
                htpSharedMemoryEnabled = true,
                contextBinariesRestored = true,
                warmupCompleted = true,
                encoderExecutionCount = 2L,
                decoderExecutionCount = 9L,
                expectedEncoderNpuLayers = 5_026,
                expectedDecoderNpuLayers = 1_213,
                layerCountSource = QnnLayerCountSource.QUALCOMM_TARGET_DEVICE_PROFILE
            )
        }
        val frontendFactory = FakeFrontendFactory()
        val callback = RecordingCallback()
        val api = AndroidWhisperQnnAsrApi(WhisperQnnTranscriberRuntimeFactory { runtime }, frontendFactory)
        val handle = api.create(
            temporaryFolder.newFolder("model-attestation").path,
            temporaryFolder.newFolder("runtime-attestation").path,
            callback
        )

        assertTrue(api.start(handle, 13L, AsrConfig()))
        frontendFactory.latest().emit(window(NativeFeatureWindowKind.FINAL, 0L, 8_000L))
        assertTrue(callback.finalLatch.await(2, TimeUnit.SECONDS))

        val diagnostics = callback.diagnostics.single()
        assertEquals(5_026, diagnostics.encoderNpuLayers)
        assertEquals(1_213, diagnostics.decoderNpuLayers)
        assertEquals(QnnLayerCountSource.QUALCOMM_TARGET_DEVICE_PROFILE, diagnostics.qnnExecution?.layerCountSource)
        assertTrue(diagnostics.qnnExecution?.fullHtpExecutionVerified == true)
        api.destroy(handle)
    }

    @Test
    fun audioQueueBackpressureTerminatesWithRecoverableError() {
        val runtime = FakeRuntime("unused")
        val frontendFactory = FakeFrontendFactory(acceptPcm = false)
        val callback = RecordingCallback()
        val api = AndroidWhisperQnnAsrApi(WhisperQnnTranscriberRuntimeFactory { runtime }, frontendFactory)
        val handle = api.create(
            temporaryFolder.newFolder("model-backpressure").path,
            temporaryFolder.newFolder("runtime-backpressure").path,
            callback
        )
        assertTrue(api.start(handle, 9L, AsrConfig()))

        val pcm = ByteBuffer.allocateDirect(320).order(ByteOrder.nativeOrder())
        assertFalse(api.pushPcm(handle, 9L, pcm, 160))
        assertTrue(callback.errorLatch.await(2, TimeUnit.SECONDS))
        assertEquals("audio_backpressure", callback.errors.single().code)
        assertTrue(callback.errors.single().recoverable)
        api.destroy(handle)
    }

    @Test
    fun pauseAndResumeAreScopedToTheActiveSessionToken() {
        val runtime = FakeRuntime("unused")
        val frontendFactory = FakeFrontendFactory()
        val api = AndroidWhisperQnnAsrApi(
            WhisperQnnTranscriberRuntimeFactory { runtime },
            frontendFactory
        )
        val handle = api.create(
            temporaryFolder.newFolder("model-pause").path,
            temporaryFolder.newFolder("runtime-pause").path,
            RecordingCallback()
        )
        assertTrue(api.start(handle, 10L, AsrConfig()))

        api.pause(handle, 99L)
        assertFalse(frontendFactory.latest().paused.get())
        api.pause(handle, 10L)
        assertTrue(frontendFactory.latest().paused.get())
        assertTrue(api.resume(handle, 10L))
        assertFalse(frontendFactory.latest().paused.get())
        api.cancel(handle, 10L)
        api.destroy(handle)
    }

    @Test
    fun severeThermalPolicySkipsPartialQnnWorkButAlwaysRunsFinal() {
        var now = 1_000L
        val runtime = FakeRuntime("final result")
        val frontendFactory = FakeFrontendFactory()
        val callback = RecordingCallback()
        val api = AndroidWhisperQnnAsrApi(
            WhisperQnnTranscriberRuntimeFactory { runtime },
            frontendFactory,
            elapsedRealtimeMs = { now }
        )
        val handle = api.create(
            temporaryFolder.newFolder("model-thermal").path,
            temporaryFolder.newFolder("runtime-thermal").path,
            callback
        )
        assertTrue(api.start(handle, 12L, AsrConfig(updateIntervalMs = 600L)))
        api.updateRuntimePolicy(
            handle,
            AsrRuntimePolicy(
                partialIntervalMs = 1_000L,
                emitIntermediateResults = false,
                thermalStatus = AsrRuntimePolicy.THERMAL_STATUS_SEVERE
            )
        )

        frontendFactory.latest().emit(window(NativeFeatureWindowKind.PARTIAL, 0L, 16_000L))
        Thread.sleep(100L)
        assertEquals(0, runtime.calls.get())
        now += 1_000L
        frontendFactory.latest().emit(window(NativeFeatureWindowKind.FINAL, 0L, 24_000L))
        assertTrue(callback.finalLatch.await(2, TimeUnit.SECONDS))

        assertEquals(1, runtime.calls.get())
        assertEquals(AsrRuntimePolicy.THERMAL_STATUS_SEVERE, callback.diagnostics.last().thermalStatus)
        api.destroy(handle)
    }

    private fun window(kind: NativeFeatureWindowKind, start: Long, end: Long) = NativeFeatureWindow(
        kind = kind,
        startSample = start,
        endSample = end,
        segmentStartSample = start,
        endReason = 0
    )

    private class FakeRuntime(vararg private val responses: String) : WhisperQnnTranscriberRuntime {
        val calls = AtomicInteger(0)
        val closed = AtomicBoolean(false)
        @Volatile var qnnExecution: QnnExecutionAttestation? = null

        override fun transcribe(
            melFeatures: FloatBuffer,
            language: String,
            maxTokens: Int
        ): WhisperQnnTranscription {
            assertEquals(384_000, melFeatures.remaining())
            assertEquals("zh", language)
            val index = calls.getAndIncrement().coerceAtMost(responses.lastIndex)
            return WhisperQnnTranscription(
                text = responses[index],
                tokenIds = listOf(index),
                encoderNanos = 200_000_000L,
                decoderNanos = 10_000_000L,
                decoderSteps = 2,
                detectedLanguage = language,
                qnnExecution = qnnExecution
            )
        }

        override fun close() {
            closed.set(true)
        }
    }

    private class FakeFrontendFactory(
        private val acceptPcm: Boolean = true
    ) : WhisperQnnAudioFrontendFactory {
        private val opened = CopyOnWriteArrayList<FakeFrontend>()

        override fun open(modelDirectory: java.io.File, config: AsrConfig): WhisperQnnAudioFrontend =
            FakeFrontend(acceptPcm).also(opened::add)

        fun latest(): FakeFrontend = opened.last()
    }

    private class FakeFrontend(
        private val acceptPcm: Boolean
    ) : WhisperQnnAudioFrontend {
        private val windows: BlockingQueue<NativeFeatureWindow> = LinkedBlockingQueue()
        val closed = AtomicBoolean(false)
        val paused = AtomicBoolean(false)
        private val started = AtomicBoolean(false)

        override fun start(): Boolean = started.compareAndSet(false, true)

        override fun pushPcm(pcm: ByteBuffer, sampleCount: Int): Boolean = acceptPcm && !paused.get()

        override fun stop() = Unit

        override fun cancel() {
            started.set(false)
        }

        override fun pause() {
            paused.set(true)
        }

        override fun resume(): Boolean {
            paused.set(false)
            return started.get()
        }

        override fun waitForFeatures(output: ByteBuffer, timeoutMs: Int): NativeFeatureWindow? {
            val result = windows.poll(timeoutMs.toLong(), TimeUnit.MILLISECONDS) ?: return null
            output.order(ByteOrder.nativeOrder()).asFloatBuffer().put(0, 1.0F)
            return result
        }

        override fun close() {
            closed.set(true)
        }

        fun emit(window: NativeFeatureWindow) {
            windows.put(window)
        }
    }

    private class RecordingCallback : QnnAsrNativeCallback {
        data class ErrorRecord(val code: String, val message: String, val recoverable: Boolean)

        val partialLatch = CountDownLatch(1)
        val finalLatch = CountDownLatch(1)
        val errorLatch = CountDownLatch(1)
        val finals = CopyOnWriteArrayList<String>()
        val errors = CopyOnWriteArrayList<ErrorRecord>()
        val diagnostics = CopyOnWriteArrayList<AsrEvent.Diagnostics>()

        override fun onPartial(
            sessionToken: Long,
            stableText: String,
            unstableText: String,
            audioDurationMs: Long,
            inferenceMs: Long
        ) {
            partialLatch.countDown()
        }

        override fun onFinal(sessionToken: Long, text: String, durationMs: Long, inferenceMs: Long) {
            finals += text
            finalLatch.countDown()
        }

        override fun onError(sessionToken: Long, code: String, message: String, recoverable: Boolean) {
            errors += ErrorRecord(code, message, recoverable)
            errorLatch.countDown()
        }

        override fun onDiagnostics(sessionToken: Long, diagnostics: AsrEvent.Diagnostics) {
            this.diagnostics += diagnostics
        }
    }
}
