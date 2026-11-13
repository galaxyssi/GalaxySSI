package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareModelReviewTest {
    private fun id() = UUID.randomUUID().toString()
    private val grant = HealthCareDiscussionGrant(id(), id(), id(), 1, "settings", "privacy", "a".repeat(64),
        1000, "fixture-provider", "fixture-model", "high", researchAuthorizationId = id())
    private val input = HealthCareModelReviewInput("Review summary", "Observed change", "No retrieved evidence yet",
        "Clarify measurement context", HealthCareReviewDecision.CLARIFY, listOf(HealthCareReviewEvent.SOURCE_CHANGE),
        listOf(HealthCareRecordRef(id(), 1)), emptyList(), "", false, "No newly verified finding", listOf(HealthCareQuestionRef(id(), 1)))
    private val value = HealthCareModelReview(grant, "b".repeat(64), "input-v1", 1001, input)

    @Test fun structuredAssessmentRoundTripsWithActualGrant() {
        assertEquals(value, HealthCareModelReview.from(value.json()))
        assertEquals(input, HealthCareModelReviewInput.parse(input.json().toNativeObject()))
    }
    @Test fun legacyAssessmentStaysReadableWithoutInventingRetainedQuestions() {
        val legacy = value.json().also { it.getJSONObject("assessment").remove("questions") }
        val saved = HealthCareModelReview.from(legacy)
        assertEquals(HealthCareReviewDecision.CLARIFY, saved.input.decision)
        assertTrue(saved.input.questions.isEmpty())
        assertThrows(IllegalArgumentException::class.java) { HealthCareModelReviewInput.parse(saved.input.json().toNativeObject()) }
        val observation = saved.input.copy(decision = HealthCareReviewDecision.OBSERVE)
        assertEquals(observation, HealthCareModelReviewInput.parse(observation.json().toNativeObject()))
    }
    @Test fun clarificationRequiresUniqueExactQuestionReferences() {
        val base = input.json().toNativeObject()
        listOf(base - "questions", base + ("questions" to emptyList<Any>()),
            base + ("questions" to listOf(mapOf("id" to input.questions.single().id, "revision" to 1.2))),
            base + ("questions" to listOf(mapOf("id" to "invented", "revision" to 1))),
            base + ("questions" to List(2) { mapOf("id" to input.questions.single().id, "revision" to it + 1) }))
            .forEach { assertThrows(IllegalArgumentException::class.java) { HealthCareModelReviewInput.parse(it) } }
    }
    @Test fun unknownExecutionFlagsAndInvalidShapesAreRejected() {
        val base = input.json().toNativeObject()
        listOf(base + ("confirmed" to true), base - "uncertainty", base + ("attention_requested" to "false"),
            base + ("records" to listOf(mapOf("id" to input.records.first().id, "revision" to 1.5))),
            base + ("review_events" to listOf("WAKE_EVERY_MINUTE")), base + ("decision" to "DIAGNOSE"))
            .forEach { assertThrows(IllegalArgumentException::class.java) { HealthCareModelReviewInput.parse(it) } }
    }
    @Test fun boundedOutputRejectsEmptyAndDuplicateEvidence() {
        assertThrows(IllegalArgumentException::class.java) { input.copy(summary = " ") }
        assertThrows(IllegalArgumentException::class.java) { input.copy(rationale = "x".repeat(2001)) }
        assertThrows(IllegalArgumentException::class.java) { input.copy(records = emptyList()) }
        assertThrows(IllegalArgumentException::class.java) { input.copy(records = input.records + input.records) }
        assertThrows(IllegalArgumentException::class.java) { input.copy(events = input.events + input.events) }
        assertThrows(IllegalArgumentException::class.java) { input.copy(evidenceIds = listOf("invented")) }
        assertThrows(IllegalArgumentException::class.java) { input.copy(decision = HealthCareReviewDecision.PROPOSE_PLAN) }
    }
    @Test fun priorOpinionRequiresSameDestinationAndSharingScope() {
        val next = grant.copy(turnId = id(), approvedAt = 2000)
        assertTrue(value.reusable(next))
        listOf(next.copy(conversationId = id()), next.copy(concernId = id()), next.copy(destination = "c".repeat(64)),
            next.copy(privacyVersion = "changed"), next.copy(settingsVersion = "changed"), next.copy(modelId = "other"),
            next.copy(targetId = "other"), next.copy(effort = "low"), next.copy(approvedAt = 1000), grant)
            .forEach { assertFalse(value.reusable(it)) }
        assertFalse(value.copy(grant = grant.copy(feedbackHistoryShared = true)).reusable(next))
        assertFalse(value.copy(grant = grant.copy(questionsShared = true)).reusable(next))
    }
    @Test fun onlyAutomaticHealthTurnsReceiveTheRecordingTool() {
        assertTrue(HealthCareModelReviewTool.ID in HealthCareDiscussionPolicy.tools(grant))
        assertFalse(HealthCareModelReviewTool.ID in HealthCareDiscussionPolicy.tools(grant.copy(researchAuthorizationId = "")))
    }
    @Test fun incompleteInputIsCorrectableWithoutBeingReportedAsRevokedConsent() {
        var incomplete = true
        val registry = AgentNativeToolRegistry()
        registry.register(HealthCareModelReviewTool.definition { _, supplied ->
            require(!incomplete) { "Missing selected inputs" }
            value.copy(input = supplied)
        })
        val failed = registry.invoke(HealthCareModelReviewTool.ID, input.json().toNativeObject())
        assertEquals("invalid_health_review", failed.error?.code)
        assertTrue(failed.error!!.message.contains("every available selected"))
        assertFalse(failed.error.retryable)
        incomplete = false
        val repaired = registry.invoke(HealthCareModelReviewTool.ID, input.json().toNativeObject())
        assertTrue(repaired.isSuccess)
        assertEquals(true, repaired.output["stored"])
        assertEquals(false, repaired.output["questions_created"])
        assertEquals(listOf(mapOf("id" to input.questions.single().id, "revision" to 1)), repaired.output["question_references"])
    }
    @Test fun legacyJobsDoNotAcquireNewCompletionRequirements() {
        val job = HealthCareResearchJob(grant.turnId, grant.researchAuthorizationId, grant.concernId, grant.conversationId,
            "b".repeat(64), 1, 1000, reviewRequired = true)
        assertTrue(HealthCareResearchJob.from(job.json()).reviewRequired)
        assertFalse(HealthCareResearchJob.from(job.json().apply { remove("review_required") }).reviewRequired)
    }
}
