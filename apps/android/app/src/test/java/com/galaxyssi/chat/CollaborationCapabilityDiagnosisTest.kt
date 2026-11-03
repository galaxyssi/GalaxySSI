package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationCapabilityDiagnosisTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var fail = false
        override fun read(key: String) = data[key]
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
        override fun commit(values: Map<String, String>) { check(!fail); data.putAll(values) }
    }
    private fun access(node: String, round: Long = 1) = CollaborationWorkspaceAccess("group", "run", "turn", round, node, node)
    private class Fixture(val owner: CollaborationCapabilityDiagnosisTest) {
        val rows = Rows()
        val evidenceRows = Rows()
        val ledger = CollaborationEvidenceLedger(evidenceRows)
        fun workspace() = CollaborationResearchWorkspace(rows, evidence = ledger::references,
            evidenceReadCoverage = ledger::requireReadCoverage, evidenceOriginal = { a, ref -> ledger.read(a, ref.getString("evidence_id"), ref.getString("sha256")) })
        val workspace = workspace()
        val gap = publish("gap", "capability_gap", JSONObject("""{"category":"unknown","symptom":"Fetch failed",
            "needed_capability":"Retrieve source","chosen_option":"probe","rationale":"Distinguish service state from missing tool",
            "learning_options":[{"id":"probe","action":"Read-only health test","expected_gain":"Narrow cause","cost":"One call",
            "goal_relevance":"Required source","verification":"Observed return"}]}"""), "author", 1, now = 10)
        val symptom = ledger.record(owner.access("executor"), "failure", "fetch", "{}", "{\"status\":\"failed\",\"error\":{\"code\":\"offline\"}}", 20, 21)
        var diagnosis: JSONObject? = null
        fun spec() = JSONObject().put("gap", gap).put("selected_option", "probe").put("uncertainty", "Transport or tool configuration")
            .put("action", "Check endpoint and inspect tool configuration").put("authorization_boundary", "Read only; no new credentials")
            .put("selected_hypothesis", "network").put("hypotheses", JSONArray()
                .put(JSONObject().put("id", "network").put("category", "environment").put("explanation", "Network unavailable")
                    .put("discriminating_test", "Read-only endpoint probe").put("would_refute", "Endpoint returns but parsing still fails"))
                .put(JSONObject().put("id", "tool").put("category", "tool").put("explanation", "Tool misconfiguration")
                    .put("discriminating_test", "Compare independent client").put("would_refute", "Both clients fail identically")))
            .put("expected_observations", JSONArray().put(JSONObject().put("id", "ready").put("source", JSONObject()
                .put("origin", "android_cloud_tool").put("tool", "fetch")).put("pointer", "/status").put("expected", "returned")
                .put("meaning", "Request returns, not proof of root cause")))
        fun diagnose(change: (JSONObject) -> Unit = {}): JSONObject = publish("diagnosis", "capability_diagnosis", spec().apply(change),
            "diagnoser", 2, JSONArray().put(symptom), 100).also { diagnosis = it }
        fun observe(output: String = "{\"status\":\"returned\"}", started: Long = 200, tool: String = "fetch",
                    origin: CollaborationEvidenceOrigin = CollaborationEvidenceOrigin.ANDROID_CLOUD_TOOL) =
            ledger.record(owner.access("executor", 3), "probe", tool, "{}", output, started, started + 1, origin)
        fun probe(ref: JSONObject, change: (JSONObject) -> Unit = {}): JSONObject = publish("probe", "capability_probe", JSONObject()
            .put("diagnosis", diagnosis!!).put("assessment", "supported").put("interpretation", "Inspect cause independently")
            .put("remaining_work", "Recheck original goal and independent evidence")
            .put("checks", JSONArray().put(JSONObject().put("expectation_id", "ready").put("observation", ref))).apply(change),
            "reviewer", 4, JSONArray().put(ref), 300)
        fun publish(id: String, kind: String, value: JSONObject, node: String, round: Long,
                    observations: JSONArray = JSONArray(), now: Long): JSONObject {
            val a = owner.access(node, round)
            repeat(observations.length()) {
                val ref = observations.getJSONObject(it)
                var offset: Int? = 0
                while (offset != null) offset = ledger.readPage(a, ref.getString("evidence_id"), ref.getString("sha256"), offset)!!.next
            }
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Fixture")
                .put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(JSONObject()
                    .put("id", id).put("kind", kind).put("title", id).put("body", JSONObject().put("content", "Original fixture").put(kind, value))
                    .put("observations", observations)))
            val receipt = workspace.publish(a, raw.toString(), now)
            if (receipt.optString("status") == "recorded") return receipt.getJSONArray("revisions").getJSONObject(0)
            return receipt
        }
    }

    @Test fun observedFailureDiagnosisAndProbeSurviveReopenWithoutClaimingLearning() {
        val f = Fixture(this)
        val diagnosis = f.diagnose()
        assertEquals("diagnosis_proposed", diagnosis.getJSONObject("host_evolution").getString("state"))
        assertEquals(1, diagnosis.getJSONObject("host_evolution").getInt("observed_failures"))
        val result = f.probe(f.observe())
        val host = result.getJSONObject("host_evolution")
        assertEquals("probe_expectations_met", host.getString("state"))
        assertFalse(host.getBoolean("cause_verified"))
        assertFalse(host.getBoolean("gap_resolved"))
        assertFalse(host.getBoolean("automatically_installed"))
        val saved = f.workspace().read(access("later", 5), result.getString("object_id"), 1)!!
        assertTrue(saved.getJSONObject("host_evolution").getJSONArray("checks").getJSONObject(0).getBoolean("met"))
        assertEquals(3, f.workspace().browseEvolution(access("later", 5)).revisions.size)
    }

    @Test fun agentChoosesHypothesisAndOptionButCannotInventSourceBinding() {
        for (change in listOf<(JSONObject) -> Unit>(
            { it.put("selected_hypothesis", "made-up") }, { it.put("selected_option", "made-up") },
            { it.getJSONArray("hypotheses").getJSONObject(0).put("category", "verified") },
            { it.getJSONArray("expected_observations").getJSONObject(0).getJSONObject("source").put("tool", "collaboration_recall") },
            { it.getJSONArray("expected_observations").getJSONObject(0).getJSONObject("source").put("origin", "invented") },
            { it.getJSONArray("expected_observations").getJSONObject(0).put("expected", JSONObject().put("any", true)) },
            { it.getJSONArray("expected_observations").getJSONObject(0).put("pointer", "/bad~3escape") }
        )) {
            val result = Fixture(this).diagnose(change)
            assertEquals(result.toString(), "rejected", result.optString("status"))
        }
    }

    @Test fun oldWrongToolAndWrongExecutorEvidenceCannotValidateProbe() {
        for (mode in listOf("old", "tool", "origin", "digest", "unknown_expectation", "duplicate")) {
            val f = Fixture(this); f.diagnose()
            val observed = f.observe(started = if (mode == "old") 50 else 200,
                tool = if (mode == "tool") "other" else "fetch",
                origin = if (mode == "origin") CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL else CollaborationEvidenceOrigin.ANDROID_CLOUD_TOOL)
            val result = f.probe(observed) {
                val check = it.getJSONArray("checks").getJSONObject(0)
                when (mode) {
                    "digest" -> check.put("observation", JSONObject(observed.toString()).put("sha256", "0".repeat(64)))
                    "unknown_expectation" -> check.put("expectation_id", "unregistered")
                    "duplicate" -> it.getJSONArray("checks").put(JSONObject(check.toString()))
                }
            }
            assertEquals("$mode: $result", "rejected", result.optString("status"))
        }
    }

    @Test fun unchangedFailureMissingFieldsAndPartialTestsArePreserved() {
        for (mode in listOf("unchanged", "signals", "missing", "partial")) {
            val f = Fixture(this)
            f.diagnose { if (mode == "partial") it.getJSONArray("expected_observations").put(JSONObject()
                .put("id", "more").put("source", JSONObject().put("origin", "android_cloud_tool").put("tool", "fetch"))
                .put("pointer", "/more").put("expected", true).put("meaning", "Additional independent condition")) }
            val result = f.probe(f.observe(when (mode) {
                "unchanged" -> "{\"status\":\"failed\",\"error\":{\"code\":\"offline\"}}"
                "signals" -> "{\"status\":\"failed\",\"error\":{\"code\":\"offline\"},\"request_id\":\"new\"}"
                "missing" -> "{}"
                else -> "{\"status\":\"returned\"}"
            }))
            val saved = f.workspace.read(access("later", 5), result.getString("object_id"), 1)!!.getJSONObject("host_evolution")
            assertEquals(if (mode == "partial") "probe_incomplete" else "probe_expectations_not_met", saved.getString("state"))
            if (mode == "unchanged") assertTrue(saved.getJSONArray("checks").getJSONObject(0).getBoolean("same_output_as_symptom"))
            if (mode == "signals") {
                assertFalse(saved.getJSONArray("checks").getJSONObject(0).getBoolean("same_output_as_symptom"))
                assertTrue(saved.getJSONArray("checks").getJSONObject(0).getBoolean("same_failure_signals_as_symptom"))
            }
            if (mode == "missing") assertFalse(saved.getJSONArray("checks").getJSONObject(0).getBoolean("field_present"))
        }
    }

    @Test fun explicitNullDiffersFromMissingAndNumbersDoNotCoerceStrings() {
        for ((output, expected, met) in listOf(
            Triple("{\"value\":null}", JSONObject.NULL, true), Triple("{}", JSONObject.NULL, false),
            Triple("{\"value\":1.0}", 1, true), Triple("{\"value\":\"1\"}", 1, false))) {
            val f = Fixture(this)
            f.diagnose { it.getJSONArray("expected_observations").getJSONObject(0).put("pointer", "/value").put("expected", expected) }
            val result = f.probe(f.observe(output))
            assertEquals(if (met) "probe_expectations_met" else "probe_expectations_not_met", result.getJSONObject("host_evolution").getString("state"))
        }
    }

    @Test fun desktopProbeUsesExactStructuredOriginalInsteadOfModelSummary() {
        val f = Fixture(this)
        f.diagnose {
            it.getJSONArray("expected_observations").getJSONObject(0)
                .put("source", JSONObject().put("origin", "desktop_codex_tool").put("tool", "codex.commandExecution"))
                .put("report_pointer", "/original_json").put("pointer", "/observation/item/exitCode").put("expected", 0)
        }
        val output = JSONObject().put("status", "returned").put("original_json", JSONObject().put("observation", JSONObject()
            .put("item", JSONObject().put("exitCode", 0))).toString()).toString()
        val result = f.probe(f.observe(output, tool = "codex.commandExecution", origin = CollaborationEvidenceOrigin.DESKTOP_CODEX_TOOL))
        assertEquals("probe_expectations_met", result.getJSONObject("host_evolution").getString("state"))
        assertFalse(result.getJSONObject("host_evolution").getBoolean("cause_verified"))
    }

    @Test fun diagnosisCannotBeEditedAndChangedGapMakesProbeHistorical() {
        val f = Fixture(this); val diagnosis = f.diagnose()
        fun revise(ref: JSONObject, author: String, body: JSONObject): JSONObject {
            val item = JSONObject().put("object_id", ref.getString("object_id")).put("base_revision", 1)
                .put("kind", ref.getString("kind")).put("title", "Revision").put("body", body)
            return f.workspace.publish(access("revision-$author", 3).copy(personId = author), JSONObject()
                .put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Revision")
                .put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(item)).toString(), 150)
        }
        val rejected = revise(diagnosis, "diagnoser", JSONObject().put("content", "Change prediction")
            .put("capability_diagnosis", f.spec()))
        assertTrue(rejected.toString(), rejected.getString("reason").contains("immutable"))
        val body = f.workspace.read(access("author", 3), f.gap.getString("object_id"), 1)!!.getJSONObject("body")
        body.getJSONObject("capability_gap").put("rationale", "Changed evidence scope")
        assertEquals("recorded", revise(f.gap, "author", body).optString("status"))
        val probe = f.probe(f.observe())
        assertFalse(probe.getJSONObject("host_evolution").getBoolean("targets_current_at_publication"))
        val directory = f.workspace().browseEvolution(access("later", 5)).revisions
        assertEquals("historical_requires_revalidation", directory.single { it.getString("object_id") == probe.getString("object_id") }
            .getString("evolution_applicability"))
    }

    @Test fun failureIndexIsAtomicScopedReplaySafeAndDoesNotRewriteOriginals() {
        val rows = Rows(); var active = true
        val ledger = CollaborationEvidenceLedger(rows) { active }
        fun fail(id: String) = ledger.record(access("a"), id, "fetch", "{}", "{\"status\":\"failed\"}", 1, 2)
        rows.fail = true
        assertTrue(runCatching { fail("first") }.isFailure)
        assertTrue(rows.data.isEmpty())
        rows.fail = false
        val first = fail("first")
        val original = rows.data.filterKeys { it.contains(":observation:") }
        rows.data.keys.filter { it.contains(":problem:") }.toList().forEach(rows.data::remove)
        assertEquals(first.toString(), fail("first").toString())
        assertEquals(original, rows.data.filterKeys { it.contains(":observation:") })
        assertEquals(1, CollaborationEvidenceLedger(rows).problems(access("a")).first.size)
        repeat(42) { fail("f$it") }
        var cursor = ""; val ids = mutableSetOf<String>()
        do {
            val page = ledger.problems(access("a"), cursor)
            page.first.forEach { assertTrue(ids.add(it.getString("evidence_id"))) }
            cursor = page.second.orEmpty()
        } while (cursor.isNotEmpty())
        assertEquals(43, ids.size)
        assertTrue(ledger.problems(access("b")).first.isEmpty())
        assertTrue(ledger.problems(access("b").copy(groupId = "other")).first.isEmpty())
        assertTrue(runCatching { ledger.problems(access("b"), "other-cursor") }.isFailure)
        active = false
        assertTrue(ledger.problems(access("a")).first.isEmpty())
    }

    @Test fun hostSignalsAreNotToolAuthoredRootCauseClaims() {
        val f = Fixture(this)
        val saved = f.ledger.problems(access("later", 2)).first.single()
        val problem = saved.getJSONObject("host_problem")
        assertEquals("not_diagnosed", problem.getString("cause"))
        assertFalse(problem.getBoolean("resolved"))
        assertTrue(problem.getJSONArray("signals").toString().contains("offline"))
        assertFalse(problem.toString().contains("input_json"))
        val remote = CollaborationCapabilityProblem.describe("""{"status":"failed","original_json":"{\"observation\":{\"item\":{\"exitCode\":7}}}"}""",
            "failed", CollaborationEvidenceOrigin.DESKTOP_CODEX_TOOL)!!
        assertTrue(remote.getJSONArray("signals").toString().contains("exitCode"))
    }

    @Test fun variedKnownAndUnknownFaultsRemainSymptomsNotHardCodedStrategies() {
        for (code in listOf("timeout", "dns_failed", "permission_denied", "invalid_json", "missing_field", "unsupported_tool",
            "out_of_memory", "quota", "evidence_conflict", "verification_failed", "missing_dependency", "future_fault_918")) {
            val rows = Rows(); val ledger = CollaborationEvidenceLedger(rows)
            val output = JSONObject().put("status", "failed").put("error", JSONObject().put("code", code))
                .put("host_problem", JSONObject().put("cause", "verified").put("resolved", true))
            val ref = ledger.record(access("a"), "fault", "tool", "{}", output.toString(), 1, 2)
            val host = ref.getJSONObject("host_problem")
            assertEquals("not_diagnosed", host.getString("cause"))
            assertFalse(host.getBoolean("resolved"))
            assertTrue(host.getJSONArray("signals").toString().contains(code))
            assertFalse(host.has("retry_after_attempts"))
        }
    }

    @Test fun diagnosisRequiresFullOriginalsAndDoesNotAcceptRecallAsEvidence() {
        val f = Fixture(this)
        val caller = access("diagnoser", 2)
        fun attempt(ref: JSONObject, read: Boolean): JSONObject {
            val reader = caller.copy(nodeId = if (read) "second" else "first")
            if (read) f.ledger.readPage(reader, ref.getString("evidence_id"), ref.getString("sha256"))
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Diagnose")
                .put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(JSONObject()
                    .put("id", "diagnosis").put("kind", "capability_diagnosis").put("title", "Diagnosis")
                    .put("body", JSONObject().put("content", "Test").put("capability_diagnosis", f.spec()))
                    .put("observations", JSONArray().put(ref))))
            return f.workspace.publish(reader, raw.toString(), 100)
        }
        assertEquals("rejected", attempt(f.symptom, false).optString("status"))
        val recall = f.ledger.record(access("executor"), "recall", "collaboration_recall", "{}", "{}", 22, 23)
        assertTrue(attempt(recall, true).getString("reason").contains("Recall"))
    }
}
