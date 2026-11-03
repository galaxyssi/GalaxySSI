package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CloudGoalPageProtocolTest {
    @Test fun sharedWireNamesMatchThePhoneContracts() {
        assertEquals("galaxyssi.goal-contract-page.v1", CloudGoalPageProtocol.FORMAT)
        assertEquals(CollaborationGoalContractStore.PAGE_FORMAT, CloudGoalPageProtocol.FORMAT)
        assertEquals(CollaborationCloudRecall.NAME, CloudGoalPageProtocol.RECALL_TOOL)
    }

    @Test fun strictIntegerParsingMatchesEvidenceProtocol() {
        for (value in listOf(null, JSONObject.NULL, true, "1", 1.0, 0, -1L, Long.MAX_VALUE)) {
            val json = JSONObject().put("value", value)
            assertEquals(CollaborationRemoteEvidenceProtocol.integer(json, "value"),
                CloudGoalPageProtocol.integer(json, "value"))
        }
    }
}
