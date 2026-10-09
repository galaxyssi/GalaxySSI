package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Explicit opt-in device suite: two tiny Python executions, no model, network or downloads. */
@RunWith(AndroidJUnit4::class)
class CollaborationSavedToolNativeDeviceTest {
    @Test fun realNativeReportsDistinguishFailureFromRepairAndPersistReceipts() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertTrue("An already installed native runtime is required; this suite does not download one",
            AgentOnDeviceRuntimeManager(context).cachedStatus().backend != AgentOnDeviceRuntimeBackend.NONE)
        val group = "saved-tool-native-fixture-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf(CollaborationMember("worker", "Fixture", "fixture", "Fixture")), coordinatorId = "worker") }
        try {
            val workspace = CollaborationResearchWorkspace(context)
            val ledger = CollaborationEvidenceLedger(context)
            val access = CollaborationWorkspaceAccess(group, "fixture-run", "fixture-turn", 3, "native-test", "worker")
            val source = System.nanoTime()
            ledger.bind(source, access)
            fun publish(id: String, kind: String, spec: JSONObject, round: Long, bodyKind: String = kind): JSONObject {
                val body = JSONObject().put("content", "Developer-authored synthetic fixture, not model-generated innovation").put(bodyKind, spec)
                val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Native fixture")
                    .put("workspace", JSONArray().put(JSONObject().put("id", id).put("kind", kind).put("title", id).put("body", body)))
                val result = workspace.publish(access.copy(round = round, nodeId = id), raw.toString(), round)
                assertEquals(result.toString(), "recorded", result.getString("status"))
                return CollaborationResearchCandidates.reference(result.getJSONArray("revisions").getJSONObject(0))
            }
            val journal = workspace.savedToolTests(access, "native-fixture")
            for (fixed in listOf(false, true)) {
                val suffix = if (fixed) "fixed" else "broken"
                val tool = publish("source-$suffix", CollaborationExecutableTool.TOOL, JSONObject()
                    .put("name", "Identity-$suffix").put("purpose", "Echo integers").put("language", "python")
                    .put("source", "def run(parameters):\n    return parameters['value']${if (fixed) "" else " + 1"}\n")
                    .put("environment", "device-python-fixture").put("dependencies", "Python standard library")
                    .put("applies_when", "Fixture integers").put("avoid_when", "Production").put("side_effects", "None")
                    .put("input_schema", JSONObject("""{"type":"object","properties":{"value":{"type":"integer"}},"required":["value"],"additional_properties":false}""")), 1)
                fun case(id: String, purpose: String, value: Int) = JSONObject().put("id", id).put("purpose", purpose)
                    .put("reason", "Identity fixture").put("input", JSONObject().put("value", value)).put("expected", value)
                val plan = publish("tests-$suffix", CollaborationExecutableTool.TEST, JSONObject().put(CollaborationExecutableTool.TOOL, tool)
                    .put("environment", "device-python-fixture").put("purpose", "Identity checks").put("oracle_basis", "Identity")
                    .put("coverage_gaps", "Two disclosed developer-authored cases")
                    .put("cases", JSONArray().put(case("one", "target", 1)).put(case("zero", "regression", 0))), 2)
                val input = JSONObject().put("mode", "start").put("execution_id", suffix).put("tool_test_plan", plan).put("timeout_ms", 120_000)
                if (fixed) {
                    val spec = workspace.read(access, plan.getString("object_id"), plan.getInt("revision"))!!
                        .getJSONObject("body").getJSONObject(CollaborationExecutableTool.TEST)
                    val generic = publish("generic-plan", "artifact", spec, 2, CollaborationExecutableTool.TEST)
                    val invalid = JSONObject(input.toString()).put("execution_id", "generic-plan").put("tool_test_plan", generic)
                    assertTrue(journal.start(invalid).launch)
                    assertTrue(journal.running("generic-plan"))
                    val rejected = AndroidCollaborationSavedToolTest.invokeNative(context, access, source, journal.key("generic-plan"), invalid,
                        AgentNativeToolCancellationToken.NONE)
                    assertEquals("failed", rejected.getString("native_status"))
                    assertTrue(rejected.isNull("passed"))
                    val detail = rejected.getJSONObject("error").getJSONObject(CollaborationRecordValidation.DETAIL)
                    assertEquals("record_kind_mismatch", detail.getString("code"))
                    assertEquals("artifact", detail.getString("actual"))
                    assertEquals(CollaborationExecutableTool.TEST, detail.getJSONArray("expected").getString(0))
                    val ref = rejected.getJSONObject("galaxyssi_evidence_receipt")
                    val original = ledger.read(access, ref.getString("evidence_id"), ref.getString("sha256"))!!
                    val originalDetail = JSONObject(original.getString("output_json")).getJSONObject("error")
                        .getJSONObject("details").getJSONObject(CollaborationRecordValidation.DETAIL)
                    assertEquals(detail.toString(), originalDetail.toString())
                    journal.finish("generic-plan", rejected)
                    val reopened = CollaborationResearchWorkspace(context).savedToolTests(access, "reopened")
                    assertFalse(reopened.start(invalid).launch)
                    assertEquals("record_kind_mismatch", reopened.read("generic-plan")!!.getJSONObject("result")
                        .getJSONObject("error").getJSONObject(CollaborationRecordValidation.DETAIL).getString("code"))
                }
                assertTrue(journal.start(input).launch)
                assertTrue(journal.running(suffix))
                val result = AndroidCollaborationSavedToolTest.invokeNative(context, access, source, journal.key(suffix), input,
                    AgentNativeToolCancellationToken.NONE)
                android.util.Log.i("GalaxySSITest", "saved_tool_native case=$suffix status=${result.optString("native_status")} passed=${result.opt("passed")}")
                assertFalse("Native execution did not produce a test verdict: $result", result.isNull("passed"))
                assertEquals(result.toString(), fixed, result.getBoolean("passed"))
                val receipt = result.getJSONObject("galaxyssi_evidence_receipt")
                val original = requireNotNull(ledger.read(access, receipt.getString("evidence_id"), receipt.getString("sha256")))
                val recorded = JSONObject(original.getString("output_json")).getJSONObject("output").getJSONObject(CollaborationExecutableTool.RECEIPT)
                assertEquals(fixed, recorded.getBoolean("passed"))
                assertEquals(2, recorded.getJSONObject("report").getJSONArray("results").length())
                assertNotEquals("fixture", recorded.getJSONObject("report").getJSONObject("runtime").getString("implementation"))
                journal.finish(suffix, result)
                val reopened = CollaborationResearchWorkspace(context).savedToolTests(access, "reopened")
                assertFalse(reopened.start(input).launch)
                assertEquals(fixed, reopened.read(suffix)!!.getJSONObject("result").getBoolean("passed"))
            }
        } finally { groups.remove(group) }
    }
}
