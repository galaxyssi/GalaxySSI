package com.galaxyssi.chat.voice.modelstream

import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test

class ModelStreamRequestLifetimesTest {
    @Test fun cancellationDuringPreparationNeverStartsHttp() = runBlocking {
        val lifetimes = ModelStreamRequestLifetimes()
        val entered = CompletableDeferred<Unit>()
        var httpStarted = false
        val run = launch { lifetimes.run("old") { entered.complete(Unit); CompletableDeferred<Unit>().await(); httpStarted = true } }
        entered.await()
        assertTrue(lifetimes.cancel("old", ModelStreamCancelReason.USER_STOP))
        withTimeout(2_000) { run.join() }
        assertFalse(httpStarted)
        assertTrue(lifetimes.activeRequestIds().isEmpty())
    }

    @Test fun toolRoundCancellationLeavesOtherConversationRunning() = runBlocking {
        val lifetimes = ModelStreamRequestLifetimes()
        val ready = CompletableDeferred<Unit>()
        val otherReady = CompletableDeferred<Unit>()
        val release = CompletableDeferred<String>()
        val cancelled = launch { lifetimes.run("old") { ready.complete(Unit); awaitCancellation() } }
        val other = async { lifetimes.run("other") { otherReady.complete(Unit); release.await() } }
        ready.await(); otherReady.await()
        lifetimes.cancel("old", ModelStreamCancelReason.USER_STOP)
        withTimeout(2_000) { cancelled.join() }
        assertTrue(other.isActive)
        release.complete("ok")
        assertEquals("ok", other.await())
        assertTrue(lifetimes.activeRequestIds().isEmpty())
    }

    @Test fun normalCompletionAndExceptionBothReleaseOwnership() = runBlocking {
        val lifetimes = ModelStreamRequestLifetimes()
        assertEquals(42, lifetimes.run("same") { 42 })
        try { lifetimes.run("same") { error("expected") } } catch (_: IllegalStateException) { }
        assertEquals(43, lifetimes.run("same") { 43 })
        assertFalse(lifetimes.cancel("same", ModelStreamCancelReason.USER_STOP))
    }

    @Test fun duplicateIdCannotCancelOrReplaceOriginalOwner() = runBlocking {
        val lifetimes = ModelStreamRequestLifetimes()
        val ready = CompletableDeferred<Unit>()
        val original = launch { lifetimes.run("same") { ready.complete(Unit); awaitCancellation() } }
        ready.await()
        try { lifetimes.run("same") { error("Must not run") }; fail() } catch (_: IllegalStateException) { }
        assertTrue(original.isActive)
        assertTrue(lifetimes.cancel("same", ModelStreamCancelReason.USER_STOP))
        original.join()
    }
}
