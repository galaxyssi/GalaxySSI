package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class AgentNativeEffectRecoveryQueryTest {
    private val scope = AgentNativeToolInvocationContext(sessionId = "session", conversationId = "conversation",
        turnId = "turn", invocationId = "original", idempotencyKey = "logical-effect")
    private val read = AgentNativeToolDescriptor("test.effect.observe", "1.0.0", "Observe", "Observe effect state",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(
            properties = mapOf("operation_id" to AgentNativeJsonSchema.string()), required = setOf("operation_id"),
            additionalProperties = false), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW,
        idempotency = AgentNativeToolIdempotency.IDEMPOTENT, concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY,
        effect = AgentNativeToolEffect.READ_ONLY)
    private val write = read.copy(id = "test.effect.submit", inputSchema = AgentNativeJsonSchema.objectSchema(),
        effect = AgentNativeToolEffect.MUTATION, idempotency = AgentNativeToolIdempotency.IDEMPOTENCY_KEY_REQUIRED,
        concurrency = AgentNativeToolConcurrency.SERIAL)
    private fun query(id: String) = AgentNativeEffectRecoveryQuery(read.id, read.version, mapOf("operation_id" to id))
    private fun key() = AgentNativeToolReplayKey(write.id, write.version, scope.idempotencyKey!!, AgentNativeEffectScope.from(scope))
    private fun registry(store: AgentNativeToolReplayStore, provider: AgentNativeEffectRecoveryProvider,
        executor: AgentNativeToolExecutor = AgentNativeToolExecutor { AgentNativeToolExecutionResult.success() }) =
        AgentNativeToolRegistry(replayStore = store).registerAll(listOf(
            AgentNativeToolDefinition(read, AgentNativeToolExecutor { invocation ->
                AgentNativeToolExecutionResult.success(mapOf("observed_operation" to invocation.input.getValue("operation_id"),
                    "state" to "completed", "business_success_verified" to false))
            }), AgentNativeToolDefinition(write, executor, effectRecoveryProvider = provider)))

    @Test fun queryIsAnImmutableSnapshotAndRoundTripsThroughThePersistedContract() {
        val nested = mutableMapOf<String, Any?>("id" to "original")
        val input = mutableMapOf<String, Any?>("reference" to nested)
        val query = AgentNativeEffectRecoveryQuery(read.id, read.version, input)
        nested["id"] = "changed"
        input["secret"] = "not-part-of-the-query"
        assertEquals(mapOf("reference" to mapOf("id" to "original")), query.arguments)
        assertEquals(query, AgentNativeEffectRecoveryQuery.fromJsonValue(query.toJsonValue()))
        (query.arguments as MutableMap<String, Any?>)["reference"] = "changed-by-reader"
        assertEquals(mapOf("reference" to mapOf("id" to "original")), query.arguments)
    }

    @Test fun malformedPersistedQueriesNeverBecomeAnEmptyOrDifferentObservation() {
        for (json in listOf(null, emptyMap<String, Any>(), query("id").toJsonValue() + ("format_version" to 1.5),
            query("id").toJsonValue() + ("arguments" to "not-object"),
            query("id").toJsonValue() + ("tool_id" to ""))) {
            assertThrows(Exception::class.java) { AgentNativeEffectRecoveryQuery.fromJsonValue(json) }
        }
    }

    @Test fun queryIsCommittedWithOwnershipBeforeTheExecutorRuns() {
        val store = InMemoryAgentNativeToolReplayStore()
        val runtime = registry(store, { query(it.context.invocationId) }) {
            val claim = store.observe(key())!!
            assertEquals("original", claim.invocationId)
            assertEquals(query("original"), claim.recoveryQuery)
            assertNull(claim.result)
            AgentNativeToolExecutionResult.success(mapOf("saved" to true))
        }
        assertTrue(runtime.invoke(write.id, emptyMap(), scope).isSuccess)
    }

    @Test fun successfulButUnverifiedEffectsKeepTheHostQueryAcrossReplay() {
        val runtime = registry(InMemoryAgentNativeToolReplayStore(), { query(it.context.invocationId) }) {
            AgentNativeToolExecutionResult.success(mapOf("state_verified" to false))
        }
        val first = runtime.invoke(write.id, emptyMap(), scope)
        assertEquals(query("original").toJsonValue(), first.metadata[AgentRecoveryObservationEvidence.QUERY_KEY])
        val replay = runtime.invoke(write.id, emptyMap(), scope.copy(invocationId = "retry"))
        assertTrue(replay.receipt.replayed)
        assertEquals(first.metadata, replay.metadata)
    }

    @Test fun observedSubjectIsImmutableAndValidated() {
        val subject = mutableMapOf("/operation/id" to "one")
        val query = AgentNativeEffectRecoveryQuery(read.id, read.version, emptyMap(), subject)
        subject["/operation/id"] = "two"
        assertEquals(mapOf("/operation/id" to "one"), query.observedSubject)
        assertEquals(query, AgentNativeEffectRecoveryQuery.fromJsonValue(query.toJsonValue()))
        for (value in listOf(mapOf("invalid" to "one"), mapOf("/id" to ""))) {
            assertThrows(IllegalArgumentException::class.java) {
                AgentNativeEffectRecoveryQuery(read.id, read.version, emptyMap(), value)
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            AgentNativeEffectRecoveryQuery.fromJsonValue(query.toJsonValue() + ("observed_subject" to mapOf("/id" to 5)))
        }
    }

    @Test fun readReceiptBindsActualInputAndScopeAndOverridesOutputClaims() {
        val runtime = registry(InMemoryAgentNativeToolReplayStore(), { query("original") })
        val context = scope.copy(invocationId = "read", idempotencyKey = null)
        val result = runtime.invoke(read.id, mapOf("operation_id" to "original"), context)
        val output = AgentRecoveryObservationEvidence.attach(mapOf(AgentRecoveryObservationEvidence.KEY to "forged"),
            result, context, read)
        val proof = output[AgentRecoveryObservationEvidence.KEY] as Map<*, *>
        assertEquals("read", proof["invocation_id"])
        assertEquals("conversation", proof["conversation_id"])
        assertEquals("turn", proof["turn_id"])
        assertEquals(AgentNativeJsonCodec.sha256(mapOf("operation_id" to "original")), proof["input_sha256"])
        assertEquals(false, proof["replayed"])
    }

    @Test fun executorMetadataCannotInventAHostRecoveryQuery() {
        val runtime = AgentNativeToolRegistry().register(AgentNativeToolDefinition(write, AgentNativeToolExecutor {
            AgentNativeToolExecutionResult.success(metadata = mapOf(AgentRecoveryObservationEvidence.QUERY_KEY to query("forged").toJsonValue()))
        }))
        val result = runtime.invoke(write.id, emptyMap(), scope)
        assertFalse(result.metadata.containsKey(AgentRecoveryObservationEvidence.QUERY_KEY))
        assertFalse(AgentRecoveryObservationEvidence.attach(mapOf(AgentRecoveryObservationEvidence.KEY to "forged"),
            result, scope, write).containsKey(AgentRecoveryObservationEvidence.KEY))
    }

    @Test fun crashWindowReturnsTheOriginalQueryWithoutRerunningTheEffectOrBuildingANewQuery() {
        val store = InMemoryAgentNativeToolReplayStore()
        val interrupted = object : AgentNativeToolReplayStore by store {
            override fun complete(key: AgentNativeToolReplayKey, invocationId: String, result: AgentNativeToolResult) {
                error("Simulated interruption before terminal commit")
            }
        }
        var writes = 0
        assertFalse(registry(interrupted, { query(it.context.invocationId) }) {
            writes++; AgentNativeToolExecutionResult.success()
        }.invoke(write.id, mapOf("form" to "private-original-input"), scope).isSuccess)
        val runtime = registry(store, { error("Recovery must use the persisted original query") }) {
            writes++; error("Must not repeat the external effect")
        }
        val recovered = runtime.invoke(write.id, mapOf("form" to "private-original-input"), scope.copy(invocationId = "after-restart"))
        assertEquals("effect_outcome_unknown", recovered.error?.code)
        val original = AgentNativeEffectRecoveryQuery.fromJsonValue(recovered.error?.details?.get("recovery_query"))
        assertEquals(query("original"), original)
        assertEquals(1, writes)
        assertFalse(recovered.toJson().contains("private-original-input"))
        val observed = runtime.invoke(original.toolId, original.arguments, scope.copy(invocationId = "observe", idempotencyKey = null))
        assertTrue(observed.isSuccess)
        assertEquals("original", observed.output["observed_operation"])
        assertEquals(false, observed.output["business_success_verified"])
        assertNull(store.observe(key())!!.result)
    }

    @Test fun inputConflictsDoNotDiscloseARecoveryQueryForAnotherOperation() {
        val store = InMemoryAgentNativeToolReplayStore()
        store.claimWithRecovery(key(), AgentNativeJsonCodec.sha256(mapOf("form" to "one")), "original", query("original"))
        val result = registry(store, { error("No new query") }).invoke(write.id, mapOf("form" to "two"), scope)
        assertEquals("idempotency_key_conflict", result.error?.code)
        assertFalse(result.error!!.details.containsKey("recovery_query"))
    }

    @Test fun uncertainExecutorResultsPersistTheirOriginalQueryForImmediateAndLaterModelObservations() {
        val store = InMemoryAgentNativeToolReplayStore()
        val first = registry(store, { query("original") }) {
            AgentNativeToolExecutionResult.failure("response_lost", "Inspect the existing operation",
                details = mapOf("outcome_unknown" to true))
        }.invoke(write.id, emptyMap(), scope)
        assertEquals(query("original").toJsonValue(), first.error?.details?.get("recovery_query"))
        val replay = registry(store, { error("No new query") }).invoke(write.id, emptyMap(), scope.copy(invocationId = "later"))
        assertTrue(replay.receipt.replayed)
        assertEquals(first.error, replay.error)
    }

    @Test fun aDifferentTurnCannotReadThePreviousRecoveryQuery() {
        val store = InMemoryAgentNativeToolReplayStore()
        store.claimWithRecovery(key(), AgentNativeJsonCodec.sha256(emptyMap<String, Any>()), "original", query("original"))
        val runtime = registry(store, { query(it.context.invocationId) }) {
            AgentNativeToolExecutionResult.success(mapOf("new_turn" to true))
        }
        val result = runtime.invoke(write.id, emptyMap(), scope.copy(turnId = "different", invocationId = "new"))
        assertTrue(result.isSuccess)
        assertEquals(true, result.output["new_turn"])
        assertEquals(query("original"), store.observe(key())!!.recoveryQuery)
    }

    @Test fun invalidQueryTargetsCannotClaimOrExecuteTheMutation() {
        for (candidate in listOf(AgentNativeEffectRecoveryQuery(write.id, write.version, emptyMap()),
            AgentNativeEffectRecoveryQuery("missing.tool", "1", emptyMap()),
            AgentNativeEffectRecoveryQuery(read.id, "wrong-version", mapOf("operation_id" to "one")),
            AgentNativeEffectRecoveryQuery(read.id, read.version, mapOf("wrong_field" to "one")))) {
            val store = InMemoryAgentNativeToolReplayStore()
            val result = registry(store, { candidate }) { error("Invalid recovery must not dispatch") }
                .invoke(write.id, emptyMap(), scope)
            assertEquals("effect_recovery_query_invalid", result.error?.code)
            assertEquals(false, result.error?.details?.get("executed"))
            assertNull(store.observe(key()))
        }
    }

    @Test fun failureToPersistTheQueryDoesNotExecuteTheMutation() {
        val backing = InMemoryAgentNativeToolReplayStore()
        val store = object : AgentNativeToolReplayStore by backing {
            override fun claimWithRecovery(key: AgentNativeToolReplayKey, inputSha256: String, invocationId: String,
                recoveryQuery: AgentNativeEffectRecoveryQuery): AgentNativeEffectClaim = error("Storage unavailable")
        }
        val result = registry(store, { query("original") }) { error("Must not execute without durable ownership") }
            .invoke(write.id, emptyMap(), scope)
        assertFalse(result.isSuccess)
        assertNull(backing.observe(key()))
    }

    @Test fun committedResultsReplayWithoutRebuildingQueriesOrExecutingObservers() {
        val store = InMemoryAgentNativeToolReplayStore()
        val first = registry(store, { query("original") }).invoke(write.id, emptyMap(), scope)
        assertTrue(first.isSuccess)
        val replay = registry(store, { error("Committed outcomes need no new recovery query") }) { error("No new effect") }
            .invoke(write.id, emptyMap(), scope.copy(invocationId = "replay"))
        assertTrue(replay.receipt.replayed)
        assertEquals(first.output, replay.output)
    }

    @Test fun legacyUnknownEffectsRemainUnknownWithoutInventingAnOperationIdentity() {
        val store = InMemoryAgentNativeToolReplayStore()
        store.claim(key(), AgentNativeJsonCodec.sha256(emptyMap<String, Any>()), "legacy-owner")
        val result = registry(store, { error("Do not reconstruct unrecorded recovery metadata") })
            .invoke(write.id, emptyMap(), scope)
        assertEquals("effect_outcome_unknown", result.error?.code)
        assertFalse(result.error!!.details.containsKey("recovery_query"))
    }

    @Test fun browserQueryKeepsTheOriginalHelperIdAcrossRegistryRecreation() {
        val store = InMemoryAgentNativeToolReplayStore()
        val broken = object : AgentNativeToolReplayStore by store {
            override fun complete(key: AgentNativeToolReplayKey, invocationId: String, result: AgentNativeToolResult) {
                error("Interrupted before observation commit")
            }
        }
        val definitions = AgentInteractiveBrowserTools.definitions({ AgentRuntimeExecutionResponse(0,
            """{"ok":true,"result":{"action_dispatched":true}}""", "", 1) })
        val first = AgentNativeToolRegistry(replayStore = broken).registerAll(definitions)
            .invoke(AgentInteractiveBrowserTools.ACT, mapOf("operation" to "click"), scope)
        assertFalse(first.isSuccess)
        val restored = AgentNativeToolRegistry(replayStore = store).registerAll(AgentInteractiveBrowserTools.definitions({
            error("Restoration must not execute another browser mutation")
        })).invoke(AgentInteractiveBrowserTools.ACT, mapOf("operation" to "click"), scope.copy(invocationId = "restored"))
        val query = AgentNativeEffectRecoveryQuery.fromJsonValue(restored.error?.details?.get("recovery_query"))
        assertEquals(AgentInteractiveBrowserTools.OBSERVE, query.toolId)
        assertEquals(mapOf("operation" to "operation_status", "request_id" to AgentInteractiveBrowserTools.operationId(scope)), query.arguments)
    }

    @Test fun modelContractExplainsObservationBeforeRetryWithoutClaimingBusinessSuccess() {
        assertTrue(AgentProblemSolvingPolicy.CONTRACT.contains("recovery_query"))
        assertTrue(AgentProblemSolvingPolicy.COMPACT_CONTRACT.contains("recovery_query"))
        assertTrue(AgentProblemSolvingPolicy.CONTRACT.contains("not proof of business success"))
    }

    @Test fun resumedModelLoopChoosesTheOriginalObservationThenVerifiesTheGoalWithoutAnotherWrite() = runBlocking {
        val store = InMemoryAgentNativeToolReplayStore()
        val loopScope = AgentNativeEffectScope(sessionId = "session", conversationId = "conversation", taskId = "task", turnId = "turn")
        store.claimWithRecovery(key().copy(scope = loopScope), AgentNativeJsonCodec.sha256(emptyMap<String, Any>()),
            "before-process-death", query("original-operation"))
        val verify = read.copy(id = "test.effect.verify")
        var writes = 0
        val runtime = registry(store, { error("Do not regenerate the original query") }) {
            writes++; error("Must not submit again")
        }.register(AgentNativeToolDefinition(verify, AgentNativeToolExecutor {
            AgentNativeToolExecutionResult.success(mapOf("actual_saved_value" to "expected-value"))
        }))
        var round = 0
        val model = AgentModelAdapter { request ->
            when (round++) {
                0 -> AgentModelResponse(toolCalls = listOf(AgentModelToolCall("resume", write.id,
                    idempotencyKey = scope.idempotencyKey)))
                1 -> {
                    val error = request.messages.last().toolResult!!.error!!
                    assertEquals("effect_outcome_unknown", error.code)
                    val original = AgentNativeEffectRecoveryQuery.fromJsonValue(error.details["recovery_query"])
                    AgentModelResponse(toolCalls = listOf(AgentModelToolCall("observe-original", original.toolId,
                        original.arguments, toolVersion = original.toolVersion)))
                }
                2 -> {
                    assertEquals("completed", request.messages.last().toolResult!!.output["state"])
                    assertEquals(false, request.messages.last().toolResult!!.output["business_success_verified"])
                    AgentModelResponse(toolCalls = listOf(AgentModelToolCall("verify-goal", verify.id, mapOf("operation_id" to "original-operation"))))
                }
                else -> {
                    assertEquals("expected-value", request.messages.last().toolResult!!.output["actual_saved_value"])
                    AgentModelResponse("\u5df2\u6838\u5bf9\u539f\u64cd\u4f5c\u5e76\u786e\u8ba4\u4fdd\u5b58\u7ed3\u679c\u3002")
                }
            }
        }
        val outcome = AgentModelToolLoop(model, runtime).run(AgentProblemSolvingPolicy.prepare(
            AgentModelToolLoopRequest.forUserMessage("session", "conversation", "turn", "task", "workspace",
                "\u7ee7\u7eed\u6838\u5bf9\u521a\u624d\u7684\u4fdd\u5b58\u64cd\u4f5c\uff0c\u4e0d\u8981\u91cd\u590d\u63d0\u4ea4\u3002")))
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(4, round)
        assertEquals(0, writes)
        assertEquals(listOf(write.id, read.id, verify.id), outcome.messages.mapNotNull { it.toolResult?.toolId })
    }
}
