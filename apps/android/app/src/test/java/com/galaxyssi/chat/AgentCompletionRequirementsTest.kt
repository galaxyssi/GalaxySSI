package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentCompletionRequirementsTest {
    @Test fun readOnlyQueryCanDeclareActualFieldsAfterObservationWithAnExplanation() {
        val initial = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false)
        val observed = AgentObservedOutcome("media", AgentAndroidSystemNativeTools.AUDIO_STATUS,
            mapOf("/streams/music/stream" to "music"),
            mapOf("/streams/music/current" to 2, "/streams/music/max" to 15))
        val verified = initial.copy(outcomes = listOf(observed))
        assertFalse(verified.canReplace(initial))
        assertTrue(verified.copy(reason = "Bound the query to fields from the actual read-only receipt.")
            .canReplace(initial))
    }

    @Test fun correctingReceiptPathsPreservesEveryPreviouslyDeclaredOutcome() {
        val original = AgentObservedOutcome("media", AgentAndroidSystemNativeTools.AUDIO_STATUS,
            mapOf("/stream" to "music"), mapOf("/current_level" to "observed"))
        val initial = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false, outcomes = listOf(original))
        val actual = original.copy(subject = mapOf("/streams/music/stream" to "music"),
            checks = mapOf("/streams/music/current" to 2))
        val corrected = initial.copy(outcomes = listOf(actual), reason = "Corrected paths from the actual receipt.")
        assertTrue(corrected.canReplace(initial))
        assertFalse(corrected.copy(reason = "").canReplace(initial))
        assertFalse(corrected.copy(outcomes = emptyList()).canReplace(initial))
        assertFalse(corrected.copy(outcomes = listOf(actual.copy(id = "unrelated"))).canReplace(initial))
    }

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
