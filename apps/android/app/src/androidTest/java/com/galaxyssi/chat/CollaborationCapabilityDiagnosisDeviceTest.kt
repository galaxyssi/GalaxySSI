package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Local fixtures only. No model, network change, task resume or physical side effect. */
@RunWith(AndroidJUnit4::class)
class CollaborationCapabilityDiagnosisDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private fun access(group: String, person: String, round: Long) = CollaborationWorkspaceAccess(group, "run", "turn", round, "$person-$round", person)

    @Test fun problemDirectoryReopensAndIsAvailableThroughCloudAndNativeAdapters() = fixture { group ->
        val source = access(group, "source", 1)
        val ledger = CollaborationEvidenceLedger(context)
        val ref = ledger.record(source, "failure", "fixture.fetch", "{}", "{\"status\":\"failed\",\"error\":{\"code\":\"offline\"}}", 10, 11)
        val reader = access(group, "analyst", 2)
        val cloud = JSONObject(CollaborationCloudRecall.execute(context, reader, JSONObject().put("mode", "problems")))
        assertEquals("returned", cloud.getString("status"))
        assertEquals(ref.getString("evidence_id"), JSONObject(cloud.getJSONArray("observations").getString(0)).getString("evidence_id"))
        assertEquals(1, CollaborationEvidenceLedger(context).problems(reader).first.size)
        assertEquals(0, JSONObject(CollaborationCloudRecall.execute(context, reader.copy(round = 1),
            JSONObject().put("mode", "problems"))).getJSONArray("observations").length())
        val id = AgentTeamDispatchIds.sourceMessageId("gap-device:$group")
        ledger.bind(id, reader)
        val registry = AgentPhoneNativeToolCatalog.defaultRegistry(context, { ScreenContext(foregroundApp = "", pageTitle = "") })
            .subset { it.id == CollaborationRecallNativeTool.ID }
        val result = registry.invoke(CollaborationRecallNativeTool.ID, mapOf("mode" to "problems"),
            AgentNativeToolInvocationContext(conversationId = group, turnId = "turn", collaborationSourceMessageId = id))
        assertTrue(result.toJson(), result.isSuccess)
        assertTrue(result.output.toString().contains("not_diagnosed"))
    }

    @Test fun diagnosisAndNegativeProbeAreDurableAndCannotCertifyCapability() = fixture { group ->
        val w = CollaborationResearchWorkspace(context)
        val ledger = CollaborationEvidenceLedger(context)
        fun publish(kind: String, value: JSONObject, person: String, round: Long, now: Long, observations: JSONArray = JSONArray()): JSONObject {
            val a = access(group, person, round)
            repeat(observations.length()) { index ->
                val ref = observations.getJSONObject(index)
                var offset: Int? = 0
                while (offset != null) offset = ledger.readPage(a, ref.getString("evidence_id"), ref.getString("sha256"), offset)!!.next
            }
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Synthetic diagnosis test")
                .put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(JSONObject()
                    .put("id", kind).put("kind", kind).put("title", kind)
                    .put("body", JSONObject().put("content", "Synthetic fixture, no real actions").put(kind, value)).put("observations", observations)))
            val receipt = w.publish(a, raw.toString(), now)
            assertEquals(receipt.toString(), "recorded", receipt.optString("status"))
            return receipt.getJSONArray("revisions").getJSONObject(0)
        }
        val gap = publish("capability_gap", JSONObject("""{"category":"unknown","symptom":"Unavailable tool","needed_capability":"Read source",
            "chosen_option":"check","rationale":"Discriminate fault","learning_options":[{"id":"check","action":"Read-only probe",
            "expected_gain":"Learn cause","cost":"One fixture","goal_relevance":"Source needed","verification":"Observed status"}]}"""), "source", 1, 10)
        val error = "{\"status\":\"failed\",\"error\":{\"code\":\"offline\"}}"
        val symptom = ledger.record(access(group, "source", 1), "symptom", "fixture.fetch", "{}", error, 20, 21)
        val diagnosis = publish("capability_diagnosis", JSONObject().put("gap", gap).put("selected_option", "check")
            .put("uncertainty", "Cause not known").put("action", "Read-only probe").put("authorization_boundary", "Fixture only")
            .put("selected_hypothesis", "network").put("hypotheses", JSONArray().put(JSONObject().put("id", "network")
                .put("category", "environment").put("explanation", "Endpoint unavailable").put("discriminating_test", "Compare status")
                .put("would_refute", "Successful return but content still missing")))
            .put("expected_observations", JSONArray().put(JSONObject().put("id", "status").put("source", JSONObject()
                .put("origin", "android_cloud_tool").put("tool", "fixture.fetch")).put("pointer", "/status")
                .put("expected", "returned").put("meaning", "Only transport status"))), "analyst", 2, 100, JSONArray().put(symptom))
        val probe = ledger.record(access(group, "source", 3), "probe", "fixture.fetch", "{}", error, 200, 201)
        val result = publish("capability_probe", JSONObject().put("diagnosis", diagnosis).put("assessment", "inconclusive")
            .put("interpretation", "Same observed failure; request another method").put("remaining_work", "Independent endpoint probe")
            .put("checks", JSONArray().put(JSONObject().put("expectation_id", "status").put("observation", probe))),
            "analyst", 4, 300, JSONArray().put(probe))
        val reopened = CollaborationResearchWorkspace(context).read(access(group, "analyst", 5), result.getString("object_id"), 1)!!
        val host = reopened.getJSONObject("host_evolution")
        assertEquals("probe_expectations_not_met", host.getString("state"))
        assertTrue(host.getJSONArray("checks").getJSONObject(0).getBoolean("same_output_as_symptom"))
        assertFalse(host.getBoolean("gap_resolved"))
        assertFalse(host.getBoolean("automatically_installed"))
    }

    private fun fixture(block: (String) -> Unit) {
        val group = "gap-device-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf("source", "analyst").map { name ->
            CollaborationMember(name, name, "fixture", "Fixture") }, coordinatorId = "analyst") }
        try { block(group) } finally { groups.remove(group) }
    }
}
