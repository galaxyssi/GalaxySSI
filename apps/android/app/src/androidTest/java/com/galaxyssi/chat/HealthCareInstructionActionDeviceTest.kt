package com.galaxyssi.chat

import android.os.CancellationSignal
import androidx.test.platform.app.InstrumentationRegistry
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

internal fun reviewedHealthInstruction(f: HealthCareInstructionFixture, kind: HealthCareInstructionKind = HealthCareInstructionKind.FOLLOW_UP): HealthCareInstruction {
    val value = f.create()
    val draft = HealthCareInstructionDraft(kind, HealthCareInstructionDraft(kind).required.associateWith {
        HealthCareInstructionValue("Synthetic ${it.name}", HealthCareFieldReview.TRANSCRIBED)
    })
    return f.repository.update(f.snapshot(value.id), draft, UUID.randomUUID().toString()).value
}

class HealthCareInstructionActionDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(block: (HealthCareInstructionFixture) -> Unit) { HealthCareInstructionFixture(context).use(block) }
    private fun confirm(f: HealthCareInstructionFixture, value: HealthCareInstruction) =
        f.repository.confirmAction(f.snapshot(value.id), CancellationSignal())
    private fun schedule(f: HealthCareInstructionFixture, action: HealthCareAction): HealthCareReminder =
        HealthCareStore(context, f.documents.names.care).use { store ->
            val issue = store.concern(f.documents.issue.id)!!
            val permission = HealthPrivacyStore(context, f.documents.names.privacy).use { it.policy() }
            val now = System.currentTimeMillis()
            store.scheduleReminder(issue.id, action.id, issue.revision, null, permission, issue.inputVersion, now + 1000, now) {
                HealthCareInstructionAccess.available(context, f.documents.names, it)
            }
        }
    private fun deliver(f: HealthCareInstructionFixture, at: Long, post: (HealthCareReminder) -> Boolean) =
        HealthCareReminderRuntime.reconcile(context, HealthReminderSettings(notifications = true, quiet = false), at,
            ZoneId.of("UTC"), true, emptySet(), post, {}, f.documents.names)
    @Test fun confirmedInstructionPersistsAndReplaysWithoutCreatingAnyReminder(): Unit = fixture { f ->
        val value = reviewedHealthInstruction(f)
        val snapshot = f.snapshot(value.id)
        val action = f.repository.confirmAction(snapshot, CancellationSignal())
        HealthCareStore(context, f.documents.names.care).use { store ->
            assertEquals(action, store.confirmInstructionAction(value.concernId, snapshot.visit.issue.revision, value.id, value.revision, System.currentTimeMillis()))
            val issue = store.concern(value.concernId)!!
            assertEquals(1, issue.actions.count { it.id == action.id }); assertTrue(store.instructionCurrent(issue, action))
            assertNull(store.reminder(action.id)); assertEquals(snapshot.visit.issue.stage, issue.stage)
            assertEquals(action, HealthCareAction.from(action.json()))
        }
    }
    @Test fun acceptedPrescriptionUsesTheSameReminderAndFeedbackPipeline(): Unit = fixture { f ->
        val value = reviewedHealthInstruction(f, HealthCareInstructionKind.MEDICATION)
        val action = confirm(f, value); val reminder = schedule(f, action); var posts = 0
        repeat(2) { deliver(f, reminder.dueAt + it) { posts++; true } }
        assertEquals(1, posts)
        HealthCareStore(context, f.documents.names.care).use { store ->
            val issue = store.concern(value.concernId)!!
            val feedback = store.recordActionFeedback(issue.id, issue.revision, action.id, HealthCareFeedbackKind.PARTIAL,
                "合成测试：记录执行困难，不代表疗效", UUID.randomUUID().toString(), System.currentTimeMillis())
            assertEquals(HealthCareFeedbackKind.PARTIAL, feedback.feedback.kind)
            assertEquals(HealthCareActionState.CONFIRMED, store.concern(issue.id)!!.actions.single { it.id == action.id }.state)
            assertEquals(value, store.instruction(value.id))
        }
    }
    @Test fun sourceEditCancelsPriorReminderAndRequiresANewExplicitAction(): Unit = fixture { f ->
        val value = reviewedHealthInstruction(f); val action = confirm(f, value); val reminder = schedule(f, action)
        val changed = f.repository.update(f.snapshot(value.id), value.draft, UUID.randomUUID().toString()).value
        HealthCareStore(context, f.documents.names.care).use { store ->
            val issue = store.concern(value.concernId)!!
            assertTrue(issue.actions.single { it.id == action.id }.instruction!!.invalidated)
            assertEquals(HealthCareReminderState.CANCELLED, store.reminder(action.id)!!.state)
            assertFalse(store.instructionCurrent(issue, action)); assertEquals(1, issue.actions.count { it.instruction != null })
        }
        deliver(f, reminder.dueAt) { fail("Obsolete instruction was delivered"); true }
        val replacement = confirm(f, changed)
        assertNotEquals(action.id, replacement.id)
        HealthCareStore(context, f.documents.names.care).use { assertNull(it.reminder(replacement.id)) }
    }
    @Test fun deletedInstructionCancelsReminderButRetainsTheActionForReview(): Unit = fixture { f ->
        val value = reviewedHealthInstruction(f); val action = confirm(f, value); val reminder = schedule(f, action)
        f.repository.delete(f.snapshot(value.id))
        HealthCareStore(context, f.documents.names.care).use { store ->
            val issue = store.concern(value.concernId)!!
            assertTrue(issue.actions.single { it.id == action.id }.instruction!!.invalidated)
            assertEquals(HealthCareReminderState.CANCELLED, store.reminder(action.id)!!.state)
            assertNull(store.instruction(value.id))
        }
        deliver(f, reminder.dueAt) { fail("Deleted instruction was delivered"); true }
    }
    @Test fun deletedEncounterInvalidatesOnlyItsDependentInstructions(): Unit = fixture { f ->
        val value = reviewedHealthInstruction(f); val action = confirm(f, value); schedule(f, action)
        HealthCareStore(context, f.documents.names.care).use { store ->
            val issue = store.concern(value.concernId)!!
            store.deleteEncounter(issue.id, issue.revision, value.encounterId, store.encounter(value.encounterId)!!.revision, System.currentTimeMillis())
            assertEquals(HealthCareReminderState.CANCELLED, store.reminder(action.id)!!.state)
            assertTrue(store.concern(issue.id)!!.actions.single { it.id == action.id }.instruction!!.invalidated)
            assertEquals(f.documents.issue.actions, store.concern(issue.id)!!.actions.filter { it.instruction == null })
        }
    }
    @Test fun missingOriginalBlocksConfirmationSchedulingAndDelivery(): Unit = fixture { f ->
        val value = reviewedHealthInstruction(f); val action = confirm(f, value); val reminder = schedule(f, action)
        f.documents.originals().use { it.removeOriginalBytes(f.original) }
        assertTrue(runCatching { confirm(f, value) }.isFailure)
        deliver(f, reminder.dueAt) { fail("Missing source was delivered"); true }
        HealthCareStore(context, f.documents.names.care).use { store ->
            assertEquals(HealthCareReminderState.CANCELLED, store.reminder(action.id)!!.state)
            val issue = store.concern(value.concernId)!!
            assertFalse(HealthCareInstructionAccess.current(context, f.documents.names, store, issue, action))
        }
    }
    @Test fun uncheckedMedicationAndUnverifiedSchedulingFailClosed(): Unit = fixture { f ->
        val initial = f.create()
        assertThrows(IllegalArgumentException::class.java) { confirm(f, initial) }
        val value = reviewedHealthInstruction(f, HealthCareInstructionKind.MEDICATION)
        val action = confirm(f, value)
        HealthCareStore(context, f.documents.names.care).use { store ->
            val issue = store.concern(value.concernId)!!; val now = System.currentTimeMillis()
            assertThrows(HealthCareConflict::class.java) { store.scheduleReminder(issue.id, action.id, issue.revision, null,
                HealthPrivacyStore(context, f.documents.names.privacy).use { it.policy() }, issue.inputVersion, now + 1000, now) }
            assertNull(store.reminder(action.id))
        }
    }
    @Test fun staleReviewAndRevokedConsentCannotAddAnAction(): Unit = fixture { f ->
        val value = reviewedHealthInstruction(f); val old = f.snapshot(value.id)
        f.repository.update(old, value.draft, UUID.randomUUID().toString())
        assertThrows(HealthCareConflict::class.java) { f.repository.confirmAction(old, CancellationSignal()) }
        val current = f.snapshot(value.id)
        HealthPrivacyStore(context, f.documents.names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        assertTrue(runCatching { f.repository.confirmAction(current, CancellationSignal()) }.isFailure)
        HealthCareStore(context, f.documents.names.care).use { assertTrue(it.concern(value.concernId)!!.actions.none { a -> a.instruction != null }) }
    }
    @Test fun corruptedOriginalCannotBeUsedForConfirmation(): Unit = fixture { f ->
        val value = reviewedHealthInstruction(f)
        val file = java.io.File(f.documents.names.originalRoot(context), f.original.relativePath)
        java.io.RandomAccessFile(file, "rw").use { it.seek(it.length() - 1); val byte = it.read(); it.seek(it.length() - 1); it.write(byte xor 255) }
        assertTrue(runCatching { confirm(f, value) }.isFailure)
        HealthCareStore(context, f.documents.names.care).use { assertTrue(it.concern(value.concernId)!!.actions.none { a -> a.instruction != null }) }
    }
    @Test fun schemaFourteenUpgradePreservesReviewedSourcesAndDoesNotInventActions(): Unit = fixture { f ->
        val value = reviewedHealthInstruction(f); val before = f.snapshot(value.id)
        context.openOrCreateDatabase(f.documents.names.care, 0, null).use { removeHealthVisitFollowUpTestTables(it); it.execSQL("DROP TABLE instruction_proposals"); it.version = 14 }
        assertEquals(before, f.snapshot(value.id))
        context.openOrCreateDatabase(f.documents.names.care, 0, null).use { assertEquals(18, it.version) }
        confirm(f, value)
    }
    @Test fun ignoredActionWriteRollsBackHistoryAndReturnsNoFalseSuccess(): Unit = fixture { f ->
        val value = reviewedHealthInstruction(f); val before = f.snapshot(value.id).visit.issue
        context.openOrCreateDatabase(f.documents.names.care, 0, null).use {
            it.execSQL("CREATE TRIGGER ignore_confirmed_action BEFORE INSERT ON concerns BEGIN SELECT RAISE(IGNORE); END")
        }
        try {
            assertThrows(IllegalStateException::class.java) { confirm(f, value) }
            assertEquals(before, f.snapshot(value.id).visit.issue)
            HealthCareStore(context, f.documents.names.care).use { assertNull(it.reminder(HealthCareInstructionActionPolicy.actionId(value))) }
        } finally { context.openOrCreateDatabase(f.documents.names.care, 0, null).use { it.execSQL("DROP TRIGGER ignore_confirmed_action") } }
    }
    @Test fun visitSummaryPreservesInstructionRevisionAndWarnsAboutChangedSources(): Unit = fixture { f ->
        val value = reviewedHealthInstruction(f); val action = confirm(f, value)
        f.repository.update(f.snapshot(value.id), value.draft, UUID.randomUUID().toString())
        val issue = f.snapshot(value.id).visit.issue
        val item = HealthCareVisitPresentation(context).items(issue, setOf(HealthCareVisitSection.ACTIONS), emptyList(), null, emptyList())
            .single { it.key == "action:${action.id}" }
        assertTrue(item.text.contains(context.getString(R.string.health_visit_stale_action)))
        assertTrue(item.text.contains(context.getString(R.string.health_instruction_action_provenance)))
        assertTrue(item.text.contains(context.getString(R.string.health_revision, value.revision)))
        assertFalse(item.text.contains("user_transcribed"))
    }
}
