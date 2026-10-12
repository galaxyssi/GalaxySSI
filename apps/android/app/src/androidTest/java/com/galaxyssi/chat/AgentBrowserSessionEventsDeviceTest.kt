package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Shared-directory/event fixtures, not real-model browser or login acceptance. */
@RunWith(AndroidJUnit4::class)
class AgentBrowserSessionEventsDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun guestAtomicRenamePassivelyWakesOnlyTheOriginalHandoff() = fixture { store, record ->
        assumeTrue(InstrumentationRegistry.getArguments().getString("browser_runtime_probe") == "true")
        val observed = CountDownLatch(1)
        var wakes = 0
        AgentBrowserSessionWatch(context, store, enqueue = {
            assertEquals("session_lost", it.interruptionCode)
            assertEquals(it, store.current(record.key, record.generation))
            wakes++
            observed.countDown()
        }).use { watch ->
            watch.watch(record)
            val event = AgentBrowserSessionEventCodec.file(context, record)
            val source = File(event.parentFile, "public-source.enc")
            source.writeBytes(envelope(record))
            try {
                val result = AgentOnDeviceRuntimeManager(context).execute(AgentRuntimeExecutionRequest(
                    language = AgentRuntimeLanguage.SHELL,
                    source = "cp .galaxyssi-inputs/event/source.enc .galaxyssi-browser-events/public-pending.tmp\n" +
                        "mv .galaxyssi-browser-events/public-pending.tmp .galaxyssi-browser-events/${event.name}",
                    arguments = emptyList(), timeoutMillis = 60_000, networkEnabled = false,
                    artifactPaths = emptyList(), workspaceId = AgentBrowserSessionEventCodec.workspace(record),
                    hostInputFiles = listOf(AgentRuntimeHostInput(source, "event/source.enc")),
                    workspaceMutationExpected = false, discoverBuildArtifacts = false))
                assertEquals(result.stderr, 0, result.exitCode)
                assertTrue("The 9P host write must notify the native observer", observed.await(10, TimeUnit.SECONDS))
                assertEquals(1, wakes)
                assertEquals("interrupted", store.current(record.key, record.generation).state)
                assertFalse(store.current(record.key, record.generation).modelObservationCommitted)
                assertNull(AgentBrowserSessionEventCodec.consume(context, record, store))
            } finally { source.delete() }
        }
    }

    @Test fun eventBeforeActiveCommitIsRecoveredBySubscriptionWithoutAnotherBrowserCall() = fixture { store, record ->
        val requested = record.copy(state = "requested", handoffId = "")
        // A separate isolated store represents a request whose active commit has not occurred yet.
        val pendingDirectory = File(context.filesDir, "public-session-pending-${record.generation}")
        val pending = AgentBrowserUserRequestStore(context, pendingDirectory)
        try {
            pending.save(requested)
            AgentBrowserSessionEventCodec.file(context, record).writeBytes(envelope(record))
            assertNull(AgentBrowserSessionEventCodec.consume(context, requested, pending))
            pending.save(record)
            val queue = ConcurrentLinkedQueue<() -> Unit>()
            var wakes = 0
            AgentBrowserSessionWatch(context, pending, enqueue = { wakes++ }, dispatch = queue::add).use { watch ->
                watch.watch(record)
                while (true) (queue.poll() ?: break).invoke()
                assertEquals(1, wakes)
                assertEquals("session_lost", pending.current(record.key, record.generation).interruptionCode)
            }
        } finally { pendingDirectory.deleteRecursively() }
    }

    @Test fun lateOldEventCannotCloseReturnedOrReplacementControl() = fixture { store, record ->
        val queue = ConcurrentLinkedQueue<() -> Unit>()
        AgentBrowserSessionWatch(context, store, enqueue = { error("No stale wake") }, dispatch = queue::add).use { watch ->
            watch.watch(record)
            val returned = record.copy(state = "returned")
            store.save(returned)
            AgentBrowserSessionEventCodec.file(context, record).writeBytes(envelope(record))
            while (true) (queue.poll() ?: break).invoke()
            assertEquals(returned, store.current(record.key, record.generation))
            val replacement = record.copy(generation = UUID.randomUUID().toString(), handoffId = "replacement")
            store.save(replacement, replaceSettled = true)
            assertNull(AgentBrowserSessionEventCodec.consume(context, replacement, store))
            assertEquals(replacement, store.current(record.key, replacement.generation))
        }
    }

    @Test fun failedWakeRemainsDurableAndCorruptEventsDoNotStopWaiting() = fixture { store, record ->
        val event = AgentBrowserSessionEventCodec.file(context, record)
        event.writeBytes(ByteArray(5000))
        assertNull(AgentBrowserSessionEventCodec.consume(context, record, store))
        assertEquals(record, store.current(record.key, record.generation))
        event.writeBytes(envelope(record).also { it[it.lastIndex] = (it.last() + 1).toByte() })
        assertNull(AgentBrowserSessionEventCodec.consume(context, record, store))
        event.writeBytes(envelope(record))
        val queue = ConcurrentLinkedQueue<() -> Unit>()
        AgentBrowserSessionWatch(context, store, enqueue = { error("Public fixture: enqueue unavailable") }, dispatch = queue::add).use { watch ->
            watch.watch(record)
            while (true) (queue.poll() ?: break).invoke()
            val reloaded = AgentBrowserUserRequestStore(context, storeDirectory(record)).current(record.key, record.generation)
            assertTrue(reloaded.pendingRunWake)
            assertEquals("session_lost", reloaded.interruptionCode)
        }
    }

    private fun storeDirectory(record: AgentBrowserUserRequest) = File(context.filesDir, "public-session-store-${record.generation}")

    private fun fixture(block: (AgentBrowserUserRequestStore, AgentBrowserUserRequest) -> Unit) {
        val scope = AgentNativeJsonCodec.sha256(UUID.randomUUID().toString())
        val record = AgentBrowserUserRequest(AgentBrowserUserRequest.key(scope, "public-browser"), UUID.randomUUID().toString(),
            scope, "public-session", "public-conversation", "public-turn", "public-caller", "public-files",
            "public-browser", "public-page", "public-handoff", "active", taskId = "public-task",
            hostProcessId = AgentProcessIdentity.instanceId, runWorkspaceId = "public-original-run")
        val directory = storeDirectory(record)
        val store = AgentBrowserUserRequestStore(context, directory)
        store.save(record)
        AgentBrowserSessionEventCodec.prepare(context, record)
        try { block(store, record) } finally {
            directory.deleteRecursively()
            // This UUID-scoped workspace belongs only to this test, never to an active user Run.
            AgentBrowserSessionEventCodec.file(context, record).parentFile!!.parentFile!!.deleteRecursively()
        }
    }

    private fun envelope(record: AgentBrowserUserRequest): ByteArray {
        val key = AgentBrowserSessionEventCodec.deriveKey(record, AgentBrowserHostAuthority.token(context, record.scope))
        val iv = ByteArray(12).also { java.security.SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
        cipher.updateAAD(AgentBrowserSessionEventCodec.binding(record).toByteArray())
        val plain = org.json.JSONObject().put("code", "session_lost").put("session_id", record.browserSessionId)
            .put("page_id", record.pageId).put("handoff_id", record.handoffId).toString().toByteArray()
        return try { byteArrayOf(1) + iv + cipher.doFinal(plain) } finally { key.fill(0); plain.fill(0) }
    }
}
