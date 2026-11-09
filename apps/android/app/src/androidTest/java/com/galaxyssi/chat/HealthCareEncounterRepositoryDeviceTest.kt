package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareEncounterRepositoryDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val draft = HealthCareEncounterDraft("Synthetic consultation", note = "Synthetic local note")
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore, HealthCareConcern, HealthCareEncounterRepository) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            val issue = HealthCareFollowUpTestFixture.confirmed(context, names)
            HealthCareStore(context, names.care).use { test(names, it, issue, HealthCareEncounterRepository(context, names)) }
        } finally { listOf(names.care, names.records, names.privacy, names.profile, names.reminders).forEach(context::deleteDatabase) }
    }
    private fun save(repository: HealthCareEncounterRepository, snapshot: HealthCareEncounterSnapshot) = repository.save(
        snapshot, UUID.randomUUID().toString(), null, draft, UUID.randomUUID().toString())

    @Test fun saveReopenEditAndDeleteUseTheSameConcernWithoutClinicalSideEffects(): Unit = fixture { names, store, issue, repository ->
        val before = repository.load(issue.id)
        val saved = save(repository, before).encounter
        val reopened = HealthCareEncounterRepository(context, names).load(issue.id, selectedId = saved.id, historyBefore = Int.MAX_VALUE)
        assertEquals(saved, reopened.selected); assertEquals(listOf(saved), reopened.history!!.items)
        assertTrue(reopened.page.items.isEmpty())
        val edited = repository.save(reopened, saved.id, saved.revision, draft.copy(facility = "Synthetic clinic"), UUID.randomUUID().toString()).encounter
        assertEquals(saved.sourceRecord, edited.sourceRecord)
        assertEquals(issue.actions, store.concern(issue.id)!!.actions); assertEquals(issue.stage, store.concern(issue.id)!!.stage)
        assertTrue(store.reminders(issue.id).isEmpty()); assertTrue(store.researchJobs(issue.id).isEmpty())
        repository.delete(repository.load(issue.id), edited)
        assertTrue(repository.load(issue.id).page.items.isEmpty())
        assertTrue(store.encounterHistory(issue.id, saved.id).items.isEmpty())
    }
    @Test fun privacyOffOnRejectsOldEditorAndDisabledReads(): Unit = fixture { names, store, issue, repository ->
        val before = repository.load(issue.id)
        HealthPrivacyStore(context, names.privacy).use { privacy ->
            privacy.change(HealthPrivacyOption.PROFILE_CONTEXT, false, privacy.policy().version)
            assertThrows(HealthAccessBlocked::class.java) { repository.load(issue.id) }
            assertThrows(HealthPrivacyConflict::class.java) { save(repository, before) }
            privacy.change(HealthPrivacyOption.PROFILE_CONTEXT, true, privacy.policy().version)
        }
        assertThrows(HealthPrivacyConflict::class.java) { save(repository, before) }
        assertTrue(store.encounters(issue.id).items.isEmpty())
        save(repository, repository.load(issue.id))
    }
    @Test fun sourceChangesBeforeEvaluationRejectTheOldEditor(): Unit = fixture { names, store, issue, repository ->
        val before = repository.load(issue.id)
        HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
            mapOf("glucose" to "6.2"), "mmol/L", System.currentTimeMillis())) }
        assertThrows(HealthCareConflict::class.java) { save(repository, before) }
        assertTrue(store.encounters(issue.id).items.isEmpty())
        save(repository, repository.load(issue.id))
    }
    @Test fun changedSettingsAndConcernRevisionsRejectTheOldEditor(): Unit = fixture { _, store, issue, repository ->
        val before = repository.load(issue.id)
        store.configure(false, store.settings().version)
        assertThrows(HealthCareConflict::class.java) { save(repository, before) }
        val refreshed = repository.load(issue.id)
        store.update(issue.id, refreshed.issue.revision, "synthetic_encounter_conflict") { it.copy(stage = HealthCareStage.REASSESS) }
        assertThrows(HealthCareConflict::class.java) { save(repository, refreshed) }
        assertTrue(store.encounters(issue.id).items.isEmpty())
    }
    @Test fun disabledProactiveChecksStillAllowManualLocalVisitRecords(): Unit = fixture { _, store, issue, repository ->
        store.configure(false, store.settings().version)
        val saved = save(repository, repository.load(issue.id)).encounter
        assertEquals(saved, repository.load(issue.id, selectedId = saved.id).selected)
        assertFalse(store.settings().enabled)
    }
    @Test fun deletedConcernAndMissingSelectionDoNotReturnAnotherRecord(): Unit = fixture { _, store, issue, repository ->
        val saved = save(repository, repository.load(issue.id)).encounter
        assertThrows(HealthCareConflict::class.java) { repository.load(issue.id, selectedId = UUID.randomUUID().toString()) }
        val before = repository.load(issue.id)
        store.delete(issue.id, before.issue.revision)
        assertThrows(HealthCareConflict::class.java) { repository.delete(before, saved) }
        assertThrows(HealthCareConflict::class.java) { repository.load(issue.id) }
    }
    @Test fun continuedPageRejectsChangesAndFreshFirstPageFindsTheNewRecord(): Unit = fixture { _, store, issue, repository ->
        repeat(32) { store.saveEncounter(issue.id, store.concern(issue.id)!!.revision, UUID.randomUUID().toString(), null,
            draft.copy(note = "Synthetic visit $it"), UUID.randomUUID().toString(), System.currentTimeMillis()) }
        val first = repository.load(issue.id)
        assertEquals(30, first.page.items.size)
        val second = repository.load(issue.id, first.page.next!!, first.page.concernRevision)
        assertEquals(2, second.page.items.size)
        val saved = save(repository, first).encounter
        assertThrows(HealthCareConflict::class.java) { repository.load(issue.id, first.page.next, first.page.concernRevision) }
        assertEquals(saved, repository.load(issue.id).page.items.first())
    }
}
