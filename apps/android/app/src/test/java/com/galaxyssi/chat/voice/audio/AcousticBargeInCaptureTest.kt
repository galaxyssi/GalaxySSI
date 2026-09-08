package com.galaxyssi.chat.voice.audio

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class AcousticBargeInCaptureTest {
    @Test fun oneRecorderContinuesFromDetectionThroughFinalSpeech() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val recorder = FakeRecorder()
        val hub = VoiceAudioHub(recorder, scope, vadFactory = { FixedVad() })
        val capture = AcousticBargeInCapture(hub, scope) { it() }
        var detections = 0
        var utterance: PcmSnapshot? = null
        val streamed = mutableListOf<PcmSnapshot>()
        val events = mutableListOf<String>()
        try {
            assertTrue(capture.start(AcousticBargeInCallbacks(
                onDetected = { detections++; events += "detected" },
                onAudio = { streamed += it.copy(samples = it.samples.copyOf()); events += "audio" },
                onUtterance = { utterance = it; events += "final" }
            )))
            repeat(60) { recorder.emit(0) }
            repeat(30) { recorder.emit(5_000) }
            assertEquals(1, detections)
            assertEquals(1, recorder.starts)
            assertTrue(capture.collectingUtterance)
            repeat(50) { recorder.emit(0) }
            assertNotNull(utterance)
            assertFalse(capture.active)
            assertNull(hub.activeSession())
            assertEquals(1, recorder.starts)
            assertTrue(utterance!!.samples.any { it == 5_000.toShort() })
            assertEquals("detected", events.first())
            assertEquals("final", events.last())
            assertTrue(streamed.size > 1)
            assertEquals(utterance!!.captureStartSample, streamed.first().captureStartSample)
            assertEquals(utterance!!.captureEndSampleExclusive, streamed.last().captureEndSampleExclusive)
            streamed.zipWithNext().forEach { (left, right) ->
                assertEquals(left.captureEndSampleExclusive, right.captureStartSample)
            }
            assertEquals(utterance!!.samples.toList(), streamed.flatMap { it.samples.toList() })
        } finally { capture.stop(); scope.cancel() }
    }

    @Test fun cancellationNeverSubmitsCapturedSpeech() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val recorder = FakeRecorder()
        val hub = VoiceAudioHub(recorder, scope, vadFactory = { FixedVad() })
        val capture = AcousticBargeInCapture(hub, scope) { it() }
        var submissions = 0
        try {
            capture.start(AcousticBargeInCallbacks(onDetected = {}, onUtterance = { submissions++ }))
            repeat(30) { recorder.emit(5_000) }
            assertTrue(capture.collectingUtterance)
            capture.stop()
            assertFalse(capture.active)
            assertNull(hub.activeSession())
            assertEquals(0, submissions)
        } finally { capture.stop(); scope.cancel() }
    }

    @Test fun absentEchoProtectionReleasesMicrophoneWithoutInterruption() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val recorder = FakeRecorder(echoProtection = false)
        val hub = VoiceAudioHub(recorder, scope)
        val capture = AcousticBargeInCapture(hub, scope) { it() }
        var unavailable = ""
        try {
            capture.start(AcousticBargeInCallbacks(onDetected = { fail("No unprotected interruption") },
                onUtterance = { fail("No unprotected submission") }, onUnavailable = { unavailable = it }))
            assertEquals("echo_protection_unavailable", unavailable)
            assertFalse(capture.active)
            assertNull(hub.activeSession())
        } finally { capture.stop(); scope.cancel() }
    }

    @Test fun partialWindowsExcludeOldPlaybackAndBorrowedAudioIsWiped() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val recorder = FakeRecorder()
        val hub = VoiceAudioHub(recorder, scope, vadFactory = { FixedVad() })
        val capture = AcousticBargeInCapture(hub, scope) { it() }
        val borrowed = mutableListOf<ShortArray>()
        try {
            capture.start(AcousticBargeInCallbacks(onDetected = {}, onAudio = { borrowed += it.samples }, onUtterance = {}))
            recorder.emit(1_000)
            repeat(199) { recorder.emit(0) }
            repeat(40) { recorder.emit(5_000) }
            val window = requireNotNull(capture.utteranceWindow(10_000L))
            assertTrue(window.speechDetected)
            assertTrue(window.captureStartSample > 0L)
            assertFalse(window.samples.contains(1_000.toShort()))
            assertTrue(window.samples.contains(5_000.toShort()))
            assertTrue(borrowed.isNotEmpty())
            assertTrue(borrowed.all { audio -> audio.all { it == 0.toShort() } })
            capture.stop()
            assertNull(capture.utteranceWindow(10_000L))
        } finally { capture.stop(); scope.cancel() }
    }

    @Test fun losingEchoProtectionDuringMonitoringCannotBecomeAnInterruption() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val recorder = FakeRecorder()
        val hub = VoiceAudioHub(recorder, scope, vadFactory = { FixedVad() })
        val capture = AcousticBargeInCapture(hub, scope) { it() }
        var unavailable = ""
        val outcomes = mutableListOf<String>()
        try {
            capture.start(AcousticBargeInCallbacks(onDetected = { fail("Lost AEC cannot interrupt playback") },
                onUtterance = { fail("Lost AEC cannot submit speech") }, onUnavailable = { unavailable = it },
                onDiagnostics = { _, state, outcome ->
                    assertFalse(state.acousticEchoCancelerEnabled)
                    outcomes += outcome
                }))
            repeat(30) { recorder.emit(0) }
            repeat(5) { recorder.emit(5_000) }
            recorder.setEchoProtection(false)
            recorder.emit(5_000)
            assertEquals("echo_protection_lost", unavailable)
            assertEquals(listOf("echo_protection_lost"), outcomes)
            assertFalse(capture.active)
            assertNull(hub.activeSession())
        } finally { capture.stop(); scope.cancel() }
    }

    @Test fun losingProtectionBeforeTheMainThreadReceivesDetectionStillPreventsIt() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val recorder = FakeRecorder()
        val hub = VoiceAudioHub(recorder, scope, vadFactory = { FixedVad() })
        val callbacks = java.util.ArrayDeque<() -> Unit>()
        val capture = AcousticBargeInCapture(hub, scope) { callbacks.addLast(it) }
        var unavailable = ""
        try {
            capture.start(AcousticBargeInCallbacks(onDetected = { fail("Stale protected state") },
                onAudio = { fail("No unprotected audio delivery") }, onUtterance = { fail("No submission") },
                onUnavailable = { unavailable = it }))
            repeat(40) { recorder.emit(5_000) }
            assertTrue(capture.collectingUtterance)
            recorder.setEchoProtection(false)
            while (callbacks.isNotEmpty()) callbacks.removeFirst().invoke()
            assertEquals("echo_protection_lost", unavailable)
            assertFalse(capture.active)
            assertNull(hub.activeSession())
        } finally { capture.stop(); scope.cancel() }
    }

    @Test fun completedSpeechKeepsCallbackOrderEvenWhenTheUiThreadWasBusy() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val recorder = FakeRecorder()
        val hub = VoiceAudioHub(recorder, scope, vadFactory = { FixedVad() })
        val callbacks = java.util.ArrayDeque<() -> Unit>()
        val capture = AcousticBargeInCapture(hub, scope) { callbacks.addLast(it) }
        val events = mutableListOf<String>()
        try {
            capture.start(AcousticBargeInCallbacks(onDetected = { events += "detected" },
                onAudio = { events += "audio" }, onUtterance = { events += "final" }))
            repeat(40) { recorder.emit(5_000) }
            repeat(80) { recorder.emit(0) }
            while (callbacks.isNotEmpty()) callbacks.removeFirst().invoke()
            assertEquals("detected", events.first())
            assertEquals("final", events.last())
            assertTrue(events.contains("audio"))
            assertFalse(capture.active)
        } finally { capture.stop(); scope.cancel() }
    }

    @Test fun queuedCallbacksAfterCancellationCannotRestartRecognition() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val recorder = FakeRecorder()
        val hub = VoiceAudioHub(recorder, scope, vadFactory = { FixedVad() })
        val callbacks = java.util.ArrayDeque<() -> Unit>()
        val capture = AcousticBargeInCapture(hub, scope) { callbacks.addLast(it) }
        var delivered = 0
        try {
            capture.start(AcousticBargeInCallbacks(onDetected = { delivered++ }, onAudio = { delivered++ },
                onUtterance = { delivered++ }))
            repeat(40) { recorder.emit(5_000) }
            assertTrue(capture.collectingUtterance)
            capture.stop()
            while (callbacks.isNotEmpty()) callbacks.removeFirst().invoke()
            assertEquals(0, delivered)
            assertFalse(capture.active)
            assertNull(hub.activeSession())
        } finally { capture.stop(); scope.cancel() }
    }

    private class FixedVad : VoiceActivityDetector {
        override fun reset() = Unit
        override fun accept(frame: AudioFrame): VadDecision {
            val voiced = frame.samples.first() != 0.toShort()
            return VadDecision(if (voiced) 1f else 0f, voiced, false, false,
                if (voiced) 0.1f else 0f, if (voiced) 5_000 else 0, -58f)
        }
    }

    private class FakeRecorder(private val echoProtection: Boolean = true) : PcmRecorder {
        private val frames = Channel<AudioFrame>(Channel.UNLIMITED)
        var starts = 0
        private var sequence = 0L
        private var state = PcmRecorderState()
        override suspend fun start(config: PcmCaptureConfig): Flow<AudioFrame> {
            starts++
            state = PcmRecorderState(phase = PcmRecorderPhase.RECORDING, inputRoute = "built_in_mic",
                acousticEchoCancelerEnabled = echoProtection)
            return frames.receiveAsFlow()
        }
        fun emit(value: Int) {
            val frame = AudioFrame(sequence, sequence * 20_000_000L, ShortArray(320) { value.toShort() }, 320, {})
            sequence++
            frames.trySend(frame)
        }
        fun setEchoProtection(enabled: Boolean) { state = state.copy(acousticEchoCancelerEnabled = enabled) }
        override fun requestStop(reason: PcmStopReason) { frames.close() }
        override suspend fun stop(reason: PcmStopReason) {
            requestStop(reason)
            state = state.copy(phase = PcmRecorderPhase.STOPPED, stopReason = reason)
        }
        override fun currentState() = state
    }
}
