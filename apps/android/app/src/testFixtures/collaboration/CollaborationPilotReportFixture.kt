package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** A completed in-memory test graph rendered with the device-report contract. */
internal object CollaborationPilotReportFixture {
    suspend fun report(plan: CollaborationRemotePilotPlan): JSONObject {
        val slots = JSONArray()
        for (slot in plan.slots) {
            val result = CollaborationPilotArtifactFixture.execute(plan, slot, runPrefix = "remote-pilot")
            slots.put(JSONObject().put("id", slot.id).put("case_id", slot.caseId).put("arm", slot.arm)
                .put("status", "completed").put("state", "SUCCEEDED").put("result_truncated", false)
                .put("cleanup_confirmed", true).put("durable_control", "STOP").put("pending_remote_owners", JSONArray())
                .put("run_id", result.source["run_id"]).put("turn_id", result.source["turn_id"])
                .put("conversation_id", result.source["conversation_id"]).put("final_output", result.snapshot.finalOutput)
                .put("phone_dispatches", result.dispatches).put("members", JSONArray(result.snapshot.members.map {
                    JSONObject().put("node", it.memberId).put("person_id", it.personId).put("status", it.status.name)
                        .put("output", it.output).put("error", "")
                })))
        }
        return JSONObject().put("format", "galaxyssi.remote-pilot-report.v1").put("finished", true)
            .put("pilot_id", plan.id).put("protocol_sha256", "a".repeat(64)).put("model_selection", plan.selection.json())
            .put("selection_source", "app_conversation_snapshot").put("selection_conversation_id", "fixture-selection")
            .put("slots", slots)
    }
}
