package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentPendingOutcomeEvidenceTest {
    private val write = "galaxyssi.fixture.write"
    private val read = "galaxyssi.fixture.read"
    private val scope = AgentPlanContinuationScope("conversation", "turn")

    @Test fun aLaterVerifiedActionCannotEraseAnotherActionsUncertainty() {
        val verified = origin("b").copy(evidence = """{"metadata":{"goal_status":"verified"}}""")
        val pending = AgentGoalEvidence.pendingReceipts(listOf(origin("a"), verified))
        assertEquals(listOf("effect-a"), pending.map { it.actionId })
        assertEquals("effect-a", AgentGoalEvidence.pendingReceipt(listOf(origin("a"), verified))?.actionId)
    }

    @Test fun onlyTheLatestSnapshotOfTheSameLogicalActionIsUsed() {
        val old = origin("a")
        val verified = old.copy(evidence = """{"metadata":{"goal_status":"verified"}}""")
        assertTrue(AgentGoalEvidence.pendingReceipts(listOf(old, verified)).isEmpty())
        assertEquals(1, AgentGoalEvidence.pendingReceipts(listOf(old, old)).size)
    }

    @Test fun undispatchedActionsDoNotInventUncertainSideEffects() {
        for (status in listOf(AgentActionStatus.PROPOSED, AgentActionStatus.PENDING_CONFIRMATION)) {
            val action = origin("a").copy(status = status)
            assertTrue(AgentGoalEvidence.pendingReceipts(listOf(action)).isEmpty())
            assertTrue(AgentGoalEvidence.pendingReceipts(listOf(action.supersededByPlanRevision(1, 2))).isEmpty())
        }
    }

    @Test fun legacyDeliveryAndEnvelopeCaveatsRemainUnverified() {
        for (evidence in listOf("""{"delivery_verified":false}""", """{"outcome_state":"unknown","output":{}}""",
            """{"metadata":{"goal_status":"verified","business_success_verified":"false"}}""")) {
            assertEquals(1, AgentGoalEvidence.pendingReceipts(listOf(origin("a").copy(evidence = evidence))).size)
        }
    }

    @Test fun aDefinitiveFailedOrBlockedAttemptIsNotAnUncertainAcceptedEffect() {
        for ((status, goalStatus) in listOf(AgentActionStatus.FAILED to "failed", AgentActionStatus.BLOCKED to "blocked")) {
            val failed = origin("a").copy(status = status,
                evidence = """{"metadata":{"goal_status":"$goalStatus","business_success_verified":"false"}}""")
            assertTrue(AgentGoalEvidence.pendingReceipts(listOf(failed)).isEmpty())
            val unknown = failed.copy(evidence = JSONObject(failed.evidence).put("outcome_state", "unknown").toString())
            assertEquals(1, AgentGoalEvidence.pendingReceipts(listOf(unknown)).size)
        }
    }

    @Test fun exactFreshObservationAndPostconditionResolveTheOriginalEffect() {
        assertTrue(unresolved(listOf(origin("a"), observation("a")), listOf(outcome("a"))).isEmpty())
    }

    @Test fun unrelatedSatisfiedOutcomeCannotResolveTheEffect() {
        val pending = unresolved(listOf(origin("a"), observation("a"), observation("b")), listOf(outcome("b")))
        assertEquals("effect-a", pending.single().receipt.actionId)
        assertTrue(pending.single().diagnosis.startsWith("postcondition_binding_missing"))
        assertTrue(pending.single().missingEvidence().contains("Unrelated success"))
    }

    @Test fun everyUncertainEffectMustHaveItsOwnEvidence() {
        val history = listOf(origin("a"), origin("b"), observation("a"))
        assertEquals(listOf("effect-b"), unresolved(history, listOf(outcome("a"), outcome("b"))).map { it.receipt.actionId })
        assertTrue(unresolved(history + observation("b"), listOf(outcome("a"), outcome("b"))).isEmpty())
    }

    @Test fun aProvenDifferentMutationSubjectDoesNotInvalidateTheFirstObservation() {
        val history = listOf(origin("a"), observation("a"), origin("b", finished = 300), observation("b", started = 400))
        assertTrue(unresolved(history, listOf(outcome("a"), outcome("b"))).isEmpty())
        assertTrue(AgentObservedOutcomeEvidence.missing(listOf(outcome("a"), outcome("b")), history).isEmpty())
    }

    @Test fun anUnknownMutationSubjectStillInvalidatesOlderObservation() {
        val unknown = origin("b", finished = 300).copy(evidence = "{}")
        val history = listOf(origin("a"), observation("a"), unknown)
        assertFalse(unresolved(history, listOf(outcome("a"))).isEmpty())
    }

    @Test fun replayedStaleOrForeignObservationsCannotResolveAnEffect() {
        val changes: List<(JSONObject) -> Unit> = listOf(
            { it.put("replayed", true) }, { it.put("started_at_ms", 99) },
            { it.put("conversation_id", "other") }, { it.put("turn_id", "other") },
            { it.put("invocation_id", "effect-invocation-a") }, { it.put("tool_version", "2.0.0") },
            { it.put("input_sha256", "other-input") }, { it.put("status", "failed") })
        for (change in changes) {
            val action = observation("a").let { it.copy(evidence = JSONObject(it.evidence).apply {
                change(getJSONObject(AgentRecoveryObservationEvidence.KEY))
            }.toString()) }
            assertFalse(unresolved(listOf(origin("a"), action), listOf(outcome("a"))).isEmpty())
        }
    }

    @Test fun theReceiptPassingProvenanceMustBeTheOneThatPassesChecks() {
        val bound = observation("a", value = 3)
        val otherInput = observation("a").copy(id = "other-input", evidence = JSONObject(observation("a").evidence).apply {
            getJSONObject(AgentRecoveryObservationEvidence.KEY).put("input_sha256", "other-input")
        }.toString())
        assertEquals("bound_postcondition_not_satisfied",
            unresolved(listOf(origin("a"), bound, otherInput), listOf(outcome("a"))).single().diagnosis)
    }

    @Test fun newerFailureCannotBorrowAnOlderSuccessfulRead() {
        val failed = observation("a").copy(id = "failed-read", status = AgentActionStatus.FAILED)
        assertFalse(unresolved(listOf(origin("a"), observation("a"), failed), listOf(outcome("a"))).isEmpty())
    }

    @Test fun missingContractOrAffectedIdentityCannotBeInventedByTheModel() {
        val missing = origin("a").copy(evidence = """{"state_verified":false}""")
        assertEquals("origin_observation_contract_missing",
            unresolved(listOf(missing, observation("a")), listOf(outcome("a"))).single().diagnosis)
        val unbound = outcome("a").copy(subject = mapOf("/scope" to "all"))
        assertTrue(unresolved(listOf(origin("a"), observation("a")), listOf(unbound)).single().diagnosis
            .startsWith("postcondition_binding_missing"))
        val noAfter = outcome("a").copy(afterToolId = "")
        assertFalse(unresolved(listOf(origin("a"), observation("a")), listOf(noAfter)).isEmpty())
    }

    @Test fun ordinaryReadOnlyResultsNeedNoRecoveryContract() {
        assertTrue(unresolved(listOf(observation("a")), listOf(outcome("a").copy(afterToolId = ""))).isEmpty())
    }

    @Test fun unavailableOrInvalidOriginContractsCannotStartAnImpossibleRepairLoop() {
        val noContract = origin("a").copy(evidence = """{"delivery_verified":false}""")
        assertFalse(unresolved(listOf(noContract), listOf(outcome("a"))).single().canInspect)
        val wrongScope = origin("a").copy(parameters = origin("a").parameters + (INTERNAL_TURN_ID to "other"))
        assertFalse(unresolved(listOf(wrongScope), listOf(outcome("a"))).single().canInspect)
        val unavailable = AgentPendingOutcomeEvidence.unresolved(requirements(listOf(outcome("a"))),
            listOf(origin("a"))) { null }
        assertFalse(unavailable.single().canInspect)
        assertTrue(unresolved(listOf(origin("a")), listOf(outcome("a"))).single().canInspect)
        assertTrue(unresolved(listOf(origin("a"), observation("a", value = 3)), listOf(outcome("a"))).single().canInspect)
    }

    @Test fun checkpointRestoreRetainsEachUnresolvedEffectWithoutExecutingAgain() {
        val values = linkedMapOf<String, String>()
        val storage = object : AgentSessionCheckpointStorage {
            override fun encodedValueLength(key: String) = values[key]?.length ?: 0
            override fun readString(key: String, defaultValue: String) = values[key] ?: defaultValue
            override fun writeString(key: String, value: String) { values[key] = value }
            override fun remove(key: String) { values.remove(key) }
            override fun keys() = values.keys.toSet()
        }
        val plan = plan().copy(actionHistory = listOf(origin("a"), origin("b"), observation("a")),
            completionRequirements = requirements(listOf(outcome("a"), outcome("b"))))
        SharedPreferencesAgentSessionStore(storage).save(AgentSessionSnapshot("session", AgentPhase.WAITING_RESPONSE,
            plan.goal, plan.screen, plan, emptyList(), null, updatedAtMillis = 1000))
        val restored = SharedPreferencesAgentSessionStore(storage).load()!!.currentPlan!!
        assertEquals(listOf("effect-b"), AgentPendingOutcomeEvidence.unresolved(restored.completionRequirements,
            AgentCompletionEvidenceHistory.resolve(restored, scope), ::descriptor).map { it.receipt.actionId })
    }

    @Test fun blockedDeliveryIsNotACompletedBusinessOutcome() {
        val receipt = AgentGoalEvidence.PendingReceipt("Delivery is not confirmed", "recipient_delivery_receipt",
            "inspect_delivery", "send-a", "galaxyssi.fixture.send")
        val decision = AgentSupervisedProjectPlanDecision.blockedResponse(plan(), listOf(receipt))
        val result = decision.finalResult(AgentActionResult("planner", true, "Model returned"))
        assertEquals(AgentPhase.BLOCKED, decision.finalPhase)
        assertTrue(decision.semanticallyAccepted)
        assertFalse(result.success)
        assertFalse(AgentGoalEvidence.permitsSuccess(result))
        assertTrue(result.metadata.getValue("unverified_outcomes").contains("send-a"))
        assertEquals("Delivery is not confirmed", result.message)
        val ordinary = AgentSupervisedProjectPlanDecision.finalResponse("An explanatory answer")
        assertEquals(AgentPhase.COMPLETED, ordinary.finalPhase)
        assertTrue(ordinary.finalResult(AgentActionResult("planner", true, "Answer")).success)
    }

    private fun unresolved(history: List<AgentAction>, outcomes: List<AgentObservedOutcome>) =
        AgentPendingOutcomeEvidence.unresolved(requirements(outcomes), history, ::descriptor)
    private fun requirements(outcomes: List<AgentObservedOutcome>) =
        AgentCompletionRequirements(AgentPublicationRequirement.NONE, false, outcomes = outcomes)
    private fun outcome(id: String) = AgentObservedOutcome("outcome-$id", read,
        mapOf("/id" to id), mapOf("/value" to 4), afterToolId = write)
    private fun origin(id: String, finished: Long = 100) = action("effect-$id", write,
        JSONObject().put("id", id).put("state_verified", false).put("message", "Outcome $id not verified")
            .put("metadata", JSONObject().put("goal_status", "unknown"))
            .put(AgentRecoveryObservationEvidence.KEY, proof(write, "effect-invocation-$id", id, finished - 10, finished)
                .put("recovery_query", JSONObject(AgentNativeEffectRecoveryQuery(read, "1.0.0",
                    mapOf("id" to id), mapOf("/id" to id)).toJsonValue()))).toString())
    private fun observation(id: String, value: Int = 4, started: Long = 200) = action("read-$id", read,
        JSONObject().put("id", id).put("value", value).put("scope", "all")
            .put(AgentRecoveryObservationEvidence.KEY, proof(read, "read-invocation-$id", id, started, started + 10)).toString())
    private fun action(id: String, tool: String, evidence: String) = scope.bind(AgentAction(id,
        AgentActionKind.CALL_NATIVE_TOOL, tool, AgentRisk.LOW, AgentActionStatus.COMPLETED, "Fixture",
        mapOf("tool_id" to tool), evidence = evidence))
    private fun proof(tool: String, invocation: String, subject: String, start: Long, finish: Long) = JSONObject()
        .put("tool_id", tool).put("tool_version", "1.0.0").put("status", "succeeded")
        .put("invocation_id", invocation).put("input_sha256", AgentNativeJsonCodec.sha256(mapOf("id" to subject)))
        .put("replayed", false).put("started_at_ms", start).put("finished_at_ms", finish)
        .put("conversation_id", "conversation").put("turn_id", "turn")
    private fun descriptor(tool: String) = if (tool != read) null else AgentNativeToolDescriptor(read, "1.0.0",
        "Inspect", "Read fixture", AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(),
        AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW, idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
        effect = AgentNativeToolEffect.READ_ONLY)
    private fun plan() = AgentPlan("Two results", ScreenContext("Test", pageTitle = "Test"), emptyList(), emptyList())
}
