package com.galaxyssi.chat.voice.model

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class WhisperModelCatalogTest {
    @Test
    fun catalogKeepsLegacyIdsAndAddsPinnedQuantizedProfiles() {
        assertEquals(
            setOf(
                "tiny",
                "tiny_q5_1",
                "base",
                "base_q5_1",
                "small",
                "small_q5_1",
                "medium",
                "medium_q5_0",
                "large",
                "large_v3_q5_0",
                "large_v3_turbo",
                "large_v3_turbo_q5_0"
            ),
            WhisperModelCatalog.profiles.mapTo(linkedSetOf()) { it.id }
        )
        assertEquals(WhisperModelFamily.LARGE_V3, WhisperModelCatalog.require("large").family)
        assertEquals("large", WhisperModelCatalog.require("large_v3").id)
        assertEquals("large", WhisperModelCatalog.require("large-v3").id)
        assertEquals("ggml-large-v3.bin", WhisperModelCatalog.require("large").fileName)
        assertTrue(WhisperModelCatalog.require("tiny").bundled)
        assertFalse(WhisperModelCatalog.require("medium").bundled)
        assertFalse(WhisperModelCatalog.require("large_v3_turbo").bundled)
    }

    @Test
    fun everyCatalogProfileUsesPinnedHttpsMetadata() {
        WhisperModelCatalog.profiles.forEach { profile ->
            assertTrue(profile.expectedSizeBytes > 30_000_000L)
            assertTrue(profile.sha256.matches(Regex("[0-9a-f]{64}")))
            assertTrue(profile.sourceUrls.all { it.startsWith("https://") })
            assertEquals(WhisperModelCatalog.SCHEMA_VERSION, profile.manifestVersion)
        }
        assertEquals(
            "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
            WhisperModelCatalog.require("large_v3_turbo").sha256
        )
    }

    @Test
    fun signedManifestRejectsBadSignatureDuplicatesAndPathTraversal() {
        val valid = manifestJson(listOf(profileJson("test", "ggml-test.bin")))
        val parsed = WhisperModelManifestParser.parseSigned(valid) { payload, signature ->
            payload.contains("4:test") && payload.contains("4:TINY") && signature == "signed"
        }
        assertEquals(WhisperManifestTrust.SIGNED_REMOTE, parsed.trust)
        assertNotNull(parsed.models.single())

        assertThrows(IllegalArgumentException::class.java) {
            WhisperModelManifestParser.parseSigned(valid) { _, _ -> false }
        }
        assertThrows(IllegalArgumentException::class.java) {
            WhisperModelManifestParser.parseSigned(
                manifestJson(listOf(profileJson("test", "ggml-test.bin"), profileJson("test", "ggml-other.bin")))
            ) { _, _ -> true }
        }
        assertThrows(IllegalArgumentException::class.java) {
            WhisperModelManifestParser.parseSigned(
                manifestJson(listOf(profileJson("test", "../model.bin")))
            ) { _, _ -> true }
        }
    }

    private fun manifestJson(models: List<JSONObject>): String = JSONObject()
        .put("schemaVersion", WhisperModelCatalog.SCHEMA_VERSION)
        .put("catalogVersion", "test-v1")
        .put("models", JSONArray(models))
        .put("signature", "signed")
        .toString()

    private fun profileJson(id: String, fileName: String): JSONObject = JSONObject()
        .put("id", id)
        .put("family", "TINY")
        .put("displayName", "Test")
        .put("fileName", fileName)
        .put("sourceUrls", JSONArray(listOf("https://example.com/$fileName")))
        .put("expectedSizeBytes", 4L)
        .put("sha256", "0".repeat(64))
        .put("quantization", "F16")
        .put("multilingual", true)
        .put("recommendedMode", "FINAL_ONLY")
        .put("minAvailableRamBytes", 0L)
        .put("minFreeStorageBytes", 0L)
        .put("defaultPartialIntervalMs", 1_000L)
        .put("maxWindowMs", 8_000L)
        .put("manifestVersion", WhisperModelCatalog.SCHEMA_VERSION)
}
