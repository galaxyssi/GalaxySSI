package com.galaxyssi.chat.voice.audio

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.runBlocking
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceAudioHubTest {
    @Test
    fun hubFansOutOnePcmStreamAndReturnsBoundedSpeechSnapshot() = runBlocking {
        val recorder = FakePcmRecorder()
        val listener = RecordingListener()
        val hub = VoiceAudioHub(
            recorder,
            CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
            sessionIdFactory = { "pcm-session" },
            vadFactory = { ThresholdVad() }
        )
        val session = assertNotNullValue(
            hub.start(
                VoiceAudioSessionConfig(
                    capture = PcmCaptureConfig(sampleRateHz = 1_000, frameDurationMs = 20, maxDurationMs = 5_000),
                    endpoint = AdaptiveEndpointConfig(
                        noSpeechTimeoutMs = 1_500,
                        minimumSpeechMs = 240,
                        shortUtteranceSilenceMs = 350,
                        normalUtteranceSilenceMs = 350,
                        longUtteranceSilenceMs = 350,
                        minTrailingSilenceMs = 350,
                        maxTrailingSilenceMs = 1_200,
                        maxDurationMs = 5_000,
                        preRollMs = 200,
                        postRollMs = 100
                    ),
                    autoEndpoint = true
                ),
                listener
            )
        )

        repeat(15) { recorder.emit(frame(it.toLong(), ShortArray(20))) }
        repeat(20) { recorder.emit(frame((15 + it).toLong(), ShortArray(20) { 5_000 })) }
        repeat(20) { recorder.emit(frame((35 + it).toLong(), ShortArray(20))) }

        assertEquals(1, listener.speechStarts)
        assertEquals(EndpointReason.TRAILING_SILENCE, listener.endpoint)
        assertEquals(55, listener.pcmFrames.size)
        assertEquals(5_000.toShort(), listener.pcmFrames[15].samples.first())
        val result = hub.stop(session, PcmStopReason.ADAPTIVE_ENDPOINT)
        assertNotNull(result)
        assertTrue(result!!.snapshot.speechDetected)
        assertTrue(result.snapshot.durationMs in 600L..800L)
        assertEquals(PcmStopReason.ADAPTIVE_ENDPOINT, result.stopReason)
    }

    @Test
    fun hubOffersDirectPcmToNativeConsumersWithoutCreatingLegacyPacket() = runBlocking {
        val recorder = FakePcmRecorder()
        val listener = DirectRecordingListener()
        val hub = VoiceAudioHub(
            recorder,
            CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
            sessionIdFactory = { "direct-session" },
            vadFactory = { ThresholdVad() }
        )
        val session = assertNotNullValue(hub.start(
            VoiceAudioSessionConfig(
                capture = PcmCaptureConfig(sampleRateHz = 1_000, frameDurationMs = 20, maxDurationMs = 5_000)
            ),
            listener
        ))
        val samples = shortArrayOf(100, -200, 300, -400)
        val pcm16 = ByteBuffer.allocateDirect(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        samples.forEach(pcm16::putShort)
        pcm16.flip()
        recorder.emit(AudioFrame(
            sequence = 0,
            captureTimeNanos = 1,
            samples = samples,
            validSamples = samples.size,
            releaseAction = {},
            directPcm16 = pcm16
        ))

        assertEquals(1, listener.frames.size)
        val received = listener.frames.single()
        assertTrue(received.pcm16.isDirect)
        assertEquals(samples.size, received.sampleCount)
        assertEquals(samples.toList(), List(samples.size) { received.pcm16.getShort(it * 2) })
        hub.stop(session, PcmStopReason.USER_CANCEL)
        Unit
    }

    private class FakePcmRecorder : PcmRecorder {
        private var frames = Channel<AudioFrame>(Channel.UNLIMITED)
        private var state = PcmRecorderState(phase = PcmRecorderPhase.IDLE)

        override suspend fun start(config: PcmCaptureConfig): Flow<AudioFrame> {
            state = PcmRecorderState(phase = PcmRecorderPhase.RECORDING, audioSource = 6, inputRoute = "built_in_mic")
            return frames.receiveAsFlow()
        }

        fun emit(frame: AudioFrame) {
            frames.trySend(frame)
            state = state.copy(currentAmplitude = frame.samples.maxOf { kotlin.math.abs(it.toInt()) })
        }

        override fun requestStop(reason: PcmStopReason) {
            state = state.copy(phase = PcmRecorderPhase.STOPPING, stopReason = reason)
            frames.close()
        }

        override suspend fun stop(reason: PcmStopReason) {
            requestStop(reason)
            state = state.copy(phase = PcmRecorderPhase.STOPPED)
        }

        override fun currentState(): PcmRecorderState = state
    }

    private class ThresholdVad : VoiceActivityDetector {
        private var active = false
        private var silenceFrames = 0

        override fun reset() {
            active = false
            silenceFrames = 0
        }

        override fun accept(frame: AudioFrame): VadDecision {
            val voiced = frame.samples.take(frame.validSamples).any { kotlin.math.abs(it.toInt()) > 1_000 }
            val started = voiced && !active
            var ended = false
            if (voiced) {
                active = true
                silenceFrames = 0
            } else if (active) {
                silenceFrames += 1
                if (silenceFrames >= 2) {
                    active = false
                    ended = true
                }
            }
            return VadDecision(if (voiced) 1f else 0f, voiced, started, ended, 0f, if (voiced) 5_000 else 0, -58f)
        }
    }

    private class RecordingListener : VoiceAudioHubListener {
        var speechStarts = 0
        var endpoint: EndpointReason? = null
        val pcmFrames = mutableListOf<PcmFramePacket>()

        override val acceptsPcmFrames: Boolean = true

        override fun onPcmFrame(session: VoiceAudioSession, frame: PcmFramePacket) {
            pcmFrames += frame
        }

        override fun onSpeechStarted(session: VoiceAudioSession, sequence: Long) {
            speechStarts += 1
        }

        override fun onEndpoint(session: VoiceAudioSession, reason: EndpointReason) {
            endpoint = reason
        }
    }

    private class DirectRecordingListener : VoiceAudioHubListener {
        val frames = mutableListOf<DirectPcmFramePacket>()
        override val acceptsDirectPcmFrames: Boolean = true

        override fun onDirectPcmFrame(session: VoiceAudioSession, frame: DirectPcmFramePacket) {
            frames += frame
        }
    }

    private fun frame(sequence: Long, samples: ShortArray) = AudioFrame(
        sequence,
        sequence * 20_000_000L,
        samples,
        samples.size,
        {}
    )

    private fun <T> assertNotNullValue(value: T?): T {
        assertNotNull(value)
        return checkNotNull(value)
    }
}
