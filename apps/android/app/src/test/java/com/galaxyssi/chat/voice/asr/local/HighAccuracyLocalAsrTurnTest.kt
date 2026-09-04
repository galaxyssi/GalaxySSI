package com.galaxyssi.chat.voice.asr.local

import com.galaxyssi.chat.QnnRuntimeResourceArbiter
import com.galaxyssi.chat.voice.audio.DirectPcmFramePacket
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.io.path.createTempDirectory

class HighAccuracyLocalAsrTurnTest {
    @Test
    fun preparedAsrKeepsQnnPriorityUntilControllerCloses() = runBlocking {
        val engine = FakeEngine()
        val arbiter = QnnRuntimeResourceArbiter()
        val controller = HighAccuracyLocalAsrController(
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
            modelDirectoryResolver = { temporaryModelDirectory() },
            engineFactory = { engine },
            resourceArbiter = arbiter
        )

        assertTrue(controller.prepareNow())
        assertTrue(controller.isReady())
        assertTrue(arbiter.asrHasPriority())
        controller.close()
        assertFalse(arbiter.asrHasPriority())
    }

    @Test
    fun controllerPreparesOnceAndStreamsStartupAudioToFinalResult() = runBlocking {
        val directory = temporaryModelDirectory()
        val engine = FakeEngine(autoListen = false)
        val partials = mutableListOf<AsrEvent.Partial>()
        val controller = HighAccuracyLocalAsrController(
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
            modelDirectoryResolver = { directory },
            engineFactory = { engine }
        )

        assertTrue(controller.prepareNow())
        assertTrue(controller.isReady())
        val turn = controller.startTurnIfReady(AsrConfig(), "large_v3_turbo", partials::add)
        assertNotNull(turn)
        assertTrue(requireNotNull(turn).offer(frame(0, shortArrayOf(7, 8, 9))))
        assertTrue(engine.pushed.isEmpty())

        engine.listen()
        assertEquals(listOf<Short>(7, 8, 9), engine.pushed.single().toList())
        engine.partial("hello", " world")
        assertEquals("hello", partials.single().stableText)

        val result = turn.finish()
        assertEquals("hello world", result.text)
        assertEquals("large_v3_turbo", result.modelProfileId)
        assertEquals(1, engine.prepareCalls)
        controller.close()
    }

    @Test
    fun unavailableModelDoesNotConstructOrStartRuntime() = runBlocking {
        var factories = 0
        val controller = HighAccuracyLocalAsrController(
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
            modelDirectoryResolver = { null },
            engineFactory = {
                factories += 1
                FakeEngine()
            }
        )

        assertFalse(controller.prepareNow())
        assertFalse(controller.isReady())
        assertEquals(null, controller.startTurnIfReady(AsrConfig(), "large_v3_turbo") {})
        assertEquals(0, factories)
        controller.close()
    }

    @Test
    fun vadFinalCommitsSegmentRestartsRuntimeAndStitchesNextSegment() = runBlocking {
        val engine = FakeEngine()
        engine.stopText = "lights in the kitchen"
        val partials = mutableListOf<AsrEvent.Partial>()
        val controller = HighAccuracyLocalAsrController(
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
            modelDirectoryResolver = { temporaryModelDirectory() },
            engineFactory = { engine }
        )
        assertTrue(controller.prepareNow())
        val turn = requireNotNull(
            controller.startTurnIfReady(AsrConfig(), "large_v3_turbo", partials::add)
        )

        engine.segmentFinal("turn on the lights", 1_000L, 100L)
        assertEquals(2, engine.startCalls)
        engine.partial("lights", " in the kitchen")
        assertEquals("turn on the lights", partials.last().stableText)
        assertEquals(" in the kitchen", partials.last().unstableText)

        val result = turn.finish()
        assertEquals("turn on the lights in the kitchen", result.text)
        assertEquals(2_000L, result.durationMs)
        assertEquals(112L, result.inferenceMs)
        controller.close()
    }

    @Test
    fun decoderLimitMarksTheTurnIncompleteForFullPcmFallback() = runBlocking {
        val engine = FakeEngine().apply {
            stopText = "unfinished sentence"
            stopTermination = AsrTranscriptTermination.TOKEN_LIMIT
        }
        val controller = HighAccuracyLocalAsrController(
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
            modelDirectoryResolver = { temporaryModelDirectory() },
            engineFactory = { engine }
        )
        assertTrue(controller.prepareNow())
        val turn = requireNotNull(controller.startTurnIfReady(AsrConfig(), "large_v3_turbo") {})

        val result = turn.finish()

        assertFalse(result.complete)
        assertEquals(AsrTranscriptTermination.TOKEN_LIMIT, result.termination)
        controller.close()
    }

    @Test
    fun startupBufferPreservesMoreThanHalfASecondOfSpeech() = runBlocking {
        val engine = FakeEngine(autoListen = false)
        val controller = HighAccuracyLocalAsrController(
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
            modelDirectoryResolver = { temporaryModelDirectory() },
            engineFactory = { engine }
        )
        assertTrue(controller.prepareNow())
        val turn = requireNotNull(controller.startTurnIfReady(AsrConfig(), "large_v3_turbo") {})

        repeat(100) { index ->
            assertTrue(turn.offer(frame(index.toLong(), ShortArray(160) { index.toShort() })))
        }
        engine.listen()

        assertEquals(100, engine.pushed.size)
        assertEquals(0.toShort(), engine.pushed.first().first())
        assertEquals(99.toShort(), engine.pushed.last().first())
        turn.cancel()
        controller.close()
    }

    @Test
    fun transientPcmRejectionIsBufferedAndReplayedInOrder() = runBlocking {
        val engine = FakeEngine()
        val controller = HighAccuracyLocalAsrController(
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
            modelDirectoryResolver = { temporaryModelDirectory() },
            engineFactory = { engine }
        )
        assertTrue(controller.prepareNow())
        val turn = requireNotNull(controller.startTurnIfReady(AsrConfig(), "large_v3_turbo") {})

        engine.acceptPcm = false
        assertTrue(turn.offer(frame(1, shortArrayOf(1, 1))))
        assertTrue(engine.pushed.isEmpty())
        engine.acceptPcm = true
        assertTrue(turn.offer(frame(2, shortArrayOf(2, 2))))

        assertEquals(listOf<Short>(1, 1), engine.pushed[0].toList())
        assertEquals(listOf<Short>(2, 2), engine.pushed[1].toList())
        turn.cancel()
        controller.close()
    }

    @Test
    fun finishWaitsForBufferedTailWhenSegmentFinalIsAlreadyInFlight() = runBlocking {
        val engine = FakeEngine()
        engine.stopText = "second part"
        val controller = HighAccuracyLocalAsrController(
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
            modelDirectoryResolver = { temporaryModelDirectory() },
            engineFactory = { engine }
        )
        assertTrue(controller.prepareNow())
        val turn = requireNotNull(controller.startTurnIfReady(AsrConfig(), "large_v3_turbo") {})

        assertTrue(turn.offer(frame(1, shortArrayOf(1, 1))))
        engine.beginSegmentFinal()
        assertTrue(turn.offer(frame(2, shortArrayOf(2, 2))))

        val result = async(start = CoroutineStart.UNDISPATCHED) { turn.finish() }
        engine.completeSegmentFinal("first part", 1_000L, 10L)

        assertEquals("first part second part", result.await().text)
        assertEquals(2, engine.startCalls)
        assertEquals(listOf<Short>(2, 2), engine.pushed.last().toList())
        val nextTurn = controller.startTurnIfReady(AsrConfig(), "large_v3_turbo") {}
        assertNotNull(nextTurn)
        nextTurn?.cancel()
        controller.close()
    }

    private fun frame(sequence: Long, samples: ShortArray): DirectPcmFramePacket {
        val bytes = ByteBuffer.allocateDirect(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        samples.forEach(bytes::putShort)
        bytes.flip()
        return DirectPcmFramePacket(sequence, sequence * 10_000_000L, bytes, samples.size, 16_000)
    }

    private fun temporaryModelDirectory(): File = createTempDirectory("galaxyssi-qnn-turn-").toFile().apply {
        deleteOnExit()
    }

    private class FakeEngine(private val autoListen: Boolean = true) : LocalAsrEngine {
        private val mutableState = MutableStateFlow<LocalAsrState>(LocalAsrState.Unprepared)
        private val mutableEvents = MutableSharedFlow<AsrEvent>(extraBufferCapacity = 32)
        var prepareCalls = 0
        var startCalls = 0
        var stopText = "hello world"
        var stopTermination = AsrTranscriptTermination.END_OF_TEXT
        var acceptPcm = true
        val pushed = mutableListOf<ShortArray>()
        private var config = AsrConfig()
        private var token = 0L

        override val state: StateFlow<LocalAsrState> = mutableState.asStateFlow()
        override val events: Flow<AsrEvent> = mutableEvents.asSharedFlow()

        override suspend fun prepare(modelDirectory: String) {
            prepareCalls += 1
            transition(LocalAsrState.Ready(modelDirectory, 1L))
        }

        override fun start(config: AsrConfig) {
            this.config = config
            token += 1L
            startCalls += 1
            transition(LocalAsrState.Starting(token, config))
            if (autoListen) listen()
        }

        fun listen() {
            transition(LocalAsrState.Listening(token, config))
        }

        fun partial(stable: String, unstable: String) {
            mutableEvents.tryEmit(AsrEvent.Partial(stable, unstable, revision = 1L))
        }

        override fun pushPcm(pcm: ByteBuffer, sampleCount: Int): Boolean {
            if (!acceptPcm) return false
            val input = pcm.duplicate().order(ByteOrder.LITTLE_ENDIAN)
            pushed += ShortArray(sampleCount) { input.getShort() }
            return true
        }

        override fun stop() {
            transition(LocalAsrState.Stopping(token, config))
            mutableEvents.tryEmit(AsrEvent.Final(stopText, 1_000L, 12L, stopTermination))
            transition(LocalAsrState.Ready("model", 1L))
        }

        fun segmentFinal(text: String, durationMs: Long, inferenceMs: Long) {
            mutableEvents.tryEmit(AsrEvent.Final(text, durationMs, inferenceMs))
            transition(LocalAsrState.Ready("model", 1L))
        }

        fun beginSegmentFinal() {
            transition(LocalAsrState.Stopping(token, config))
        }

        fun completeSegmentFinal(text: String, durationMs: Long, inferenceMs: Long) {
            mutableEvents.tryEmit(AsrEvent.Final(text, durationMs, inferenceMs))
            transition(LocalAsrState.Ready("model", 1L))
        }

        override fun cancel() {
            transition(LocalAsrState.Ready("model", 1L))
        }

        override fun pause(reason: LocalAsrPauseReason) = Unit
        override fun resume(reason: LocalAsrPauseReason) = Unit

        override fun close() {
            transition(LocalAsrState.Closed)
        }

        private fun transition(next: LocalAsrState) {
            mutableState.value = next
            mutableEvents.tryEmit(AsrEvent.StateChanged(next))
        }
    }
}
