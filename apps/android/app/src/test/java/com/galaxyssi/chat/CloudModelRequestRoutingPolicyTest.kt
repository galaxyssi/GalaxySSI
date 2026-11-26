package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudModelRequestRoutingPolicyTest {
    @Test
    fun presetsMatchTheirProviderProtocolsAndDoNotOfferRetiredDeepSeekNames() {
        val groups = CLOUD_MODEL_PRESETS.groupBy(CloudModelPreset::provider)
        assertEquals(listOf("deepseek-v4-pro", "deepseek-flash"), groups.getValue("DeepSeek").map { it.modelId })
        assertTrue(groups.getValue("Google Gemini").all {
            it.apiStyle == "gemini" && it.endpoint.endsWith("/${it.modelId}:generateContent")
        })
        assertTrue(groups.getValue("Anthropic").all {
            it.apiStyle == "anthropic" && it.endpoint == "https://api.anthropic.com/v1/messages"
        })
        val gpt62 = CLOUD_MODEL_PRESETS.filter { "gpt-6.2" in it.modelId }
        assertEquals(listOf("openai/gpt-6.2-astra", "openai/gpt-6.2-sol"), gpt62.map { it.modelId })
        assertTrue(gpt62.all { it.provider == "OpenRouter" && it.apiStyle == "openai" })
        assertEquals(CLOUD_MODEL_PRESETS.size, CLOUD_MODEL_PRESETS.distinctBy { it.provider to it.modelId }.size)
    }

    @Test
    fun existingGeminiKeyCanSelectANewPresetAndOnlyItsModelPathChanges() {
        val oldId = "gemini-3.1-flash-lite"
        val newId = "gemini-4-neon"
        val oldUrl = "https://generativelanguage.googleapis.com/v1beta/models/$oldId:generateContent"
        val newUrl = "https://generativelanguage.googleapis.com/v1beta/models/$newId:generateContent"
        val contact = JSONObject()
            .put("cloud_provider", "Google Gemini")
            .put("cloud_model", oldId)
            .put("cloud_endpoint", oldUrl)
            .put("cloud_api_style", "gemini")
            .put("cloud_api_key", "gemini-fixture")
        val profile = CloudModelRequestRoutingPolicy.invocationProfile(contact)
        assertEquals(oldId, profile.defaultModelId)
        assertTrue(profile.models.any { it.id == newId })

        val resolved = CloudModelRequestRoutingPolicy.resolve(contact, newId, hasImageInput = true)
        assertEquals(newId, resolved.getString("cloud_model"))
        assertEquals(newUrl, resolved.getString("cloud_endpoint"))
        assertEquals("gemini-fixture", resolved.getString("cloud_api_key"))
        assertEquals(oldUrl, contact.getString("cloud_endpoint"))

        contact.put("cloud_endpoint", oldUrl.replace("generativelanguage.googleapis.com", "gateway.example.com"))
        assertEquals(listOf(oldId), CloudModelRequestRoutingPolicy.invocationProfile(contact).models.map { it.id })
    }

    @Test
    fun deepSeekProfileExposesTwoCurrentIdsAndResolvesOldSelections() {
        val existingContact = deepSeekContact(legacyFlash)
            .put(
                "cloud_models",
                JSONArray().put(model(legacyFlash, "flash-key"))
            )
        val profile = CloudModelRequestRoutingPolicy.invocationProfile(existingContact)

        assertEquals(
            listOf(
                CloudModelRequestRoutingPolicy.DEEPSEEK_V4_PRO,
                CloudModelRequestRoutingPolicy.DEEPSEEK_FLASH
            ),
            profile.models.map(AgentModelOption::id)
        )
        assertEquals(CloudModelRequestRoutingPolicy.DEEPSEEK_FLASH, profile.defaultModelId)
        assertEquals(CloudModelRequestRoutingPolicy.DEEPSEEK_FLASH, profile.normalizedModelId(legacyVision))
        assertTrue(profile.reasoningEfforts.isEmpty())
    }

    @Test
    fun proImageTurnTemporarilyUsesVisionWithoutMutatingSavedSelection() {
        val contact = deepSeekContact(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_PRO)

        val resolved = CloudModelRequestRoutingPolicy.resolve(
            contact,
            requestedModelId = CloudModelRequestRoutingPolicy.DEEPSEEK_V4_PRO,
            hasImageInput = true
        )

        assertEquals(CloudModelRequestRoutingPolicy.DEEPSEEK_FLASH, resolved.getString("cloud_model"))
        assertEquals(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_PRO, resolved.getString("selected_cloud_model"))
        assertEquals("vision-key", resolved.getString("cloud_api_key"))
        assertEquals(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_PRO, contact.getString("cloud_model"))
        assertEquals(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_PRO, contact.getString("selected_cloud_model"))
    }

    @Test
    fun bothLegacyIdsUseCurrentFlashWithoutLosingTheirCredential() {
        for ((legacyId, key) in listOf(legacyFlash to "flash-key", legacyVision to "vision-key")) {
            val contact = deepSeekContact(legacyId)
            for (image in listOf(true, false)) {
                val resolved = CloudModelRequestRoutingPolicy.resolve(contact, legacyId, hasImageInput = image)
                assertEquals(CloudModelRequestRoutingPolicy.DEEPSEEK_FLASH, resolved.getString("cloud_model"))
                assertEquals(key, resolved.getString("cloud_api_key"))
                assertEquals(legacyId, contact.getString("selected_cloud_model"))
            }
        }
    }

    @Test
    fun canonicalFlashUsesItsConfiguredCredentialForTextAndImages() {
        val id = CloudModelRequestRoutingPolicy.DEEPSEEK_FLASH
        val contact = deepSeekContact(id).put("cloud_models", JSONArray().put(model(id, "current-key")))
        for (image in listOf(true, false)) {
            val resolved = CloudModelRequestRoutingPolicy.resolve(contact, id, hasImageInput = image)
            assertEquals(id, resolved.getString("cloud_model"))
            assertEquals("current-key", resolved.getString("cloud_api_key"))
        }
    }

    @Test
    fun thirdPartyEndpointsKeepTheirOwnModelIds() {
        val thirdParty = deepSeekContact(legacyFlash)
            .put("cloud_endpoint", "https://gateway.example.com/v1/chat/completions")
            .put("cloud_models", JSONArray().put(model(legacyFlash, "third-party-key")
                .put("endpoint", "https://gateway.example.com/v1/chat/completions")))
        val qwen = JSONObject()
            .put("cloud_provider", "Qwen")
            .put("cloud_model", "qwen3.7-max")
            .put("selected_cloud_model", "qwen3.7-max")

        val resolved = CloudModelRequestRoutingPolicy.resolve(thirdParty, legacyFlash, true)
        assertEquals(legacyFlash, resolved.getString("cloud_model"))
        assertEquals("https://gateway.example.com/v1/chat/completions", resolved.getString("cloud_endpoint"))
        assertEquals(
            "qwen3.7-max",
            CloudModelRequestRoutingPolicy.resolve(qwen, "qwen3.7-max", true).getString("cloud_model")
        )
        assertFalse(CloudModelRequestRoutingPolicy.invocationProfile(qwen).models.any {
            it.id == CloudModelRequestRoutingPolicy.DEEPSEEK_FLASH
        })
    }

    private fun deepSeekContact(
        selectedModelId: String = CloudModelRequestRoutingPolicy.DEEPSEEK_V4_PRO
    ): JSONObject = JSONObject()
        .put("cloud_provider", "DeepSeek")
        .put("cloud_endpoint", "https://api.deepseek.com/chat/completions")
        .put("cloud_api_key", "provider-key")
        .put("cloud_api_style", "openai")
        .put("cloud_model", selectedModelId)
        .put("selected_cloud_model", selectedModelId)
        .put("cloud_models", JSONArray()
            .put(model(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_PRO, "pro-key"))
            .put(model(legacyFlash, "flash-key"))
            .put(model(legacyVision, "vision-key")))

    private val legacyFlash = "deepseek-v4-flash"
    private val legacyVision = "deepseek-v4-flash-vision-exp"

    private fun model(id: String, apiKey: String): JSONObject = JSONObject()
        .put("name", id)
        .put("model_id", id)
        .put("endpoint", "https://api.deepseek.com/chat/completions")
        .put("api_key", apiKey)
        .put("api_style", "openai")
}
