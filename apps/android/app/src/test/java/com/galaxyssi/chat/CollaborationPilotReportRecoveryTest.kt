package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationPilotReportRecoveryTest {
    private val plan get() = CollaborationPilotArtifactFixture.plan()
    private fun report() = runBlocking { CollaborationPilotReportFixture.report(plan) }
    private fun hash(raw: String) = CollaborationRemotePilotDispatch.sha256(raw.toByteArray(Charsets.UTF_8))
    private fun recover(value: JSONObject, slot: Int = 0): CollaborationPilotArtifact {
        val raw = value.toString()
        return CollaborationPilotArtifact.recoverReport(plan, plan.slots[slot], "a".repeat(64), raw, hash(raw))
    }

    @Test fun exactTextRecoveredForBothArmsWithReportProvenance() {
        val report = report()
        for (index in plan.slots.indices) {
            val artifact = recover(report, index)
            assertEquals(report.getJSONArray("slots").getJSONObject(index).getString("final_output"), artifact.finalOutput)
            assertTrue(artifact.finalOutput.startsWith("  ") && artifact.finalOutput.endsWith("\n"))
            val body = JSONObject(artifact.payload)
            assertEquals("completed_test_report", body.getJSONObject("report_recovery").getString("origin"))
            assertEquals(hash(report.toString()), body.getJSONObject("report_recovery").getString("report_sha256"))
            assertFalse(body.getJSONObject("report_recovery").getBoolean("provider_attested"))
            assertEquals("unverified_candidate", body.getString("trust"))
            assertFalse(body.getBoolean("grants_permissions"))
            assertEquals(artifact.payload, CollaborationPilotArtifact.restore(artifact.envelope(), artifact.source, artifact.reference).payload)
        }
    }

    @Test fun changedReportDigestProtocolSelectionAndSlotAreRejected() {
        val report = report()
        val raw = report.toString()
        assertThrows(RuntimeException::class.java) {
            CollaborationPilotArtifact.recoverReport(plan, plan.slots.first(), "a".repeat(64), raw + " ", hash(raw))
        }
        val mutations: List<(JSONObject) -> Unit> = listOf(
            { it.put("finished", false) }, { it.put("pilot_id", "other") },
            { it.put("protocol_sha256", "b".repeat(64)) }, { it.put("selection_source", "host_default") },
            { it.getJSONObject("model_selection").put("requested_model", "other") },
            { it.getJSONObject("model_selection").put("requested_reasoning_effort", "low") },
            { it.getJSONArray("slots").remove(1) }, { it.getJSONArray("slots").getJSONObject(0).put("arm", "team") },
            { it.getJSONArray("slots").getJSONObject(0).put("case_id", "other") }
        )
        mutations.forEach { change ->
            assertThrows(RuntimeException::class.java) { recover(JSONObject(raw).also(change)) }
        }
    }

    @Test fun incompleteTruncatedOrUncleanRunsCannotBeRecovered() {
        val raw = report().toString()
        val changes: List<(JSONObject) -> Unit> = listOf(
            { it.put("status", "failed") }, { it.put("state", "RUNNING") }, { it.put("result_truncated", true) },
            { it.put("cleanup_confirmed", false) }, { it.put("durable_control", "PAUSE") },
            { it.put("pending_remote_owners", JSONArray().put("pending")) }, { it.put("run_id", "other") },
            { it.put("turn_id", "other") }, { it.put("conversation_id", "other") },
            { it.put("final_output", "changed") }, { it.getJSONArray("members").getJSONObject(0).put("error", "failure") },
            { it.getJSONArray("members").getJSONObject(0).put("status", "FAILED") },
            { it.getJSONArray("phone_dispatches").getJSONObject(0).put("transport_instance_id", "other") }
        )
        changes.forEach { change ->
            val value = JSONObject(raw)
            change(value.getJSONArray("slots").getJSONObject(0))
            assertThrows(RuntimeException::class.java) { recover(value) }
        }
    }

    @Test fun rehashedRecoveredPayloadCannotGrantTrustOrHideOrigin() {
        val artifact = recover(report())
        for (key in listOf("origin", "report_sha256", "provider_attested")) {
            val body = JSONObject(artifact.payload)
            body.getJSONObject("report_recovery").put(key, "changed")
            val payload = body.toString()
            val ref = artifact.reference.copy(sha256 = hash(payload))
            val envelope = JSONObject().put("payload_json", payload).put("reference", ref.json()).toString()
            assertThrows(RuntimeException::class.java) { CollaborationPilotArtifact.restore(envelope, artifact.source, ref) }
        }
    }
}
