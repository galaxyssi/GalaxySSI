package com.galaxyssi.chat

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRunRecoveryCoordinatorTest {
    private fun remote(status: String = "running") = AgentRecoverableRun(
        AgentRunHandle("run-1", "turn-1", "codex", "remote-1"), 0,
        observation = AgentRemoteRecoveryObservation("conversation-1", "desktop-1", status, "remote-task", "remote-1", 7)
    )

    private fun workspace() = AgentWorkspace("turn-1", "session-1", "conversation-1", "turn-1",
        parentRunId = "run-1", agentId = "codex", deviceId = "desktop-1", status = AgentWorkspaceStatus.RUNNING)

    @Test fun unverifiedLocalHandoffIsNotRemoteEvidence(): Unit = runBlocking {
        val store = RecoveryRunControlStore(runEvent(AgentRunControlEventType.RUN_STARTED, 1))
        val workspaces = InMemoryAgentWorkspaceStore().apply { upsert(workspace()) }
        val coordinator = AgentRunRecoveryCoordinator(store, workspaces, { runningRecordedRun() },
            { _, _ -> durableRegistration() }, { RecoveryAgentAdapter(durableRegistration(), listOf(remote().copy(observation = null))) })
        assertEquals(AgentRunRecoveryOutcome.WAITING_FOR_REMOTE, coordinator.recover().single().outcome)
    }

    @Test fun matchingOnlyOneIdentifierCannotRecoverAnotherRun(): Unit = runBlocking {
        val valid = remote()
        val candidates = listOf(
            valid.copy(handle = valid.handle.copy(runId = "wrong")),
            valid.copy(handle = valid.handle.copy(taskId = "wrong")),
            valid.copy(handle = valid.handle.copy(agentId = "wrong")),
            valid.copy(observation = valid.observation!!.copy(conversationId = "wrong")),
            valid.copy(observation = valid.observation!!.copy(deviceId = "wrong")),
            valid.copy(observation = valid.observation!!.copy(status = "unknown"))
        )
        for (candidate in candidates) {
            val store = RecoveryRunControlStore(runEvent(AgentRunControlEventType.RUN_STARTED, 1))
            val coordinator = AgentRunRecoveryCoordinator(store, InMemoryAgentWorkspaceStore(), { runningRecordedRun() },
                { _, _ -> durableRegistration() }, { RecoveryAgentAdapter(durableRegistration(), listOf(candidate)) })
            assertEquals(AgentRunRecoveryOutcome.WAITING_FOR_REMOTE, coordinator.recover().single().outcome)
        }
    }

    @Test fun workspaceFromAnotherConversationIsNeverModified(): Unit = runBlocking {
        val workspaces = InMemoryAgentWorkspaceStore().apply { upsert(workspace().copy(conversationId = "other")) }
        val original = workspaces.serializedSnapshot()
        AgentRunRecoveryCoordinator(RecoveryRunControlStore(runEvent(AgentRunControlEventType.RUN_STARTED, 1)),
            workspaces, { runningRecordedRun() }, { _, _ -> durableRegistration() },
            { RecoveryAgentAdapter(durableRegistration(), listOf(remote("cancelled"))) }).recover()
        assertEquals(original, workspaces.serializedSnapshot())
    }

    @Test fun remoteTerminalAndWaitStatesAreNotRestoredAsRunning(): Unit = runBlocking {
        val expected = mapOf("cancelled" to AgentWorkspaceStatus.CANCELLED, "failed" to AgentWorkspaceStatus.FAILED,
            "paused" to AgentWorkspaceStatus.PAUSED, "waiting_input" to AgentWorkspaceStatus.WAITING_CONFIRMATION,
            "completed" to AgentWorkspaceStatus.WAITING_RESPONSE)
        for ((status, result) in expected) {
            val store = RecoveryRunControlStore(runEvent(AgentRunControlEventType.RUN_STARTED, 1))
            val workspaces = InMemoryAgentWorkspaceStore().apply { upsert(workspace()) }
            AgentRunRecoveryCoordinator(store, workspaces, { runningRecordedRun() }, { _, _ -> durableRegistration() },
                { RecoveryAgentAdapter(durableRegistration(), listOf(remote(status))) }).recover()
            assertEquals(status, result, workspaces.find("turn-1")!!.status)
            assertTrue(store.appended.single().idempotencyKey != runEvent(AgentRunControlEventType.RUN_STARTED, 1).idempotencyKey)
            if (status == "completed") assertTrue(store.appended.single().type != AgentRunControlEventType.RUN_COMPLETED)
        }
    }

    @Test fun cancellationPropagatesWithoutAppendingRecovery(): Unit = runBlocking {
        val store = RecoveryRunControlStore(runEvent(AgentRunControlEventType.RUN_STARTED, 1))
        try {
            AgentRunRecoveryCoordinator(store, InMemoryAgentWorkspaceStore(), { runningRecordedRun() },
                { _, _ -> durableRegistration() }, { throw kotlinx.coroutines.CancellationException("cancelled") }).recover()
            error("Cancellation was swallowed")
        } catch (_: kotlinx.coroutines.CancellationException) {
            assertTrue(store.appended.isEmpty())
        }
    }

    @Test fun phoneOwnedRunUsesRegisteredRemoteExecutorIdentity(): Unit = runBlocking {
        val store = RecoveryRunControlStore(runEvent(AgentRunControlEventType.RUN_STARTED, 1).copy(deviceId = "phone-1"))
        val workspaces = InMemoryAgentWorkspaceStore().apply { upsert(workspace().copy(deviceId = "phone-1")) }
        val result = AgentRunRecoveryCoordinator(store, workspaces, { runningRecordedRun() },
            { _, _ -> durableRegistration() }, { RecoveryAgentAdapter(durableRegistration(), listOf(remote())) }).recover().single()
        assertEquals(AgentRunRecoveryOutcome.RECONNECTED_REMOTE, result.outcome)
    }

    @Test fun oldWorkspaceWithoutRunBindingIsNotAdoptedByMatchingTask(): Unit = runBlocking {
        val workspaces = InMemoryAgentWorkspaceStore().apply { upsert(workspace().copy(parentRunId = "")) }
        val before = workspaces.serializedSnapshot()
        AgentRunRecoveryCoordinator(RecoveryRunControlStore(runEvent(AgentRunControlEventType.RUN_STARTED, 1)),
            workspaces, { runningRecordedRun() }, { _, _ -> durableRegistration() },
            { RecoveryAgentAdapter(durableRegistration(), listOf(remote("cancelled"))) }).recover()
        assertEquals(before, workspaces.serializedSnapshot())
    }

    @Test fun localCancellationWhileQueryRunsWinsOverRemoteRunning(): Unit = runBlocking {
        val store = RecoveryRunControlStore(runEvent(AgentRunControlEventType.RUN_STARTED, 1))
        val workspaces = InMemoryAgentWorkspaceStore().apply { upsert(workspace()) }
        val result = AgentRunRecoveryCoordinator(store, workspaces, { runningRecordedRun() },
            { _, _ -> durableRegistration() }, {
                store.appendNext(runEvent(AgentRunControlEventType.RUN_CANCELLED, 2))
                RecoveryAgentAdapter(durableRegistration(), listOf(remote()))
            }).recover().single()
        assertEquals("local_run_advanced_during_query", result.reason)
        assertEquals(AgentRunControlEventType.RUN_CANCELLED, store.appended.single().type)
    }

    @Test fun unavailableObservationDoesNotOverwriteAWorkspaceResumedDuringQuery(): Unit = runBlocking {
        val store = RecoveryRunControlStore(runEvent(AgentRunControlEventType.WAITING_FOR_DEVICE, 1))
        val workspaces = InMemoryAgentWorkspaceStore().apply { upsert(workspace().copy(status = AgentWorkspaceStatus.WAITING_RESPONSE)) }
        AgentRunRecoveryCoordinator(store, workspaces, { runningRecordedRun() }, { _, _ -> durableRegistration() }, {
            val current = workspaces.find("turn-1")!!
            workspaces.upsert(current.copy(status = AgentWorkspaceStatus.RUNNING), current.revision)
            null
        }).recover()
        assertEquals(AgentWorkspaceStatus.RUNNING, workspaces.find("turn-1")!!.status)
        assertTrue(store.appended.isEmpty())
    }

    @Test fun remoteObservationDoesNotOverwriteNewerWorkspaceProgress(): Unit = runBlocking {
        val store = RecoveryRunControlStore(runEvent(AgentRunControlEventType.RUN_STARTED, 1))
        val workspaces = InMemoryAgentWorkspaceStore().apply { upsert(workspace()) }
        AgentRunRecoveryCoordinator(store, workspaces, { runningRecordedRun() }, { _, _ -> durableRegistration() }, {
            val current = workspaces.find("turn-1")!!
            workspaces.upsert(current.copy(currentPlanSnapshot = "new local progress"), current.revision)
            RecoveryAgentAdapter(durableRegistration(), listOf(remote("waiting_input")))
        }).recover()
        assertEquals(AgentWorkspaceStatus.RUNNING, workspaces.find("turn-1")!!.status)
        assertEquals("new local progress", workspaces.find("turn-1")!!.currentPlanSnapshot)
    }

    @Test fun transportObservationsDoNotCreateDuplicateWorkspacesOnStartup() = runBlocking {
        val eventStore = RecoveryRunControlStore(runEvent(AgentRunControlEventType.RUN_STARTED, 1L)
            .copy(payload = mapOf("recovery_mode" to "observation_only")))
        val results = AgentRunRecoveryCoordinator(eventStore, InMemoryAgentWorkspaceStore(),
            recordedRun = { error("Observation recovery belongs to the parent dispatch") },
            registration = { _, _ -> error("No additional agent registration") },
            adapterResolver = { error("Never replay an observational child Run") }).recover()
        assertTrue(results.isEmpty())
        assertTrue(eventStore.appended.isEmpty())
    }

    @Test
    fun activeRunIsExcludedFromStartupRecovery() = runBlocking {
        val workspaceStore = InMemoryAgentWorkspaceStore(clock = { 2_000L })
        workspaceStore.upsert(AgentWorkspace(
            workspaceId = "turn-1",
            sessionId = "session-1",
            conversationId = "conversation-1",
            taskId = "turn-1",
            parentRunId = "run-1",
            status = AgentWorkspaceStatus.RUNNING
        ))
        val eventStore = RecoveryRunControlStore(runEvent(AgentRunControlEventType.TOOL_PROGRESS, 5L))

        val results = AgentRunRecoveryCoordinator(
            eventStore,
            workspaceStore,
            recordedRun = { runningRecordedRun() },
            registration = { _, _ -> durableRegistration() },
            adapterResolver = { null }
        ).recover(excludedRunIds = setOf("run-1"))

        assertTrue(results.isEmpty())
        assertTrue(eventStore.appended.isEmpty())
        assertEquals(AgentWorkspaceStatus.RUNNING, workspaceStore.find("turn-1")?.status)
    }

    @Test
    fun processRecreationReconnectsRemoteCursorCheckpointAndToolState() = runBlocking {
        val workspaceStore = InMemoryAgentWorkspaceStore(clock = { 2_000L })
        workspaceStore.upsert(AgentWorkspace(
            workspaceId = "turn-1",
            sessionId = "session-1",
            conversationId = "conversation-1",
            taskId = "turn-1",
            goal = "Continue a durable Codex task",
            parentRunId = "run-1",
            agentId = "codex",
            deviceId = "desktop-1",
            remoteRunId = "remote-1",
            status = AgentWorkspaceStatus.WAITING_RESPONSE,
            permissionScopes = listOf("filesystem.project.write"),
            toolCalls = listOf(AgentToolCallRecord(
                id = "shell-1",
                toolName = "shell",
                status = AgentToolCallStatus.RUNNING,
                argumentsJson = "{\"cmd\":\"gradle test\"}",
                startedAtMillis = 1_000L
            )),
            checkpoints = listOf(AgentWorkspaceCheckpoint(
                id = "before-death",
                stateJson = "{\"cursor\":7,\"permission_wait\":true}",
                createdAtMillis = 1_500L
            )),
            lastRemoteEventSequence = 7L
        ))
        val eventStore = RecoveryRunControlStore(
            event = runEvent(AgentRunControlEventType.WAITING_FOR_DEVICE, sequence = 8L)
        )
        val registration = durableRegistration()
        val remoteHandle = AgentRunHandle(
            runId = "run-1",
            taskId = "turn-1",
            agentId = "codex",
            remoteRunId = "remote-1"
        )
        val adapter = RecoveryAgentAdapter(
            registration,
            listOf(AgentRecoverableRun(
                handle = remoteHandle,
                lastEventSequence = 22L,
                observation = AgentRemoteRecoveryObservation("conversation-1", "desktop-1", "running", "remote-task-1", "remote-1", 12),
                checkpoint = mapOf(
                    "cursor" to 22,
                    "permission_wait" to true,
                    "active_tool_call_id" to "shell-1"
                )
            ))
        )
        val results = AgentRunRecoveryCoordinator(
            runStore = eventStore,
            workspaceStore = workspaceStore,
            recordedRun = { runningRecordedRun() },
            registration = { _, _ -> registration },
            adapterResolver = { adapter }
        ).recover()

        val restoredStore = InMemoryAgentWorkspaceStore(
            AgentWorkspaceJsonCodec.decodeList(workspaceStore.serializedSnapshot()),
            clock = { 3_000L }
        )
        val restored = restoredStore.find("turn-1")!!
        assertEquals(AgentRunRecoveryOutcome.RECONNECTED_REMOTE, results.single().outcome)
        assertEquals(AgentWorkspaceStatus.RUNNING, restored.status)
        assertEquals(22L, restored.lastRemoteEventSequence)
        assertEquals("remote-1", restored.remoteRunId)
        assertEquals(AgentToolCallStatus.RUNNING, restored.toolCalls.single().status)
        assertTrue(restored.checkpoints.last().stateJson.contains("active_tool_call_id"))
        assertEquals(AgentRunControlEventType.RUN_RECOVERED, eventStore.appended.single().type)
    }

    @Test
    fun unavailableRemoteIsKeptRecoverableInsteadOfBeingReplayedOrFailed() = runBlocking {
        val workspaceStore = InMemoryAgentWorkspaceStore(clock = { 2_000L })
        workspaceStore.upsert(AgentWorkspace(
            workspaceId = "turn-1",
            sessionId = "session-1",
            conversationId = "conversation-1",
            taskId = "turn-1",
            goal = "Wait for the trusted desktop",
            parentRunId = "run-1",
            agentId = "codex",
            status = AgentWorkspaceStatus.RUNNING
        ))
        val eventStore = RecoveryRunControlStore(runEvent(AgentRunControlEventType.TOOL_PROGRESS, 5L))
        val registration = durableRegistration()

        val coordinator = AgentRunRecoveryCoordinator(
            eventStore,
            workspaceStore,
            recordedRun = { runningRecordedRun() },
            registration = { _, _ -> registration },
            adapterResolver = { null }
        )

        val result = coordinator.recover().single()
        val repeated = coordinator.recover().single()

        assertEquals(AgentRunRecoveryOutcome.WAITING_FOR_REMOTE, result.outcome)
        assertEquals(AgentRunRecoveryOutcome.WAITING_FOR_REMOTE, repeated.outcome)
        assertEquals(AgentWorkspaceStatus.WAITING_RESPONSE, workspaceStore.find("turn-1")?.status)
        assertEquals(
            AgentTaskEventKinds.RECOVERY_WAITING_RESPONSE,
            workspaceStore.find("turn-1")?.eventJournal?.last()?.kind
        )
        assertEquals(
            1,
            workspaceStore.find("turn-1")?.eventJournal?.count {
                it.kind == AgentTaskEventKinds.RECOVERY_WAITING_RESPONSE
            }
        )
        assertEquals(AgentRunControlEventType.WAITING_FOR_DEVICE, eventStore.appended.single().type)
    }

    @Test
    fun localPermissionWaitRemainsWaitingAcrossRepeatedStartupRecovery() = runBlocking {
        val workspaceStore = InMemoryAgentWorkspaceStore(clock = { 2_000L })
        workspaceStore.upsert(AgentWorkspace(
            workspaceId = "turn-1",
            sessionId = "session-1",
            conversationId = "conversation-1",
            taskId = "turn-1",
            goal = "Wait for user confirmation",
            parentRunId = "run-1",
            status = AgentWorkspaceStatus.WAITING_CONFIRMATION,
            permissionScopes = listOf("contacts.write")
        ))
        val eventStore = RecoveryRunControlStore(runEvent(AgentRunControlEventType.WAITING_FOR_USER, 4L))
        val phoneRegistration = durableRegistration().copy(
            location = AgentResourceLocation.PHONE,
            connectionKind = AgentConnectionKind.IN_PROCESS
        )
        val coordinator = AgentRunRecoveryCoordinator(
            eventStore,
            workspaceStore,
            recordedRun = { runningRecordedRun() },
            registration = { _, _ -> phoneRegistration },
            adapterResolver = { error("A local wait must not reconnect or replay an Agent") }
        )

        val first = coordinator.recover().single()
        val second = coordinator.recover().single()

        assertEquals(AgentRunRecoveryOutcome.RESTORED_LOCAL_WAIT, first.outcome)
        assertEquals(AgentRunRecoveryOutcome.RESTORED_LOCAL_WAIT, second.outcome)
        assertEquals(AgentRunControlEventType.WAITING_FOR_USER, eventStore.appended.single().type)
        assertEquals(AgentWorkspaceStatus.WAITING_CONFIRMATION, workspaceStore.find("turn-1")?.status)
    }

    private fun runningRecordedRun() = AgentRecordedRun(
        runId = "run-1",
        conversationId = "conversation-1",
        taskThreadId = "turn-1",
        originalRequest = "Continue the task"
    )

    private fun durableRegistration() = AgentRegistration(
        agentId = "codex",
        installationId = "installation-1",
        deviceId = "desktop-1",
        providerId = "desktop-provider",
        displayName = "Codex",
        kind = AgentConnectorKind.AGENT,
        location = AgentResourceLocation.TRUSTED_DESKTOP,
        status = AgentEndpointStatus.BUSY,
        capabilities = setOf(AgentCapability.CODE),
        protocol = AgentProtocolRange(
            preferred = "1.0",
            minimum = "1.0",
            maximum = "1.0",
            features = setOf("run.recover")
        ),
        connectionKind = AgentConnectionKind.GALAXYSSI_LINK,
        trust = AgentResourceTrust.VERIFIED_PAIRED
    )

    private fun runEvent(type: AgentRunControlEventType, sequence: Long) = AgentRunControlEvent(
        conversationId = "conversation-1",
        messageId = "message-1",
        taskId = "turn-1",
        runId = "run-1",
        agentId = "codex",
        deviceId = "desktop-1",
        type = type,
        sequence = sequence
    )
}

private class RecoveryRunControlStore(
    private val event: AgentRunControlEvent
) : AgentRunControlStore {
    val appended = mutableListOf<AgentRunControlEvent>()

    override fun appendNext(event: AgentRunControlEvent): AgentRunControlEvent {
        val next = event.copy(sequence = this.event.sequence + appended.size + 1L)
        appended += next
        return next
    }

    override fun recoverableRuns(): List<AgentRunControlSnapshot> = listOf(
        (appended.lastOrNull() ?: event).let { latest ->
            AgentRunControlSnapshot(
                runId = latest.runId,
                taskId = latest.taskId,
                state = AgentRunEventStore.reduce(AgentRunControlState.RUNNING, latest.type),
                agentId = latest.agentId,
                deviceId = latest.deviceId,
                lastSequence = latest.sequence,
                lastEvent = latest
            )
        }
    )
}

private class RecoveryAgentAdapter(
    override val registration: AgentRegistration,
    private val recoverable: List<AgentRecoverableRun>
) : AgentAdapter {
    override suspend fun connect(): AgentProtocolAgreement = AgentProtocolAgreement("1.0", setOf("run.recover"))
    override suspend fun disconnect() = Unit
    override suspend fun status(): AgentRegistration = registration
    override suspend fun startRun(request: AgentRunRequest): AgentRunHandle = error("Recovery must not replay Run start")
    override suspend fun sendMessage(runId: String, message: AgentControlMessage) = Unit
    override suspend fun cancelRun(runId: String) = Unit
    override fun observeEvents(runId: String): Flow<AgentRunControlEvent> = emptyFlow()
    override suspend fun recoverRuns(): List<AgentRecoverableRun> = recoverable
}
