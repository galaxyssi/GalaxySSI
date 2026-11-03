package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentInvocationMetadataCacheTest {
    private fun profile(id: String = "model-a") = AgentInvocationProfile(
        defaultModelId = id, models = listOf(AgentModelOption(id, "Model", "Description")),
        reasoningEfforts = listOf(AgentModelReasoningEffort.HIGH))

    @Test fun metadataSurvivesTenMinutesButExpiresAtOneDayWithoutSliding() {
        var now = 0L
        val cache = AgentInvocationMetadataCache(clockNanos = { now })
        val first = cache.get("catalog", "v1") { profile() }
        now = RuntimeCachePolicy.SENSITIVE_TTL_NANOS
        assertSame(first, cache.get("catalog", "v1") { error("Should hit") })
        now = RuntimeCachePolicy.STATIC_METADATA_TTL_NANOS - 1
        assertSame(first, cache.get("catalog", "v1") { error("Should hit") })
        now++
        assertNotSame(first, cache.get("catalog", "v1") { profile() })
    }

    @Test fun versionChangeAndExplicitInvalidationReloadUnexpiredMetadata() {
        val cache = AgentInvocationMetadataCache()
        val first = cache.get("catalog", "v1") { profile() }
        val second = cache.get("catalog", "v2") { profile("model-b") }
        assertNotSame(first, second)
        cache.invalidate()
        assertNotSame(second, cache.get("catalog", "v2") { profile() })
    }

    @Test fun changedCatalogAndCapacityEvictionCannotReturnOldMetadata() {
        val cache = AgentInvocationMetadataCache(capacity = 1)
        cache.get("old", "v1") { profile() }
        assertEquals("model-b", cache.get("new", "v1") { profile("model-b") }.defaultModelId)
        var loads = 0
        cache.get("old", "v1") { loads++; profile() }
        assertEquals(1, loads)
    }

    @Test fun returnedCollectionsCannotPoisonSubsequentLookups() {
        val cache = AgentInvocationMetadataCache()
        val value = cache.get("catalog", "v1") { profile() }
        assertThrows(UnsupportedOperationException::class.java) {
            (value.models as MutableList).clear()
        }
        assertEquals(1, cache.get("catalog", "v1") { error("Should hit") }.models.size)
    }

    @Test fun oversizedCatalogStillDecodesButIsNotRetained() {
        val cache = AgentInvocationMetadataCache()
        var loads = 0
        repeat(2) {
            val value = cache.get("catalog", "v1") {
                loads++
                profile().copy(models = List(129) { AgentModelOption("model-$it") })
            }
            assertEquals(129, value.models.size)
        }
        assertEquals(2, loads)
    }

    @Test fun codecCachesOnlyCatalogFieldsAndRespondsToChangedModels() {
        val source = JSONObject().put("default_model", "model-a")
            .put("models", JSONArray().put(JSONObject().put("id", "model-a")))
            .put("api_key", "must-not-be-retained").put("link_secret", "private-link")
            .put("endpoint", "https://private.example").put("status", "online")
        val first = AgentInvocationProfileJsonCodec.decode(source)
        assertFalse(first.toString().contains("must-not-be-retained"))
        assertFalse(first.toString().contains("private-link"))
        assertFalse(first.toString().contains("private.example"))
        assertSame(first, AgentInvocationProfileJsonCodec.decode(source))
        AgentInvocationMetadataCache.shared.invalidate()
        assertNotSame(first, AgentInvocationProfileJsonCodec.decode(source))
        source.put("default_model", "model-b").put("models", JSONArray().put("model-b"))
        assertEquals("model-b", AgentInvocationProfileJsonCodec.decode(source).defaultModelId)
        AgentInvocationMetadataCache.shared.invalidate()
    }
}
