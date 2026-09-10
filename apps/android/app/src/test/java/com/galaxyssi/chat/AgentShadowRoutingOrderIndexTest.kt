package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentShadowRoutingOrderIndexTest {
    private fun entry(id: String, at: Long) = AgentShadowRoutingOrderEntry("recommendation:$id", at)

    @Test fun retainsNewestTimestampsNotInsertionOrder() {
        val ordered = AgentShadowRoutingOrderIndex.retain(listOf(entry("later", 30), entry("old", 1), entry("mid", 20)))
        assertEquals(listOf(30L, 20L, 1L), ordered.map { it.createdAtMillis })
        assertEquals(ordered, AgentShadowRoutingOrderIndex.decode(AgentShadowRoutingOrderIndex.encode(ordered)))
    }

    @Test fun equalTimesUseStableKeyOrder() {
        assertEquals(listOf(entry("a", 1), entry("b", 1)),
            AgentShadowRoutingOrderIndex.retain(listOf(entry("b", 1), entry("a", 1))))
    }

    @Test fun boundsHistoryAndDeduplicatesKeys() {
        val items = (0..1000).map { entry("id-$it", it.toLong()) } + entry("id-1000", 2000)
        val retained = AgentShadowRoutingOrderIndex.retain(items)
        assertEquals(500, retained.size)
        assertEquals(2000L, retained.first().createdAtMillis)
        assertEquals(500, retained.map { it.key }.distinct().size)
    }

    @Test fun rejectsCorruptUnsupportedOrUnsortedIndexesForRecovery() {
        assertNull(AgentShadowRoutingOrderIndex.decode("broken"))
        assertNull(AgentShadowRoutingOrderIndex.decode("{\"version\":2,\"entries\":[]}"))
        assertNull(AgentShadowRoutingOrderIndex.decode(AgentShadowRoutingOrderIndex.encode(listOf(entry("a", 1), entry("b", 2)))))
        assertNull(AgentShadowRoutingOrderIndex.decode(AgentShadowRoutingOrderIndex.encode(listOf(entry("a", 1), entry("a", 1)))))
        assertNull(AgentShadowRoutingOrderIndex.decode(AgentShadowRoutingOrderIndex.encode(listOf(AgentShadowRoutingOrderEntry("wrong:key", 1)))))
        assertNull(AgentShadowRoutingOrderIndex.decode(AgentShadowRoutingOrderIndex.encode((0..500).map { entry("$it", -it.toLong()) })))
    }

    @Test fun rejectsCoercedNonIntegerTimes() {
        for (time in listOf<Any>("123", 1.5, JSONObject.NULL)) {
            val raw = JSONObject().put("version", 1).put("entries",
                JSONArray().put(JSONArray().put("recommendation:a").put(time))).toString()
            assertNull(AgentShadowRoutingOrderIndex.decode(raw))
        }
    }

    @Test fun emptyIndexIsValidAndNegativeLegacyTimesRemainOrdered() {
        assertEquals(emptyList<AgentShadowRoutingOrderEntry>(),
            AgentShadowRoutingOrderIndex.decode(AgentShadowRoutingOrderIndex.encode(emptyList())))
        val retained = AgentShadowRoutingOrderIndex.retain(listOf(entry("a", -2), entry("b", -1)))
        assertEquals(retained, AgentShadowRoutingOrderIndex.decode(AgentShadowRoutingOrderIndex.encode(retained)))
    }
}
