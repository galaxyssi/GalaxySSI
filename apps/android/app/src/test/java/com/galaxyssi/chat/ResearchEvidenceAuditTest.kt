package com.galaxyssi.chat

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ResearchEvidenceAuditTest {
    private val url = "https://example.org/paper"
    private val quote = "A Smith works at Institute A."
    private fun observation(body: Boolean = true) = JSONObject().put("research_trace", JSONObject()
        .put("queries", JSONArray(listOf("Smith publications"))).put("sources", JSONArray().put(JSONObject().put("url", url))))
        .put("evidence_pack", JSONObject().put("items", JSONArray().put(JSONObject().put("url", url)
            .put("excerpt", quote).put("evidence_level", if (body) "retrieved_body" else "search_snippet"))))
    private fun proposal() = JSONObject().put("scope", "Confirmed-so-far publication inventory")
        .put("entities", JSONArray().put(JSONObject().put("id", "person").put("name", "A Smith")
            .put("decision", "include").put("basis", "positive_match").put("reason", "Affiliation matches")
            .put("evidence", JSONArray().put(JSONObject().put("url", url).put("quote", quote)))))
        .put("claims", JSONArray().put(JSONObject().put("id", "c1").put("statement", "The author works at Institute A")
            .put("entity_ids", JSONArray(listOf("person"))).put("assessment", "supported")
            .put("evidence", JSONArray().put(JSONObject().put("url", url).put("quote", quote).put("relation", "supports")))))
        .put("coverage", JSONArray().put(JSONObject().put("facet", "English records").put("status", "searched")
            .put("query", "Smith publications").put("gap", "")))

    @Test fun observedPassageIsAnchoredButNeverSemanticVerification() {
        val audit = ResearchEvidenceAudit().apply { observe(observation()) }
        val result = audit.submit(proposal())
        assertEquals("recorded", result.getString("status"))
        assertEquals("supported", result.getJSONArray("claims").getJSONObject(0).getString("assessment"))
        val ref = result.getJSONArray("claims").getJSONObject(0).getJSONArray("evidence").getJSONObject(0)
        assertTrue(ref.getBoolean("passage_observed"))
        assertEquals(64, ref.getString("passage_sha256").length)
        assertEquals("not_independently_verified", result.getString("semantic_verification"))
        assertEquals("not_established", result.getString("completeness"))
    }

    @Test fun inventedEvidenceAndEntityLinksCannotBecomeSupported() {
        val audit = ResearchEvidenceAudit()
        val result = audit.submit(proposal())
        assertEquals("pending", result.getJSONArray("entities").getJSONObject(0).getString("decision"))
        assertEquals("unknown", result.getJSONArray("claims").getJSONObject(0).getString("assessment"))
        assertFalse(result.getJSONArray("coverage").getJSONObject(0).getBoolean("query_observed"))
        assertEquals(0, result.getJSONObject("observed").getInt("source_urls"))
    }

    @Test fun absenceIsPendingAndCounterevidenceSurvives() {
        val audit = ResearchEvidenceAudit().apply { observe(observation()) }
        val input = proposal()
        input.getJSONArray("entities").getJSONObject(0).put("decision", "exclude").put("basis", "insufficient_evidence")
        input.getJSONArray("claims").getJSONObject(0).getJSONArray("evidence").put(JSONObject()
            .put("url", "https://example.org/other").put("quote", "Disputed identity remains unresolved.").put("relation", "contradicts"))
        val result = audit.submit(input)
        assertEquals("pending", result.getJSONArray("entities").getJSONObject(0).getString("decision"))
        assertEquals("disputed", result.getJSONArray("claims").getJSONObject(0).getString("assessment"))
        assertEquals(2, result.getJSONArray("claims").getJSONObject(0).getJSONArray("evidence").length())
    }

    @Test fun positiveMismatchRemainsExplicitModelAssessment() {
        val audit = ResearchEvidenceAudit().apply { observe(observation()) }
        val input = proposal()
        input.getJSONArray("entities").getJSONObject(0).put("decision", "exclude").put("basis", "positive_mismatch")
        val entity = audit.submit(input).getJSONArray("entities").getJSONObject(0)
        assertEquals("exclude", entity.getString("decision"))
        assertEquals("model_assessment_not_independent_verification", entity.getString("decision_authority"))
    }

    @Test fun duplicateObservationsAndFragmentUrlsDoNotInflateCounts() {
        val audit = ResearchEvidenceAudit().apply { repeat(3) { observe(observation()) } }
        val other = observation().apply {
            getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0).put("url", "$url#section")
        }
        audit.observe(other)
        val counts = audit.report().getJSONObject("observed")
        assertEquals(1, counts.getInt("unique_queries"))
        assertEquals(1, counts.getInt("source_urls"))
        assertEquals(1, counts.getInt("body_urls"))
    }

    @Test fun snippetCannotBeUpgradedByAnUnrelatedBodyPassage() {
        val audit = ResearchEvidenceAudit().apply { observe(observation(false)) }
        val another = observation()
        another.getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0).put("excerpt", "An unrelated paragraph from the body.")
        audit.observe(another)
        val ref = audit.submit(proposal()).getJSONArray("claims").getJSONObject(0).getJSONArray("evidence").getJSONObject(0)
        assertEquals("search_snippet_or_unavailable", ref.getString("evidence_scope"))
    }

    @Test fun foreignTaskAndWebSubmittedAuditCannotPolluteState() {
        val first = ResearchEvidenceAudit().apply { observe(observation()); submit(proposal()) }
        val second = ResearchEvidenceAudit().apply { observe(first.report()) }
        assertEquals("not_submitted", second.report().getString("status"))
        assertEquals(0, second.report().getJSONObject("observed").getInt("source_urls"))
    }

    @Test fun duplicateIdsAndOversizedRowsRejectAtomically() {
        val audit = ResearchEvidenceAudit().apply { observe(observation()); submit(proposal()) }
        val input = proposal()
        input.getJSONArray("claims").put(input.getJSONArray("claims").getJSONObject(0))
        assertEquals("invalid", audit.submit(input).getString("status"))
        val oversized = proposal().put("entities", JSONArray((0..40).map { JSONObject() }))
        assertEquals("invalid", audit.submit(oversized).getString("status"))
        assertEquals(1, audit.report().getJSONArray("claims").length())
    }

    @Test fun malformedValuesReturnInvalidNotCrashOrSuccessfulAudit() {
        val audit = ResearchEvidenceAudit()
        val input = proposal()
        input.getJSONArray("entities").getJSONObject(0).put("evidence", "not an array")
        assertEquals("invalid", audit.submit(input).getString("status"))
        input.getJSONArray("entities").getJSONObject(0).put("evidence", JSONArray()).put("decision", JSONObject())
        assertEquals("invalid", audit.submit(input).getString("status"))
    }

    @Test fun checkpointsReplayEvidenceBeforeAuditAndRequireKnownTool() {
        val audit = ResearchEvidenceAudit().apply { observe(observation()); restore(ResearchEvidenceAudit.TOOL, proposal()) }
        assertEquals("recorded", audit.report().getString("status"))
        assertTrue(CloudResearchCheckpoint.isReadOnly(ResearchEvidenceAudit.TOOL, proposal()))
        val empty = ResearchEvidenceAudit().apply { restore("web_search", proposal()) }
        assertEquals("not_submitted", empty.report().getString("status"))
    }

    @Test fun investigationReviewDoesNotAffectOrdinaryWeather() {
        val audit = ResearchEvidenceAudit().apply { observe(observation()) }
        assertNull(audit.reviewPrompt("Weather today"))
        assertNotNull(audit.reviewPrompt("Find all publications by this author"))
        audit.submit(proposal())
        assertNull(audit.reviewPrompt("Find all publications by this author"))
    }

    @Test fun sharedToolSchemaIsAvailableWithoutChangingOtherTools() {
        val folder = File("../../desktop/core/galaxyssi-link/backend/research_contract")
        val spec = JSONObject(File(folder, "research-audit-tool.json").readText())
        val standard = ResearchQualityStandard(JSONObject(File(folder, "research-quality.json").readText()), spec)
        assertEquals(ResearchEvidenceAudit.TOOL, standard.auditTool!!.getJSONObject("function").getString("name"))
        assertEquals(80, spec.getJSONObject("parameters").getJSONObject("properties").getJSONObject("claims").getInt("maxItems"))
        assertTrue(standard.prompt.contains("positive") || standard.prompt.contains("affirmative"))
    }
}
