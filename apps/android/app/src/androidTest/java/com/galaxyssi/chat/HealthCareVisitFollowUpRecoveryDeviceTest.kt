package com.galaxyssi.chat

import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class HealthCareVisitFollowUpRecoveryDeviceTest {
    @Test fun isolatedJournalSurvivesAnActualProcessRestart() {
        val phase = InstrumentationRegistry.getArguments().getString("health_visit_followup_phase")
        assumeTrue(phase in setOf("seed", "recover"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val markers = context.getSharedPreferences("health-visit-followup-recovery-test", Context.MODE_PRIVATE)
        if (phase == "seed") {
            check(!markers.contains("fixture")) { "Recover the existing fixture before creating another" }
            val fixture = HealthCareVisitFollowUpFixture(context)
            try {
                fixture.start()
                repeat(32) { fixture.record(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN,
                    feelings = "Synthetic observation $it", needsReview = it == 31)) }
                fixture.record(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.PAUSE, note = "Synthetic pause"))
                val saved = fixture.snapshot()
                assertTrue(markers.edit().putString("fixture", fixture.names.fixture)
                    .putString("concern", fixture.issue.id).putString("encounter", fixture.visit.id)
                    .putString("journal", saved.followUp!!.id).putInt("revision", saved.visit.issue.revision)
                    .putString("stage", saved.visit.issue.stage.name)
                    .putString("process", AgentProcessIdentity.instanceId).commit())
                println("HEALTH_VISIT_FOLLOWUP ready_for_process_restart=true isolated=true entries=34")
            } catch (error: Throwable) { fixture.close(); markers.edit().clear().commit(); throw error }
            return
        }
        val fixtureId = markers.getString("fixture", "").orEmpty()
        require(HealthProfilePolicy.uuid(fixtureId))
        val names = HealthOverviewDatabases(fixtureId)
        assertNotEquals("Restart the app process before recovery", markers.getString("process", ""), AgentProcessIdentity.instanceId)
        try {
            val concern = markers.getString("concern", "").orEmpty()
            val encounter = markers.getString("encounter", "").orEmpty()
            val repository = HealthCareVisitFollowUpRepository(context, names)
            val saved = repository.load(concern, encounter)
            assertEquals(markers.getString("journal", ""), saved.followUp!!.id)
            assertEquals(markers.getInt("revision", -1), saved.visit.issue.revision)
            assertEquals(markers.getString("stage", ""), saved.visit.issue.stage.name)
            assertEquals(HealthCareVisitFollowUpState.PAUSED, saved.followUp.state)
            assertEquals(30, saved.history.items.size)
            val older = repository.load(concern, encounter, saved.history.next!!).history
            assertEquals(4, older.items.size); assertNull(older.next)
            val history = saved.history.items + older.items
            assertEquals(34, history.map { it.operationId }.distinct().size)
            assertTrue(history.zipWithNext().all { (new, old) -> new.value.revision > old.value.revision })
            val last = history.first()
            HealthCareStore(context, names.care).use {
                assertEquals(last, it.recordVisitFollowUp(concern, last.expectedConcern, encounter, last.encounterRevision,
                    last.expectedFollowUp, last.input, last.operationId, System.currentTimeMillis()))
                assertEquals(saved.visit.issue, it.concern(concern)); assertTrue(it.reminders(concern).isEmpty())
            }
            repository.record(saved, HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.RESUME,
                note = "Synthetic reviewed restart"), UUID.randomUUID().toString())
            val resumed = repository.load(concern, encounter)
            assertEquals(HealthCareVisitFollowUpState.REVIEW, resumed.followUp!!.state)
            assertEquals(saved.visit.issue.actions, resumed.visit.issue.actions)
            assertEquals(saved.visit.issue.assessment, resumed.visit.issue.assessment)
            println("HEALTH_VISIT_FOLLOWUP process_changed=true same_journal=true entries=34 replay_idempotent=true resumed_to_review=true")
        } finally {
            listOf(names.care, names.records, names.privacy, names.profile, names.reminders).forEach(context::deleteDatabase)
            assertTrue(markers.edit().clear().commit())
        }
    }
}
