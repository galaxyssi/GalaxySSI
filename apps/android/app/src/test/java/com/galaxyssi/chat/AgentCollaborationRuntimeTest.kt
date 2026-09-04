package com.galaxyssi.chat

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentCollaborationRuntimeTest {
    @Test
    fun onlyQueuedOrRunningMembersInAnActiveTeamAcceptMessages() {
        fun member(status: AgentSubagentStatus) = AgentTeamMemberSnapshot(
            agentId = "codex",
            role = "reviewer",
            deliveryMode = AgentDeliveryMode.OBSERVE,
            status = status,
            instanceId = "codex-reviewer"
        )

        assertTrue(member(AgentSubagentStatus.QUEUED).canReceiveTeamMessage(AgentTeamExecutionState.RUNNING))
        assertTrue(member(AgentSubagentStatus.RUNNING).canReceiveTeamMessage(AgentTeamExecutionState.RUNNING))
        assertFalse(member(AgentSubagentStatus.SUCCEEDED).canReceiveTeamMessage(AgentTeamExecutionState.RUNNING))
        assertFalse(member(AgentSubagentStatus.FAILED).canReceiveTeamMessage(AgentTeamExecutionState.RUNNING))
        assertFalse(member(AgentSubagentStatus.RUNNING).canReceiveTeamMessage(AgentTeamExecutionState.INTERRUPTED))
        assertFalse(member(AgentSubagentStatus.RUNNING).canReceiveTeamMessage(AgentTeamExecutionState.SUCCEEDED))
    }

    @Test
    fun sameAgentProviderCanRunAsIndependentTeamInstances() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        val runtime = AgentTeamExecutionRuntime(
            store,
            AgentSubagentLimits(maxChildren = 4, maxConcurrency = 2)
        )
        val definition = AgentTeamDefinition(
            teamId = "two-codex",
            primaryAgentId = "codex",
            primaryInstanceId = "codex-implementer",
            members = listOf(
                AgentTeamMember(
                    agentId = "codex",
                    deliveryMode = AgentDeliveryMode.RESPOND,
                    role = "implementer",
                    instanceId = "codex-implementer"
                ),
                AgentTeamMember(
                    agentId = "codex",
                    deliveryMode = AgentDeliveryMode.OBSERVE,
                    role = "reviewer",
                    instanceId = "codex-reviewer"
                )
            )
        )
        val runIds = linkedMapOf<String, String>()

        val result = runtime.start(definition, request()) { context ->
            runIds[context.member.memberId] = context.request.runId
            AgentSubagentOutput(
                if (context.member.memberId == "codex-reviewer") "review evidence" else "final"
            )
        }.await()
        runtime.close()

        assertEquals(2, result.snapshot.members.size)
        assertEquals("codex-implementer", result.snapshot.primaryMemberId)
        assertEquals(
            setOf("codex-implementer", "codex-reviewer"),
            result.snapshot.members.mapTo(linkedSetOf(), AgentTeamMemberSnapshot::memberId)
        )
        assertNotEquals(runIds["codex-implementer"], runIds["codex-reviewer"])
        assertEquals("final", result.finalOutput)
    }

    @Test
    fun queuedMailboxMessageIsCompiledIntoMemberContext() = runBlocking {
        val mailbox = InMemoryAgentTeamMailbox()
        mailbox.append(AgentTeamMessageEnvelope(
            messageId = "message-1",
            teamId = "team",
            conversationId = "conversation",
            supervisorRunId = "supervisor-run",
            fromInstanceId = "user",
            toInstanceId = "primary",
            kind = AgentTeamMessageKind.USER_DIRECTIVE,
            text = "Preserve the public API"
        ))
        val runtime = AgentTeamExecutionRuntime(
            InMemoryAgentTeamExecutionStore(),
            mailbox = mailbox
        )
        var received = ""

        runtime.start(teamDefinition(), request()) { context ->
            if (context.member.memberId == "primary") {
                @Suppress("UNCHECKED_CAST")
                val messages = context.request.context["team_messages"] as List<Map<String, String>>
                received = messages.single().getValue("text")
                AgentSubagentOutput("final")
            } else {
                AgentSubagentOutput("evidence")
            }
        }.await()
        runtime.close()

        assertEquals("Preserve the public API", received)
        assertEquals(
            AgentTeamMessageState.DELIVERED,
            mailbox.messages("supervisor-run", "primary").single().state
        )
    }

    @Test
    fun backgroundTeamRunsObserversInParallelAndPublishesOnlyPrimaryOutput() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        val runtime = AgentTeamExecutionRuntime(
            store,
            AgentSubagentLimits(maxChildren = 8, maxConcurrency = 3)
        )
        val activeObservers = AtomicInteger()
        val maximumActiveObservers = AtomicInteger()
        val executed = CopyOnWriteArrayList<String>()
        val definition = teamDefinition()
        val request = request()

        val result = runtime.start(definition, request) { context ->
            executed += context.member.agentId
            if (context.member.deliveryMode == AgentDeliveryMode.OBSERVE) {
                val active = activeObservers.incrementAndGet()
                maximumActiveObservers.updateAndGet { maxOf(it, active) }
                delay(60L)
                activeObservers.decrementAndGet()
                AgentSubagentOutput("${context.member.agentId}-evidence")
            } else {
                assertEquals(2, context.handoff.dependencies.size)
                assertTrue(context.handoff.dependencies.all { it.status == AgentSubagentStatus.SUCCEEDED })
                AgentSubagentOutput(
                    "final:${context.handoff.dependencies.joinToString("|") { it.output }}"
                )
            }
        }.await()
        runtime.close()

        assertEquals(AgentTeamExecutionState.SUCCEEDED, result.snapshot.state)
        assertEquals("final:researcher-evidence|tester-evidence", result.finalOutput)
        assertEquals(2, maximumActiveObservers.get())
        assertEquals(setOf("researcher", "tester", "primary"), executed.toSet())
        assertFalse("ignored" in executed)
        assertTrue(AgentTeamProgressPolicy.project(result.snapshot, expanded = false).members.isEmpty())
        assertEquals(4, AgentTeamProgressPolicy.project(result.snapshot, expanded = true).members.size)
    }

    @Test
    fun observerFailureIsIsolatedAndPrimaryStillProducesTheSingleReply() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        val runtime = AgentTeamExecutionRuntime(store)

        val result = runtime.start(teamDefinition(), request()) { context ->
            when (context.member.agentId) {
                "researcher" -> error("Research service unavailable")
                "tester" -> AgentSubagentOutput("verified evidence")
                "primary" -> {
                    assertEquals(AgentSubagentStatus.FAILED, context.handoff.dependencies.first {
                        it.childId == "researcher"
                    }.status)
                    assertEquals("Research service unavailable", context.handoff.dependencies.first {
                        it.childId == "researcher"
                    }.errorMessage)
                    AgentSubagentOutput("final answer from remaining evidence")
                }
                else -> error("Ignored member must not execute")
            }
        }.await()
        runtime.close()

        assertEquals(AgentTeamExecutionState.COMPLETED_WITH_FAILURES, result.snapshot.state)
        assertEquals("final answer from remaining evidence", result.finalOutput)
        assertEquals(
            AgentSubagentStatus.SUCCEEDED,
            result.snapshot.members.first { it.agentId == "primary" }.status
        )
    }

    @Test
    fun memberScopedKnowledgeOverridesTheSupervisorDefault() = runBlocking {
        val runtime = AgentTeamExecutionRuntime(InMemoryAgentTeamExecutionStore())
        val definition = AgentTeamDefinition(
            teamId = "scoped-team",
            primaryAgentId = "primary",
            members = listOf(
                AgentTeamMember(
                    "primary",
                    AgentDeliveryMode.RESPOND,
                    context = mapOf("_galaxyssi_agent_knowledge_context" to "lead-only")
                ),
                AgentTeamMember(
                    "researcher",
                    AgentDeliveryMode.OBSERVE,
                    context = mapOf("_galaxyssi_agent_knowledge_context" to "research-only")
                )
            )
        )
        val observed = linkedMapOf<String, String>()

        runtime.start(
            definition,
            request().copy(context = mapOf("_galaxyssi_agent_knowledge_context" to "shared-default"))
        ) { context ->
            observed[context.member.agentId] = context.request.context[
                "_galaxyssi_agent_knowledge_context"
            ].toString()
            AgentSubagentOutput(if (context.member.agentId == "primary") "final" else "evidence")
        }.await()
        runtime.close()

        assertEquals("lead-only", observed["primary"])
        assertEquals("research-only", observed["researcher"])
    }

    @Test
    fun teamRejectsMultipleRespondersAndUnknownDependencies() {
        val store = InMemoryAgentTeamExecutionStore()
        val runtime = AgentTeamExecutionRuntime(store)
        val request = request()
        val multipleResponders = teamDefinition().copy(
            members = teamDefinition().members.map {
                if (it.agentId == "tester") it.copy(deliveryMode = AgentDeliveryMode.RESPOND) else it
            }
        )
        val unknownDependency = teamDefinition().copy(
            members = teamDefinition().members.map {
                if (it.agentId == "tester") it.copy(dependsOnAgentIds = setOf("missing")) else it
            }
        )
        val cyclicDependency = teamDefinition().copy(
            members = teamDefinition().members.map {
                if (it.agentId == "researcher") it.copy(dependsOnAgentIds = setOf("primary")) else it
            }
        )

        assertTrue(runCatching {
            runtime.start(multipleResponders, request) { AgentSubagentOutput() }
        }.exceptionOrNull() is IllegalArgumentException)
        assertTrue(runCatching {
            runtime.start(unknownDependency, request.copy(runId = "another-run")) { AgentSubagentOutput() }
        }.exceptionOrNull() is IllegalArgumentException)
        assertTrue(runCatching {
            runtime.start(cyclicDependency, request.copy(runId = "cyclic-run")) { AgentSubagentOutput() }
        }.exceptionOrNull() is IllegalArgumentException)
        assertTrue(store.snapshots().isEmpty())
        runtime.close()
    }

    @Test
    fun nonterminalDurableTeamIsMarkedInterruptedWithoutSilentReplay() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        val definition = teamDefinition()
        val request = request()
        store.create(definition, request)
        store.append(AgentSubagentEvent(
            sequence = 1L,
            supervisorId = request.runId,
            kind = AgentSubagentEventKinds.SUPERVISOR_STARTED,
            timestampMillis = 1_000L
        ))
        store.append(AgentSubagentEvent(
            sequence = 2L,
            supervisorId = request.runId,
            childId = "researcher",
            kind = AgentSubagentEventKinds.CHILD_RUNNING,
            childStatus = AgentSubagentStatus.RUNNING,
            timestampMillis = 1_100L
        ))

        val interrupted = store.markNonTerminalInterrupted(2_000L)
        store.create(definition, request)

        assertEquals(1, interrupted.size)
        assertEquals(AgentTeamExecutionState.INTERRUPTED, interrupted.single().state)
        assertEquals(2, store.records().single().events.size)
        assertEquals(2_000L, store.snapshot(request.runId)?.interruptedAtMillis)
    }

    @Test
    fun oneTeamCanBeMarkedInterruptedWithoutMutatingAnotherActiveTeam() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        val first = request().copy(runId = "first-run")
        val second = request().copy(runId = "second-run")
        store.create(teamDefinition(), first)
        store.create(teamDefinition().copy(teamId = "second-team"), second)
        listOf(first, second).forEach { request ->
            store.append(AgentSubagentEvent(
                sequence = 1L,
                supervisorId = request.runId,
                kind = AgentSubagentEventKinds.SUPERVISOR_STARTED,
                timestampMillis = 1_000L
            ))
        }

        val interrupted = store.markInterrupted(first.runId, 2_000L)

        assertEquals(AgentTeamExecutionState.INTERRUPTED, interrupted?.state)
        assertEquals(AgentTeamExecutionState.RUNNING, store.snapshot(second.runId)?.state)
        assertEquals(0L, store.snapshot(second.runId)?.interruptedAtMillis)
        assertNull(store.markInterrupted("missing-run", 2_000L))
    }

    @Test
    fun lateManagedResponsesCompleteInterruptedTeamExactlyOnce() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        val definition = AgentTeamDefinition(
            teamId = "late-team",
            primaryAgentId = "primary",
            members = listOf(
                AgentTeamMember("primary", AgentDeliveryMode.RESPOND, role = "writer"),
                AgentTeamMember("observer", AgentDeliveryMode.OBSERVE, role = "reviewer")
            )
        )
        val request = request()
        store.create(definition, request)
        store.append(AgentSubagentEvent(
            sequence = 1L,
            supervisorId = request.runId,
            kind = AgentSubagentEventKinds.SUPERVISOR_STARTED,
            timestampMillis = 1_000L
        ))
        store.append(AgentSubagentEvent(
            sequence = 2L,
            supervisorId = request.runId,
            childId = "observer",
            kind = AgentSubagentEventKinds.CHILD_RUNNING,
            childStatus = AgentSubagentStatus.RUNNING,
            timestampMillis = 1_100L
        ))
        store.append(AgentSubagentEvent(
            sequence = 3L,
            supervisorId = request.runId,
            childId = "primary",
            kind = AgentSubagentEventKinds.CHILD_RUNNING,
            childStatus = AgentSubagentStatus.RUNNING,
            timestampMillis = 1_200L
        ))
        store.markNonTerminalInterrupted(1_300L)

        val observer = managedResponse(
            ownerRunId = "observer-run",
            agentId = "observer",
            sourceMessageId = 71L,
            content = "verified evidence"
        )
        val primary = managedResponse(
            ownerRunId = "primary-run",
            agentId = "primary",
            sourceMessageId = 72L,
            content = "final reviewed answer"
        )

        assertTrue(store.applyLateResponse(observer))
        assertEquals(AgentTeamExecutionState.INTERRUPTED, store.snapshot(request.runId)?.state)
        assertTrue(store.applyLateResponse(primary))
        val completed = requireNotNull(store.snapshot(request.runId))
        val eventCount = store.records().single().events.size
        assertEquals(AgentTeamExecutionState.SUCCEEDED, completed.state)
        assertEquals("final reviewed answer", completed.finalOutput)
        assertEquals(AgentSubagentStatus.SUCCEEDED, completed.members.first {
            it.agentId == "observer"
        }.status)

        assertTrue(store.applyLateResponse(primary))
        assertEquals(eventCount, store.records().single().events.size)
        assertEquals(AgentTeamExecutionState.SUCCEEDED, store.snapshot(request.runId)?.state)
    }

    @Test
    fun lateResponsesUseInstanceIdsWhenSameProviderHasMultipleMembers() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        val request = request()
        val definition = AgentTeamDefinition(
            teamId = "two-codex-late",
            primaryAgentId = "codex",
            primaryInstanceId = "codex-primary",
            members = listOf(
                AgentTeamMember(
                    "codex",
                    AgentDeliveryMode.RESPOND,
                    role = "writer",
                    instanceId = "codex-primary"
                ),
                AgentTeamMember(
                    "codex",
                    AgentDeliveryMode.OBSERVE,
                    role = "reviewer",
                    instanceId = "codex-reviewer"
                )
            )
        )
        store.create(definition, request)
        store.append(AgentSubagentEvent(
            sequence = 1L,
            supervisorId = request.runId,
            kind = AgentSubagentEventKinds.SUPERVISOR_STARTED,
            timestampMillis = 1_000L
        ))
        listOf("codex-reviewer", "codex-primary").forEachIndexed { index, instanceId ->
            store.append(AgentSubagentEvent(
                sequence = index + 2L,
                supervisorId = request.runId,
                childId = instanceId,
                kind = AgentSubagentEventKinds.CHILD_RUNNING,
                childStatus = AgentSubagentStatus.RUNNING,
                timestampMillis = 1_100L + index
            ))
        }
        store.markNonTerminalInterrupted(1_300L)

        fun response(instanceId: String, success: Boolean, sourceId: Long) =
            AgentManagedResponseRecord(
                ownerRunId = stableAgentTeamMemberRunId(request.runId, instanceId),
                supervisorRunId = request.runId,
                agentId = "codex",
                deliveryMode = if (instanceId == "codex-primary") {
                    AgentDeliveryMode.RESPOND
                } else AgentDeliveryMode.OBSERVE,
                sourceMessageId = sourceId,
                contactId = "codex",
                state = AgentManagedResponseState.COMPLETED,
                response = AgentConnectorResponse(
                    sourceMessageId = sourceId,
                    contactId = "codex",
                    content = if (success) "final" else "review failed",
                    success = success,
                    receivedAtMillis = 2_000L + sourceId
                ),
                createdAtMillis = 1_000L,
                completedAtMillis = 2_000L + sourceId
            )

        assertTrue(store.applyLateResponse(response("codex-reviewer", false, 81L)))
        assertTrue(store.applyLateResponse(response("codex-primary", true, 82L)))

        val completed = requireNotNull(store.snapshot(request.runId))
        assertEquals(AgentTeamExecutionState.COMPLETED_WITH_FAILURES, completed.state)
        assertEquals(AgentSubagentStatus.FAILED, completed.members.first {
            it.memberId == "codex-reviewer"
        }.status)
        assertEquals("final", completed.finalOutput)
    }

    @Test
    fun managedResponseLedgerCorrelatesAndReleasesLateReply() {
        val ledger = InMemoryAgentManagedResponseLedger()
        val record = AgentManagedResponseRecord(
            ownerRunId = "child-run",
            supervisorRunId = "supervisor-run",
            agentId = "primary",
            deliveryMode = AgentDeliveryMode.RESPOND,
            sourceMessageId = 91L,
            contactId = "primary",
            createdAtMillis = 1_000L
        )
        ledger.register(record)

        assertNull(ledger.complete(AgentConnectorResponse(92L, "primary", "wrong source")))
        val completed = ledger.complete(AgentConnectorResponse(
            sourceMessageId = 91L,
            contactId = "primary",
            content = "late answer",
            receivedAtMillis = 2_000L
        ))

        assertEquals("child-run", completed?.ownerRunId)
        assertEquals("late answer", ledger.completedUnapplied().single().response?.content)
        ledger.markApplied("child-run")
        assertTrue(ledger.completedUnapplied().isEmpty())
        assertEquals(
            AgentManagedResponseState.APPLIED,
            ledger.complete(AgentConnectorResponse(91L, "primary", "duplicate"))?.state
        )
        ledger.removeOwner("child-run")
        assertTrue(ledger.completedUnapplied().isEmpty())
    }

    @Test
    fun managedResponseLedgerDoesNotCaptureReusedMessageIdFromAnotherTurn() {
        val ledger = InMemoryAgentManagedResponseLedger()
        ledger.register(AgentManagedResponseRecord(
            ownerRunId = "managed-child",
            supervisorRunId = "managed-parent",
            agentId = "deepseek",
            deliveryMode = AgentDeliveryMode.RESPOND,
            sourceMessageId = 44L,
            contactId = "cloud:deepseek",
            conversationId = "managed-conversation",
            turnId = "managed-turn",
            taskId = "managed-task"
        ))

        assertNull(ledger.complete(AgentConnectorResponse(
            sourceMessageId = 44L,
            contactId = "cloud:deepseek",
            content = "foreground failure",
            conversationId = "foreground-conversation",
            turnId = "foreground-turn",
            taskId = "foreground-turn",
            success = false
        )))
        assertNotNull(ledger.complete(AgentConnectorResponse(
            sourceMessageId = 44L,
            contactId = "cloud:deepseek",
            content = "managed result",
            conversationId = "managed-conversation",
            turnId = "managed-turn",
            taskId = "managed-task"
        )))
    }

    @Test
    fun managedResponseRegistryKeepsInterceptorWhenTurnIdentityDoesNotMatch() {
        AgentManagedConnectorResponseRegistry.clear()
        val consumed = AtomicInteger()
        try {
            AgentManagedConnectorResponseRegistry.register(
                sourceMessageId = 44L,
                contactId = "cloud:deepseek",
                ownerId = "managed-child",
                conversationId = "managed-conversation",
                turnId = "managed-turn",
                taskId = "managed-task"
            ) {
                consumed.incrementAndGet()
                true
            }

            assertFalse(AgentManagedConnectorResponseRegistry.consume(AgentConnectorResponse(
                sourceMessageId = 44L,
                contactId = "cloud:deepseek",
                content = "foreground failure",
                conversationId = "foreground-conversation",
                turnId = "foreground-turn",
                taskId = "foreground-turn",
                success = false
            )))
            assertTrue(AgentManagedConnectorResponseRegistry.consume(AgentConnectorResponse(
                sourceMessageId = 44L,
                contactId = "cloud:deepseek",
                content = "managed result",
                conversationId = "managed-conversation",
                turnId = "managed-turn",
                taskId = "managed-task"
            )))
            assertEquals(1, consumed.get())
        } finally {
            AgentManagedConnectorResponseRegistry.clear()
        }
    }

    @Test
    fun managedResponseRegistryRecognizesForegroundReplyThroughContactAlias() {
        AgentManagedConnectorResponseRegistry.clear()
        try {
            AgentManagedConnectorResponseRegistry.register(
                sourceMessageId = 45L,
                contactId = "desktop:codex",
                ownerId = "managed-child",
                conversationId = "managed-conversation",
                turnId = "managed-turn",
                taskId = "managed-task"
            ) { true }
            val response = AgentConnectorResponse(
                sourceMessageId = 45L,
                contactId = "desktop",
                content = "managed result",
                conversationId = "managed-conversation",
                turnId = "managed-turn",
                taskId = "managed-task"
            )

            assertTrue(AgentManagedConnectorResponseRegistry.contains(response))
            assertTrue(AgentManagedConnectorResponseRegistry.consume(response))
            assertFalse(AgentManagedConnectorResponseRegistry.contains(response))
        } finally {
            AgentManagedConnectorResponseRegistry.clear()
        }
    }

    @Test
    fun adapterWorkerUsesStableChildRunsAndStructuredDependencyContext() = runBlocking {
        val primary = EventAgentAdapter("primary", setOf(AgentCapability.CODE))
        val observer = EventAgentAdapter("observer", setOf(AgentCapability.RESEARCH))
        val directory = AgentAdapterDirectory().apply {
            register(primary)
            register(observer)
        }
        val store = InMemoryAgentTeamExecutionStore()
        val runtime = AgentTeamExecutionRuntime(store)
        val definition = AgentTeamDefinition(
            teamId = "adapter-team",
            primaryAgentId = "primary",
            members = listOf(
                AgentTeamMember("primary", AgentDeliveryMode.RESPOND, setOf(AgentCapability.CODE)),
                AgentTeamMember("observer", AgentDeliveryMode.OBSERVE, setOf(AgentCapability.RESEARCH))
            )
        )

        val result = runtime.start(
            definition,
            request().copy(requiredCapabilities = setOf(AgentCapability.CODE)),
            AgentAdapterTeamMemberWorker(directory, livenessProbeMillis = 5_000L)
        ).await()
        runtime.close()

        assertEquals("primary-result", result.finalOutput)
        assertEquals(setOf(AgentCapability.RESEARCH), observer.requests.single().requiredCapabilities)
        assertEquals(setOf(AgentCapability.CODE), primary.requests.single().requiredCapabilities)
        assertNotEquals(primary.requests.single().runId, observer.requests.single().runId)
        val dependencies = primary.requests.single().context["team_dependencies"] as List<*>
        assertEquals(1, dependencies.size)
    }

    @Test
    fun adapterWorkerProbesLivenessWithoutCancellingAHealthyLongRun() = runBlocking {
        val adapter = DelayedTerminalAgentAdapter(
            delayMillis = 0L,
            recoveryCallsBeforeCompletion = 2
        )
        val request = request().copy(runId = "long-running-member")
        val output = withTimeout(5_000L) {
            AgentAdapterTeamMemberWorker(
                AgentAdapterDirectory().apply { register(adapter) },
                livenessProbeMillis = 20L
            ).execute(
                AgentTeamMemberExecutionContext(
                    member = AgentTeamMember(
                        agentId = adapter.registration.agentId,
                        deliveryMode = AgentDeliveryMode.RESPOND,
                        requiredCapabilities = adapter.registration.capabilities
                    ),
                    request = request,
                    handoff = AgentSubagentContextHandoff("", emptyList(), 0, 0, false),
                    depth = 0,
                    provenance = AgentSubagentProvenance()
                )
            )
        }

        assertEquals("completed after liveness checks", output.content)
        assertTrue(adapter.statusCalls.get() >= 3)
        assertTrue(adapter.recoveryCalls.get() >= 2)
        assertEquals(0, adapter.cancelCalls.get())
    }

    @Test
    fun adapterWorkerKeepsTwoCodexInstancesInIndependentRuns() = runBlocking {
        val codex = EventAgentAdapter(
            "codex",
            setOf(AgentCapability.CODE, AgentCapability.REASONING),
            maxParallelRuns = 2
        )
        val runtime = AgentTeamExecutionRuntime(
            InMemoryAgentTeamExecutionStore(),
            AgentSubagentLimits(maxChildren = 4, maxConcurrency = 2)
        )
        val definition = AgentTeamDefinition(
            teamId = "adapter-two-codex",
            primaryAgentId = "codex",
            primaryInstanceId = "codex-implementer",
            members = listOf(
                AgentTeamMember(
                    "codex",
                    AgentDeliveryMode.RESPOND,
                    setOf(AgentCapability.CODE),
                    role = "implementer",
                    instanceId = "codex-implementer"
                ),
                AgentTeamMember(
                    "codex",
                    AgentDeliveryMode.OBSERVE,
                    setOf(AgentCapability.REASONING),
                    role = "reviewer",
                    instanceId = "codex-reviewer"
                )
            )
        )

        val result = runtime.start(
            definition,
            request(),
            AgentAdapterTeamMemberWorker(
                AgentAdapterDirectory().apply { register(codex) },
                livenessProbeMillis = 5_000L
            )
        ).await()
        runtime.close()

        assertEquals("codex-result", result.finalOutput)
        assertEquals(2, codex.requests.size)
        assertEquals(2, codex.requests.map(AgentRunRequest::runId).distinct().size)
        assertEquals(
            setOf("codex-implementer", "codex-reviewer"),
            codex.requests.mapTo(linkedSetOf()) { it.context["agent_instance_id"] }
        )
        val primary = codex.requests.single {
            it.context["agent_instance_id"] == "codex-implementer"
        }
        @Suppress("UNCHECKED_CAST")
        val dependencies = primary.context["team_dependencies"] as List<Map<String, Any?>>
        assertEquals("codex-reviewer", dependencies.single()["agent_id"])
    }

    @Test
    fun adapterWorkerExecutesCodexClaudeAndDeepSeekAsOneTeam() = runBlocking {
        val codex = EventAgentAdapter("codex", setOf(AgentCapability.CODE, AgentCapability.REASONING))
        val claude = EventAgentAdapter("claude", setOf(AgentCapability.RESEARCH))
        val deepSeek = EventAgentAdapter(
            "deepseek-v4",
            setOf(AgentCapability.REASONING),
            kind = AgentConnectorKind.MODEL
        )
        val directory = AgentAdapterDirectory().apply {
            register(codex)
            register(claude)
            register(deepSeek)
        }
        val runtime = AgentTeamExecutionRuntime(
            InMemoryAgentTeamExecutionStore(),
            AgentSubagentLimits(maxChildren = 6, maxConcurrency = 3)
        )
        val definition = AgentTeamDefinition(
            teamId = "mixed-team",
            primaryAgentId = "codex",
            primaryInstanceId = "codex-lead",
            members = listOf(
                AgentTeamMember(
                    "codex",
                    AgentDeliveryMode.RESPOND,
                    role = "lead",
                    instanceId = "codex-lead"
                ),
                AgentTeamMember(
                    "claude",
                    AgentDeliveryMode.OBSERVE,
                    role = "researcher",
                    instanceId = "claude-researcher"
                ),
                AgentTeamMember(
                    "deepseek-v4",
                    AgentDeliveryMode.OBSERVE,
                    role = "reviewer",
                    instanceId = "deepseek-reviewer"
                )
            )
        )

        val result = runtime.start(
            definition,
            request(),
            AgentAdapterTeamMemberWorker(directory, livenessProbeMillis = 5_000L)
        ).await()
        runtime.close()

        assertEquals("codex-result", result.finalOutput)
        assertEquals("codex-lead", codex.requests.single().context["agent_instance_id"])
        assertEquals("claude-researcher", claude.requests.single().context["agent_instance_id"])
        assertEquals("deepseek-reviewer", deepSeek.requests.single().context["agent_instance_id"])
        @Suppress("UNCHECKED_CAST")
        val dependencies = codex.requests.single().context["team_dependencies"] as List<Map<String, Any?>>
        assertEquals(
            setOf("claude-researcher", "deepseek-reviewer"),
            dependencies.mapTo(linkedSetOf()) { it["agent_id"] }
        )
        assertEquals(1, result.snapshot.members.count {
            it.deliveryMode == AgentDeliveryMode.RESPOND
        })
    }

    @Test
    fun productionActionBridgeExecutesObserversInternallyBeforePrimaryResponse() = runBlocking {
        AgentManagedConnectorResponseRegistry.clear()
        val actions = CopyOnWriteArrayList<AgentAction>()
        val managedResponses = InMemoryAgentManagedResponseLedger()
        val registrations = listOf(
            registration("primary", AgentCapability.CODE),
            registration("observer", AgentCapability.RESEARCH)
        )
        val provider = ActionExecutorAgentProvider(
            registrationSource = { registrations },
            managedResponses = managedResponses,
            delegate = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                    actions += action
                    val connectorId = action.parameters["connector_id"].orEmpty()
                    val sourceMessageId = if (connectorId == "observer") 81L else 82L
                    thread(name = "managed-response-$connectorId") {
                        val response = AgentConnectorResponse(
                            sourceMessageId = sourceMessageId,
                            contactId = connectorId,
                            content = if (connectorId == "observer") "verified evidence" else "reviewed final answer",
                            conversationId = action.parameters["_galaxyssi_conversation_id"].orEmpty(),
                            turnId = action.parameters["_galaxyssi_turn_id"].orEmpty(),
                            taskId = action.parameters["_galaxyssi_task_id"].orEmpty()
                        )
                        repeat(100) {
                            if (AgentManagedConnectorResponseRegistry.consume(response)) return@thread
                            Thread.sleep(5L)
                        }
                    }
                    return AgentActionResult(
                        action.id,
                        true,
                        "Waiting",
                        mapOf(
                            "awaiting_response" to "true",
                            "source_message_id" to sourceMessageId.toString(),
                            "contact_id" to connectorId
                        )
                    )
                }
            }
        )
        val directory = AgentAdapterDirectory().apply { register(provider) }
        val runtime = AgentTeamExecutionRuntime(InMemoryAgentTeamExecutionStore())
        val worker = ActionExecutorAgentTeamMemberWorker(
            provider = provider,
            directory = directory,
            screenProvider = { ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent") },
            livenessProbeMillis = 5_000L
        )
        val definition = AgentTeamDefinition(
            teamId = "production-team",
            primaryAgentId = "primary",
            members = listOf(
                AgentTeamMember("primary", AgentDeliveryMode.RESPOND, setOf(AgentCapability.CODE)),
                AgentTeamMember("observer", AgentDeliveryMode.OBSERVE, setOf(AgentCapability.RESEARCH))
            )
        )

        val policyPrompt = "Research and compare two primary sources"
        val result = runtime.start(
            definition,
            request(mapOf(EXECUTION_POLICY_PROMPT_ACTION_PARAMETER to policyPrompt)),
            worker
        ).await()
        runtime.close()

        assertEquals("reviewed final answer", result.finalOutput)
        assertEquals(2, actions.size)
        val observerAction = actions.first { it.parameters["connector_id"] == "observer" }
        val primaryAction = actions.first { it.parameters["connector_id"] == "primary" }
        assertEquals("respond", observerAction.parameters["delivery_mode"])
        assertEquals(policyPrompt, observerAction.parameters[EXECUTION_POLICY_PROMPT_ACTION_PARAMETER])
        assertEquals(policyPrompt, primaryAction.parameters[EXECUTION_POLICY_PROMPT_ACTION_PARAMETER])
        assertTrue(primaryAction.parameters["prompt"].orEmpty().contains("verified evidence"))
        assertTrue(primaryAction.parameters["prompt"].orEmpty().contains(
            "selected specialist Agents have already completed"
        ))
        assertTrue(primaryAction.parameters["prompt"].orEmpty().contains("do not claim they are unavailable"))
        val duplicateResponse = AgentConnectorResponse(
            sourceMessageId = 82L,
            contactId = "primary",
            content = "duplicate",
            conversationId = primaryAction.parameters["_galaxyssi_conversation_id"].orEmpty(),
            turnId = primaryAction.parameters["_galaxyssi_turn_id"].orEmpty(),
            taskId = primaryAction.parameters["_galaxyssi_task_id"].orEmpty()
        )
        assertFalse(AgentManagedConnectorResponseRegistry.consume(duplicateResponse))
        val duplicate = managedResponses.complete(duplicateResponse)
        assertNotNull(duplicate)
        assertEquals(AgentManagedResponseState.APPLIED, duplicate?.state)
        AgentManagedConnectorResponseRegistry.clear()
    }

    private fun managedResponse(
        ownerRunId: String,
        agentId: String,
        sourceMessageId: Long,
        content: String
    ) = AgentManagedResponseRecord(
        ownerRunId = ownerRunId,
        supervisorRunId = "supervisor-run",
        agentId = agentId,
        deliveryMode = if (agentId == "primary") AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
        sourceMessageId = sourceMessageId,
        contactId = agentId,
        state = AgentManagedResponseState.COMPLETED,
        response = AgentConnectorResponse(
            sourceMessageId = sourceMessageId,
            contactId = agentId,
            content = content,
            receivedAtMillis = 2_000L + sourceMessageId
        ),
        createdAtMillis = 1_000L,
        completedAtMillis = 2_000L + sourceMessageId
    )

    private fun teamDefinition() = AgentTeamDefinition(
        teamId = "team",
        primaryAgentId = "primary",
        members = listOf(
            AgentTeamMember("primary", AgentDeliveryMode.RESPOND, role = "architect"),
            AgentTeamMember("researcher", AgentDeliveryMode.OBSERVE, role = "research"),
            AgentTeamMember("tester", AgentDeliveryMode.OBSERVE, role = "verification"),
            AgentTeamMember("ignored", AgentDeliveryMode.IGNORE, role = "unused")
        ),
        visibilityMode = AgentTeamVisibilityMode.BACKGROUND
    )

    private fun request(context: Map<String, Any?> = emptyMap()) = AgentRunRequest(
        conversationId = "conversation",
        messageId = "message",
        taskId = "task",
        runId = "supervisor-run",
        goal = "Produce one reviewed answer",
        idempotencyKey = "team-task",
        context = context
    )

    private fun registration(agentId: String, capability: AgentCapability) = AgentRegistration(
        agentId = agentId,
        installationId = "$agentId-installation",
        deviceId = "desktop-device",
        providerId = "galaxyssi-connectors",
        displayName = agentId,
        kind = AgentConnectorKind.AGENT,
        location = AgentResourceLocation.TRUSTED_DESKTOP,
        status = AgentEndpointStatus.ONLINE,
        capabilities = setOf(capability),
        protocol = AgentProtocolRange(
            preferred = "1.0",
            minimum = "1.0",
            maximum = "1.0",
            features = setOf("run.cancel", "run.recover", "run.events", "message.respond", "message.observe")
        ),
        connectionKind = AgentConnectionKind.GALAXYSSI_LINK,
        trust = AgentResourceTrust.VERIFIED_PAIRED,
        adapterType = agentId
    )
}

private class EventAgentAdapter(
    agentId: String,
    capabilities: Set<AgentCapability>,
    kind: AgentConnectorKind = AgentConnectorKind.AGENT,
    maxParallelRuns: Int = 1
) : AgentAdapter {
    override val registration = AgentRegistration(
        agentId = agentId,
        installationId = "$agentId-installation",
        deviceId = "device",
        providerId = "test",
        displayName = agentId,
        kind = kind,
        location = AgentResourceLocation.PHONE,
        status = AgentEndpointStatus.ONLINE,
        capabilities = capabilities,
        protocol = AgentProtocolRange("1.0", "1.0", "1.0", setOf("run.events")),
        connectionKind = AgentConnectionKind.IN_PROCESS,
        trust = AgentResourceTrust.PHONE_SYSTEM,
        maxParallelRuns = maxParallelRuns
    )
    val requests = CopyOnWriteArrayList<AgentRunRequest>()
    private val events = mutableMapOf<String, MutableSharedFlow<AgentRunControlEvent>>()

    override suspend fun connect() = AgentProtocolAgreement("1.0", setOf("run.events"))
    override suspend fun disconnect() = Unit
    override suspend fun status() = registration
    override suspend fun startRun(request: AgentRunRequest): AgentRunHandle {
        requests += request
        events.getOrPut(request.runId) { MutableSharedFlow(extraBufferCapacity = 4) }.emit(
            AgentRunControlEvent(
                conversationId = request.conversationId,
                messageId = request.messageId,
                taskId = request.taskId,
                runId = request.runId,
                agentId = registration.agentId,
                deviceId = registration.deviceId,
                type = AgentRunControlEventType.RUN_COMPLETED,
                sequence = 1L,
                payload = mapOf("result" to "${registration.agentId}-result")
            )
        )
        return AgentRunHandle(request.runId, request.taskId, registration.agentId)
    }
    override suspend fun sendMessage(runId: String, message: AgentControlMessage) = Unit
    override suspend fun cancelRun(runId: String) = Unit
    override fun observeEvents(runId: String): Flow<AgentRunControlEvent> =
        events.getOrPut(runId) { MutableSharedFlow(extraBufferCapacity = 4) }
    override suspend fun recoverRuns(): List<AgentRecoverableRun> = emptyList()
}

private class DelayedTerminalAgentAdapter(
    private val delayMillis: Long,
    private val recoveryCallsBeforeCompletion: Int = 0
) : AgentAdapter {
    override val registration = AgentRegistration(
        agentId = "slow-agent",
        installationId = "slow-agent-installation",
        deviceId = "device",
        providerId = "test",
        displayName = "slow-agent",
        kind = AgentConnectorKind.AGENT,
        location = AgentResourceLocation.PHONE,
        status = AgentEndpointStatus.ONLINE,
        capabilities = setOf(AgentCapability.REASONING),
        protocol = AgentProtocolRange("1.0", "1.0", "1.0", setOf("run.events", "run.recover")),
        connectionKind = AgentConnectionKind.IN_PROCESS,
        trust = AgentResourceTrust.PHONE_SYSTEM
    )
    val statusCalls = AtomicInteger()
    val recoveryCalls = AtomicInteger()
    val cancelCalls = AtomicInteger()

    override suspend fun connect() = AgentProtocolAgreement("1.0", setOf("run.events", "run.recover"))
    override suspend fun disconnect() = Unit
    override suspend fun status(): AgentRegistration = registration.also { statusCalls.incrementAndGet() }
    override suspend fun startRun(request: AgentRunRequest) =
        AgentRunHandle(request.runId, request.taskId, registration.agentId)
    override suspend fun sendMessage(runId: String, message: AgentControlMessage) = Unit
    override suspend fun cancelRun(runId: String) {
        cancelCalls.incrementAndGet()
    }
    override fun observeEvents(runId: String): Flow<AgentRunControlEvent> = flow {
        delay(delayMillis)
        while (recoveryCalls.get() < recoveryCallsBeforeCompletion) delay(1L)
        emit(
            AgentRunControlEvent(
                conversationId = "conversation",
                messageId = "message",
                taskId = "task",
                runId = runId,
                agentId = registration.agentId,
                deviceId = registration.deviceId,
                type = AgentRunControlEventType.RUN_COMPLETED,
                sequence = 1L,
                payload = mapOf("result" to "completed after liveness checks")
            )
        )
    }
    override suspend fun recoverRuns(): List<AgentRecoverableRun> {
        recoveryCalls.incrementAndGet()
        return emptyList()
    }
}
