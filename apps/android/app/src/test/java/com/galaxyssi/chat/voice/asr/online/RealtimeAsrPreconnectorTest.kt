package com.galaxyssi.chat.voice.asr.online

import com.galaxyssi.chat.voice.asr.AsrAbortReason
import com.galaxyssi.chat.voice.asr.AsrAudioFrame
import com.galaxyssi.chat.voice.asr.AsrAvailability
import com.galaxyssi.chat.voice.asr.AsrEvent
import com.galaxyssi.chat.voice.asr.AsrNetworkType
import com.galaxyssi.chat.voice.asr.AsrPrivacyPolicy
import com.galaxyssi.chat.voice.asr.AsrProvider
import com.galaxyssi.chat.voice.asr.AsrSession
import com.galaxyssi.chat.voice.asr.AsrSessionConfig
import com.galaxyssi.chat.voice.asr.AsrTransport
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class RealtimeAsrPreconnectorTest {
    @Test
    fun acquireReusesThePreparedSessionAndDoesNotOpenAnotherConnection() = runBlocking {
        val provider = FakeProvider()
        val pool = RealtimeAsrPreconnector(provider, idleTtlMs = 10_000L)
        val config = config()

        assertTrue(pool.preconnect(config))
        val session = pool.acquire(config)

        assertSame(provider.sessions.single(), session)
        assertEquals(1, provider.createCount)
        assertEquals(1, provider.sessions.single().startCount)
        pool.close()
    }

    @Test
    fun expiredPreparedSessionIsClosedBeforeReplacement() = runBlocking {
        var now = 1_000L
        val provider = FakeProvider()
        val pool = RealtimeAsrPreconnector(provider, nowEpochMs = { now }, idleTtlMs = 1_000L)
        pool.preconnect(config())
        val first = provider.sessions.single()
        now = 2_001L

        val second = pool.acquire(config())

        assertTrue(first.closed)
        assertEquals(2, provider.createCount)
        assertSame(provider.sessions.last(), second)
        pool.close()
    }

    private fun config() = AsrSessionConfig(
        voiceSessionId = "voice-1",
        transcriptId = "transcript-1",
        networkType = AsrNetworkType.WIFI,
        privacy = AsrPrivacyPolicy(allowOnlineVoice = true, allowRawAudioUpload = true)
    )

    private class FakeProvider : AsrProvider {
        override val id = "fake"
        var createCount = 0
        val sessions = mutableListOf<FakeSession>()

        override suspend fun isAvailable(config: AsrSessionConfig) = AsrAvailability.ready(AsrTransport.WEBSOCKET)

        override suspend fun createSession(config: AsrSessionConfig): AsrSession {
            createCount += 1
            return FakeSession().also(sessions::add)
        }
    }

    private class FakeSession : AsrSession {
        override val events: Flow<AsrEvent> = emptyFlow()
        var startCount = 0
        var closed = false

        override suspend fun start() {
            startCount += 1
        }

        override suspend fun pushPcm(frame: AsrAudioFrame) = Unit
        override suspend fun finishInput() = Unit
        override fun requestAbort(reason: AsrAbortReason) = Unit
        override fun close() {
            closed = true
        }
    }
}
