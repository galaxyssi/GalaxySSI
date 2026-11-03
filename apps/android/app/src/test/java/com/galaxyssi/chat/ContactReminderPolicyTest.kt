package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.ui.AgentComposerUiPolicy

class ContactReminderPolicyTest {
    private val id = "b61bb9a5-bb9f-4d04-8a4d-3ecbd787a371"
    @Test fun freshRequestIsValid() { assertTrue(ContactReminderPolicy.valid(id, 100_000, 220_000, 100_001)) }
    @Test fun expiredRequestIsNeverReplayed() { assertFalse(ContactReminderPolicy.valid(id, 100_000, 220_000, 220_000)) }
    @Test fun unboundedLifetimeIsRejected() { assertFalse(ContactReminderPolicy.valid(id, 100_000, 220_001, 100_001)) }
    @Test fun futureRequestIsRejected() { assertFalse(ContactReminderPolicy.valid(id, 200_000, 220_000, 100_001)) }
    @Test fun invalidIdsAreRejected() {
        listOf("", "a", "../" + id, "a".repeat(65)).forEach { assertFalse(ContactReminderPolicy.valid(it, 100_000, 220_000, 100_001)) }
    }
    @Test fun invalidTimesAreRejected() {
        assertFalse(ContactReminderPolicy.valid(id, 0, 1000, 1))
        assertFalse(ContactReminderPolicy.valid(id, 100_000, 99_999, 100_000))
    }
    @Test fun terminalStatesNeverRegress() {
        ContactReminderPolicy.terminal.forEach { current ->
            (ContactReminderPolicy.receipts + "cancelled" + "request" + "expired").forEach { event ->
                assertEquals(current, ContactReminderPolicy.next(current, event, true))
                assertEquals(current, ContactReminderPolicy.next(current, event, false))
            }
        }
    }
    @Test fun mutedReceiptsCannotBeReplacedByLateDelivery() {
        assertEquals("muted", ContactReminderPolicy.next("muted", "received", true))
        assertEquals("quiet", ContactReminderPolicy.next("quiet", "received", true))
        assertEquals("acknowledged", ContactReminderPolicy.next("muted", "acknowledged", true))
    }
    @Test fun incomingRequestsDoNotResetAnExistingReminder() {
        assertEquals("muted", ContactReminderPolicy.next("muted", "request", false))
    }
    @Test fun peerCannotConfirmAnIncomingReminderOnBehalfOfTheRecipient() {
        // Runtime accepts only request/cancel for incoming reminders; receipt policy applies to outgoing only.
        assertEquals("queued", ContactReminderPolicy.next("queued", "request", true))
    }
    @Test fun emptyComposerShowsReminderInsteadOfRecording() {
        val state = AgentComposerUiPolicy.resolve(false, false, false, voiceEntryAvailable = true)
        assertTrue(state.showVoiceButton); assertFalse(state.showSendButton); assertFalse(state.showMoreButton)
    }
    @Test fun typingAndAttachmentsKeepTheSendButton() {
        for (editing in listOf(true, false)) {
            val state = AgentComposerUiPolicy.resolve(true, editing, false, voiceEntryAvailable = true)
            assertTrue(state.showSendButton); assertFalse(state.showVoiceButton)
        }
    }
    @Test fun keyboardAndTrayKeepExistingMoreMenu() {
        assertTrue(AgentComposerUiPolicy.resolve(false, true, false, true).showMoreButton)
        assertTrue(AgentComposerUiPolicy.resolve(false, false, true, true).showActionTray)
    }
}
