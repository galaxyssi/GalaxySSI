package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

/** Deterministic framework tests; scripted decisions are not real-provider intelligence evidence. */
class AgentProblemSolvingLoopTest {
    private val request = AgentModelToolLoopRequest.forUserMessage("session", "conversation", "turn", "task",
        "workspace", "Complete the requested task", budget = AgentModelToolLoopBudget(
            maxRetriesPerCall = 0, enforceCountLimits = false)).copy(loopId = "problem-solving")

    @Test fun nonRetryableFailureReturnsToModelAndCanBeDiagnosedRepairedAndVerified() = runBlocking {
        var installed = false
        val operations = mutableListOf<String>()
        val registry = registry { operation ->
            operations += operation
            when (operation) {
                "build" -> if (installed) AgentNativeToolExecutionResult.success(mapOf("exit_code" to 0))
                    else AgentNativeToolExecutionResult.failure("dependency_missing", "Required compiler is absent",
                        details = mapOf("non_retriable" to true))
                "inspect" -> AgentNativeToolExecutionResult.success(mapOf("compiler_installed" to installed))
                "install" -> { installed = true; AgentNativeToolExecutionResult.success(mapOf("installed" to true)) }
                else -> error("Unexpected operation")
            }
        }
        val outcome = AgentModelToolLoop(AgentModelAdapter { input ->
            when (input.round) {
                1 -> action("build-1", "build")
                2 -> {
                    assertEquals("dependency_missing", input.messages.last().toolResult?.error?.code)
                    action("inspect-1", "inspect")
                }
                3 -> action("install-1", "install")
                4 -> action("build-2", "build")
                else -> {
                    assertEquals(0, input.messages.last().toolResult?.output?.get("exit_code"))
                    AgentModelResponse("The original build now passes.")
                }
            }
        }, registry).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(listOf("build", "inspect", "install", "build"), operations)
        assertEquals(5, outcome.usage.rounds)
    }

    @Test fun repeatedMutationRejectionsDoNotCountAsNewExternalEvidenceOrEndTheGoal() = runBlocking {
        val operations = mutableListOf<String>()
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            when (it.round) {
                1, 2, 3 -> action("submit-${it.round}", "submit")
                4 -> {
                    assertEquals("repeated_tool_call", it.messages.last().toolResult?.error?.code)
                    action("inspect", "inspect")
                }
                else -> AgentModelResponse("The submission was already saved; verification is complete.")
            }
        }, registry { operations += it; AgentNativeToolExecutionResult.success() }).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(listOf("submit", "inspect"), operations)
        assertEquals(2, outcome.messages.count { it.toolResult?.error?.code == "repeated_tool_call" })
        assertTrue(outcome.messages.filter { it.toolResult?.error?.code == "repeated_tool_call" }
            .all { it.toolResult!!.error!!.details["executed"] == false })
    }

    @Test fun readOnlyPollingMayObserveTheSamePageUntilItChangesWithoutLifetimeCutoff() = runBlocking {
        var reads = 0
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            if (it.round <= 12) action("read-${it.round}", "read")
            else {
                assertEquals("ready", it.messages.last().toolResult?.output?.get("state"))
                AgentModelResponse("The operation is ready.")
            }
        }, registry(readOnly = true) {
            reads++
            AgentNativeToolExecutionResult.success(mapOf("state" to if (reads < 12) "loading" else "ready"))
        }).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(12, reads)
        assertTrue(outcome.events.none { it.type == AgentModelToolLoopEventType.LOOP_DETECTED })
    }

    @Test fun websiteFlowCanRecoverExpiredLoginAndStaleControlsBeforeExtractingInformation() = runBlocking {
        var loggedIn = false
        var revision = 1
        val registry = registry { operation ->
            when (operation) {
                "open-private-page" -> AgentNativeToolExecutionResult.failure("login_expired", "The sign-in page is visible")
                "inspect-login" -> AgentNativeToolExecutionResult.success(mapOf("revision" to revision, "form" to "login"))
                "stale-submit" -> { revision++; PhoneUiOperationResult.stale(1, "revision-$revision") }
                "inspect-current" -> AgentNativeToolExecutionResult.success(mapOf("revision" to revision, "form" to "login"))
                "submit-current" -> { loggedIn = true; PhoneUiOperationResult.from(mapOf("accepted" to true), "rejected", "Rejected") }
                "read-orders" -> {
                    check(loggedIn)
                    AgentNativeToolExecutionResult.success(mapOf("items" to listOf("order-1"), "next_page" to 2))
                }
                "read-page-2" -> AgentNativeToolExecutionResult.success(mapOf("items" to listOf("order-2"), "next_page" to null))
                else -> error("Unexpected browser operation")
            }
        }
        val operations = listOf("open-private-page", "inspect-login", "stale-submit", "inspect-current",
            "submit-current", "read-orders", "read-page-2")
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            if (it.round <= operations.size) action("web-${it.round}", operations[it.round - 1])
            else {
                assertNull(it.messages.last().toolResult?.output?.get("next_page"))
                AgentModelResponse("Both orders were read from the signed-in account.")
            }
        }, registry).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        val results = outcome.messages.mapNotNull { it.toolResult }
        assertEquals(listOf("login_expired", "ui_observation_stale"), results.mapNotNull { it.error?.code })
        assertEquals(false, results[4].output["business_success_verified"])
        assertEquals(2, results.count { it.output.containsKey("items") })
    }

    @Test fun serialAutomaticRetryKeepsTheOriginalFailureInTheModelObservation() = runBlocking {
        var attempts = 0
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            if (it.round == 1) action("read", "read") else {
                val observed = it.messages.last().toolResult!!
                val prior = observed.toModelJsonValue()["recovery_attempts"] as List<*>
                assertEquals("temporary", ((prior.single() as Map<*, *>)["error"] as Map<*, *>)["code"])
                AgentModelResponse("Read succeeded after the transient error.")
            }
        }, registry(readOnly = true) {
            if (++attempts == 1) AgentNativeToolExecutionResult.failure("temporary", "Network unavailable", true)
            else AgentNativeToolExecutionResult.success(mapOf("content" to "read"))
        }).run(request.copy(budget = request.budget.copy(maxRetriesPerCall = 1)))
        assertEquals(2, attempts)
        assertEquals(1, outcome.usage.retries)
    }

    @Test fun parallelAutomaticRetryPreservesFailureAndOtherBranchResults() = runBlocking {
        val attempts = java.util.concurrent.ConcurrentHashMap<String, Int>()
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            if (it.round == 1) AgentModelResponse(toolCalls = listOf(call("a", "a"), call("b", "b"))) else {
                val results = it.messages.mapNotNull { message -> message.toolResult }
                assertEquals(2, results.size)
                assertNotNull(results.first().toModelJsonValue()["recovery_attempts"])
                assertEquals("b", results.last().output["branch"])
                AgentModelResponse("Both branches recovered.")
            }
        }, registry(readOnly = true, parallel = true) { operation ->
            val count = attempts.merge(operation, 1, Int::plus)!!
            if (operation == "a" && count == 1) AgentNativeToolExecutionResult.failure("temporary", "Try another observation", true)
            else AgentNativeToolExecutionResult.success(mapOf("branch" to operation))
        }).run(request.copy(budget = request.budget.copy(maxRetriesPerCall = 1)))
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(2, attempts["a"])
        assertEquals(1, attempts["b"])
    }

    @Test fun interruptedDiagnosisResumesFromCommittedFailureWithoutRepeatingTheOperation() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val operations = mutableListOf<String>()
        val registry = registry {
            operations += it
            if (it == "submit") AgentNativeToolExecutionResult.failure("effect_outcome_unknown", "Check the saved record")
            else AgentNativeToolExecutionResult.success(mapOf("record_exists" to true))
        }
        try {
            AgentModelToolLoop(AgentModelAdapter {
                if (it.round == 1) action("submit", "submit") else throw CancellationException("Process lost")
            }, registry, journal = journal).run(request)
            fail("Expected interruption")
        } catch (_: CancellationException) { }
        val resumed = AgentModelToolLoop(AgentModelAdapter {
            if (it.round == 2) {
                assertEquals("effect_outcome_unknown", it.messages.last().toolResult?.error?.code)
                action("inspect", "inspect")
            } else AgentModelResponse("The submitted record exists; it was not submitted twice.")
        }, registry, journal = journal).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, resumed.status)
        assertEquals(listOf("submit", "inspect"), operations)
        assertEquals(1, resumed.messages.count { it.text == AgentProblemSolvingPolicy.CONTRACT })
    }

    @Test fun ordinaryConversationStillUsesOneModelRequestAndNoTools() = runBlocking {
        var requests = 0
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            requests++
            assertTrue(it.messages.first().text.contains(AgentProblemSolvingPolicy.CONTRACT))
            AgentModelResponse("Hello")
        }, registry { error("Conversation must not execute tools") }).run(request)
        assertEquals(1, requests)
        assertEquals(0, outcome.usage.toolCallAttempts)
    }

    @Test fun capabilityDiscoveryAndContractInspectionCannotUnlockAnUnverifiedMutation() = runBlocking {
        val operations = mutableListOf<String>()
        val registry = registry { operation ->
            operations += operation
            if (operation == "submit") AgentNativeToolExecutionResult.failure(
                "effect_outcome_unknown", "Observe the external record before deciding whether to resubmit",
                details = mapOf("outcome_unknown" to true))
            else AgentNativeToolExecutionResult.success(mapOf("record_exists" to true))
        }.register(AgentToolInspectionTools.definition()).register(AgentToolDiscoveryTools.definition())
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            when (it.round) {
                1 -> action("submit-original", "submit")
                2 -> AgentModelResponse(toolCalls = listOf(AgentModelToolCall("discover",
                    AgentToolDiscoveryTools.ID, mapOf("query" to "test.problem.operation"))))
                3 -> AgentModelResponse(toolCalls = listOf(AgentModelToolCall("describe",
                    AgentToolInspectionTools.DESCRIBE, mapOf("tool_id" to "test.problem.operation"))))
                4 -> action("submit-after-metadata", "submit")
                5 -> {
                    assertEquals("repeated_tool_call", it.messages.last().toolResult?.error?.code)
                    action("inspect-external-record", "inspect")
                }
                else -> {
                    assertEquals(true, it.messages.last().toolResult?.output?.get("record_exists"))
                    AgentModelResponse("The external record exists; the mutation was not repeated.")
                }
            }
        }, registry).run(request.copy(budget = request.budget.copy(maxRepeatedCallSignatures = 2)))
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(listOf("submit", "inspect"), operations)
    }

    @Test fun invalidArgumentsExposeTheRealContractAndAllowModelCorrectionWithoutExecution() = runBlocking {
        val operations = mutableListOf<String>()
        val registry = registry { operations += it; AgentNativeToolExecutionResult.success() }
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            when (it.round) {
                1 -> AgentModelResponse(toolCalls = listOf(AgentModelToolCall(
                    "invalid", "test.problem.operation", mapOf("arguments" to "inspect"))))
                2 -> {
                    val error = it.messages.last().toolResult!!.error!!
                    assertEquals(false, error.details["executed"])
                    assertEquals(false, error.details["goal_terminal"])
                    assertEquals(registry.lookup("test.problem.operation")!!.descriptor.inputSchema.document,
                        error.details["input_schema"])
                    action("corrected", "inspect")
                }
                else -> AgentModelResponse("The corrected observation completed.")
            }
        }, registry).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(listOf("inspect"), operations)
    }

    @Test fun unknownOutcomeCanBeRetriedAfterTheModelObservesThatTheExternalRecordIsAbsent() = runBlocking {
        val operations = mutableListOf<String>()
        var submissions = 0
        val native = registry { operation ->
            operations += operation
            if (operation == "inspect") AgentNativeToolExecutionResult.success(mapOf("record_exists" to false))
            else if (++submissions == 1) AgentNativeToolExecutionResult.failure("connection_lost", "Submission outcome unknown",
                details = mapOf("outcome_unknown" to true))
            else AgentNativeToolExecutionResult.success(mapOf("saved" to true))
        }
        val result = AgentModelToolLoop(AgentModelAdapter {
            when (it.round) {
                1 -> action("submit-original", "submit")
                2 -> action("submit-without-observation", "submit")
                3 -> {
                    assertEquals("repeated_tool_call", it.messages.last().toolResult?.error?.code)
                    action("inspect-external", "inspect")
                }
                4 -> {
                    assertEquals(false, it.messages.last().toolResult?.output?.get("record_exists"))
                    action("submit-after-observation", "submit")
                }
                else -> {
                    assertEquals(true, it.messages.last().toolResult?.output?.get("saved"))
                    AgentModelResponse("The original operation was verified after reconciliation.")
                }
            }
        }, native).run(request.copy(budget = request.budget.copy(maxRepeatedCallSignatures = 2)))
        assertEquals(AgentModelToolLoopStatus.COMPLETED, result.status)
        assertEquals(listOf("submit", "inspect", "submit"), operations)
    }

    @Test fun uncertaintyFenceIsRebuiltOnRecoveryAndMetadataCannotReplaceExternalVerification() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val operations = mutableListOf<String>()
        val native = registry { operation ->
            operations += operation
            if (operation == "submit") AgentNativeToolExecutionResult.failure("effect_outcome_unknown", "Observe the record")
            else AgentNativeToolExecutionResult.success(mapOf("record_exists" to true))
        }.register(AgentToolInspectionTools.definition()).register(AgentToolDiscoveryTools.definition())
        val durable = request.copy(budget = request.budget.copy(maxRepeatedCallSignatures = 2))
        try {
            AgentModelToolLoop(AgentModelAdapter {
                when (it.round) {
                    1 -> action("submit", "submit")
                    2 -> AgentModelResponse(toolCalls = listOf(AgentModelToolCall("describe",
                        AgentToolInspectionTools.DESCRIBE, mapOf("tool_id" to "test.problem.operation"))))
                    else -> throw CancellationException("Public process interruption fixture")
                }
            }, native, journal = journal).run(durable)
            fail("Expected the public interruption")
        } catch (_: CancellationException) { }
        val resumed = AgentModelToolLoop(AgentModelAdapter {
            when (it.round) {
                3 -> action("submit-after-restart", "submit")
                4 -> {
                    assertEquals("repeated_tool_call", it.messages.last().toolResult?.error?.code)
                    action("inspect-external", "inspect")
                }
                else -> AgentModelResponse("The existing record was verified without another submission.")
            }
        }, native, journal = journal).run(durable)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, resumed.status)
        assertEquals(listOf("submit", "inspect"), operations)
    }

    @Test fun invalidArgumentsDoNotUnlockAnotherAttemptAtAnUnverifiedMutation() = runBlocking {
        val operations = mutableListOf<String>()
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            when (it.round) {
                1 -> action("submit-1", "submit")
                2 -> AgentModelResponse(toolCalls = listOf(AgentModelToolCall(
                    "invalid", "test.problem.operation", emptyMap())))
                3 -> action("submit-2", "submit")
                else -> {
                    assertEquals("repeated_tool_call", it.messages.last().toolResult?.error?.code)
                    AgentModelResponse("Inspect the original operation before attempting another mutation.")
                }
            }
        }, registry {
            operations += it
            AgentNativeToolExecutionResult.failure("effect_outcome_unknown", "Inspect the external record")
        }).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(listOf("submit"), operations)
    }

    @Test fun cancellationStopsBeforeTheNextDiagnostic() = runBlocking {
        var cancelled = false
        var requests = 0
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            requests++; action("first", "read")
        }, registry { cancelled = true; AgentNativeToolExecutionResult.failure("failed", "Actual failure") })
            .run(request.copy(cancellationToken = object : AgentNativeToolCancellationToken by AgentNativeToolCancellationToken.NONE {
                override val isCancellationRequested: Boolean get() = cancelled
            }))
        assertEquals(AgentModelToolLoopStatus.CANCELLED, outcome.status)
        assertEquals(1, requests)
    }

    private fun action(id: String, operation: String) = AgentModelResponse(toolCalls = listOf(call(id, operation)))
    private fun call(id: String, operation: String) = AgentModelToolCall(id, "test.problem.operation", mapOf("operation" to operation))
    private fun registry(readOnly: Boolean = false, parallel: Boolean = false,
        execute: (String) -> AgentNativeToolExecutionResult) = AgentNativeToolRegistry().register(AgentNativeToolDefinition(
        AgentNativeToolDescriptor("test.problem.operation", "1.0.0", "Problem-solving test operation",
            "Deterministic test operation", AgentNativeToolLocation.PHONE,
            AgentNativeJsonSchema.objectSchema(mapOf("operation" to AgentNativeJsonSchema.string()), setOf("operation")),
            AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW,
            idempotency = if (readOnly) AgentNativeToolIdempotency.IDEMPOTENT else AgentNativeToolIdempotency.IDEMPOTENCY_KEY_REQUIRED,
            concurrency = if (parallel) AgentNativeToolConcurrency.PARALLEL_READ_ONLY else AgentNativeToolConcurrency.SERIAL,
            effect = if (readOnly) AgentNativeToolEffect.READ_ONLY else AgentNativeToolEffect.MUTATION),
        AgentNativeToolExecutor { execute(it.input["operation"] as String) }))
}
