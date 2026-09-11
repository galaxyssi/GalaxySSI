package com.galaxyssi.chat.voice.asr.local

import java.nio.ByteBuffer
import kotlin.io.path.createTempDirectory
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test

class SharedHighAccuracyAsrPoolTest {
    @Test fun hundredWindowsShareOnePreparationAndRuntime() = runBlocking {
        fixture { pool, engine ->
            engine.gate = CompletableDeferred()
            val clients = List(100) { pool.acquire() }
            coroutineScope { clients.map { client -> async(Dispatchers.Default) { client.prepareAsync() } }.awaitAll() }
            assertEquals(1, engine.prepareCalls)
            assertEquals(1, pool.snapshot().controllerCreations)
            engine.gate!!.complete(Unit)
            await { clients.all { it.isReady() } }
            clients.forEach { it.close() }
            await { engine.closeCalls == 1 }
            assertEquals(0, pool.snapshot().clients)
        }
    }

    @Test fun unrelatedWindowCannotCancelOrCloseOwnersRecording() = runBlocking {
        fixture { pool, engine ->
            val a = pool.acquire()
            val b = pool.acquire()
            a.prepareAsync()
            await { a.isReady() }
            val turn = requireNotNull(a.startTurnIfReady(AsrConfig(), "test") {})
            assertNull(b.startTurnIfReady(AsrConfig(), "test") {})
            b.cancelActive()
            b.prepareAsync()
            b.close()
            assertEquals(1, engine.prepareCalls)
            assertEquals(0, engine.cancelCalls)
            assertEquals(0, engine.closeCalls)
            assertEquals(a.ownerId, pool.snapshot().activeOwner)
            turn.cancel()
            a.close()
            await { engine.closeCalls == 1 }
        }
    }

    @Test fun resultsStayWithOwnerAndLateClosedOwnerCallbacksAreIgnored() = runBlocking {
        fixture { pool, engine ->
            val a = pool.acquire()
            val b = pool.acquire()
            val aText = mutableListOf<String>()
            val bText = mutableListOf<String>()
            a.prepareAsync()
            await { a.isReady() }
            requireNotNull(a.startTurnIfReady(AsrConfig(), "a") { aText += it.stableText })
            engine.partial("first")
            assertEquals(listOf("first"), aText)
            a.close()
            engine.partial("late")
            assertEquals(listOf("first"), aText)
            val turn = requireNotNull(b.startTurnIfReady(AsrConfig(), "b") { bText += it.stableText })
            engine.partial("second")
            assertEquals(listOf("second"), bText)
            engine.stopText = "owner b final"
            assertEquals("owner b final", turn.finish().text)
            assertEquals(listOf("first"), aText)
            b.close()
        }
    }

    @Test fun reacquiringBeforeIdleReleaseKeepsTheLoadedModel() = runBlocking {
        fixture { pool, engine ->
            val first = pool.acquire()
            first.prepareAsync()
            await { first.isReady() }
            first.close()
            val second = pool.acquire()
            second.prepareAsync()
            delay(100)
            assertTrue(second.isReady())
            assertEquals(1, engine.prepareCalls)
            assertEquals(0, engine.closeCalls)
            second.close()
            await { engine.closeCalls == 1 }
        }
    }

    @Test fun closedClientCannotPrepareStartOrChangeTheSharedRuntime() = runBlocking {
        fixture { pool, engine ->
            val client = pool.acquire()
            client.close()
            client.prepareAsync()
            client.onAppForegroundChanged(true)
            client.onMicrophonePermissionChanged(true)
            assertNull(client.startTurnIfReady(AsrConfig(), "test") {})
            assertFalse(client.isReady())
            assertEquals(0, engine.prepareCalls)
            assertEquals(0, pool.snapshot().controllerCreations)
        }
    }

    @Test fun unrelatedForegroundWindowsCannotResumeBackgroundOwnersMicrophone() = runBlocking {
        val monitor = FakeMonitor()
        fixture(monitor) { pool, engine ->
            val a = pool.acquire()
            val b = pool.acquire()
            a.onAppForegroundChanged(true)
            b.onAppForegroundChanged(true)
            a.prepareAsync()
            await { a.isReady() }
            requireNotNull(a.startTurnIfReady(AsrConfig(), "test") {})
            a.onAppForegroundChanged(false)
            b.onAppForegroundChanged(true)
            assertFalse(monitor.foreground)
            b.close()
            assertFalse(monitor.foreground)
            assertEquals(0, engine.cancelCalls)
            a.onAppForegroundChanged(true)
            assertTrue(monitor.foreground)
            a.close()
            await { engine.closeCalls == 1 }
            assertTrue(monitor.closed)
        }
    }

    @Test fun failedStartReleasesOwnershipForTheNextWindow() = runBlocking {
        fixture { pool, engine ->
            val a = pool.acquire()
            val b = pool.acquire()
            a.prepareAsync()
            await { a.isReady() }
            engine.failStart = true
            assertTrue(runCatching { a.startTurnIfReady(AsrConfig(), "a") {} }.isFailure)
            assertNull(pool.snapshot().activeOwner)
            engine.failStart = false
            val turn = requireNotNull(b.startTurnIfReady(AsrConfig(), "b") {})
            turn.cancel()
            a.close()
            b.close()
        }
    }

    private suspend fun fixture(monitor: FakeMonitor? = null,
        test: suspend (SharedHighAccuracyAsrPool, FakeEngine) -> Unit) {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val directory = createTempDirectory("shared-asr-").toFile()
        val engine = FakeEngine()
        val pool = SharedHighAccuracyAsrPool(scope, idleReleaseMs = 50) {
            HighAccuracyLocalAsrController(scope, { directory }, { engine }, runtimeMonitorFactory =
                monitor?.let { observed -> { _: LocalAsrEngine -> observed } })
        }
        try { test(pool, engine) } finally {
            scope.cancel()
            directory.delete()
        }
    }

    private suspend fun await(condition: () -> Boolean) = withTimeout(2_000) {
        while (!condition()) delay(5)
    }

    private class FakeMonitor : LocalAsrRuntimeMonitor {
        var foreground = false
        var closed = false
        override fun onAppForegroundChanged(foreground: Boolean) { this.foreground = foreground }
        override fun onMicrophonePermissionChanged(granted: Boolean) = Unit
        override fun close() { closed = true }
    }

    private class FakeEngine : LocalAsrEngine {
        override val state = MutableStateFlow<LocalAsrState>(LocalAsrState.Unprepared)
        override val events = MutableSharedFlow<AsrEvent>(extraBufferCapacity = 32)
        var gate: CompletableDeferred<Unit>? = null
        var prepareCalls = 0
        var cancelCalls = 0
        var closeCalls = 0
        var stopText = "done"
        var failStart = false
        private var token = 0L
        override suspend fun prepare(modelDirectory: String) {
            prepareCalls++
            gate?.await()
            transition(LocalAsrState.Ready(modelDirectory, 1))
        }
        override fun start(config: AsrConfig) {
            check(!failStart) { "test startup failure" }
            transition(LocalAsrState.Listening(++token, config))
        }
        override fun stop() {
            events.tryEmit(AsrEvent.Final(stopText, 1_000, 10, AsrTranscriptTermination.END_OF_TEXT))
            transition(LocalAsrState.Ready("model", 1))
        }
        fun partial(text: String) { events.tryEmit(AsrEvent.Partial(text, "", revision = 1)) }
        override fun pushPcm(pcm: ByteBuffer, sampleCount: Int) = true
        override fun cancel() { cancelCalls++; transition(LocalAsrState.Ready("model", 1)) }
        override fun pause(reason: LocalAsrPauseReason) = Unit
        override fun resume(reason: LocalAsrPauseReason) = Unit
        override fun close() { closeCalls++; transition(LocalAsrState.Closed) }
        private fun transition(value: LocalAsrState) {
            state.value = value
            events.tryEmit(AsrEvent.StateChanged(value))
        }
    }
}
