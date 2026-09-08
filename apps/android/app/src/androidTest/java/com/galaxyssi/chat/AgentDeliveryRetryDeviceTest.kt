package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentDeliveryRetryDeviceTest {
    private val now = 2_000_000L

    @Test fun recoveryPreservesCiphertextMessageAndTaskIdentity() {
        val value = item()
        assertTrue(AgentDeliveryRetryPolicy.defer(value, 6, now))
        assertEquals("stable-id", value.getString("message_id"))
        assertEquals("original-signal-ciphertext", value.getString("wire_payload"))
        assertEquals(123L, value.getLong("client_source_message_id"))
        assertEquals(5, value.getInt("attempts"))
        assertEquals(now + 60_000L, value.getLong("next_attempt_at"))
    }

    @Test fun retryCountAndAgeAreBothBounded() {
        val value = item()
        repeat(6) {
            value.put("attempts", 6)
            assertTrue(AgentDeliveryRetryPolicy.defer(value, 6, now + it * 60_000L))
        }
        value.put("attempts", 6)
        assertFalse(AgentDeliveryRetryPolicy.defer(value, 6, now + 360_000L))
        assertFalse(AgentDeliveryRetryPolicy.defer(item(), 6, now + 15 * 60_000L))
        assertFalse(AgentDeliveryRetryPolicy.defer(item(), 6, now - 2_000L))
    }

    @Test fun attachmentsAndUnexhaustedMessagesAreNotRearmed() {
        assertFalse(AgentDeliveryRetryPolicy.defer(item().put("attempts", 5), 6, now))
        assertFalse(AgentDeliveryRetryPolicy.defer(item().put("attachment_transfer_id", "a".repeat(64)), 6, now))
        assertFalse(AgentDeliveryRetryPolicy.defer(item().put("blocked_by_attachment_transfers", JSONArray().put("pending")), 6, now))
    }

    @Test fun queuedUploadTimeDoesNotConsumePostUploadRecoveryWindow() {
        val value = item().put("created_at", 1L).put("first_attempt_at", now - 1_000L)
        assertTrue(AgentDeliveryRetryPolicy.defer(value, 6, now))
    }

    @Test fun recoverySurvivesDatabaseReopenAndDeletionCannotResurrectIt() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "delivery_retry_test_${System.nanoTime()}.db"
        try {
            GalaxySSILinkOutboxDatabase(context, name).use { db ->
                db.insert(item())
                db.insert(item().put("message_id", "other-contact").put("client_source_message_id", 456L))
                assertTrue(db.update("stable-id") { assertTrue(AgentDeliveryRetryPolicy.defer(it, 6, now)) })
                assertEquals(0, db.retryCandidates(now, true, 6, 9, 4).length())
            }
            GalaxySSILinkOutboxDatabase(context, name).use { db ->
                val candidates = db.retryCandidates(now + 60_000L, true, 6, 9, 4)
                assertEquals(1, candidates.length())
                assertEquals("original-signal-ciphertext", candidates.getJSONObject(0).getString("wire_payload"))
                assertEquals(1, candidates.getJSONObject(0).getInt("agent_recovery_attempts"))
                db.delete("stable-id")
                assertFalse(db.update("stable-id") { fail("Deleted request was revived") })
                assertTrue(db.contains("other-contact"))
            }
        } finally {
            context.deleteDatabase(name)
        }
    }

    @Test fun unknownOrUnpairedContactsCannotEnterRecovery() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        assertFalse(AgentDeliveryRetryPolicy.eligible(context, 0L, ""))
        assertFalse(AgentDeliveryRetryPolicy.eligible(context, Long.MAX_VALUE, "unpaired-fixture"))
    }

    @Test fun delayedWakeCannotDispatchAnExpiredRecovery() {
        val value = item()
        assertTrue(AgentDeliveryRetryPolicy.defer(value, 6, now))
        val pending = GalaxySSILinkDeliveryStore.pendingFromArray(JSONArray().put(value), now + 60_000L,
            maxAttempts = 6).single()
        assertFalse(AgentDeliveryRetryPolicy.expired(pending.recoveryFirstAttemptMillis, now + 60_000L))
        assertTrue(AgentDeliveryRetryPolicy.expired(pending.recoveryFirstAttemptMillis, now + 60 * 60_000L))
        assertTrue(AgentDeliveryRetryPolicy.expired(pending.recoveryFirstAttemptMillis, now - 10_000L))
    }

    private fun item() = JSONObject()
        .put("message_id", "stable-id").put("topic", "opaque-mailbox")
        .put("wire_payload", "original-signal-ciphertext")
        .put("client_source_message_id", 123L).put("contact_id", "fixture-contact")
        .put("attempts", 6).put("status", "published")
        .put("first_attempt_at", now - 1_000L).put("created_at", now - 1_000L)
        .put("next_attempt_at", now).put("updated_at", now)
}
