package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject

class AgentUnverifiedOutcomeRecoveryTest {
    private val originKey = AgentUnverifiedOutcomeRecovery.ORIGIN_ACTION
    private val phoneKey = AgentUnverifiedOutcomeRecovery.PHONE_CONTROL
    private val readTool = AgentAndroidSystemNativeTools.AUDIO_STATUS
    private val writeTool = AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET
    private val requirements = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false)

    @Test fun acceptedButUnverifiedShortcutNeedsReview() {
        assertTrue(AgentUnverifiedOutcomeRecovery.needsReview(plan(), origin(), receipt()))
    }

    @Test fun verifiedAndPendingAndFailedResultsDoNotStartAnotherLoop() {
        val verified = receipt().copy(metadata = mapOf("goal_status" to "verified"))
        for (result in listOf(null, verified, receipt().copy(success = false), receipt().copy(actionId = "other"),
            receipt().copy(metadata = receipt().metadata + ("awaiting_response" to "true")))) {
            assertFalse(AgentUnverifiedOutcomeRecovery.needsReview(plan(), origin(), result))
        }
        assertFalse(AgentUnverifiedOutcomeRecovery.needsReview(plan(origin().copy(status = AgentActionStatus.RUNNING)),
            origin(), receipt()))
    }

    @Test fun existingReviewerOrPlanOnlyDoesNotEscalate() {
        assertFalse(AgentUnverifiedOutcomeRecovery.needsReview(plan().copy(
            plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE), origin(), receipt()))
        assertFalse(AgentUnverifiedOutcomeRecovery.needsReview(plan().copy(
            executionMode = AgentTaskExecutionMode.PLAN_ONLY), origin(), receipt()))
        assertFalse(AgentUnverifiedOutcomeRecovery.needsReview(plan().copy(
            actions = listOf(origin(), provider().copy(status = AgentActionStatus.WAITING_RESPONSE))), origin(), receipt()))
    }

    @Test fun unavailableVerificationCapabilityRemainsAnExplicitBlockedOutcome() {
        val action = origin().copy(evidence = """{"state_verified":false,"metadata":{"required_capability":"receipt_access"}}""")
        assertFalse(AgentUnverifiedOutcomeRecovery.needsReview(plan(action), action, receipt()))
    }

    @Test fun recoveryPreservesProviderScopeAndReceiptWithoutReplayingEffect() {
        val prior = plan().copy(expectedResult = "Observed requested state", artifactRichOutputJson = "saved-artifact")
        val recovered = recover(prior)!!
        val connector = recovered.actions.single()
        assertEquals(prior.planId, recovered.planId)
        assertEquals(prior.revision + 1, recovered.revision)
        assertEquals(prior.executionMode, recovered.executionMode)
        assertEquals(prior.expectedResult, recovered.expectedResult)
        assertEquals(prior.artifactRichOutputJson, recovered.artifactRichOutputJson)
        assertEquals(requirements, recovered.completionRequirements)
        assertEquals(AgentActionKind.CALL_CONNECTOR, connector.kind)
        for (key in listOf("connector_id", "model_id", "manual_model_id", "manual_target_locked", "agent_reasoning_effort")) {
            assertEquals(key, provider().parameters[key], connector.parameters[key])
        }
        assertEquals("conversation", connector.parameters[INTERNAL_CONVERSATION_ID])
        assertEquals("turn", connector.parameters[INTERNAL_TURN_ID])
        assertEquals("original-effect", connector.parameters[originKey])
        assertEquals("1", connector.parameters["supervised_iteration"])
        assertEquals("true", connector.parameters[phoneKey])
        assertEquals(origin().evidence, recovered.actionHistory.single().evidence)
        val prompt = connector.parameters.getValue("prompt")
        assertTrue(prompt.contains(readTool))
        assertTrue(prompt.contains("First return read-only"))
        assertTrue(prompt.contains("business outcome remains unverified"))
        assertFalse(prompt.contains("The last phone action failed"))
        assertTrue(recovered.isSupervisedProjectPlan())
    }

    @Test fun noProviderOrExplicitLocalOnlyRequestDoesNotExportEvidence() {
        assertNull(AgentUnverifiedOutcomeRecovery.create(plan(), origin(), receipt(), request(), null))
        assertNull(AgentUnverifiedOutcomeRecovery.create(plan(), origin(), receipt(), request(), provider().copy(
            parameters = mapOf("connector_id" to UNAVAILABLE_REASONING_CONNECTOR_ID))))
        assertNull(AgentUnverifiedOutcomeRecovery.create(plan(), origin(), receipt(), request("offline local only"), provider()))
    }

    @Test fun conflictingCurrentConversationFailsClosed() {
        val request = request().copy(conversationContext = AgentConversationContext("other", "", emptyList(), false))
        assertNull(AgentUnverifiedOutcomeRecovery.create(plan(), origin(), receipt(), request, provider()))
    }

    @Test fun foreignHistoryAndPrivateContextDoNotLeakIntoRecoveryPrompt() {
        val foreign = origin().copy(id = "foreign", evidence = "FOREIGN_RECEIPT", parameters = mapOf(
            "tool_id" to writeTool, INTERNAL_CONVERSATION_ID to "other", INTERNAL_TURN_ID to "other-turn"))
        val request = request().copy(conversationContext = AgentConversationContext("conversation", "PRIVATE_SUMMARY",
            emptyList(), false, globalContext = "PRIVATE_MEMORY"))
        val recovered = AgentUnverifiedOutcomeRecovery.create(plan().copy(actionHistory = listOf(foreign)),
            origin(), receipt(), request, provider())!!
        assertFalse(recovered.actionHistory.any { it.id == "foreign" })
        val prompt = recovered.actions.single().parameters.getValue("prompt")
        for (text in listOf("FOREIGN_RECEIPT", "PRIVATE_SUMMARY", "PRIVATE_MEMORY")) assertFalse(prompt.contains(text))
    }

    @Test fun mutationCompletionAndMixedBatchRequireAnObservationFirst() {
        val connector = recover()!!.actions.single()
        for (proposed in listOf(emptyList(), listOf(origin()), listOf(read(), origin()),
            listOf(read().copy(kind = AgentActionKind.DRAFT_PLAN)))) {
            assertNotNull(violation(connector, listOf(origin()), proposed))
        }
        assertNull(violation(connector, listOf(origin()), listOf(read())))
    }

    @Test fun missingDescriptorOrLowRiskMutationCannotMasqueradeAsReadOnly() {
        val connector = recover()!!.actions.single()
        assertNotNull(violation(connector, listOf(origin()), listOf(read("unknown.tool"))))
        assertNotNull(violation(connector, listOf(origin()), listOf(read(writeTool))))
    }

    @Test fun completedObservationUnlocksNextStepNotItsCompletionEvidence() {
        val connector = recover()!!.actions.single()
        assertNull(violation(connector, listOf(origin(), read()), listOf(origin())))
        assertFalse(AgentGoalEvidence.permitsSuccess(receipt()))
    }

    @Test fun recoveryValidationUsesDurableOriginEvidenceOutsideThePromptBudget() {
        val connector = recover()!!.actions.single()
        val filler = (1..80).map { read("galaxyssi.fixture.inspect").copy(id = "unrelated-$it",
            result = "Unrelated public observation. ".repeat(80), evidence = "") }
        val plan = plan().copy(plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE,
            actions = listOf(connector), actionHistory = listOf(origin(), read()) + filler)
        val projection = plan.historyForReplan()
        assertFalse(projection.any { it.id == read().id })
        assertNotNull(violation(connector, projection, listOf(origin())))
        val history = AgentCompletionEvidenceHistory.resolve(plan, AgentPlanContinuationScope("conversation", "turn"))
        assertNull(violation(connector, history, listOf(origin())))
    }

    @Test fun unrelatedReadDoesNotUnlockEffectsOrCompletion() {
        val connector = recover()!!.actions.single()
        for (actions in listOf(emptyList(), listOf(origin()))) {
            assertNotNull(violation(connector, listOf(origin(), read("galaxyssi.android.battery.status")), actions))
            assertNotNull(violation(connector, listOf(origin(), read().copy(evidence = "{}")), actions))
        }
    }

    @Test fun wrongSubjectCannotProveAffectedStreamWasRead() {
        val read = editRead { it.getJSONObject("streams").remove("media") }
        assertTrue(violation(recover()!!.actions.single(), listOf(origin(), read), listOf(origin()))!!
            .contains("observation_subject_mismatch"))
    }

    @Test fun staleReplayedForeignOrMismatchedReceiptsCannotUnlockEffects() {
        val mutations: List<(JSONObject) -> Unit> = listOf(
            { it.put("replayed", true) }, { it.remove("replayed") }, { it.put("started_at_ms", 99) },
            { it.put("finished_at_ms", 100) }, { it.put("invocation_id", "effect-invocation") },
            { it.put("invocation_id", "") }, { it.put("conversation_id", "other") },
            { it.put("turn_id", "other-turn") }, { it.put("status", "failed") },
            { it.put("tool_version", "other-version") }, { it.put("tool_id", writeTool) },
            { it.put("input_sha256", "other-subject") })
        for (mutate in mutations) {
            val read = editRead { mutate(it.getJSONObject(AgentRecoveryObservationEvidence.KEY)) }
            assertNotNull(violation(recover()!!.actions.single(), listOf(origin(), read), listOf(origin())))
        }
    }

    @Test fun foreignActionsOrConnectorCannotBorrowAnObservation() {
        val connector = recover()!!.actions.single()
        assertNotNull(violation(connector, listOf(origin(), read().copy(parameters = read().parameters +
            (INTERNAL_TURN_ID to "other"))), listOf(origin())))
        assertNotNull(violation(connector.copy(parameters = connector.parameters + (INTERNAL_TURN_ID to "other")),
            listOf(origin(), read()), listOf(origin())))
    }

    @Test fun latestRelevantFailureCannotBorrowAnOlderSuccess() {
        assertNotNull(violation(recover()!!.actions.single(), listOf(origin(), read(),
            read().copy(id = "later", status = AgentActionStatus.FAILED)), listOf(origin())))
    }

    @Test fun missingContractAndUnavailableObserverStayUnverified() {
        val connector = recover()!!.actions.single()
        val missing = origin().copy(evidence = """{"state_verified":false}""")
        assertFalse(AgentUnverifiedOutcomeRecovery.needsReview(plan(missing), missing, receipt()))
        assertNotNull(violation(connector, listOf(missing, read()), listOf(origin())))
        assertNotNull(AgentUnverifiedOutcomeRecovery.observationViolation(connector, listOf(origin(), read()),
            listOf(origin())) { descriptor(it)?.copy(version = "2.0.0") })
    }

    @Test fun failedUnknownEmptyOrOlderObservationDoesNotUnlockEffects() {
        val connector = recover()!!.actions.single()
        for (read in listOf(read().copy(status = AgentActionStatus.FAILED), read().copy(evidence = ""),
            read().copy(evidence = """{"state_verified":false}"""))) {
            assertNotNull(violation(connector, listOf(origin(), read), listOf(origin())))
        }
        assertNotNull(violation(connector, listOf(read(), origin()), listOf(origin())))
        assertNotNull(violation(connector, listOf(read()), listOf(origin())))
    }

    @Test fun schemaLookupAloneDoesNotCountAsObservingDeviceState() {
        val connector = recover()!!.actions.single()
        val schema = read(AgentToolInspectionTools.toolIds.first())
        assertNull(violation(connector, listOf(origin()), listOf(schema)))
        assertNotNull(violation(connector, listOf(origin(), schema), listOf(origin())))
    }

    @Test fun ordinarySupervisedPlansAreNotChanged() {
        assertNull(violation(provider(), emptyList(), listOf(origin())))
    }

    @Test fun durableRoundTripRetainsProviderReceiptAndReadFirstBarrier() {
        val storage = MemoryStorage()
        val recovered = recover()!!
        SharedPreferencesAgentSessionStore(storage).save(AgentSessionSnapshot("runtime", AgentPhase.PLANNING,
            recovered.goal, recovered.screen, recovered, emptyList(), receipt(), updatedAtMillis = 1000))
        val restored = SharedPreferencesAgentSessionStore(storage).load()!!.currentPlan!!
        assertEquals(recovered.actions, restored.actions)
        assertEquals(recovered.actionHistory, restored.actionHistory)
        assertNotNull(violation(restored.actions.single(), restored.actionHistory, listOf(origin())))
    }

    @Test fun compactFallbackRetainsOriginAndBarrierEvenWithNoisyMetadata() {
        val recovered = recover()!!
        val noisy = (1..40).associate { "extra-$it" to "value-$it" }
        val connector = recovered.actions.single().let { it.copy(parameters = noisy + it.parameters) }
        val history = recovered.actionHistory + (1..20).map { read().copy(id = "old-$it") }
        for (minimal in listOf(false, true)) {
            val compact = AgentSessionPersistencePolicy.compactRecoveryPlan(recovered.copy(
                actions = listOf(connector), actionHistory = history), connector.id, minimal)
            val restored = compact.actions.single()
            assertEquals(origin().id, restored.parameters[originKey])
            assertEquals("true", restored.parameters[phoneKey])
            assertTrue(compact.actionHistory.any { it.id == origin().id })
            assertTrue(AgentRecoveryObservationEvidence.hasContract(compact.actionHistory.first { it.id == origin().id }))
            assertNull(violation(restored, compact.actionHistory.filter { it.id == origin().id } + read(), listOf(origin())))
            assertTrue(AgentUnverifiedOutcomeRecovery.isPhoneControl(request().copy(executionHistory = listOf(restored))))
        }
    }

    @Test fun audioToolsAreExposedWithoutAddingSensitiveAndroidTools() {
        for (tool in listOf(readTool, writeTool, AgentAndroidSystemNativeTools.AUDIO_MUTE_SET)) {
            assertTrue(PhoneAssistantToolPolicy.allowsRemotePhoneTool(tool))
        }
        for (tool in listOf("galaxyssi.android.sms.send", "galaxyssi.android.contacts.delete", "unknown.tool")) {
            assertFalse(PhoneAssistantToolPolicy.allowsRemotePhoneTool(tool))
        }
    }

    @Test fun explicitReceiptUnknownFieldsAreNotMisdiagnosedAsFailedJson() {
        for (evidence in listOf("""{"state_verified":false}""", """{"output":{"delivery_verified":false}}""",
            """{"outcome_state":"unknown","output":{}}""",
            """{"metadata":{"goal_status":"dispatched"}}""", """{"outcome_state":"unknown"}""")) {
            assertTrue(AgentSupervisedProjectRecoveryPolicy.hasUnknownOutcome(origin().copy(evidence = evidence)))
        }
        for (evidence in listOf("invalid", "{}", """{"state_verified":true}""", """{"outcome_state":"failed"}""")) {
            assertFalse(AgentSupervisedProjectRecoveryPolicy.hasUnknownOutcome(origin().copy(evidence = evidence)))
        }
    }

    private fun recover(plan: AgentPlan = plan()) = AgentUnverifiedOutcomeRecovery.create(plan, origin(), receipt(), request(), provider())
    private fun violation(connector: AgentAction, history: List<AgentAction>, actions: List<AgentAction>) =
        AgentUnverifiedOutcomeRecovery.observationViolation(connector, history, actions, ::descriptor)
    private fun origin() = AgentAction("original-effect", AgentActionKind.CALL_NATIVE_TOOL, writeTool, AgentRisk.LOW,
        AgentActionStatus.COMPLETED, "Set media volume", mapOf("tool_id" to writeTool,
            INTERNAL_CONVERSATION_ID to "conversation", INTERNAL_TURN_ID to "turn"), requiresConfirmation = false,
        evidence = JSONObject("""{"state_verified":false,"requested_level":4,"current_level":3,"metadata":{"goal_status":"unknown"}}""")
            .put(AgentRecoveryObservationEvidence.KEY, proof(writeTool, "effect-invocation", 90, 100)
                .put("recovery_query", JSONObject(AgentNativeEffectRecoveryQuery(readTool, "1.0.0", emptyMap(),
                    mapOf("/streams/media/stream" to "media")).toJsonValue()))).toString())
    private fun receipt() = AgentActionResult(origin().id, true, "Unverified", mapOf("goal_status" to "unknown",
        "native_tool_id" to writeTool, "native_tool_output" to origin().evidence))
    private fun plan(action: AgentAction = origin()) = AgentPlan("Set media volume", request().screen, emptyList(), listOf(action),
        planId = "original-plan", completionRequirements = requirements)
    private fun provider() = AgentAction("selected-provider", AgentActionKind.CALL_CONNECTOR, "Selected model", AgentRisk.LOW,
        AgentActionStatus.PROPOSED, "Reason", parameters = mapOf("connector_id" to "selected", "model_id" to "user-model",
            "manual_model_id" to "user-model", "manual_target_locked" to "true", "agent_reasoning_effort" to "high"))
    private fun read(tool: String = readTool) = AgentAction("read-state", AgentActionKind.CALL_NATIVE_TOOL, tool, AgentRisk.LOW,
        AgentActionStatus.COMPLETED, "Inspect", mapOf("tool_id" to tool, INTERNAL_CONVERSATION_ID to "conversation",
            INTERNAL_TURN_ID to "turn"), evidence = JSONObject("""{"streams":{"media":{"stream":"media","current":3}}}""")
            .put(AgentRecoveryObservationEvidence.KEY, proof(tool, "read-invocation", 110, 120)).toString())
    private fun proof(tool: String, invocation: String, start: Long, finish: Long) = JSONObject()
        .put("tool_id", tool).put("tool_version", "1.0.0").put("status", "succeeded")
        .put("invocation_id", invocation).put("input_sha256", AgentNativeJsonCodec.sha256(emptyMap<String, Any>()))
        .put("replayed", false).put("started_at_ms", start).put("finished_at_ms", finish)
        .put("conversation_id", "conversation").put("turn_id", "turn")
    private fun editRead(edit: (JSONObject) -> Unit): AgentAction = read().let {
        it.copy(evidence = JSONObject(it.evidence).apply(edit).toString())
    }
    private fun descriptor(tool: String): AgentNativeToolDescriptor? {
        if (tool !in AgentToolInspectionTools.toolIds && tool !in listOf(readTool, writeTool)) return null
        return AgentNativeToolDescriptor(tool, "1.0.0", "Test", "Test observation", AgentNativeToolLocation.PHONE,
            AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW,
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
            effect = if (tool == writeTool) AgentNativeToolEffect.MUTATION else AgentNativeToolEffect.READ_ONLY)
    }
    private fun request(goal: String = "Set media volume"): AgentRequest {
        val screen = ScreenContext("com.galaxyssi.chat", pageTitle = "Test")
        val targets = listOf(AgentCallableTarget("selected", "Selected model", AgentConnectorKind.MODEL,
            AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.REASONING)))
        return AgentRequest(goal, screen, targets, memories = emptyList(), executionTurnId = "turn",
            conversationContext = AgentConversationContext("conversation", "", emptyList(), false),
            runtimeContext = AgentRuntimeContextBuilder.build("runtime", goal, screen, PermissionMode.FULL_ACCESS,
                false, false, emptyList(), emptyList(), nativeTools = listOf(descriptor(readTool)!!, descriptor(writeTool)!!)))
    }
    private class MemoryStorage : AgentSessionCheckpointStorage {
        val values = linkedMapOf<String, String>()
        override fun encodedValueLength(key: String) = values[key]?.length ?: 0
        override fun readString(key: String, defaultValue: String) = values[key] ?: defaultValue
        override fun writeString(key: String, value: String) { values[key] = value }
        override fun remove(key: String) { values.remove(key) }
        override fun keys() = values.keys.toSet()
    }
}
