package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationExecutableTool.TEST
import com.galaxyssi.chat.CollaborationExecutableTool.TOOL
import java.io.Closeable
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic process outputs exercise real device storage and validation, not model capability. */
@RunWith(AndroidJUnit4::class)
class CollaborationToolComparisonDeviceTest {
    private class Fixture : Closeable {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "tool-comparison-fixture-${UUID.randomUUID()}"
        private val groups = CollaborationGroupStore(context)
        var ledger = CollaborationEvidenceLedger(context)
        var workspace = CollaborationResearchWorkspace(context)

        init {
            groups.update(group) { it.copy(members = listOf("author", "tester", "reviewer").map { id ->
                CollaborationMember(id, id, "fixture", "Fixture")
            }, coordinatorId = "reviewer") }
        }

        fun access(person: String = "reviewer", round: Long = 5, node: String = "comparison") =
            CollaborationWorkspaceAccess(group, "fixture-run", "fixture-turn", round, node, person)

        fun reopen() {
            ledger = CollaborationEvidenceLedger(context)
            workspace = CollaborationResearchWorkspace(context)
        }

        fun publish(id: String, kind: String, value: JSONObject, person: String, round: Long,
                    observations: JSONArray = JSONArray()): JSONObject {
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Synthetic device comparison")
                .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject()
                    .put("id", id).put("kind", kind).put("title", id).put("observations", observations)
                    .put("body", JSONObject().put("content", "Synthetic fixture; not real Python or model execution").put(kind, value))))
            return workspace.publish(access(person, round, id), raw.toString(), round * 10)
        }

        fun ref(result: JSONObject): JSONObject {
            assertEquals(result.toString(), "recorded", result.getString("status"))
            return result.getJSONArray("revisions").getJSONObject(0)
        }

        fun tool(id: String, source: String) = ref(publish(id, TOOL, JSONObject()
            .put("name", id).put("purpose", "Sort integers").put("language", "python").put("source", source)
            .put("environment", "synthetic-device-fixture").put("dependencies", "Python standard library")
            .put("applies_when", "Integer arrays").put("avoid_when", "Production").put("side_effects", "None")
            .put("input_schema", JSONObject("""{"type":"object","properties":{"values":{"type":"array","items":{"type":"integer"}}},"required":["values"],"additional_properties":false}""")), "author", 1))

        fun plan(id: String, tool: JSONObject, changeOracle: Boolean = false): JSONObject {
            fun case(name: String, purpose: String, input: String, expected: String) = JSONObject()
                .put("id", name).put("purpose", purpose).put("reason", "Check $name")
                .put("input", JSONObject().put("values", JSONArray(input))).put("expected", JSONArray(expected))
            return ref(publish(id, TEST, JSONObject().put(TOOL, tool).put("environment", "synthetic-device-fixture")
                .put("purpose", "Correct integer ordering").put("oracle_basis", "Manually specified sorted integer arrays")
                .put("coverage_gaps", "Three disclosed fixture cases only").put("cases", JSONArray()
                    .put(case("mixed", "target", "[3,1,2]", "[1,2,3]"))
                    .put(case("empty", "edge", "[]", "[]"))
                    .put(case("duplicates", "regression", "[2,-1,2]", if (changeOracle) "[-1,2]" else "[-1,2,2]"))), "reviewer", 2))
        }

        fun observe(id: String, plan: JSONObject, mixed: String, duplicates: String): JSONObject {
            val caller = access("tester", 3, id)
            val prepared = CollaborationToolRuntime.prepare(mapOf(CollaborationToolRuntime.INPUT to JSONObject()
                .put("mode", "test").put(TEST, plan).toNativeObject()), caller) { reference, kind ->
                requireNotNull(workspace.read(caller, reference.getString("object_id"), reference.getInt("revision"))).also {
                    require(it.getString("kind") == kind && CollaborationResearchCandidates.same(it, reference))
                }
            }!!
            val report = JSONObject().put("format", CollaborationToolRuntime.FORMAT).put("runtime", JSONObject()
                .put("python", JSONArray("[3,12,0]")).put("implementation", "fixture").put("machine", "synthetic"))
                .put("results", JSONArray().put(JSONObject().put("id", "mixed").put("output", JSONArray(mixed)))
                    .put(JSONObject().put("id", "empty").put("output", JSONArray()))
                    .put(JSONObject().put("id", "duplicates").put("output", JSONArray(duplicates))))
            val result = CollaborationToolRuntime.finish(prepared,
                AgentRuntimeExecutionResponse(0, report.toString(), "", 1, requestId = "synthetic-$id"),
                AgentNativeToolExecutionResult.success())
            val output = JSONObject().put("output", JSONObject(result.output))
            result.error?.let { output.put("error", JSONObject().put("code", it.code).put("details", JSONObject(it.details))) }
            return ledger.record(caller, "synthetic-$id", AgentOnDeviceRuntimeTools.EXECUTE, "{}", output.toString(),
                30, 31, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
        }

        val baselineTool = tool("baseline", "def run(parameters):\n    values = parameters['values']\n    return values if all(v >= 0 for v in values) else sorted(values)\n")
        val candidateTool = tool("candidate", "def run(parameters):\n    return sorted(set(parameters['values']))\n")
        val baselinePlan = plan("baseline-plan", baselineTool)
        val candidatePlan = plan("candidate-plan", candidateTool)
        val baseline = observe("baseline-observation", baselinePlan, "[3,1,2]", "[-1,2,2]")
        val candidate = observe("candidate-observation", candidatePlan, "[1,2,3]", "[-1,2]")

        fun compare(plan: JSONObject = candidatePlan, observation: JSONObject = candidate, read: Boolean = true): JSONObject {
            val refs = JSONArray().put(baseline).put(observation)
            if (read) repeat(refs.length()) { index ->
                val ref = refs.getJSONObject(index)
                var offset: Int? = 0
                while (offset != null) offset = ledger.readPage(access(), ref.getString("evidence_id"), ref.getString("sha256"), offset)!!.next
            }
            return publish("comparison", CollaborationToolComparison.KIND, JSONObject()
                .put("purpose", "Retain both repairs and regressions")
                .put("baseline", JSONObject().put(TEST, baselinePlan).put("observation", baseline))
                .put("candidate", JSONObject().put(TEST, plan).put("observation", observation))
                .put("interpretation", "One fix and one regression; not a successful replacement")
                .put("limitations", "Synthetic process outputs; no capability gain or Python execution claimed"), "reviewer", 5, refs)
        }

        override fun close() {
            groups.remove(group)
        }
    }

    @Test fun repairAndRegressionRemainDistinctAfterEncryptedStoreReopen() {
        Fixture().use { f ->
            val receipt = f.ref(f.compare())
            assertFalse(receipt.getJSONObject(HOST).has("cases"))
            f.reopen()
            val record = f.workspace.read(f.access(), receipt.getString("object_id"), receipt.getInt("revision"))!!
            for (page in listOf(f.workspace.browse(f.access()), f.workspace.browseEvolution(f.access()))) {
                val entry = page.revisions.single { it.getString("object_id") == receipt.getString("object_id") }
                assertEquals("inspect_scope_before_reuse", entry.getString("evolution_applicability"))
            }
            val host = record.getJSONObject(HOST)
            assertEquals(1, host.getJSONObject("counts").getInt("improved"))
            assertEquals(1, host.getJSONObject("counts").getInt("regressed"))
            assertEquals(1, host.getJSONObject("counts").getInt("both_passed"))
            assertEquals(0, host.getJSONObject("counts").getInt("both_failed"))
            assertFalse(host.getBoolean("candidate_all_passed"))
            assertFalse(host.getBoolean("capability_gain_verified"))
            assertFalse(host.getBoolean("automatically_adopted"))
            val regression = host.getJSONArray("cases").getJSONObject(2)
            assertEquals("regressed", regression.getString("outcome"))
            assertEquals("[-1,2,2]", regression.getJSONObject("candidate").getJSONArray("expected").toString())
            assertEquals("[-1,2]", regression.getJSONObject("candidate").getJSONArray("actual").toString())
            for (ref in listOf(f.baseline, f.candidate)) {
                val original = f.ledger.read(f.access(), ref.getString("evidence_id"), ref.getString("sha256"))!!
                assertEquals("failed", original.getString("status"))
            }
            val future = f.access().copy(runId = "future", turnId = "future", round = 0)
            assertNotNull(f.workspace.read(future, receipt.getString("object_id"), receipt.getInt("revision")))
            assertNull(f.workspace.read(future.copy(groupId = "unrelated"), receipt.getString("object_id"), receipt.getInt("revision")))
        }
    }

    @Test fun comparisonReplayRecoversSameReceiptWithoutAnotherRevision() {
        Fixture().use { f ->
            val first = f.compare()
            val before = f.workspace.browse(f.access()).revisions.size
            f.reopen()
            assertEquals(first.toString(), f.compare().toString())
            assertEquals(before, f.workspace.browse(f.access()).revisions.size)
        }
    }

    @Test fun unreadEvidenceAndChangedExpectedAnswersCannotManufactureImprovement() {
        Fixture().use { f ->
            assertEquals("rejected", f.compare(read = false).getString("status"))
            val changed = f.plan("changed-plan", f.candidateTool, changeOracle = true)
            val observed = f.observe("changed-observation", changed, "[1,2,3]", "[-1,2]")
            assertEquals("rejected", f.compare(changed, observed).getString("status"))
            f.reopen()
            assertTrue(f.workspace.browse(f.access()).revisions.none { it.getString("kind") == CollaborationToolComparison.KIND })
        }
    }
}
