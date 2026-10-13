package com.galaxyssi.chat

import android.util.AtomicFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkManager
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Isolated public assignments, encrypted production stores and scripted inference; no real model goal or login. */
@RunWith(AndroidJUnit4::class)
class AgentManagedBrowserRecoveryDeviceTest {
    private val app get() = InstrumentationRegistry.getInstrumentation().targetContext
    private inner class Fixture(enroll: Boolean = true, val research: Boolean = false) : AutoCloseable {
        val run = "public-managed-browser-${UUID.randomUUID()}"
        val members = listOf(AgentTeamMember("public-local", AgentDeliveryMode.RESPOND, instanceId = "first"),
            AgentTeamMember("public-local", AgentDeliveryMode.OBSERVE, instanceId = "second")).map {
                if (research) it.copy(context = mapOf("collaboration_group_id" to "$run-conversation")) else it
            }
        val request = AgentRunRequest("$run-conversation", "$run-turn", "$run-task", runId = run,
            goal = "公开框架测试：归还浏览器后继续原成员任务。", idempotencyKey = "$run-key")
        val team = EncryptedAgentTeamExecutionStore(app, AgentEncryptedDatabase(app, run))
        val controls = AgentTeamDurableControl(app)
        val ledger = EncryptedAgentManagedResponseLedger(app)
        val owners = AgentLocalBrowserDispatchStore(app)
        val browsers = AgentBrowserUserRequestStore(app)
        val databaseName = "$run-journal.db"
        val events = AgentRunEventStore(app, databaseName)
        val journal = EncryptedAgentModelLoopJournal(app, events)
        val ids = members.map { member ->
            val owner = stableAgentTeamMemberRunId(run, member.memberId)
            AgentLocalDispatchIdentity(AgentTeamDispatchIds.sourceMessageId("member:${request.idempotencyKey}:${member.memberId}"),
                "$run-local-contact", request.conversationId, request.messageId, request.taskId, "team-$owner")
        }
        val dispatches = mutableListOf<AgentLocalBrowserDispatch>()
        val records = mutableListOf<AgentBrowserUserRequest>()
        val id get() = ids[0]
        val dispatch get() = dispatches[0]
        val record get() = records[0]
        init {
            if (research) CollaborationGroupStore(app).update(request.conversationId) { group -> group.copy(
                members = members.map { CollaborationMember(it.memberId, it.memberId, "fixture", "Public member") },
                coordinatorId = members.first().memberId) }
            team.create(AgentTeamDefinition("$run-team", "public-local", members, primaryInstanceId = "first"), request)
            runBlocking {
                team.append(AgentSubagentEvent(1, run, kind = AgentSubagentEventKinds.SUPERVISOR_STARTED))
                members.forEachIndexed { index, member ->
                    team.append(AgentSubagentEvent(index + 2L, run, member.memberId, AgentSubagentEventKinds.CHILD_RUNNING,
                        childStatus = AgentSubagentStatus.RUNNING))
                }
            }
            members.forEachIndexed { index, member ->
                val id = ids[index]
                ledger.register(AgentManagedResponseRecord(stableAgentTeamMemberRunId(run, member.memberId), run,
                    member.agentId, member.deliveryMode, id.sourceMessageId, id.contactId, id.conversationId, id.turnId, id.taskId))
                if (research) {
                    val checkpoint = AgentTeamExecutionLocations(app).state(run, id.conversationId, id.turnId, id.taskId).first
                    val managed = checkNotNull(ledger.findOwner(id.actionId.removePrefix("team-")))
                    CollaborationEvidenceLedger(app).bind(id.sourceMessageId,
                        CollaborationWorkspaceAccess.from(checkNotNull(CollaborationLateResult.execution(checkpoint, managed))))
                }
                if (enroll) {
                    val dispatch = checkNotNull(owners.registerManagedIfOwned(id, "Public model", System.currentTimeMillis(), emptySet(), journal))
                    dispatches += dispatch
                    val scope = dispatch.scope
                    val context = AgentNativeToolInvocationContext(sessionId = scope.session, conversationId = scope.conversation,
                        turnId = scope.turn, callerId = scope.caller, collaborationSourceMessageId = id.sourceMessageId,
                        attributes = mapOf("task_id" to scope.task, "workspace_id" to scope.workspace))
                    val browserScope = AgentInteractiveBrowserTools.scope(context)
                    val record = owners.bind(AgentBrowserUserRequest(AgentBrowserUserRequest.key(browserScope, "public-browser"),
                        UUID.randomUUID().toString(), browserScope, scope.session, scope.conversation, scope.turn, scope.caller,
                        scope.workspace, "public-browser", "public-page", "public-handoff", "active", taskId = scope.task,
                        modelLoopId = scope.loop, collaborationSourceMessageId = id.sourceMessageId))
                    records += record
                    browsers.save(record)
                }
            }
        }
        fun returned(index: Int = 0): AgentBrowserUserRequest = records[index].copy(state = "returned").also(browsers::save)
        fun response(text: String = "公开框架测试完成。") = AgentConnectorResponse(id.sourceMessageId, id.contactId, text,
            id.conversationId, id.turnId, id.taskId)
        override fun close() {
            ids.forEach { AgentLocalDispatchRegistry.current(it)?.close() }
            records.forEach {
                WorkManager.getInstance(app).cancelUniqueWork(AgentLongTaskRecoveryScheduler.browserEventWorkName(it)).result.get()
                AtomicFile(File(app.filesDir, "browser-user-requests/${it.key}.enc")).delete()
            }
            ids.forEach {
                AtomicFile(File(app.noBackupFilesDir, "local-browser-dispatches/${LocalModelLoopContinuation.scope(it).loop}.enc")).delete()
                File(app.noBackupFilesDir, "model-loop-leases/${LocalModelLoopContinuation.scope(it).digest}.lock").delete()
                ledger.removeOwner(it.actionId.removePrefix("team-"))
                AgentConnectorResponseStore.removeTurn(app, it.conversationId, it.turnId)
            }
            team.remove(run)
            controls.remove(run)
            if (research) CollaborationGroupStore(app).remove(request.conversationId)
            events.close()
            app.deleteDatabase(databaseName)
            app.getSharedPreferences("galaxyssi_agent_resource_health", android.content.Context.MODE_PRIVATE)
                .edit().remove("target:${id.contactId}").commit()
        }
    }

    @Test fun researchMemberGetsBrowserAndSetupToolsWithoutUnscopedExecutionAndDeletedGroupCannotResume() = runBlocking {
        Fixture(research = true).use { f ->
            val ids = LocalModelWebToolRunner.registry(app, f.id.conversationId, f.id.turnId,
                f.id.sourceMessageId, true, f.dispatch.managedOwner).registeredContractCatalog().descriptors.map { it.id }.toSet()
            assertTrue(ids.containsAll(AgentInteractiveBrowserTools.toolIds))
            assertTrue(CollaborationRecallNativeTool.ID in ids)
            assertTrue(AgentOnDeviceRuntimeTools.INSTALL_PACK in ids)
            assertFalse(AgentOnDeviceRuntimeTools.EXECUTE in ids)
            assertFalse(ids.any { it.startsWith("galaxyssi.workspace.") })
            f.returned()
            CollaborationGroupStore(app).remove(f.id.conversationId)
            assertEquals(AgentManagedBrowserState.OBSOLETE, f.owners.managedState(f.dispatch))
            assertTrue(AgentLocalBrowserRecovery.recover(app, f.record.key, f.record.generation) { _, _ -> error("Deleted group") })
            assertEquals("cancelled", f.owners.load(f.dispatch.key)?.state)
        }
    }

    @Test fun unavailableOwnerDuringDeliveryDoesNotAcknowledgeAnObservedWake() = runBlocking {
        Fixture().use { f ->
            f.returned()
            assertFalse(AgentLocalBrowserRecovery.recover(app, f.record.key, f.record.generation) { _, _ ->
                f.browsers.markObservationCommitted(f.browsers.load(f.record.key)!!)
                AgentEncryptedDatabase(app, f.run).clear()
                LocalModelWebToolCompletion("Must remain undelivered", null)
            })
            assertTrue(f.browsers.load(f.record.key)!!.pendingRunWake)
            assertEquals(AgentManagedResponseState.PENDING, f.ledger.findOwner(f.dispatch.managedOwner!!.ownerRunId)?.state)
        }
    }

    @Test fun realManagedCatalogAndEncryptedOwnersSeparateMembersWithoutOrdinaryRunAnchors() {
        Fixture().use { f ->
            assertNotEquals(f.records[0].scope, f.records[1].scope)
            f.dispatches.forEachIndexed { index, dispatch ->
                assertEquals(dispatch, AgentLocalBrowserDispatchStore(app).load(dispatch.key))
                assertTrue(dispatch.runWorkspaceId.isBlank())
                assertTrue(dispatch.runSessionId.isBlank())
                assertTrue(f.owners.owned(dispatch, pending = true))
                assertEquals(dispatch.managedOwner?.ownerRunId, f.records[index].managedOwnerRunId)
                val registry = LocalModelWebToolRunner.registry(app, dispatch.identity.conversationId,
                    dispatch.identity.turnId, dispatch.identity.sourceMessageId, true, dispatch.managedOwner)
                val ids = registry.registeredContractCatalog().descriptors.map { it.id }.toSet()
                assertTrue(ids.containsAll(AgentInteractiveBrowserTools.toolIds))
                assertTrue(AgentOnDeviceRuntimeTools.INSTALL_PACK in ids)
                assertTrue(AgentToolInspectionTools.DESCRIBE in ids)
                val bytes = File(app.noBackupFilesDir, "local-browser-dispatches/${dispatch.key}.enc").readBytes()
                try { assertFalse(bytes.toString(Charsets.ISO_8859_1).contains(f.run)) } finally { bytes.fill(0) }
            }
        }
    }

    @Test fun pausedHandoffReopensOriginalJournalThenObservesAndDeliversOnlyToOriginalMember() = runBlocking {
        Fixture().use { f ->
            var rounds = 0
            var handoffs = 0
            var observations = 0
            val registry = AgentNativeToolRegistry().registerAll(listOf(
                AgentNativeToolDefinition(descriptor(AgentInteractiveBrowserTools.ACT), AgentNativeToolExecutor {
                    handoffs++
                    AgentNativeToolExecutionResult.success(mapOf("durable_resume_available" to true,
                        "host_wait_key" to f.record.key, "host_wait_generation" to f.record.generation))
                }), AgentNativeToolDefinition(descriptor(AgentInteractiveBrowserTools.OBSERVE), AgentNativeToolExecutor {
                    observations++
                    assertEquals(f.id.sourceMessageId, it.context.collaborationSourceMessageId)
                    AgentNativeToolExecutionResult.success(mapOf("public_page_observed" to true))
                })))
            val catalog = registry.availableCatalog()
            val saved = LocalModelLoopContinuationStore(f.journal).prepare(f.id, f.request.goal, "public-scripted-profile", false,
                f.id.sourceMessageId, catalog.manifest.sha256, "Public framework system")
            val resolver = AgentBrowserModelEventWaitResolver(f.browsers::load,
                { AgentLocalBrowserDispatchPolicy.matches(f.dispatch, it) && f.owners.owned(f.dispatch) },
                commitObservation = f.browsers::markObservationCommitted)
            fun local() = LocalModelWebToolSession(app, "public-scripted-profile", false, inference = { _, prompt ->
                val output = when (++rounds) {
                    1 -> """{"tool_calls":[{"id":"handoff","name":"${AgentInteractiveBrowserTools.ACT}","arguments":{"operation":"request_user_control","session_id":"public-browser","page_id":"public-page"}}]}"""
                    2 -> {
                        assertTrue(prompt.contains("browser_control_returned"))
                        """{"tool_calls":[{"id":"observe","name":"${AgentInteractiveBrowserTools.OBSERVE}","arguments":{}}]}"""
                    }
                    3 -> {
                        assertTrue(prompt.contains("public_page_observed"))
                        """{"answer":"公开框架测试完成。","tool_calls":[]}"""
                    }
                    else -> error("A completed member must not infer again")
                }
                LocalModelInferenceResult(text = output, profileId = "public-scripted-profile", backend = "fixture",
                    smeAvailable = false, elapsedMillis = 1)
            })
            suspend fun loop(request: LocalModelLoopContinuation) = AgentModelToolLoop(local().adapter(catalog.descriptors), registry,
                journal = f.journal, eventWaitResolver = resolver).run(request.request(catalog.descriptors,
                    AgentNativeToolCancellationToken.NONE, AgentModelToolLoopEventSink.NONE))
            val waiting = loop(saved)
            assertEquals(AgentModelToolLoopStatus.WAITING_FOR_EVENT, waiting.status)
            AgentLocalBrowserDelivery.settle(app, f.dispatch, Result.success(LocalModelWebToolCompletion("", null, true)))
            assertEquals(AgentManagedResponseState.PENDING, f.ledger.findOwner(f.dispatch.managedOwner!!.ownerRunId)?.state)
            f.controls.set(f.run, AgentTeamUserControl.PAUSE)
            f.returned()
            assertFalse(AgentLocalBrowserRecovery.recover(app, f.record.key, f.record.generation) { _, _ -> error("Paused") })
            assertEquals(1, rounds)
            f.controls.set(f.run, AgentTeamUserControl.RUN)
            assertTrue(AgentLocalBrowserRecovery.recover(app, f.record.key, f.record.generation) { dispatch, _ ->
                val restored = runBlocking { LocalModelLoopContinuationStore(EncryptedAgentModelLoopJournal(app, f.events))
                    .restore(dispatch.identity, catalog.manifest.sha256) }
                assertEquals(saved, restored)
                val completed = runBlocking { loop(restored) }
                assertEquals(AgentModelToolLoopStatus.COMPLETED, completed.status)
                LocalModelWebToolCompletion(completed.assistantText, null)
            })
            assertEquals(3, rounds)
            assertEquals(1, handoffs)
            assertEquals(1, observations)
            val completed = f.ledger.findOwner(f.dispatch.managedOwner!!.ownerRunId)!!
            assertEquals("公开框架测试完成。", completed.response?.content)
            assertEquals(f.id.sourceMessageId, completed.response?.sourceMessageId)
            assertFalse(AgentConnectorResponseStore.contains(app, f.response()))
            assertEquals(AgentManagedResponseState.PENDING, f.ledger.findOwner(f.dispatches[1].managedOwner!!.ownerRunId)?.state)
            assertFalse(f.browsers.load(f.record.key)!!.pendingRunWake)
            assertTrue(AgentLocalBrowserRecovery.recover(app, f.record.key, f.record.generation) { _, _ -> error("Duplicate inference") })
        }
    }

    @Test fun stopWhileWaitingSettlesOriginalMemberWithoutInferringOrTouchingSibling() = runBlocking {
        Fixture().use { f ->
            f.returned()
            f.controls.set(f.run, AgentTeamUserControl.STOP)
            assertTrue(AgentLocalBrowserRecovery.recover(app, f.record.key, f.record.generation) { _, _ -> error("Stopped") })
            assertEquals("cancelled", f.owners.load(f.dispatch.key)?.state)
            assertEquals("cancelled", f.ledger.findOwner(f.dispatch.managedOwner!!.ownerRunId)?.response?.taskStatus)
            assertEquals(AgentManagedResponseState.PENDING, f.ledger.findOwner(f.dispatches[1].managedOwner!!.ownerRunId)?.state)
            assertTrue(AgentLocalBrowserDelivery.settle(app, f.dispatch, Result.success(LocalModelWebToolCompletion("Late reply", null))))
            assertEquals("cancelled", f.ledger.findOwner(f.dispatch.managedOwner!!.ownerRunId)?.response?.taskStatus)
        }
    }

    @Test fun unavailableCheckpointDoesNotFallBackToDefaultStoreOrPublishFailureAsFinal() = runBlocking {
        Fixture().use { f ->
            f.returned()
            // Remove only this fixture's isolated row, preserving its host location to simulate unavailable storage.
            AgentEncryptedDatabase(app, f.run).clear()
            assertEquals(AgentManagedBrowserState.UNVERIFIED, f.owners.managedState(f.dispatch))
            assertFalse(AgentLocalBrowserRecovery.recover(app, f.record.key, f.record.generation) { _, _ -> error("Unverified") })
            assertTrue(f.browsers.load(f.record.key)!!.pendingRunWake)
            assertEquals(AgentManagedResponseState.PENDING, f.ledger.findOwner(f.dispatch.managedOwner!!.ownerRunId)?.state)
        }
    }

    @Test fun aPreparedRequestWithoutAnInitialInferenceCannotBeSilentlyEnrolledIntoANewCatalog() = runBlocking {
        Fixture(enroll = false).use { f ->
            val saved = LocalModelLoopContinuationStore(f.journal).prepare(f.id, f.request.goal, "public-profile", false,
                f.id.sourceMessageId, "a".repeat(64), "Public system")
            assertFalse(f.journal.hasRecords(saved.scope))
            assertTrue(f.journal.hasOperation(saved.scope, LocalModelLoopContinuationStore.OPERATION))
            assertNull(f.owners.registerManagedIfOwned(f.id, "Public model", 1, emptySet(), f.journal))
            assertEquals(saved, LocalModelLoopContinuationStore(f.journal).restore(f.id, "a".repeat(64)))
        }
    }

    @Test fun durableResultBeforeDispatchAcknowledgementNeverStartsAnotherInference() = runBlocking {
        Fixture().use { f ->
            f.returned()
            f.ledger.acknowledge(f.response())
            assertTrue(AgentLocalBrowserRecovery.recover(app, f.record.key, f.record.generation) { _, _ -> error("Already delivered") })
            assertEquals("delivered", f.owners.load(f.dispatch.key)?.state)
            assertFalse(f.browsers.load(f.record.key)!!.pendingRunWake)
        }
    }

    @Test fun fastReturnWaitsForInitialMemberLeaseAndCannotStartASecondLoop() = runBlocking {
        Fixture().use { f ->
            f.returned()
            val lease = AgentLocalDispatchRegistry.register(f.id)
            var calls = 0
            val pending = async(Dispatchers.IO) {
                AgentLocalBrowserRecovery.recover(app, f.record.key, f.record.generation) { _, _ ->
                    calls++
                    f.browsers.markObservationCommitted(f.browsers.load(f.record.key)!!)
                    LocalModelWebToolCompletion("公开框架测试完成。", null)
                }
            }
            try {
                kotlinx.coroutines.delay(150)
                assertFalse(pending.isCompleted)
                assertEquals(0, calls)
                lease.close()
                assertTrue(withTimeout(10_000) { pending.await() })
                assertEquals(1, calls)
            } finally { lease.close(); pending.cancel() }
        }
    }

    private fun descriptor(id: String) = AgentNativeToolDescriptor(id, "1.0.0", "Public fixture", "Public fixture",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW)
}
