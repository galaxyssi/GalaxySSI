package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareVisitDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val defaults = HealthCareVisitSection.entries.filter { it != HealthCareVisitSection.PROFILE }.toSet()
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore, HealthCareConcern, HealthCareVisitRepository) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            val issue = HealthCareFollowUpTestFixture.confirmed(context, names)
            HealthCareStore(context, names.care).use { test(names, it, issue, HealthCareVisitRepository(context, names)) }
        } finally { listOf(names.care, names.records, names.privacy, names.profile, names.reminders).forEach(context::deleteDatabase) }
    }
    private fun profile(names: HealthOverviewDatabases, store: HealthCareStore, issue: HealthCareConcern): HealthCareConcern {
        HealthProfileStore(context, names.profile, names.privacy).use { saved ->
            fun basic(field: HealthProfileField, value: String, unit: String = "") {
                val before = saved.snapshot()
                saved.saveBasics(HealthProfileDraft(before.generation, mapOf(field to HealthProfileInput(value, unit)),
                    mapOf(field to before.cells.getValue(field).token)))
            }
            basic(HealthProfileField.NAME, "private-fixture-name")
            basic(HealthProfileField.HEIGHT, "170", "cm")
            val included = saved.newEntry(HealthBackgroundKind.HISTORY).let { saved.saveEntry(it.copy(entry = it.entry.copy(name = "included-fixture-history"))) }
            saved.newEntry(HealthBackgroundKind.ALLERGY).let { saved.saveEntry(it.copy(entry = it.entry.copy(name = "excluded-fixture-allergy"))) }
            val capture = saved.capture(setOf(HealthProfileField.HEIGHT), setOf(included.id))
            val link = HealthCareProfileLink(HealthCareProfileScope(capture.stamp.generation, capture.fields.keys, setOf(included.id)), capture.stamp)
            return store.update(issue.id, issue.revision, "fixture_visit_scope") { it.copy(profileLink = link) }
        }
    }
    private fun text(value: HealthCareVisitSummary) = value.selectedText(value.items.map { it.key }.toSet())

    @Test fun defaultScopeDoesNotReadProfileOrCreateResearchOrReminders(): Unit = fixture { names, store, initial, repository ->
        val issue = profile(names, store, initial)
        val value = repository.load(issue.id, defaults)
        val output = text(value)
        assertFalse(output.contains("private-fixture-name")); assertFalse(output.contains("included-fixture-history"))
        assertFalse(output.contains("excluded-fixture-allergy")); assertNull(value.profile)
        assertTrue(store.researchJobs(issue.id).isEmpty()); assertTrue(store.reminders(issue.id).isEmpty())
        repository.validate(value)
    }
    @Test fun profileAddsOnlyLinkedSavedFieldsAndCanBeIndividuallyExcluded(): Unit = fixture { names, store, initial, repository ->
        val issue = profile(names, store, initial)
        val value = repository.load(issue.id, HealthCareVisitSection.entries.toSet())
        val output = text(value)
        assertTrue(output.contains("170 cm")); assertTrue(output.contains("included-fixture-history"))
        assertFalse(output.contains("private-fixture-name")); assertFalse(output.contains("excluded-fixture-allergy"))
        val reduced = value.selectedText(value.items.filter { it.section != HealthCareVisitSection.PROFILE }.map { it.key }.toSet())
        assertFalse(reduced.contains("170 cm")); assertFalse(reduced.contains("included-fixture-history"))
    }
    @Test fun changesAfterPreviewRejectSharingBeforeEngineRefresh(): Unit = fixture { names, _, issue, repository ->
        val before = repository.load(issue.id, defaults)
        HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.4"),
            "mmol/L", System.currentTimeMillis(), reference = "4-6")) }
        assertThrows(HealthCareConflict::class.java) { repository.validate(before) }
        val after = repository.load(issue.id, defaults); assertNotEquals(before.inputVersion, after.inputVersion)
    }
    @Test fun privacyOffOnCannotReuseOldPreview(): Unit = fixture { names, _, issue, repository ->
        val before = repository.load(issue.id, defaults)
        HealthPrivacyStore(context, names.privacy).use {
            it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version)
            assertThrows(HealthCareConflict::class.java) { repository.validate(before) }
            assertThrows(IllegalStateException::class.java) { repository.load(issue.id, defaults) }
            it.change(HealthPrivacyOption.CONFIRMED_METRICS, true, it.policy().version)
        }
        assertThrows(HealthCareConflict::class.java) { repository.validate(before) }
    }
    @Test fun selectedProfileEditsInvalidatePreviewEvenBeforeConcernChanges(): Unit = fixture { names, store, initial, repository ->
        val issue = profile(names, store, initial)
        val before = repository.load(issue.id, HealthCareVisitSection.entries.toSet())
        HealthProfileStore(context, names.profile, names.privacy).use {
            val saved = it.snapshot(); it.saveBasics(HealthProfileDraft(saved.generation,
                mapOf(HealthProfileField.HEIGHT to HealthProfileInput("172", "cm")),
                mapOf(HealthProfileField.HEIGHT to saved.cells.getValue(HealthProfileField.HEIGHT).token)))
        }
        assertThrows(HealthCareConflict::class.java) { repository.validate(before) }
    }
    @Test fun deletedConcernAndExpiredPreviewCannotBeShared(): Unit = fixture { _, store, issue, repository ->
        val before = repository.load(issue.id, defaults)
        assertThrows(HealthCareConflict::class.java) { repository.validate(before, before.createdAt + HealthCareVisitSummary.MAX_AGE) }
        store.delete(issue.id, store.concern(issue.id)!!.revision)
        assertThrows(HealthCareConflict::class.java) { repository.validate(before) }
    }
    @Test fun historyIsBoundedAndOmissionIsExplicit(): Unit = fixture { names, _, issue, repository ->
        val now = System.currentTimeMillis()
        HealthRecordStore(context, names.records).use { records -> repeat(20) { index ->
            records.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.${index % 10}"), "mmol/L", now - index * 1000))
        } }
        val value = repository.load(issue.id, setOf(HealthCareVisitSection.MEASUREMENTS))
        assertEquals(8, value.items.size)
        assertTrue(value.limitations.contains(context.getString(R.string.health_visit_more_records)))
        assertTrue(value.items.all { it.record != null })
    }
    @Test fun partialFeedbackIsNotRenderedAsClinicalRecovery(): Unit = fixture { _, store, issue, repository ->
        store.recordActionFeedback(issue.id, issue.revision, issue.actions.first().id, HealthCareFeedbackKind.BARRIER,
            "synthetic-practical-barrier", UUID.randomUUID().toString(), System.currentTimeMillis())
        val value = repository.load(issue.id, setOf(HealthCareVisitSection.ACTIONS))
        assertTrue(text(value).contains("synthetic-practical-barrier"))
        assertTrue(text(value).contains(context.getString(R.string.health_visit_action_notice)))
        assertEquals(HealthCareActionState.CONFIRMED, store.concern(issue.id)!!.actions.first().state)
    }
    @Test fun missingAndStaleContextDoNotTurnIntoNoAnswers(): Unit = fixture { _, store, issue, repository ->
        store.update(issue.id, issue.revision, "fixture_old_context") { it.copy(context = HealthCareContext(
            HealthCareRecordRef(UUID.randomUUID().toString(), 1), HealthCareTruth.NO, fastingHours = 0, confirmedAt = System.currentTimeMillis())) }
        val value = repository.load(issue.id, setOf(HealthCareVisitSection.CONTEXT))
        assertTrue(text(value).contains(context.getString(R.string.health_care_unknown)))
        assertTrue(text(value).contains(context.getString(R.string.health_visit_context_notice)))
    }
    @Test fun foreignConcernQuestionIsRejected(): Unit = fixture { _, _, issue, _ ->
        val question = HealthCareQuestion(UUID.randomUUID().toString(), UUID.randomUUID().toString(), "fixture.question",
            "Synthetic question", "Synthetic purpose", HealthCareQuestionPolicy.basis(issue), HealthCareQuestionPolicy.scope(issue),
            issue.assessment.record, issue.assessment.measuredAt, UUID.randomUUID().toString(), 1, issue.createdAt, issue.createdAt)
        assertThrows(IllegalArgumentException::class.java) { HealthCareVisitPresentation(context).items(issue,
            setOf(HealthCareVisitSection.QUESTIONS), emptyList(), null, listOf(question)) }
    }
    @Test fun alreadyKnownContextQuestionIsNotShownAsUnanswered(): Unit = fixture { _, _, initial, _ ->
        val issue = initial.copy(context = HealthCareContext(initial.assessment.record!!,
            adult = HealthCareTruth.YES, confirmedAt = System.currentTimeMillis()))
        val knownKey = HealthCareQuestionPolicy.known(issue, null).keys.first()
        val question = HealthCareQuestion(UUID.randomUUID().toString(), issue.id, knownKey,
            "Synthetic known question", "Synthetic purpose", HealthCareQuestionPolicy.basis(issue), HealthCareQuestionPolicy.scope(issue),
            issue.assessment.record, issue.assessment.measuredAt, UUID.randomUUID().toString(), 1, issue.createdAt, issue.createdAt)
        val item = HealthCareVisitPresentation(context).items(issue, setOf(HealthCareVisitSection.QUESTIONS),
            emptyList(), null, listOf(question)).single()
        assertTrue(item.text.contains(context.getString(R.string.health_visit_question_answered)))
        assertTrue(item.text.contains(context.getString(R.string.health_visit_question_known)))
        assertFalse(item.text.contains(context.getString(R.string.health_visit_question_open)))
    }
    @Test fun staleQuestionAnswerIsNotSharedAsCurrentFact(): Unit = fixture { _, _, issue, _ ->
        val question = HealthCareQuestion(UUID.randomUUID().toString(), issue.id, "fixture.old",
            "Synthetic previous question", "Synthetic purpose", "0".repeat(64), HealthCareQuestionPolicy.scope(issue),
            issue.assessment.record, issue.assessment.measuredAt, UUID.randomUUID().toString(), 1, issue.createdAt, issue.createdAt,
            HealthCareQuestionState.ANSWERED, "private-old-answer")
        val item = HealthCareVisitPresentation(context).items(issue, setOf(HealthCareVisitSection.QUESTIONS),
            emptyList(), null, listOf(question)).single()
        assertTrue(item.text.contains(context.getString(R.string.health_visit_stale_question)))
        assertFalse(item.text.contains("private-old-answer"))
    }
}
