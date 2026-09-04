package com.galaxyssi.chat.voice.asr.local

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer

class LocalAsrLifecycleCoordinatorTest {
    @Test
    fun `multiple transient blockers pause once and resume after all clear`() {
        val engine = RecordingEngine()
        val coordinator = LocalAsrLifecycleCoordinator(engine)

        coordinator.onAppForegroundChanged(false)
        coordinator.onPhoneCallChanged(true)
        coordinator.onAppForegroundChanged(true)
        assertEquals(0, engine.nativeResumeCount)
        assertTrue(LocalAsrPauseReason.PHONE_CALL in coordinator.activeBlockers())

        coordinator.onPhoneCallChanged(false)
        assertEquals(1, engine.nativePauseCount)
        assertEquals(1, engine.nativeResumeCount)
        assertTrue(coordinator.activeBlockers().isEmpty())
    }

    @Test
    fun `microphone permission revocation cancels and never auto resumes`() {
        val engine = RecordingEngine()
        val coordinator = LocalAsrLifecycleCoordinator(engine)

        coordinator.onMicrophonePermissionChanged(false)
        coordinator.onMicrophonePermissionChanged(true)

        assertEquals(1, engine.cancelCount)
        assertEquals(0, engine.nativeResumeCount)
    }

    @Test
    fun `clearing an inactive blocker never resumes or mutates the engine`() {
        val engine = RecordingEngine()
        val coordinator = LocalAsrLifecycleCoordinator(engine)

        coordinator.onPhoneCallChanged(false)
        coordinator.onAudioFocusChanged(true)
        coordinator.onThermalLimitChanged(false)

        assertEquals(0, engine.nativePauseCount)
        assertEquals(0, engine.nativeResumeCount)
        assertTrue(coordinator.activeBlockers().isEmpty())
    }

    private class RecordingEngine : LocalAsrEngine {
        private val mutableState = MutableStateFlow<LocalAsrState>(
            LocalAsrState.Listening(1L, AsrConfig())
        )
        override val state: StateFlow<LocalAsrState> = mutableState
        override val events: Flow<AsrEvent> = MutableSharedFlow()
        var nativePauseCount = 0
        var nativeResumeCount = 0
        var cancelCount = 0
        private val reasons = linkedSetOf<LocalAsrPauseReason>()

        override suspend fun prepare(modelDirectory: String) = Unit
        override fun start(config: AsrConfig) = Unit
        override fun pushPcm(pcm: ByteBuffer, sampleCount: Int): Boolean = true
        override fun stop() = Unit

        override fun cancel() {
            cancelCount += 1
            mutableState.value = LocalAsrState.Ready("model", 0L)
        }

        override fun pause(reason: LocalAsrPauseReason) {
            val invoke = reasons.isEmpty()
            reasons += reason
            if (invoke) nativePauseCount += 1
            mutableState.value = LocalAsrState.Paused(1L, AsrConfig(), reasons.toSet())
        }

        override fun resume(reason: LocalAsrPauseReason) {
            reasons -= reason
            if (reasons.isEmpty()) {
                nativeResumeCount += 1
                mutableState.value = LocalAsrState.Listening(1L, AsrConfig())
            } else {
                mutableState.value = LocalAsrState.Paused(1L, AsrConfig(), reasons.toSet())
            }
        }

        override fun close() = Unit
    }
}
