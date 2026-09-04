package com.galaxyssi.chat.voice.asr.online

import com.galaxyssi.chat.voice.asr.AsrAudioFrame
import com.galaxyssi.chat.voice.asr.AsrAvailability
import com.galaxyssi.chat.voice.asr.AsrEvent
import com.galaxyssi.chat.voice.asr.AsrNetworkType
import com.galaxyssi.chat.voice.asr.AsrPrivacyPolicy
import com.galaxyssi.chat.voice.asr.AsrSessionConfig
import com.galaxyssi.chat.voice.asr.AsrTransport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.ByteString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList

class RealtimeAsrProviderTest {
    @Test
    fun websocketStreamsPcmAndPublishesExactlyOneNormalizedFinal() = runBlocking {
        val server = MockWebServer()
        val batches = CopyOnWriteArrayList<AsrAudioBatch>()
        server.enqueue(
            MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
                override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                    batches += SignalAsrRealtimeProtocol.decodeAudio(bytes)
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    if (text.contains("input.finish")) {
                        val final = """{"event_type":"transcript.final","transcript_id":"transcript-1","revision":4,"text":"hello"}"""
                        webSocket.send(final)
                        webSocket.send(final)
                    }
                }
            })
        )
        server.start()
        val client = OkHttpClient()
        val source = FakeCredentialSource(
            websocketUrl = server.url("/realtime").toString().replaceFirst("http", "ws")
        )
        val provider = RealtimeAsrProvider(
            id = "realtime",
            client = client,
            credentialSource = source,
            dispatcher = Dispatchers.IO,
            heartbeatIntervalMs = 60_000L
        )
        val session = provider.createSession(config())
        val events = Channel<AsrEvent>(Channel.UNLIMITED)
        val collector = launch { session.events.collect { events.send(it) } }

        session.start()
        repeat(3) { index ->
            session.pushPcm(
                AsrAudioFrame(
                    sequence = index.toLong(),
                    captureTimeNanos = index * 20_000_000L,
                    samples = ShortArray(320) { (index + 1).toShort() }
                )
            )
        }
        session.finishInput()

        var finalCount = 0
        withTimeout(3_000L) {
            while (finalCount == 0) {
                if (events.receive() is AsrEvent.Final) finalCount += 1
            }
        }
        kotlinx.coroutines.delay(100L)
        while (true) {
            val event = events.tryReceive().getOrNull() ?: break
            if (event is AsrEvent.Final) finalCount += 1
        }

        assertEquals(1, finalCount)
        assertEquals(1, batches.size)
        assertEquals(60L, batches.single().durationMs)
        assertEquals(0L, batches.single().firstSequence)
        assertEquals(2L, batches.single().lastSequence)

        session.close()
        collector.cancelAndJoin()
        provider.close()
        client.dispatcher.executorService.shutdown()
        server.shutdown()
    }

    @Test
    fun providerRefusesOnlineAudioWithoutExplicitPrivacyConsent() = runBlocking {
        val source = FakeCredentialSource("ws://127.0.0.1/realtime")
        val provider = RealtimeAsrProvider("realtime", OkHttpClient(), source)

        val availability = provider.isAvailable(
            config().copy(privacy = AsrPrivacyPolicy(allowOnlineVoice = true, allowRawAudioUpload = false))
        )

        assertFalse(availability.available)
        assertEquals(0, source.issueCount)
        provider.close()
    }

    private fun config() = AsrSessionConfig(
        voiceSessionId = "voice-1",
        transcriptId = "transcript-1",
        networkType = AsrNetworkType.WIFI,
        privacy = AsrPrivacyPolicy(allowOnlineVoice = true, allowRawAudioUpload = true)
    )

    private class FakeCredentialSource(
        private val websocketUrl: String
    ) : RealtimeAsrCredentialSource {
        var issueCount = 0

        override suspend fun availability(config: AsrSessionConfig): AsrAvailability =
            AsrAvailability.ready(AsrTransport.WEBSOCKET)

        override suspend fun issue(config: AsrSessionConfig): EphemeralAsrCredential {
            issueCount += 1
            return EphemeralAsrCredential(
                providerId = "realtime",
                providerSessionId = "provider-session",
                websocketUrl = websocketUrl,
                authorizationToken = "temporary-token",
                expiresAtEpochMs = System.currentTimeMillis() + 60_000L
            )
        }
    }
}
