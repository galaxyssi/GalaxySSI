package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkManager
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real encrypted host persistence and production recovery broker; inference is explicitly injected. */
@RunWith(AndroidJUnit4::class)
class AgentLocalBrowserRecoveryDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private inner class Fixture : AutoCloseable {
        val transcripts = AgentTranscriptStore(context)
        val conversation = transcripts.createAgentConversation("Public local browser ${UUID.randomUUID()}").id
        val id = AgentLocalDispatchIdentity(ChatHistoryStore.reserveMessageId(context), "public-local-${UUID.randomUUID()}", conversation,
            "public-turn-${UUID.randomUUID()}", "public-native-${UUID.randomUUID()}", "public-action")
        val workspaces = EncryptedAgentWorkspaceStore(context)
        val sessions = SharedPreferencesAgentSessionStore(context, "task:${id.turnId}")
        val owners = AgentLocalBrowserDispatchStore(context)
        val browsers = AgentBrowserUserRequestStore(context)
        val screen = ScreenContext("Public", pageTitle = "Public")
        val action = AgentAction(id.actionId, AgentActionKind.CALL_CONNECTOR, "Public model", AgentRisk.LOW,
            AgentActionStatus.WAITING_RESPONSE, "Public fixture")
        val pending = AgentActionResult(id.actionId, true, "Public waiting", mapOf("awaiting_response" to "true",
            "source_message_id" to id.sourceMessageId.toString(), "contact_id" to id.contactId))
        val session = AgentSessionSnapshot(id.taskId, AgentPhase.WAITING_RESPONSE, "公开浏览器恢复测试", screen,
            AgentPlan("公开浏览器恢复测试", screen, emptyList(), listOf(action)).addCheckpoint(
                AgentExecutionContinuity.checkpointBefore(action, screen, 1)), emptyList(), pending,
            processInstanceId = AgentProcessIdentity.instanceId, updatedAtMillis = System.currentTimeMillis())
        val claim = checkNotNull(AgentLongTaskRecoveryClaims.tryAcquire(id.turnId))
        val dispatch: AgentLocalBrowserDispatch
        val record: AgentBrowserUserRequest
        init {
            workspaces.upsert(AgentWorkspace(id.turnId, id.turnId, conversation, id.turnId,
                status = AgentWorkspaceStatus.WAITING_RESPONSE))
            sessions.save(session)
            dispatch = checkNotNull(owners.registerIfOwned(id, "Public model", System.currentTimeMillis(), emptySet()))
            val scope = dispatch.scope
            val invocation = AgentNativeToolInvocationContext("public-browser-call", scope.session, scope.conversation,
                scope.turn, scope.caller, attributes = mapOf("task_id" to scope.task, "workspace_id" to scope.workspace))
            val browserScope = AgentInteractiveBrowserTools.scope(invocation)
            record = owners.bind(AgentBrowserUserRequest(AgentBrowserUserRequest.key(browserScope, "public-browser"),
                UUID.randomUUID().toString(), browserScope, scope.session, scope.conversation, scope.turn, scope.caller,
                scope.workspace, "public-browser", "public-page", "public-handoff", "returned",
                taskId = scope.task, modelLoopId = scope.loop))
            check(record.localDispatchId == dispatch.key)
            browsers.save(record)
        }
        fun response(text: String) = AgentConnectorResponse(id.sourceMessageId, id.contactId, text, conversation,
            id.turnId, id.taskId, success = true)
        fun observed() { browsers.markObservationCommitted(checkNotNull(browsers.load(record.key))) }
        override fun close() {
            AgentLocalDispatchRegistry.current(id)?.close()
            val response = response("Public final")
            WorkManager.getInstance(context).cancelUniqueWork("galaxyssi-connector-recovery-${AgentConnectorResponseCodec.identity(response)}").result.get()
            WorkManager.getInstance(context).cancelUniqueWork(AgentLongTaskRecoveryScheduler.browserEventWorkName(record)).result.get()
            AgentConnectorResponseStore.removeTurn(context, conversation, id.turnId)
            context.getSharedPreferences("galaxyssi_agent_resource_health", android.content.Context.MODE_PRIVATE)
                .edit().remove("target:${id.contactId}").commit()
            sessions.clear()
            workspaces.delete(id.turnId)
            transcripts.deleteConversation(conversation)
            listOf("", ".bak", ".new").forEach {
                File(context.noBackupFilesDir, "local-browser-dispatches/${dispatch.key}.enc$it").delete()
                File(context.filesDir, "browser-user-requests/${record.key}.enc$it").delete()
            }
            claim.close()
        }
    }

    @Test fun encryptedOwnerReopensAndWaitingNeverPublishesAnAnswer() {
        Fixture().use { f ->
            assertEquals(f.dispatch, AgentLocalBrowserDispatchStore(context).load(f.dispatch.key))
            val encrypted = File(context.noBackupFilesDir, "local-browser-dispatches/${f.dispatch.key}.enc").readBytes()
            try { assertFalse(encrypted.toString(Charsets.ISO_8859_1).contains(f.conversation)) }
            finally { encrypted.fill(0) }
            assertTrue(AgentLocalBrowserDelivery.settle(context, f.dispatch,
                Result.success(LocalModelWebToolCompletion("", null, waitingForEvent = true))))
            assertEquals("waiting", f.owners.load(f.dispatch.key)?.state)
            assertFalse(AgentConnectorResponseStore.wasRecorded(context, f.response("Public final")))
            assertTrue(f.transcripts.list(f.conversation).isEmpty())
        }
    }

    @Test fun returnedEventResumesOriginalDispatchAndDeliversExactlyOnce() = runBlocking {
        Fixture().use { f ->
            var calls = 0
            assertTrue(AgentLocalBrowserRecovery.recover(context, f.record.key, f.record.generation) { saved, token ->
                assertEquals(f.dispatch, saved)
                assertFalse(token.isCancellationRequested)
                calls++
                f.observed()
                LocalModelWebToolCompletion("Public final", null)
            })
            assertEquals(1, calls)
            assertTrue(AgentConnectorResponseStore.wasRecorded(context, f.response("Public final")))
            assertEquals("delivered", f.owners.load(f.dispatch.key)?.state)
            assertFalse(checkNotNull(f.browsers.load(f.record.key)).pendingRunWake)
            assertTrue(AgentLocalBrowserRecovery.recover(context, f.record.key, f.record.generation) { _, _ ->
                error("An acknowledged event must not infer again")
            })
            assertTrue(AgentLocalBrowserDelivery.settle(context, f.dispatch,
                Result.success(LocalModelWebToolCompletion("Public final", null))))
            assertEquals(1, calls)
        }
    }

    @Test fun priorProcessCrashBeforePendingCommitRestoresOnlyCheckpointedOriginalBinding() {
        Fixture().use { f ->
            val executing = f.session.copy(phase = AgentPhase.EXECUTING, lastActionResult = null,
                processInstanceId = "public-old-process")
            f.sessions.save(executing)
            assertFalse(f.owners.restorePendingBinding(f.dispatch))
            f.owners.checkpoint(f.dispatch)
            assertTrue(f.owners.restorePendingBinding(f.dispatch))
            val restored = checkNotNull(f.sessions.load())
            assertEquals(f.id.taskId, restored.sessionId)
            assertEquals(f.id.sourceMessageId.toString(), restored.lastActionResult?.metadata?.get("source_message_id"))
            assertTrue(f.owners.owned(f.dispatch, pending = true))
            f.sessions.save(executing.copy(processInstanceId = AgentProcessIdentity.instanceId))
            assertFalse(f.owners.restorePendingBinding(f.dispatch))
        }
    }

    @Test fun cancelledDeletedAndSupersededRunsNeverExecuteOnLateReturn() = runBlocking {
        repeat(3) { mode -> Fixture().use { f ->
            when (mode) {
                0 -> f.workspaces.find(f.id.turnId)!!.let { f.workspaces.upsert(it.copy(cancellationRequested = true), it.revision) }
                1 -> f.transcripts.deleteConversation(f.conversation)
                else -> f.sessions.save(f.session.copy(lastActionResult = f.pending.copy(metadata =
                    f.pending.metadata + ("source_message_id" to (f.id.sourceMessageId + 1).toString()))))
            }
            assertTrue(AgentLocalBrowserRecovery.recover(context, f.record.key, f.record.generation) { _, _ ->
                error("An obsolete owner must not invoke any model or tool")
            })
            assertEquals("cancelled", f.owners.load(f.dispatch.key)?.state)
            assertFalse(checkNotNull(f.browsers.load(f.record.key)).pendingRunWake)
        } }
    }

    @Test fun recoveryErrorDoesNotStartAFreshLoopOrPublishFailureAsFinal() = runBlocking {
        Fixture().use { f ->
            assertFalse(AgentLocalBrowserRecovery.recover(context, f.record.key, f.record.generation) { _, _ ->
                throw AgentModelLoopRecoveryException("public_checkpoint_unavailable")
            })
            assertTrue(checkNotNull(f.browsers.load(f.record.key)).pendingRunWake)
            assertFalse(AgentConnectorResponseStore.wasRecorded(context, f.response("Public final")))
            assertEquals("pending", f.owners.load(f.dispatch.key)?.state)
        }
    }

    @Test fun fastReturnWaitsForInitialLeaseInsteadOfStartingASecondLoop() = runBlocking {
        Fixture().use { f ->
            val initial = AgentLocalDispatchRegistry.register(f.id)
            var calls = 0
            val observer = async(Dispatchers.IO) {
                AgentLocalBrowserRecovery.recover(context, f.record.key, f.record.generation) { _, _ ->
                    calls++
                    f.observed()
                    LocalModelWebToolCompletion("Public final", null)
                }
            }
            try {
                kotlinx.coroutines.delay(150)
                assertFalse(observer.isCompleted)
                assertEquals(0, calls)
                initial.close()
                assertTrue(withTimeout(10_000) { observer.await() })
                assertEquals(1, calls)
            } finally { initial.close(); observer.cancel() }
        }
    }

    @Test fun cancellingWorkerObservationDoesNotCancelOwnedModelExecution() = runBlocking {
        Fixture().use { f ->
            val started = CountDownLatch(1)
            val release = CountDownLatch(1)
            val finished = CountDownLatch(1)
            val observer = async(Dispatchers.IO) {
                AgentLocalBrowserRecovery.recover(context, f.record.key, f.record.generation) { _, token ->
                    started.countDown()
                    check(release.await(10, TimeUnit.SECONDS))
                    assertFalse(token.isCancellationRequested)
                    f.observed()
                    finished.countDown()
                    LocalModelWebToolCompletion("Public final", null)
                }
            }
            try {
                assertTrue(started.await(10, TimeUnit.SECONDS))
                observer.cancel()
                release.countDown()
                assertTrue(finished.await(10, TimeUnit.SECONDS))
                AgentLocalDispatchRegistry.current(f.id)?.let { withTimeout(10_000) { it.awaitClosed() } }
                assertEquals("delivered", f.owners.load(f.dispatch.key)?.state)
            } finally { release.countDown(); observer.cancel() }
        }
    }

    @Test fun staleGenerationCannotConsumeCurrentBrowserReturn() = runBlocking {
        Fixture().use { f ->
            assertTrue(AgentLocalBrowserRecovery.recover(context, f.record.key, "public-old-generation") { _, _ ->
                error("A stale event must not execute")
            })
            assertTrue(checkNotNull(f.browsers.load(f.record.key)).pendingRunWake)
            assertEquals("pending", f.owners.load(f.dispatch.key)?.state)
        }
    }
}
