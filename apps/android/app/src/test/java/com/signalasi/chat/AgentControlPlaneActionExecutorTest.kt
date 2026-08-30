package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

class AgentControlPlaneActionExecutorTest {
    @Test
    fun phoneCloudModelApiBypassesRemoteAgentControlPlane() {
        val executions = AtomicInteger()
        val executor = AgentControlPlaneActionExecutor(
            ActionExecutorAgentProvider(
                registrationSource = { emptyList() },
                delegate = object : AgentActionExecutor {
                    override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                        executions.incrementAndGet()
                        return AgentActionResult(
                            action.id,
                            true,
                            "Waiting for DeepSeek",
                            mapOf("awaiting_response" to "true")
                        )
                    }
                }
            )
        )
        val action = connectorAction().copy(
            id = "route-deepseek",
            target = "DeepSeek",
            parameters = connectorAction().parameters + mapOf(
                "connector_id" to "deepseek",
                "connector_kind" to "model",
                "connector_adapter_type" to "cloud-model-api"
            )
        )

        val result = executor.execute(
            action,
            ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent")
        )

        assertTrue(result.success)
        assertEquals(1, executions.get())
        assertFalse(result.metadata.containsKey("control_plane_run_id"))
    }

    @Test
    fun productionConnectorActionRunsThroughAdapterOnlyOnce() {
        val executions = AtomicInteger()
        val registrationReads = AtomicInteger()
        val delegate = object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                executions.incrementAndGet()
                return AgentActionResult(
                    action.id,
                    true,
                    "Waiting",
                    mapOf("awaiting_response" to "true", "source_message_id" to "42")
                )
            }
        }
        val provider = ActionExecutorAgentProvider({
            registrationReads.incrementAndGet()
            listOf(registration())
        }, delegate)
        val executor = AgentControlPlaneActionExecutor(provider)
        val action = connectorAction()

        val first = executor.execute(action, ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent"))
        val replay = executor.execute(action, ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent"))

        assertTrue(first.success)
        assertTrue(replay.success)
        assertEquals(1, executions.get())
        assertEquals(first.metadata["control_plane_run_id"], replay.metadata["control_plane_run_id"])
        assertEquals("codex", first.metadata["control_plane_agent_id"])
        assertEquals("codex", first.metadata["control_plane_adapter_family"])
        assertEquals(1, registrationReads.get())
    }

    @Test
    fun ignoreDeliveryNeverTouchesConnectorTransport() {
        val executions = AtomicInteger()
        val delegate = object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                executions.incrementAndGet()
                return AgentActionResult(action.id, true, "unexpected")
            }
        }
        val executor = AgentControlPlaneActionExecutor(
            ActionExecutorAgentProvider({ listOf(registration()) }, delegate)
        )

        val result = executor.execute(
            connectorAction().copy(
                parameters = connectorAction().parameters + ("delivery_mode" to "ignore")
            ),
            ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent")
        )

        assertTrue(result.success)
        assertEquals("ignore", result.metadata["delivery_mode"])
        assertEquals(0, executions.get())
    }

    @Test
    fun incompatibleAgentProtocolFailsWithoutBypassingAdapter() {
        val executions = AtomicInteger()
        val delegate = object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                executions.incrementAndGet()
                return AgentActionResult(action.id, true, "unexpected")
            }
        }
        val incompatible = registration().copy(
            protocol = AgentProtocolRange("2.0", "2.0", "2.1", setOf("message.respond"))
        )
        val executor = AgentControlPlaneActionExecutor(
            ActionExecutorAgentProvider({ listOf(incompatible) }, delegate)
        )

        val result = executor.execute(
            connectorAction(),
            ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent")
        )

        assertFalse(result.success)
        assertTrue(result.message.contains("compatible", ignoreCase = true))
        assertEquals(0, executions.get())
    }

    @Test
    fun repeatedDispatchFailuresOpenOnlyTheSelectedRuntimeCircuit() {
        val executions = AtomicInteger()
        val health = InMemoryAgentProviderHealthLedger()
        val registration = registration().copy(
            adapterType = "codex-app-server-or-cli",
            runtimeFailureDomain = "desktop-installation:codex"
        )
        val provider = ActionExecutorAgentProvider(
            registrationSource = { listOf(registration) },
            delegate = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                    executions.incrementAndGet()
                    return AgentActionResult(action.id, false, "Codex execution failed")
                }
            },
            healthLedger = health
        )
        val executor = AgentControlPlaneActionExecutor(provider)
        val screen = ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent")

        repeat(3) { index ->
            val action = connectorAction().copy(
                id = "route-codex-$index",
                parameters = connectorAction().parameters + ("_signalasi_turn_id" to "turn-$index")
            )
            assertFalse(executor.execute(action, screen).success)
        }
        val blocked = executor.execute(
            connectorAction().copy(
                id = "route-codex-blocked",
                parameters = connectorAction().parameters + ("_signalasi_turn_id" to "turn-blocked")
            ),
            screen
        )

        assertFalse(blocked.success)
        assertEquals("true", blocked.metadata["provider_circuit_open"])
        assertEquals(3, executions.get())
    }

    @Test
    fun managedAsyncResponseCompletesRunAndIsInterceptedOnce() = runBlocking {
        AgentManagedConnectorResponseRegistry.clear()
        val provider = ActionExecutorAgentProvider(
            registrationSource = { listOf(registration()) },
            delegate = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext) = AgentActionResult(
                    action.id,
                    true,
                    "Waiting",
                    mapOf(
                        "awaiting_response" to "true",
                        "source_message_id" to "73",
                        "contact_id" to "codex"
                    )
                )
            }
        )
        val directory = AgentAdapterDirectory().apply { register(provider) }
        val adapter = requireNotNull(directory.resolveAdapter("codex"))
        val request = AgentRunRequest(
            conversationId = "conversation",
            messageId = "message",
            taskId = "task",
            runId = "managed-run",
            goal = "Inspect the project",
            context = mapOf("managed_team" to true),
            idempotencyKey = "managed-run"
        )
        provider.prepare(
            "codex",
            request,
            connectorAction(),
            ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent")
        )
        adapter.startRun(request)

        val response = AgentConnectorResponse(
            sourceMessageId = 73L,
            contactId = "codex",
            content = "Reviewed result",
            conversationId = request.conversationId,
            turnId = request.messageId,
            taskId = request.taskId,
            inputTokens = 10L,
            outputTokens = 4L
        )
        assertTrue(AgentManagedConnectorResponseRegistry.consume(response))
        assertFalse(AgentManagedConnectorResponseRegistry.consume(response))
        val terminal = async(start = CoroutineStart.UNDISPATCHED) {
            adapter.observeEvents(request.runId).first {
                it.type in setOf(AgentRunControlEventType.RUN_COMPLETED, AgentRunControlEventType.RUN_FAILED)
            }
        }.await()

        assertEquals(AgentRunControlEventType.RUN_COMPLETED, terminal.type)
        assertEquals("Reviewed result", terminal.payload["result"])
        assertEquals("Reviewed result", provider.result("codex", request.runId)?.message)
        assertEquals("false", provider.result("codex", request.runId)?.metadata?.get("awaiting_response"))
        AgentManagedConnectorResponseRegistry.clear()
    }

    @Test
    fun runningCodexAcceptsSupervisedFollowUpWithoutLeakingASecondReply() = runBlocking {
        AgentManagedConnectorResponseRegistry.clear()
        val actions = CopyOnWriteArrayList<AgentAction>()
        val sourceIds = AtomicInteger(80)
        val provider = ActionExecutorAgentProvider(
            registrationSource = { listOf(registration()) },
            delegate = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                    actions += action
                    val sourceId = sourceIds.incrementAndGet().toLong()
                    return AgentActionResult(
                        action.id,
                        true,
                        "Waiting",
                        mapOf(
                            "awaiting_response" to "true",
                            "source_message_id" to sourceId.toString(),
                            "contact_id" to "codex",
                            "conversation_id" to action.parameters["_signalasi_conversation_id"].orEmpty(),
                            "turn_id" to action.parameters["_signalasi_turn_id"].orEmpty(),
                            "remote_task_id" to "task-$sourceId"
                        )
                    )
                }
            }
        )
        val directory = AgentAdapterDirectory().apply { register(provider) }
        val adapter = requireNotNull(directory.resolveAdapter("codex"))
        val request = AgentRunRequest(
            conversationId = "conversation",
            messageId = "turn",
            taskId = "task",
            runId = "managed-run",
            goal = "Implement the feature",
            context = mapOf("managed_team" to true),
            idempotencyKey = "managed-run"
        )
        provider.prepare(
            "codex",
            request,
            connectorAction().copy(parameters = connectorAction().parameters + mapOf(
                "agent_instance_id" to "codex-implementer",
                MANAGED_AGENT_TEAM_ACTION_PARAMETER to "true"
            )),
            ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent")
        )
        adapter.startRun(request)

        adapter.sendMessage(
            request.runId,
            AgentControlMessage("follow-up", "user", "Keep the public API compatible")
        )

        assertEquals(2, actions.size)
        val followUp = actions.last()
        assertEquals("true", followUp.parameters["agent_team_message"])
        assertEquals("codex-implementer", followUp.parameters["agent_instance_id"])
        assertEquals("Keep the public API compatible", followUp.parameters["prompt"])
        assertTrue(AgentManagedConnectorResponseRegistry.consume(AgentConnectorResponse(
            sourceMessageId = 82L,
            contactId = "codex",
            content = "Follow-up merged",
            conversationId = "conversation",
            turnId = "follow-up",
            taskId = "task-82"
        )))
        assertFalse(AgentManagedConnectorResponseRegistry.consume(AgentConnectorResponse(
            sourceMessageId = 82L,
            contactId = "codex",
            content = "duplicate",
            conversationId = "conversation",
            turnId = "follow-up",
            taskId = "task-82"
        )))
        AgentManagedConnectorResponseRegistry.clear()
    }

    @Test
    fun warmedExecutorKeepsDirectRunBoundUntilResponse() {
        val provider = ActionExecutorAgentProvider(
            registrationSource = { listOf(registration()) },
            delegate = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext) = AgentActionResult(
                    action.id,
                    true,
                    "Waiting",
                    mapOf(
                        "awaiting_response" to "true",
                        "source_message_id" to "74",
                        "contact_id" to "codex",
                        "conversation_id" to "conversation",
                        "turn_id" to "turn",
                        "task_id" to "turn"
                    )
                )
            }
        )
        val executor = AgentControlPlaneActionExecutor(provider)
        executor.warm()
        val dispatched = executor.execute(
            connectorAction(),
            ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent")
        )

        assertTrue(dispatched.success)
        assertTrue(executor.consumeConnectorResponse(AgentConnectorResponse(
            sourceMessageId = 74L,
            contactId = "codex",
            content = "Fast result",
            conversationId = "conversation",
            turnId = "turn",
            taskId = "turn"
        )))
        assertFalse(executor.consumeConnectorResponse(AgentConnectorResponse(
            sourceMessageId = 74L,
            contactId = "codex",
            content = "Duplicate",
            conversationId = "conversation",
            turnId = "turn",
            taskId = "turn"
        )))
        val runId = requireNotNull(dispatched.metadata["control_plane_run_id"])
        assertEquals("Fast result", provider.result("codex", runId)?.message)
    }

    private fun connectorAction() = AgentAction(
        id = "route-codex",
        kind = AgentActionKind.CALL_CONNECTOR,
        target = "Codex",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.PROPOSED,
        description = "Ask Codex",
        parameters = mapOf(
            "connector_id" to "codex",
            "prompt" to "Inspect the project",
            "_signalasi_conversation_id" to "conversation",
            "_signalasi_turn_id" to "turn"
        ),
        requiresConfirmation = false
    )

    private fun registration() = AgentRegistration(
        agentId = "codex",
        installationId = "desktop-installation",
        deviceId = "desktop-device",
        providerId = "desktop-provider",
        displayName = "Codex",
        kind = AgentConnectorKind.AGENT,
        location = AgentResourceLocation.TRUSTED_DESKTOP,
        status = AgentEndpointStatus.ONLINE,
        capabilities = setOf(AgentCapability.CODE, AgentCapability.TASK_EXECUTION),
        protocol = AgentProtocolRange(
            preferred = "1.0",
            minimum = "1.0",
            maximum = "1.0",
            features = setOf("run.cancel", "run.recover", "run.events", "message.respond", "message.observe")
        ),
        connectionKind = AgentConnectionKind.SIGNALASI_LINK,
        trust = AgentResourceTrust.VERIFIED_PAIRED,
        adapterType = "codex-app-server-or-cli",
        runtimeFailureDomain = "desktop-installation:codex"
    )
}
