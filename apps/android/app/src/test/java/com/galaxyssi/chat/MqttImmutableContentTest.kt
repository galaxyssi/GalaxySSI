package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MqttImmutableContentTest {
    @Test fun objectOrderDoesNotChangeBinding() {
        val a = JSONObject("""{"b":2,"a":{"z":false,"x":null}}""")
        val b = JSONObject("""{"a":{"x":null,"z":false},"b":2}""")
        assertEquals(MqttImmutableContent.hash(a), MqttImmutableContent.hash(b))
    }

    @Test fun arrayOrderIsImmutable() {
        assertNotEquals(MqttImmutableContent.hash(JSONObject().put("a", JSONArray("[1,2]"))),
            MqttImmutableContent.hash(JSONObject().put("a", JSONArray("[2,1]"))))
    }

    @Test fun typeChangesAreConflicts() {
        val hashes = listOf<Any>(1, "1", true, JSONObject.NULL).map {
            MqttImmutableContent.hash(JSONObject().put("v", it))
        }
        assertEquals(4, hashes.toSet().size)
    }

    @Test fun timestampsAndAllEnvelopeFieldsAreBound() {
        val envelope = JSONObject().put("message_id", "id").put("created_at", 42).put("payload", JSONObject())
        val before = MqttImmutableContent.hash(envelope)
        envelope.put("created_at", 43)
        assertNotEquals(before, MqttImmutableContent.hash(envelope))
    }

    @Test fun hashingDoesNotMutatePayload() {
        val value = JSONObject().put("text", "quote\"\nbackslash\\").put("number", 1.5)
        val before = value.toString()
        assertEquals(MqttImmutableContent.hash(value), MqttImmutableContent.hash(JSONObject(before)))
        assertEquals(before, value.toString())
    }

    @Test fun excessiveNestingIsRejected() {
        val root = JSONObject()
        var value = root
        repeat(66) { val child = JSONObject(); value.put("next", child); value = child }
        assertThrows(IllegalArgumentException::class.java) { MqttImmutableContent.hash(root) }
    }

    @Test fun sha256UsesFullDigest() {
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", MqttImmutableContent.sha256("abc"))
    }
}
