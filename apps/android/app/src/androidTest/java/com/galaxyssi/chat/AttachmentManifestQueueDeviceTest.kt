package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class AttachmentManifestQueueDeviceTest {
    @Test fun reconnectDeclarationsRemainBoundedWithoutRemovingMessagesOrAttemptedRows() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "manifest-queue-test-${UUID.randomUUID()}.db"
        try {
            GalaxySSILinkOutboxDatabase(context, name).use { db ->
                fun row(id: String, time: Long, type: String = "input_attachment_manifest",
                    route: String = "route-a", attempts: Int = 0) = JSONObject()
                    .put("message_id", id).put("status", "queued").put("attempts", attempts)
                    .put("created_at", time).put("next_attempt_at", time)
                    .put("client_source_message_id", 123).put("attachment_transfer_id", "a".repeat(64))
                    .put("receipt_binding", route).put("payload_type", type).put("wire_payload", "{}")
                assertTrue(db.insert(row("first", 1)))
                repeat(54) { assertTrue(db.insert(row("duplicate-$it", 2L + it))) }
                assertTrue(db.insert(row("message", 100, type = "peer_message")))
                assertFalse(db.canEnqueue("route-a", false))
                assertTrue(db.hasAttachmentManifest("route-a", "a".repeat(64)))
                assertFalse(db.hasAttachmentManifest("route-b", "a".repeat(64)))
                assertFalse(db.hasAttachmentManifest("route-a", "b".repeat(64)))
                assertTrue(db.insert(row("attempted", 101, attempts = 1)))
                assertTrue(db.insert(row("other-route", 102, route = "route-b")))
                assertTrue(db.insert(row("chunk", 103, type = "input_attachment_chunk")))
                val redundant = db.redundantUnsentAttachmentManifests()
                assertEquals(54, redundant.size)
                redundant.forEach { db.delete(it) }
                assertTrue(db.canEnqueue("route-a", false))
                listOf("first", "message", "attempted", "other-route", "chunk").forEach {
                    assertTrue("Preserve $it", db.contains(it))
                }
                assertTrue(db.redundantUnsentAttachmentManifests().isEmpty())
            }
            GalaxySSILinkOutboxDatabase(context, name).use { db ->
                assertTrue(db.hasAttachmentManifest("route-a", "a".repeat(64)))
                assertEquals(5, db.readAll().length())
            }
        } finally { context.deleteDatabase(name) }
    }
}
