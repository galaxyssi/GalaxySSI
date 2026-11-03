package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationResearchArtifactTest {
    @Test fun instructionsUseExactRosterIdsWithoutRequiringUuidSyntax() {
        CollaborationResearchStage.values().forEach { stage ->
            val instructions = CollaborationResearchArtifact.instructions(stage)
            assertFalse(instructions.contains("exact member UUID"))
            if (stage == CollaborationResearchStage.DELIVER) {
                assertTrue(instructions.contains("Return a concise public Markdown answer"))
                assertFalse(instructions.contains("requests"))
            } else {
                assertTrue(instructions.contains("exact roster member ID"))
                assertTrue(instructions.contains(CollaborationPeerExchangePolicy.RECIPIENT_INSTRUCTIONS))
            }
        }
        for (id in listOf("turing", "member:primary-7", "f71e12a1-d4dc-4b53-9bfe-e69f081f7826")) {
            val raw = artifact().put("requests", JSONArray().put(JSONObject()
                .put("to", JSONArray(listOf(id))).put("question", "Check the measured alternative")))
            val decoded = requireNotNull(CollaborationResearchArtifact.decode(raw.toString()))
            assertEquals(id, decoded.getJSONArray("requests").getJSONObject(0).getJSONArray("to").getString(0))
        }
    }

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

    @Test fun missingNotesDefaultOnlyInDecodedEnvelopeWithoutInventingFindings() {
        val input = artifact().apply { remove("candidates"); remove("findings") }
        val original = input.toString()
        val decoded = requireNotNull(CollaborationResearchArtifact.decode(original))
        assertEquals(0, decoded.getJSONArray("candidates").length())
        assertEquals(0, decoded.getJSONArray("findings").length())
        assertEquals(input.getJSONArray("memory").toString(), decoded.getJSONArray("memory").toString())
        assertFalse(input.has("candidates")); assertFalse(input.has("findings"))
        assertEquals(original, input.toString())
        val handoff = JSONObject(CollaborationResearchArtifact.handoff(original, CollaborationResearchStage.EXPLORE))
        assertEquals(decoded.toString(), handoff.toString())
        assertFalse(handoff.optBoolean("unstructured"))
        assertEquals(original, CollaborationResearchArtifact.compactHandoff(original, "a".repeat(64)))
    }

    @Test fun missingOneArrayDoesNotDiscardTheOtherAndMalformedSuppliedValuesStayInvalid() {
        listOf("candidates", "findings").forEach { field ->
            val other = if (field == "candidates") "findings" else "candidates"
            val input = artifact().apply { remove(field) }
            val decoded = requireNotNull(CollaborationResearchArtifact.decode(input.toString()))
            assertEquals(0, decoded.getJSONArray(field).length())
            assertEquals(input.getJSONArray(other).toString(), decoded.getJSONArray(other).toString())
            listOf(JSONObject.NULL, "[]", JSONObject(), 0, false).forEach { bad ->
                input.put(field, bad)
                assertNull(CollaborationResearchArtifact.decode(input.toString()))
                assertEquals("$field must be an array when supplied", CollaborationResearchArtifact.validationError(input.toString()))
            }
        }
    }

    @Test fun formatAndNonblankSummaryAreStillRequired() {
        val minimal = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Observed result")
        assertNotNull(CollaborationResearchArtifact.decode(minimal.toString()))
        assertNull(CollaborationResearchArtifact.decode(JSONObject(minimal.toString()).apply { remove("format") }.toString()))
        assertNull(CollaborationResearchArtifact.decode(JSONObject(minimal.toString()).apply { remove("summary") }.toString()))
        assertNull(CollaborationResearchArtifact.decode(minimal.put("summary", " ").toString()))
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
