package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentRunSnapshotContractTest {
    @Test fun ordinaryEventsHaveNoProjection() {
        assertNull(AgentRunSnapshotContract.describe(event().copy(payload = emptyMap())))
    }

    @Test fun validSnapshotExposesOnlyLookupIdentities() {
        val projection = requireNotNull(AgentRunSnapshotContract.describe(event()))
        assertEquals(AgentRunSnapshotContract.VOICE, projection.kind)
        assertEquals("task", projection.taskId)
        assertEquals("42", projection.messageId)
        assertEquals("request", projection.requestId)
    }

    @Test fun mismatchedRootFieldsAreRejected() {
        listOf("run_id", "task_id", "conversation_id", "source_message_id").forEach { field ->
            val changed = json().put(field, if (field == "source_message_id") 43 else "other")
            assertTrue(field, runCatching { AgentRunSnapshotContract.describe(event(changed)) }.isFailure)
        }
    }

    @Test fun missingIdentityFieldsAreRejected() {
        listOf("run_id", "task_id", "conversation_id", "source_message_id", "turn_id", "idempotency_key").forEach { field ->
            val changed = json().apply { remove(field) }
            assertTrue(field, runCatching { AgentRunSnapshotContract.describe(event(changed)) }.isFailure)
        }
    }

    @Test fun blankTurnAndRequestAreRejected() {
        listOf("turn_id", "idempotency_key").forEach { field ->
            assertTrue(runCatching { AgentRunSnapshotContract.describe(event(json().put(field, "  "))) }.isFailure)
        }
    }

    @Test fun invalidPayloadDoesNotBecomeAnEmptySnapshot() {
        listOf<Any>("{", 42, JSONObject()).forEach { payload ->
            assertTrue(runCatching { AgentRunSnapshotContract.describe(event().copy(
                payload = mapOf(AgentRunSnapshotContract.VOICE_PAYLOAD to payload))) }.isFailure)
        }
    }

    @Test fun lookupValidatesKindAndExactIdentity() {
        val event = event()
        val kind = AgentRunSnapshotContract.VOICE
        assertTrue(AgentRunSnapshotContract.matches(event, kind, null, "run"))
        assertFalse(AgentRunSnapshotContract.matches(event, "other", null, "run"))
        mapOf(AgentRunSnapshotLookup.TASK to "task", AgentRunSnapshotLookup.MESSAGE to "42",
            AgentRunSnapshotLookup.REQUEST to "request").forEach { (lookup, value) ->
            assertTrue(AgentRunSnapshotContract.matches(event, kind, lookup, value))
            assertFalse(AgentRunSnapshotContract.matches(event, kind, lookup, "$value-other"))
        }
    }

    @Test fun hashesAreDeterministicAndDomainSeparated() {
        fun hash(kind: String, lookup: AgentRunSnapshotLookup, value: String) =
            AgentRunSnapshotContract.lookupHash(kind, lookup, value)
        val task = AgentRunSnapshotLookup.TASK
        val value = "\u6d4b\u8bd5\u0000\u001f\ud83d\ude00"
        val encoded = hash("kind", task, value)
        assertTrue(encoded.matches(Regex("[0-9a-f]{64}")))
        assertEquals(encoded, hash("kind", task, value))
        assertNotEquals(encoded, hash("other", task, value))
        assertNotEquals(encoded, hash("kind", AgentRunSnapshotLookup.MESSAGE, value))
        assertNotEquals(hash("a", task, "bc"), hash("ab", task, "c"))
        assertNotEquals(hash("a\u0000", task, "b"), hash("a", task, "\u0000b"))
    }

    private fun json() = JSONObject().put("run_id", "run").put("task_id", "task")
        .put("conversation_id", "conversation").put("source_message_id", 42L)
        .put("turn_id", "turn").put("idempotency_key", "request")

    private fun event(snapshot: JSONObject = json()) = AgentRunControlEvent(
        conversationId = "conversation", messageId = "42", taskId = "task", runId = "run",
        agentId = "codex", deviceId = "phone", type = AgentRunControlEventType.RUN_STARTED,
        sequence = 1L, payload = mapOf(AgentRunSnapshotContract.VOICE_PAYLOAD to snapshot.toString()))
}
