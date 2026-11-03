package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST

class CollaborationNumericModelTrialTest {
    private class Fixture {
        val rows = CollaborationEvolutionTest.Rows()
        var authorized = true
        fun reopen() = CollaborationResearchWorkspace(rows, { authorized })
        val workspace = reopen()
        fun access(person: String = "researcher", round: Long = 1) = CollaborationWorkspaceAccess("group", "run", "turn", round, "node-$round", person)
        fun spec() = JSONObject("""{"id":"numeric_model_cases.v1","variables":["x"],"cases":[
            {"id":"positive","input":{"x":2},"expected":4,"absolute_tolerance":0},
            {"id":"negative","input":{"x":-3},"expected":9,"absolute_tolerance":0}]}""")
        fun value(model: String = """{"op":"mul","args":[{"constant":2},{"variable":"x"}]}""") = JSONObject()
            .put("purpose", "Test the proposed response curve").put("reference_basis", "Synthetic supplied numbers, not physical observations")
            .put("limitations", "Two visible cases only; no generalization claim").put("validator", spec())
            .put("computation", JSONObject().put("validator_id", "numeric_model_cases.v1").put("model", JSONObject(model)))
        fun publish(value: JSONObject = value(), id: String = "first", round: Long = 1, parents: JSONArray = JSONArray(),
                    person: String = "researcher", extra: (JSONObject) -> Unit = {}): JSONObject {
            val item = JSONObject().put("id", id).put("kind", CollaborationNumericModelTrial.KIND).put("title", id)
                .put("body", JSONObject().put("content", "Numeric candidate").put(CollaborationNumericModelTrial.KIND, value)).put("parents", parents)
            extra(item)
            return workspace.publish(access(person, round), JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
                .put("summary", "Actual host replay, not empirical validation").put("findings", JSONArray()).put("candidates", JSONArray())
                .put("workspace", JSONArray().put(item)).toString())
        }
        fun saved(report: JSONObject): JSONObject {
            assertEquals(report.toString(), "recorded", report.getString("status"))
            val ref = report.getJSONArray("revisions").getJSONObject(0)
            return workspace.read(access(round = 10), ref.getString("object_id"), ref.getInt("revision"))!!
        }
        fun reference(record: JSONObject) = CollaborationResearchCandidates.reference(record)
    }

    @Test fun failedTrialIsSavedAndPeerCanUseItsCounterexampleToRevise() {
        val f = Fixture()
        val first = f.saved(f.publish())
        val ref = f.reference(first)
        assertFalse(first.getJSONObject(HOST).getJSONObject("evaluation").getBoolean("passed"))
        val changed = f.value("""{"op":"mul","args":[{"variable":"x"},{"variable":"x"}]}""").put("previous_trial", ref)
        val second = f.saved(f.publish(changed, "corrected", 2, JSONArray().put(ref), "peer"))
        val host = second.getJSONObject(HOST)
        assertTrue(host.getJSONObject("evaluation").getBoolean("passed"))
        assertEquals("[\"negative\"]", host.getJSONObject("comparison").getJSONArray("improved_case_ids").toString())
        assertEquals(0, host.getJSONObject("comparison").getJSONArray("regressed_case_ids").length())
        assertTrue(host.getJSONObject("comparison").getBoolean("model_changed"))
        for (field in listOf("eligible_for_retention", "reference_truth_verified", "goal_accepted", "automatically_installed")) assertFalse(host.getBoolean(field))
        val restored = f.reopen().read(f.access(round = 11), first.getString("object_id"), 1)!!
        assertEquals(first.getString("sha256"), restored.getString("sha256"))
        assertFalse(restored.getJSONObject(HOST).getJSONObject("evaluation").getBoolean("passed"))
    }

    @Test fun localImprovementDoesNotHideARegressionOnAnotherCase() {
        val f = Fixture()
        val first = f.saved(f.publish(f.value("""{"constant":4}""")))
        val ref = f.reference(first)
        val second = f.saved(f.publish(f.value("""{"constant":9}""").put("previous_trial", ref), "changed", 2, JSONArray().put(ref)))
        val comparison = second.getJSONObject(HOST).getJSONObject("comparison")
        assertEquals("[\"negative\"]", comparison.getJSONArray("improved_case_ids").toString())
        assertEquals("[\"positive\"]", comparison.getJSONArray("regressed_case_ids").toString())
        assertEquals(1, comparison.getInt("current_failed_cases"))
        assertFalse(second.getJSONObject(HOST).getBoolean("eligible_for_retention"))
    }

    @Test fun noOpRevisionIsExplicitAndDoesNotInventProgress() {
        val f = Fixture(); val first = f.saved(f.publish()); val ref = f.reference(first)
        val second = f.saved(f.publish(f.value().put("previous_trial", ref), "unchanged", 2, JSONArray().put(ref)))
        val comparison = second.getJSONObject(HOST).getJSONObject("comparison")
        assertFalse(comparison.getBoolean("model_changed"))
        assertEquals(0, comparison.getJSONArray("improved_case_ids").length())
        assertEquals(0, comparison.getJSONArray("error_reduced_case_ids").length())
        assertEquals(0, comparison.getJSONArray("error_increased_case_ids").length())
    }

    @Test fun reducedErrorsRemainVisibleWhileBothVersionsStillFail() {
        val f = Fixture(); val first = f.saved(f.publish(f.value("""{"constant":0}"""))); val ref = f.reference(first)
        val second = f.saved(f.publish(f.value("""{"constant":3}""").put("previous_trial", ref), "closer", 2, JSONArray().put(ref)))
        val comparison = second.getJSONObject(HOST).getJSONObject("comparison")
        assertEquals(2, comparison.getInt("previous_failed_cases"))
        assertEquals(2, comparison.getInt("current_failed_cases"))
        assertEquals(0, comparison.getJSONArray("improved_case_ids").length())
        assertEquals(2, comparison.getJSONArray("error_reduced_case_ids").length())
        assertEquals(0, comparison.getJSONArray("error_increased_case_ids").length())
        assertFalse(second.getJSONObject(HOST).getBoolean("eligible_for_retention"))
    }

    @Test fun domainTransitionsAreReportedWithoutMakingUpErrorImprovements() {
        val f = Fixture(); val first = f.saved(f.publish(f.value("""{"op":"div","args":[{"constant":1},{"constant":0}]}""")))
        val ref = f.reference(first)
        val second = f.saved(f.publish(f.value("""{"constant":3}""").put("previous_trial", ref), "finite", 2, JSONArray().put(ref)))
        val comparison = second.getJSONObject(HOST).getJSONObject("comparison")
        assertEquals(2, comparison.getJSONArray("domain_recovered_case_ids").length())
        assertEquals(0, comparison.getJSONArray("error_reduced_case_ids").length())
        assertEquals(2, comparison.getInt("current_failed_cases"))
        val next = f.reference(second)
        val third = f.saved(f.publish(f.value("""{"op":"log","args":[{"constant":-1}]}""").put("previous_trial", next),
            "invalid-domain", 3, JSONArray().put(next)))
        assertEquals(2, third.getJSONObject(HOST).getJSONObject("comparison").getJSONArray("domain_failed_case_ids").length())
    }

    @Test fun computedErrorCanHaveMoreDigitsThanEitherInput() {
        val f = Fixture()
        val spec = f.spec().apply { val cases = getJSONArray("cases"); repeat(cases.length()) { cases.getJSONObject(it).put("expected", "1e-128") } }
        val first = f.saved(f.publish(f.value("""{"constant":"1e128"}""").put("validator", spec)))
        val ref = f.reference(first)
        val second = f.saved(f.publish(f.value("""{"constant":0}""").put("validator", spec).put("previous_trial", ref),
            "closer", 2, JSONArray().put(ref)))
        assertEquals(2, second.getJSONObject(HOST).getJSONObject("comparison").getJSONArray("error_reduced_case_ids").length())
    }

    @Test fun changedCasesMissingParentsOrWrongDigestCannotBecomeSameCaseImprovement() {
        for (reason in listOf("cases", "parents", "digest")) {
            val f = Fixture(); val first = f.saved(f.publish()); val ref = f.reference(first)
            val value = f.value().put("previous_trial", ref)
            if (reason == "cases") value.getJSONObject("validator").getJSONArray("cases").getJSONObject(1).put("expected", -6)
            if (reason == "digest") ref.put("sha256", "0".repeat(64))
            val parents = if (reason == "parents") JSONArray() else JSONArray().put(ref)
            assertEquals(reason, "rejected", f.publish(value, "bad", 2, parents).getString("status"))
        }
    }

    @Test fun trialsAreImmutableAndCannotBeReadAcrossGroups() {
        val f = Fixture(); val first = f.saved(f.publish()); val ref = f.reference(first)
        assertEquals("rejected", f.publish(f.value("""{"constant":4}"""), "changed", 2) {
            it.put("object_id", ref.getString("object_id")).put("base_revision", 1)
        }.getString("status"))
        assertNull(f.reopen().read(f.access(round = 10).copy(groupId = "other"), first.getString("object_id"), 1))
        f.authorized = false
        assertNull(f.reopen().read(f.access(round = 10), first.getString("object_id"), 1))
    }

    @Test fun allDomainErrorsHaveNoInventedFiniteErrorScore() {
        val f = Fixture()
        val record = f.saved(f.publish(f.value("""{"op":"div","args":[{"constant":1},{"constant":0}]}""")))
        val report = record.getJSONObject(HOST).getJSONObject("evaluation")
        assertEquals(0, report.getInt("finite_cases"))
        assertEquals(2, report.getInt("domain_error_cases"))
        assertTrue(report.isNull("max_absolute_error_on_finite_cases"))
        assertEquals(2, report.getJSONArray("checks").length())
    }

    @Test fun malformedExpressionsAndMissingSourceQualificationsAreNotRecordedAsTrials() {
        val f = Fixture()
        assertEquals("rejected", f.publish(f.value("""{"source":"not an expression"}""")).getString("status"))
        assertEquals("rejected", f.publish(f.value().put("reference_basis", "")).getString("status"))
        assertEquals("rejected", f.publish(f.value().put("passed", true)).getString("status"))
    }

    @Test fun schemasAreDiscoverableWithoutIncreasingEveryMemberPromptByFullRules() {
        assertTrue(CollaborationEvolutionProtocol.instructions().contains("numeric_model_trial"))
        val rules = CollaborationEvolutionProtocol.rules("tools").getString("contract")
        assertTrue(rules.contains(CollaborationNumericModelTrial.rules()))
        assertFalse(CollaborationEvolutionProtocol.instructions().contains("2000000"))
        assertTrue(CollaborationResearchWorkspace.KINDS.contains(CollaborationNumericModelTrial.KIND))
    }
}
