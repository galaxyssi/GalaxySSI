package com.galaxyssi.chat

import java.time.Instant
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCarePlanPolicyTest {
    private val now = 1_793_000_000_000L
    private val settings = HealthCareSettings(true, "settings1")
    private val privacy = HealthPrivacyPolicy(version = "privacy1")
    private val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "input1",
        HealthCareAssessment(HealthCareRecordRef(UUID.randomUUID().toString(), 1), now, "6.3", "mmol/L", "4-6", setOf(HealthCareSignal.REPORT_HIGH)))
    private val grant = HealthCareDiscussionGrant(UUID.randomUUID().toString(), UUID.randomUUID().toString(), issue.id,
        issue.revision, settings.version, privacy.version, "a".repeat(64), now, "fixture-provider", "fixture-model", "high")
    private val source = mapOf("title" to "Synthetic source", "url" to "https://example.test/guideline", "version" to "fixture-2026",
        "applicability" to "Synthetic fixture; no medical advice", "evidence_id" to UUID.randomUUID().toString(),
        "supporting_quote" to "Synthetic fixture; no medical advice")
    private fun action(kind: String = "CONTEXT", from: String = "", until: String = ""): AgentNativeJsonObject = mapOf(
        "kind" to kind, "description" to "Confirm the test conditions", "rationale" to "The report context is incomplete",
        "source_index" to 0, "due_from" to from, "due_until" to until)
    private fun input(actions: List<AgentNativeJsonObject> = listOf(action()), sources: List<AgentNativeJsonObject> = listOf(source)) =
        mapOf("uncertainty" to "Fasting conditions have not been confirmed", "sources" to sources, "actions" to actions)
    private fun parse(input: AgentNativeJsonObject = input()) = HealthCarePlanPolicy.parse(input, grant, issue, now)
    private fun current(plan: HealthCarePlan = parse(), c: HealthCareConcern? = issue, s: HealthCareSettings = settings,
        p: HealthPrivacyPolicy = privacy, version: String = issue.inputVersion) = HealthCarePlanPolicy.current(plan, c, s, p, version)

    @Test fun modelDraftHasNoConfirmedActionTargetOrReminder() {
        val plan = parse()
        assertEquals(HealthCarePlanState.PENDING, plan.state)
        assertTrue(plan.selected.isEmpty()); assertNull(plan.resolvedAt)
        assertTrue(plan.actions.all { it.state == HealthCareActionState.PROPOSED && it.confirmedAt == null })
        assertEquals(plan, HealthCarePlan.from(plan.json()))
        assertNull(issue.target); assertNull(issue.nextDue)
    }
    @Test fun canonicalReplayIgnoresMapOrderButNotChangedContent() {
        val input = input(); val first = parse(input)
        assertEquals(first.requestHash, parse(input.toList().reversed().toMap()).requestHash)
        assertEquals(first.actions, parse(input).actions)
        assertNotEquals(first.requestHash, parse(input + ("uncertainty" to "Other uncertainty")).requestHash)
        val other = HealthCarePlanPolicy.parse(input, grant.copy(turnId = UUID.randomUUID().toString()), issue, now)
        assertNotEquals(first.actions.single().id, other.actions.single().id)
    }
    @Test fun unknownFieldsCannotSmuggleTargetsConfirmationOrOtherConcernIds() {
        listOf("confirmed", "target", "concern_id", "reminder", "medication").forEach {
            assertThrows(IllegalArgumentException::class.java) { parse(input() + (it to "unexpected")) }
        }
        assertThrows(IllegalArgumentException::class.java) { parse(input(actions = listOf(action() + ("state" to "CONFIRMED")))) }
        assertThrows(IllegalArgumentException::class.java) { parse(input(actions = listOf(action("MEDICATION")))) }
    }
    @Test fun sourcesMustBeBoundedHttpsAndExplicitAboutVersionAndApplicability() {
        listOf("http://example.test", "file:///record", "https://user:pass@example.test", "https:///missing").forEach { url ->
            assertThrows(IllegalArgumentException::class.java) { parse(input(sources = listOf(source + ("url" to url)))) }
        }
        listOf("title", "version", "applicability").forEach { key ->
            assertThrows(IllegalArgumentException::class.java) { parse(input(sources = listOf(source + (key to "")))) }
        }
        assertThrows(IllegalArgumentException::class.java) { parse(input(sources = listOf(source, source))) }
        assertThrows(IllegalArgumentException::class.java) { parse(input(actions = listOf(action() + ("source_index" to 1)))) }
        assertThrows(IllegalArgumentException::class.java) { parse(input(actions = listOf(action() + ("source_index" to 0.5)))) }
    }
    @Test fun reviewWindowsNeedPairedOffsetDatesAndCannotAlreadyBeExpired() {
        val future = Instant.ofEpochMilli(now + 86400000).toString()
        val past = Instant.ofEpochMilli(now - 1).toString()
        listOf(action("RECHECK", future, ""), action("RECHECK", "", future), action("RECHECK", future, past),
            action("RECHECK", past, past), action("RECHECK", "2027-01-01T00:00:00", future)).forEach {
            assertThrows(IllegalArgumentException::class.java) { parse(input(actions = listOf(it))) }
        }
        assertNotNull(parse(input(actions = listOf(action("RECHECK", future, future)))).actions.single().dueFrom)
        assertNull(parse(input(actions = listOf(action("CLINICIAN_DISCUSSION")))).actions.single().dueFrom)
    }
    @Test fun acceptanceRequiresActualSelectionAndNeverSelectsAllByDefault() {
        val plan = parse(input(actions = listOf(action(), action("LIFESTYLE"))))
        assertThrows(IllegalArgumentException::class.java) { HealthCarePlanPolicy.accept(plan, issue, emptySet(), now) }
        assertThrows(IllegalArgumentException::class.java) { HealthCarePlanPolicy.accept(plan, issue, setOf(UUID.randomUUID().toString()), now) }
        val next = HealthCarePlanPolicy.accept(plan, issue, setOf(plan.actions.first().id), now + 1)
        assertEquals(1, next.actions.size); assertEquals(HealthCareActionState.CONFIRMED, next.actions.single().state)
        assertEquals(HealthCareStage.REVIEW_PLAN, next.stage); assertNull(next.target); assertNull(next.nextDue)
    }
    @Test fun acceptanceAddsToExistingPlanAndDoesNotMarkConcernNormalOrComplete() {
        val first = parse(); val accepted = HealthCarePlanPolicy.accept(first, issue, first.actions.map { it.id }.toSet(), now)
        val nextPlan = HealthCarePlanPolicy.parse(input(), grant.copy(turnId = UUID.randomUUID().toString()), accepted, now)
        val result = HealthCarePlanPolicy.accept(nextPlan, accepted, nextPlan.actions.map { it.id }.toSet(), now)
        assertEquals(2, result.actions.size); assertEquals(issue.assessment, result.assessment); assertNull(result.target)
        assertThrows(IllegalArgumentException::class.java) { HealthCarePlanPolicy.accept(first, accepted, first.actions.map { it.id }.toSet(), now) }
    }
    @Test fun recheckTransitionsToWaitingButPastWindowsCannotBeConfirmedLater() {
        val future = Instant.ofEpochMilli(now + 1000).toString()
        val plan = parse(input(actions = listOf(action("RECHECK", future, future))))
        assertEquals(HealthCareStage.WAITING_RESULTS, HealthCarePlanPolicy.accept(plan, issue, setOf(plan.actions.single().id), now).stage)
        assertThrows(IllegalArgumentException::class.java) { HealthCarePlanPolicy.accept(plan, issue, setOf(plan.actions.single().id), now + 1001) }
    }
    @Test fun editsRebindingPauseDeletionAndPermissionsInvalidateDrafts() {
        assertTrue(current()); assertFalse(current(c = null)); assertFalse(current(c = issue.copy(revision = 2)))
        assertFalse(current(c = issue.copy(id = UUID.randomUUID().toString())))
        assertFalse(current(c = issue.copy(stage = HealthCareStage.PAUSED)))
        assertFalse(current(c = issue.copy(assessment = issue.assessment.copy(signals = setOf(HealthCareSignal.SOURCE_REMOVED)))))
        assertFalse(current(p = privacy.copy(profile = false))); assertFalse(current(p = privacy.copy(metrics = false)))
        assertFalse(current(p = privacy.copy(version = "privacy2"))); assertFalse(current(s = settings.copy(enabled = false)))
        assertFalse(current(s = settings.copy(version = "settings2"))); assertFalse(current(version = "new-metric-revision"))
    }
    @Test fun nativeToolReturnsDraftReceiptAndDoesNotExposeConfirmationAuthority() {
        val definition = HealthCarePlanTool.definition { _, input -> parse(input) }
        val registry = AgentNativeToolRegistry().register(definition)
        val result = registry.invoke(HealthCarePlanTool.ID, input(), AgentNativeToolInvocationContext(
            conversationId = grant.conversationId, turnId = grant.turnId))
        assertEquals(AgentNativeToolResultStatus.SUCCEEDED, result.status)
        assertTrue(HealthCarePlanTool.ID in HealthCareDiscussionPolicy.discussionTools)
        assertFalse("galaxyssi.health.plan.confirm" in HealthCareDiscussionPolicy.discussionTools)
        assertEquals(AgentNativeToolEffect.MUTATION, definition.descriptor.effect)
    }
}
