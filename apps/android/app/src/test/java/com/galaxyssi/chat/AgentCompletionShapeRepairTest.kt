package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentCompletionShapeRepairTest {
    private fun requirements(subject: Any, checks: Any) = JSONObject()
        .put("publication", "none").put("phone_linux", false)
        .put("outcomes", JSONArray().put(JSONObject()
            .put("id", "timer-running").put("tool_id", "galaxyssi.agent_action.set.alarm")
            .put("subject", subject).put("checks", checks)
            .put("after_tool_id", "galaxyssi.agent_action.set.alarm")))

    @Test fun stringSubjectHasSpecificRepairWithoutRepeatingTheMutation() {
        val invalid = requirements("observed-timer-id", JSONObject().put("/metadata/timer_state", "running"))
        assertNull(AgentCompletionRequirements.parse(invalid))
        val repair = AgentCompletionRequirements.rejectionDetail(invalid)
        assertTrue(repair.contains("outcomes[0].subject must be a JSON object"))
        assertTrue(repair.contains("do not rerun a successful tool"))
    }

    @Test fun arrayChecksHaveSpecificObjectRepairAndValidReceiptPasses() {
        val subject = JSONObject().put("/metadata/operation_id", "observed-timer-id")
        val invalid = requirements(subject, JSONArray().put(JSONObject().put("pointer", "/metadata/timer_state").put("equals", "running")))
        assertNull(AgentCompletionRequirements.parse(invalid))
        assertTrue(AgentCompletionRequirements.rejectionDetail(invalid).contains("outcomes[0].checks must be a JSON object"))
        assertNotNull(AgentCompletionRequirements.parse(requirements(subject,
            JSONObject().put("/metadata/timer_state", "running").put("/metadata/business_success_verified", "true"))))
    }
}
