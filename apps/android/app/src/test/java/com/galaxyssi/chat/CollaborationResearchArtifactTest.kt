package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationResearchArtifactTest {
    private fun artifact() = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "A concise contribution; experimental verification is still pending.")
        .put("candidates", JSONArray((1..10).map {
            JSONObject().put("id", "C$it").put("proposal", "Candidate $it").put("criteria", JSONArray())
        })).put("findings", JSONArray((1..24).map {
            JSONObject().put("claim", "Finding $it").put("outcome", "not_tested")
        })).put("memory", JSONArray((1..12).map {
            JSONObject().put("kind", "open_question").put("text", "Unresolved question $it")
        }))

    @Test fun completeContributionsHaveNoHiddenArrayCountLimit() {
        val input = artifact()
        val decoded = requireNotNull(CollaborationResearchArtifact.decode(input.toString()))
        assertEquals(input.toString(), decoded.toString())
        assertEquals(24, decoded.getJSONArray("findings").length())
        assertEquals(12, decoded.getJSONArray("memory").length())
    }

    @Test fun invalidTypedFieldsStillFailWithTheExactField() {
        val input = artifact()
        input.getJSONArray("findings").getJSONObject(11).put("outcome", "verified")
        assertNull(CollaborationResearchArtifact.decode(input.toString()))
        assertTrue(CollaborationResearchArtifact.validationError(input.toString()).contains("findings[11].outcome"))
        val duplicate = artifact()
        duplicate.getJSONArray("candidates").getJSONObject(9).put("id", "C1")
        assertTrue(CollaborationResearchArtifact.validationError(duplicate.toString()).contains("candidates[9].id"))
    }

    @Test fun historicalTruncatedWorkspaceDoesNotExposeRawJsonInConversation() {
        val header = "{\"format\":\"${CollaborationResearchArtifact.FORMAT}\",\"summary\":\"Useful public summary\",\"workspace\":[{"
        assertEquals("Useful public summary", CollaborationResearchArtifact.publicText(header))
        assertEquals("Useful public summary", CollaborationResearchArtifact.publicText("```json\n$header"))
        assertEquals("Normal text", CollaborationResearchArtifact.publicText("Normal text"))
        val unrelated = "{\"format\":\"unrelated\",\"summary\":\"not a research answer\"}"
        assertEquals(unrelated, CollaborationResearchArtifact.publicText(unrelated))
    }

    @Test fun longHandoffRemainsParseableAndRetainsAnExplicitOriginalReference() {
        val raw = artifact().put("workspace", JSONArray().put(JSONObject().put("body", "x".repeat(25_000)))).toString()
        val compact = CollaborationResearchArtifact.compactHandoff(raw, "a".repeat(64))
        assertTrue(compact.length < 12_000)
        val json = requireNotNull(CollaborationResearchArtifact.decode(compact))
        assertEquals(24, json.getJSONArray("findings").length())
        assertEquals("a".repeat(64), json.getString("archive_record_id"))
        assertTrue(json.getBoolean("handoff_projection"))
        assertEquals(raw, CollaborationResearchArtifact.compactHandoff(raw, ""))
    }
}
