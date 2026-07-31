package com.signalasi.chat.voice.audio

import kotlinx.coroutines.flow.Flow

interface PcmRecorder {
    suspend fun start(config: PcmCaptureConfig): Flow<AudioFrame>
    fun requestStop(reason: PcmStopReason)
    suspend fun stop(reason: PcmStopReason)
    fun currentState(): PcmRecorderState
}
