package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentCompletionRequirementsTest {
    @Test fun validDeclarationsRoundTripAllPublicationAndRuntimeCombinations() {
        for (publication in AgentPublicationRequirement.entries) for (linux in listOf(false, true)) {
            val value = AgentCompletionRequirements(publication, linux, "User requested this outcome")
            assertEquals(value, AgentCompletionRequirements.parse(value.toJson()))
        }
    }

    @Test fun malformedDeclarationsAreNotInterpretedAsNoRequirements() {
        val malformed = listOf("{}", "null",
            """{"publication":"none","phone_linux":"false"}""",
            """{"publication":"unknown","phone_linux":false}""",
            """{"publication":true,"phone_linux":false}""",
            """{"publication":"none","phone_linux":false,"reason":null}""",
            """{"publication":"none","phone_linux":false,"reason":123}""")
        assertNull(AgentCompletionRequirements.parse(null))
        for (raw in malformed.filterNot { it == "null" }) {
            assertNull(raw, AgentCompletionRequirements.parse(JSONObject(raw)))
        }
        assertNull(AgentCompletionRequirements.parse(JSONObject().put("publication", "none")
            .put("phone_linux", false).put("reason", "x".repeat(1001))))
    }

    @Test fun amendmentsRequireExplanationButDoNotPreventCorrectingAnIntentMistake() {
        val local = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false)
        assertTrue(local.canReplace(null))
        assertTrue(local.canReplace(local))
        assertFalse(local.copy(phoneLinux = true).canReplace(local))
        assertFalse(local.copy(publication = AgentPublicationRequirement.COMMIT).canReplace(local))
        val mistaken = local.copy(publication = AgentPublicationRequirement.COMMIT)
        assertTrue(local.copy(reason = "User said not to commit; previous interpretation was wrong.").canReplace(mistaken))
    }
}
