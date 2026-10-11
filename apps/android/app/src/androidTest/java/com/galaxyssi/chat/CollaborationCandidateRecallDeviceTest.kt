package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.CollaborationExecutableTool.RECEIPT
import com.galaxyssi.chat.CollaborationExecutableTool.TEST
import com.galaxyssi.chat.CollaborationExecutableTool.TOOL
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic failure persistence and real recall adapters only; no model or Python execution. */
@RunWith(AndroidJUnit4::class)
class CollaborationCandidateRecallDeviceTest {
    @Test fun newAssignmentDiscoversFailedCandidateAndReadsOriginalThroughCloudAndNativeRecall() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "candidate-recall-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf("author", "reader").map { id ->
            CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "author") }
        val access = CollaborationWorkspaceAccess(group, "$group-old", "old-turn", 1, "author", "author")
        val workspace = CollaborationResearchWorkspace(context)
        val ledger = CollaborationEvidenceLedger(context)
        fun publish(id: String, kind: String, spec: JSONObject): JSONObject {
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Synthetic candidate history test")
                .put("workspace", JSONArray().put(JSONObject().put("id", id).put("kind", kind).put("title", id)
                    .put("body", JSONObject().put(kind, spec))))
            val publisher = access.copy(nodeId = id, dependencyNodes = if (id == "tests") setOf("source") else emptySet())
            val result = workspace.publish(publisher, raw.toString())
            assertEquals(result.toString(), "recorded", result.getString("status"))
            return CollaborationResearchCandidates.reference(result.getJSONArray("revisions").getJSONObject(0))
        }
        try {
            val spec = JSONObject().put("name", "Counterexample fixture").put("purpose", "Preserve negative synthetic integers")
                .put("language", "python").put("source", "def run(parameters):\n    return abs(parameters['value'])\n")
                .put("environment", "synthetic-no-execution").put("dependencies", "None executed")
                .put("applies_when", "Synthetic integers").put("avoid_when", "Never deploy this deliberately incorrect fixture")
                .put("side_effects", "None executed").put("input_schema", JSONObject().put("type", "object")
                    .put("properties", JSONObject().put("value", JSONObject().put("type", "integer")))
                    .put("required", JSONArray().put("value")).put("additional_properties", false))
            val tool = publish("source", TOOL, spec)
            val cases = JSONArray()
            for ((id, purpose, number) in listOf(Triple("negative", "target", -2), Triple("positive", "regression", 2)))
                cases.put(JSONObject().put("id", id).put("purpose", purpose).put("reason", "Synthetic sign preservation")
                    .put("input", JSONObject().put("value", number)).put("expected", number))
            val plan = publish("tests", TEST, JSONObject().put(TOOL, tool).put("environment", "synthetic-no-execution")
                .put("purpose", "Check sign").put("oracle_basis", "Fixture integers").put("coverage_gaps", "Not a real execution")
                .put("cases", cases))
            val input = JSONObject().put(CollaborationToolRuntime.INPUT, JSONObject().put("mode", "test").put(TEST, plan))
            val failure = JSONObject().put("status", "failed").put("output", JSONObject().put(RECEIPT,
                JSONObject().put("mode", "test").put(TEST, plan).put(TOOL, tool).put("passed", false)
                    .put("synthetic_fixture", true).put("evaluation", JSONObject().put("checks", JSONArray().put(
                        JSONObject().put("id", "negative").put("passed", false).put("expected", -2).put("actual", 2))))))
            val original = ledger.record(access, "synthetic-observation", AgentOnDeviceRuntimeTools.EXECUTE,
                input.toString(), failure.toString(), 10, 11, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
            val next = access.copy(runId = "$group-new", turnId = "new-turn", round = 0, nodeId = "reader", personId = "reader")
            val page = JSONObject(CollaborationCloudRecall.execute(context, next, JSONObject().put("mode", "capabilities").put("query", "counterexample")))
            assertEquals(page.toString(), "returned", page.getString("status"))
            val found = page.getJSONArray("records").let { a -> (0 until a.length()).map(a::getJSONObject) }
            assertEquals(setOf(TOOL, TEST), found.map { it.getString("kind") }.toSet())
            val source = System.currentTimeMillis()
            ledger.bind(source, next)
            fun invocation() = AgentNativeToolInvocationContext(conversationId = group, turnId = next.turnId, collaborationSourceMessageId = source)
            val registry = AgentNativeToolRegistry().registerAll(CollaborationRecallNativeTool.definitions(context))
            for (record in found) {
                val result = registry.invoke(CollaborationRecallNativeTool.ID, record.getJSONObject("usage_recall").toNativeObject(), invocation())
                assertTrue(result.toJson(), result.isSuccess)
                val row = JSONObject(result.output).getJSONArray("records").getJSONObject(0)
                assertEquals(original.getString("sha256"), row.getString("sha256"))
                assertFalse(row.getBoolean("runtime_reported_passed"))
                val read = JSONObject(CollaborationCloudRecall.execute(context, next, row.getJSONObject("read_original"), recordCoverage = false))
                assertEquals("returned", read.getString("status"))
                val saved = JSONObject(read.getString("content"))
                val check = JSONObject(saved.getString("output_json")).getJSONObject("output").getJSONObject(RECEIPT)
                    .getJSONObject("evaluation").getJSONArray("checks").getJSONObject(0)
                assertEquals(-2, check.getInt("expected")); assertEquals(2, check.getInt("actual"))
            }
            assertEquals(tool.getString("sha256"), CollaborationResearchWorkspace(context)
                .read(next, tool.getString("object_id"), 1)!!.getString("sha256"))
            groups.update(group) { it.copy(members = it.members.filterNot { member -> member.id == "reader" }) }
            val revoked = registry.invoke(CollaborationRecallNativeTool.ID, found.first().getJSONObject("usage_recall").toNativeObject(), invocation())
            assertFalse(revoked.toJson(), revoked.isSuccess)
            assertNotEquals("idempotency_key_conflict", revoked.error?.code)
        } finally {
            CollaborationResearchWorkspace.remove(context, group)
            CollaborationEvidenceLedger.remove(context, group)
            groups.remove(group)
        }
    }
}
