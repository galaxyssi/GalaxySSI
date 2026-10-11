package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationWorkflowCheckTest {
    private fun arguments(x: CollaborationWorkflowSelectionTest.Fixture, inputs: Any = x.inputs()) = mapOf<String, Any?>(
        "mode" to CollaborationWorkflowCheck.MODE, "object_id" to x.rule.getString("object_id"),
        "revision" to x.rule.getInt("revision"), "sha256" to x.rule.getString("sha256"), "inputs" to inputs)
    private fun inspect(x: CollaborationWorkflowSelectionTest.Fixture, input: Map<String, Any?> = arguments(x)) =
        CollaborationWorkflowCheck.inspect(input, x.f.reopen(), x.f.access(round = 20))

    @Test fun knownApplicableInputsExposeExactMethodsWithoutExecutingOrCertifying() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        val result = inspect(x)
        assertEquals("candidate", result.getJSONObject("selection").getString("variant"))
        assertEquals(x.t.method.getString("sha256"), result.getJSONObject("baseline_method").getString("sha256"))
        assertEquals(x.candidate.getString("sha256"), result.getJSONObject("candidate_method").getString("sha256"))
        assertFalse(result.getBoolean("executes_work"))
        assertFalse(result.getBoolean("grants_permissions"))
        assertFalse(result.getBoolean("baseline_applicability_verified"))
        assertTrue(result.isNull("quality_effect"))
        assertFalse(result.getBoolean("unknowns_may_change_selection"))
        assertEquals("declared_unverified_not_a_tool_observation", result.getString("input_evidence"))
        assertEquals(0, x.f.reopen().methodHistory(x.f.access(round = 20), x.candidate).getJSONArray("records").length())
    }

    @Test fun missingCounterconditionCanMotivateEvidenceWithoutCallingBaselineValid() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        val values = x.inputs().apply { getJSONObject("dataset").remove("mutable") }
        val result = inspect(x, arguments(x, values))
        assertTrue(result.getBoolean("unknowns_may_change_selection"))
        assertEquals("mutable", result.getJSONArray("unknown_conditions").getString(0))
        val condition = result.getJSONArray("unless_any").getJSONObject(0)
        assertEquals("pointer_unavailable", condition.getString("unknown_reason"))
        assertEquals("/mutable", condition.getString("pointer"))
        assertTrue(condition.getBoolean("resolving_unknown_may_change_selection"))
        assertFalse(result.getBoolean("baseline_applicability_verified"))
    }

    @Test fun alreadyKnownBlockersMakeOtherUnknownsIrrelevantToThisSelection() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        for ((values, blocker) in listOf(x.inputs(mutable = true).apply { getJSONObject("dataset").remove("repetitions") } to "mutable",
            x.inputs(1).apply { getJSONObject("dataset").remove("mutable") } to "repeated")) {
            val result = inspect(x, arguments(x, values))
            assertEquals(1, result.getJSONArray("unknown_conditions").length())
            assertEquals(blocker, result.getJSONArray("known_blockers").getString(0))
            assertFalse(result.getBoolean("unknowns_may_change_selection"))
        }
    }

    @Test fun allMissingInputsAndNativeMapsAreAcceptedButNotSilentlyFilled() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        val result = inspect(x, arguments(x, emptyMap<String, Any>()))
        assertEquals(2, result.getJSONArray("unknown_conditions").length())
        assertEquals("input_missing", result.getJSONArray("when_all").getJSONObject(0).getString("unknown_reason"))
        val map = mapOf("dataset" to mapOf("repetitions" to 3, "mutable" to false))
        assertEquals("candidate", inspect(x, arguments(x, map)).getJSONObject("selection").getString("variant"))
    }

    @Test fun noTypeCoercionAndInputRuleSnapshotsStayUnchangedAcrossReopen() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        val values = x.inputs("3")
        val before = values.toString() to x.savedRule().toString()
        val result = inspect(x, arguments(x, values))
        val condition = result.getJSONArray("when_all").getJSONObject(0)
        assertEquals("type_mismatch", condition.getString("unknown_reason"))
        assertEquals("string", condition.getString("actual_type"))
        assertEquals(before, values.toString() to x.savedRule().toString())
        assertEquals(result.toString(), inspect(x, arguments(x, values)).toString())
    }

    @Test fun inspectionDoesNotChangeExistingFallbackDispatchOrRecoveryBindings() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        val values = x.inputs().apply { getJSONObject("dataset").remove("mutable") }
        val before = x.admit(x.instance(values)).claims
        inspect(x, arguments(x, values))
        assertEquals(before, x.admit(x.instance(values)).claims)
    }

    @Test fun wrongIdentityOtherGroupsAndIndependentAssignmentsCannotInspect() {
        val x = CollaborationWorkflowSelectionTest.Fixture(); val args = arguments(x)
        for (change in listOf(mapOf("sha256" to "0".repeat(64)), mapOf("object_id" to x.candidate.getString("object_id"))))
            assertTrue(runCatching { inspect(x, args + change) }.isFailure)
        for (access in listOf(x.f.access(round = 20).copy(groupId = "other"), x.f.access("independent", 12)))
            assertTrue(runCatching { CollaborationWorkflowCheck.inspect(args, x.f.reopen(), access) }.isFailure)
    }

    @Test fun staleLineageCannotMasqueradeAsCurrentApplicability() {
        val x = CollaborationWorkflowSelectionTest.Fixture(); val args = arguments(x)
        val raw = JSONObject(x.f.raw("revise-idea", "innovation", x.idea(x.candidate)))
        raw.getJSONArray("workspace").getJSONObject(0).put("object_id", x.after.getString("object_id")).put("base_revision", 1)
        assertEquals("recorded", x.f.workspace.publish(x.f.access("selection-after", 21, "revise-idea"), raw.toString(), 1500).getString("status"))
        assertTrue(runCatching { inspect(x, args) }.isFailure)
    }

    @Test fun exactHostSharedRevisionCanBeInspectedWithoutOpeningOtherCurrentWork() {
        val x = CollaborationWorkflowSelectionTest.Fixture(); val args = arguments(x)
        val isolated = x.f.access("independent", 12)
        assertTrue(runCatching { CollaborationWorkflowCheck.inspect(args, x.f.reopen(), isolated) }.isFailure)
        val shared = isolated.copy(pinnedReads = setOf(requireNotNull(CollaborationMilestoneDispatch.grant(x.rule))))
        assertEquals("candidate", CollaborationWorkflowCheck.inspect(args, x.f.reopen(), shared).getJSONObject("selection").getString("variant"))
        assertTrue(runCatching { CollaborationWorkflowCheck.inspect(args, x.f.reopen(),
            isolated.copy(pinnedReads = setOf(requireNotNull(CollaborationMilestoneDispatch.grant(x.candidate)))) ) }.isFailure)
    }

    @Test fun invalidSelectorsOversizedInputsAndForeignInputNamesFailBeforeUse() {
        val x = CollaborationWorkflowSelectionTest.Fixture(); val args = arguments(x)
        val changes = listOf(mapOf("inputs" to "{}"), mapOf("inputs" to JSONArray()), mapOf("revision" to 1.5),
            mapOf("offset" to -1), mapOf("offset" to 0.5), mapOf("group_id" to "other"), mapOf("cursor" to ""),
            mapOf("inputs" to JSONObject().put("foreign", true)), mapOf("inputs" to x.inputs("x".repeat(4096))))
        for (change in changes) assertTrue(change.toString(), runCatching { inspect(x, args + change) }.isFailure)
        for (key in args.keys) assertTrue(key, runCatching { inspect(x, args - key) }.isFailure)
    }

    @Test fun conditionalUncertaintyIsNotClaimedAsJointSatisfiabilityOrProbeValue() {
        val x = CollaborationWorkflowSelectionTest.Fixture()
        x.ruleSpec.put("when_all", JSONArray().put(x.condition("high", "/repetitions", "gt", 10))
            .put(x.condition("low", "/repetitions", "lt", 0))).put("unless_any", JSONArray())
        val result = inspect(x, arguments(x, JSONObject()))
        assertTrue(result.getBoolean("unknowns_may_change_selection"))
        assertTrue(result.getString("decision_scope").contains("no joint satisfiability"))
        assertFalse(result.has("expected_information_gain"))
    }
}
