package com.galaxyssi.chat

import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class HealthCareVisitReviewRecoveryDeviceTest {
    @Test fun sameReminderSurvivesActualProcessDeathAndDeliversOnce() {
        val phase = InstrumentationRegistry.getArguments().getString("health_visit_review_phase")
        assumeTrue(phase in setOf("seed", "recover"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val markers = context.getSharedPreferences("health-visit-review-recovery-test", Context.MODE_PRIVATE)
        if (phase == "seed") {
            check(!markers.contains("fixture")) { "Recover the existing fixture first" }
            val f = HealthCareVisitFollowUpFixture(context)
            try {
                f.start(); val reminder = f.repository.schedule(f.snapshot(), System.currentTimeMillis() + 60000)
                f.record(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN, note = "Synthetic check-in after scheduling"))
                assertTrue(markers.edit().putString("fixture", f.names.fixture).putString("concern", f.issue.id)
                    .putString("encounter", f.visit.id).putString("token", reminder.token).putString("action", reminder.actionId)
                    .putString("process", AgentProcessIdentity.instanceId).commit())
                println("HEALTH_VISIT_REVIEW ready_for_process_restart=true isolated=true")
            } catch (error: Throwable) { f.close(); markers.edit().clear().commit(); throw error }
            return
        }
        val fixture = markers.getString("fixture", "").orEmpty(); require(HealthProfilePolicy.uuid(fixture))
        val names = HealthOverviewDatabases(fixture)
        assertNotEquals("An actual process restart is required", markers.getString("process", ""), AgentProcessIdentity.instanceId)
        try {
            val id = markers.getString("concern", "").orEmpty(); val encounter = markers.getString("encounter", "").orEmpty()
            val snapshot = HealthCareVisitFollowUpRepository(context, names).load(id, encounter)
            val reminder = snapshot.reminder!!
            assertEquals(markers.getString("token", ""), reminder.token); assertEquals(markers.getString("action", ""), reminder.actionId)
            assertEquals(2, snapshot.history.items.size); assertEquals(HealthCareReminderState.SCHEDULED, reminder.state)
            var posted = 0
            repeat(3) { HealthCareReminderRuntime.reconcile(context, HealthReminderSettings(notifications = true, quiet = false),
                maxOf(System.currentTimeMillis(), reminder.dueAt) + it, ZoneId.of("UTC"), true, emptySet(),
                post = { posted++; true }, cancel = {}, names = names) }
            assertEquals(1, posted)
            HealthCareStore(context, names.care).use { assertEquals(HealthCareReminderState.DELIVERED, it.reminder(reminder.actionId)!!.state) }
            println("HEALTH_VISIT_REVIEW process_changed=true same_reminder=true same_journal=true delivery_count=1")
        } finally {
            listOf(names.care, names.records, names.privacy, names.profile, names.reminders).forEach(context::deleteDatabase)
            assertTrue(markers.edit().clear().commit())
        }
    }
}
