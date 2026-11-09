package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

internal fun instructionProposalInput(value: HealthCareInstruction): AgentNativeJsonObject = mapOf("kind" to "FOLLOW_UP",
    "fields" to HealthCareInstructionDraft(HealthCareInstructionKind.FOLLOW_UP).required.associate { field -> field.name to
        when (field) {
            HealthCareInstructionField.NAME -> mapOf("quote" to value.source.quote.lineSequence().first(), "certainty" to "QUOTED")
            HealthCareInstructionField.DETAILS -> mapOf("quote" to value.source.quote.lineSequence().last(), "certainty" to "UNCERTAIN")
            else -> mapOf("quote" to "", "certainty" to "NOT_FOUND")
        } })
internal fun stageInstructionProposal(context: Context, f: HealthCareInstructionFixture, value: HealthCareInstruction): HealthCareInstructionProposal =
    HealthCareStore(context, f.documents.names.care).use { care ->
        val issue = care.concern(value.concernId)!!
        val grant = HealthCareDiscussionGrant(issue.conversationId, UUID.randomUUID().toString(), issue.id, issue.revision,
            care.settings().version, HealthPrivacyStore(context, f.documents.names.privacy).use { it.policy().version }, "a".repeat(64),
            System.currentTimeMillis(), "local-llm", "synthetic", "high", profileLink = issue.profileLink,
            instruction = HealthCareInstructionScope.of(value))
        care.approveDiscussion(grant)
        care.proposeInstruction(grant, instructionProposalInput(value), System.currentTimeMillis())
    }

class HealthCareInstructionProposalDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()
    private fun fixture(test: (HealthCareInstructionFixture) -> Unit) = HealthCareInstructionFixture(context).use(test)
    @Test fun separateEncryptedProposalSurvivesReopenAndDoesNotConfirmAnything(): Unit = fixture { f ->
        val value = f.create(); val before = f.snapshot(value.id).visit.issue
        val proposal = stageInstructionProposal(context, f, value)
        assertEquals(proposal, f.snapshot(value.id).proposal)
        HealthCareStore(context, f.documents.names.care).use { care ->
            assertEquals(before, care.concern(value.concernId)); assertEquals(value, care.instruction(value.id))
            assertEquals(proposal, care.proposeInstruction(proposal.grant, instructionProposalInput(value), System.currentTimeMillis()))
            assertTrue(care.reminders(value.concernId).isEmpty()); assertNull(care.plan(proposal.id))
        }
        context.openOrCreateDatabase(f.documents.names.care, 0, null).use { db -> db.rawQuery("SELECT payload FROM instruction_proposals", null).use {
            assertTrue(it.moveToFirst()); assertFalse(it.getBlob(0).toString(Charsets.ISO_8859_1).contains("Synthetic follow-up"))
        } }
    }
    @Test fun reviewRequiresExplicitSaveAndRemainsSeparateFromActionConfirmation(): Unit = fixture { f ->
        val value = f.create(); val proposal = stageInstructionProposal(context, f, value)
        val before = f.snapshot(value.id); val operation = id()
        val receipt = f.repository.update(before, proposal.draft, operation, proposalId = proposal.id)
        assertEquals(proposal.id, receipt.value.modelProposalId); assertFalse(receipt.value.draft.reviewed)
        assertNull(f.snapshot(value.id).proposal)
        HealthCareStore(context, f.documents.names.care).use { care ->
            assertEquals(HealthCareInstructionProposalState.APPLIED, care.instructionProposal(proposal.id)!!.state)
            assertEquals(before.visit.issue.actions, care.concern(value.concernId)!!.actions)
            assertTrue(care.reminders(value.concernId).isEmpty())
            assertEquals(receipt, care.saveInstruction(value.concernId, receipt.expectedConcern, value.encounterId, value.id,
                value.revision, value.source, proposal.draft, operation, System.currentTimeMillis(), proposal.id))
        }
    }
    @Test fun dismissedReplayCannotResurrectCandidateAndNewTurnCanPropose(): Unit = fixture { f ->
        val value = f.create(); val proposal = stageInstructionProposal(context, f, value)
        f.repository.dismiss(f.snapshot(value.id)); assertNull(f.snapshot(value.id).proposal)
        HealthCareStore(context, f.documents.names.care).use { care ->
            val replay = care.proposeInstruction(proposal.grant, instructionProposalInput(value), System.currentTimeMillis())
            assertEquals(HealthCareInstructionProposalState.DISMISSED, replay.state); assertNull(care.pendingInstructionProposal(value.id))
        }
        assertNotEquals(proposal.id, stageInstructionProposal(context, f, value).id)
    }
    @Test fun concurrentProposalAndManualReviewCannotOverwriteEachOther(): Unit = fixture { f ->
        val value = f.create(); val proposal = stageInstructionProposal(context, f, value)
        assertThrows(HealthCareConflict::class.java) { stageInstructionProposal(context, f, value) }
        val stale = f.snapshot(value.id)
        f.repository.update(stale, HealthCareInstructionDraft(fields = mapOf(HealthCareInstructionField.NAME to
            HealthCareInstructionValue("User edited", HealthCareFieldReview.TRANSCRIBED))), id())
        assertThrows(HealthCareConflict::class.java) { f.repository.update(stale, proposal.draft, id(), proposalId = proposal.id) }
        HealthCareStore(context, f.documents.names.care).use { care ->
            assertEquals(HealthCareInstructionProposalState.DISMISSED, care.instructionProposal(proposal.id)!!.state)
            assertThrows(HealthCareConflict::class.java) { care.proposeInstruction(proposal.grant, instructionProposalInput(value), System.currentTimeMillis()) }
        }
    }
    @Test fun missingOriginalAndRevokedPrivacyBlockCandidateReview(): Unit = fixture { f ->
        val value = f.create(); val proposal = stageInstructionProposal(context, f, value); val old = f.snapshot(value.id)
        f.documents.originals().use { it.removeOriginalBytes(f.original) }
        assertFalse(f.snapshot(value.id).available)
        assertThrows(HealthCareConflict::class.java) { f.repository.update(old, proposal.draft, id(), proposalId = proposal.id) }
        HealthCareStore(context, f.documents.names.care).use { care ->
            assertThrows(HealthCareConflict::class.java) { HealthCareInstructionTool.selected(context, care, value.concernId, proposal.scope, f.documents.names) }
        }
        HealthPrivacyStore(context, f.documents.names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        assertThrows(HealthPrivacyConflict::class.java) { f.repository.update(old, proposal.draft, id(), proposalId = proposal.id) }
    }
    @Test fun deletingSourceDraftPurgesProposalButPreservesOriginal(): Unit = fixture { f ->
        val value = f.create(); val proposal = stageInstructionProposal(context, f, value)
        f.repository.delete(f.snapshot(value.id))
        HealthCareStore(context, f.documents.names.care).use { assertNull(it.instructionProposal(proposal.id)) }
        f.documents.originals().use { assertTrue(it.present(f.original)) }
    }
    @Test fun tamperedEncounterIndexCannotChangeCandidateOwnership(): Unit = fixture { f ->
        val value = f.create(); val proposal = stageInstructionProposal(context, f, value)
        context.openOrCreateDatabase(f.documents.names.care, 0, null).use { db -> db.update("instruction_proposals",
            ContentValues().apply { put("encounter_id", id()) }, "turn_id=?", arrayOf(proposal.id)) }
        HealthCareStore(context, f.documents.names.care).use { care ->
            assertThrows(Exception::class.java) { care.instructionProposal(proposal.id) }
        }
    }
    @Test fun ignoredProposalWriteDoesNotReportSuccessfulReceipt(): Unit = fixture { f ->
        val value = f.create()
        context.openOrCreateDatabase(f.documents.names.care, 0, null).use {
            it.execSQL("CREATE TRIGGER ignore_proposal BEFORE INSERT ON instruction_proposals BEGIN SELECT RAISE(IGNORE); END")
        }
        assertThrows(IllegalStateException::class.java) { stageInstructionProposal(context, f, value) }
        assertNull(f.snapshot(value.id).proposal); assertEquals(value, f.snapshot(value.id).selected)
    }
    @Test fun schemaFifteenMigrationPreservesInstructionsAndDoesNotInventCandidates(): Unit = fixture { f ->
        val value = f.create()
        context.openOrCreateDatabase(f.documents.names.care, 0, null).use { it.execSQL("DROP TABLE instruction_proposals"); it.version = 15 }
        assertEquals(value, f.snapshot(value.id).selected); assertNull(f.snapshot(value.id).proposal)
        stageInstructionProposal(context, f, value)
        context.openOrCreateDatabase(f.documents.names.care, 0, null).use { assertEquals(16, it.version) }
    }
}
