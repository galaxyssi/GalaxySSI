package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudModelRequestRoutingPolicyTest {
    @Test
    fun deepSeekProfileAlwaysExposesTheThreeSupportedModelIds() {
        val existingContact = deepSeekContact(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_FLASH)
            .put(
                "cloud_models",
                JSONArray().put(model(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_FLASH, "flash-key"))
            )
        val profile = CloudModelRequestRoutingPolicy.invocationProfile(existingContact)

        assertEquals(
            listOf(
                CloudModelRequestRoutingPolicy.DEEPSEEK_V4_PRO,
                CloudModelRequestRoutingPolicy.DEEPSEEK_V4_FLASH,
                CloudModelRequestRoutingPolicy.DEEPSEEK_V4_FLASH_VISION
            ),
            profile.models.map(AgentModelOption::id)
        )
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

        assertEquals(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_FLASH_VISION, resolved.getString("cloud_model"))
        assertEquals(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_PRO, resolved.getString("selected_cloud_model"))
        assertEquals("vision-key", resolved.getString("cloud_api_key"))
        assertEquals(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_PRO, contact.getString("cloud_model"))
        assertEquals(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_PRO, contact.getString("selected_cloud_model"))
    }

    @Test
    fun flashImageTurnUsesVisionAndTextTurnKeepsFlash() {
        val contact = deepSeekContact(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_FLASH)

        val image = CloudModelRequestRoutingPolicy.resolve(contact, "", hasImageInput = true)
        val text = CloudModelRequestRoutingPolicy.resolve(contact, "", hasImageInput = false)

        assertEquals(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_FLASH_VISION, image.getString("cloud_model"))
        assertEquals(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_FLASH, text.getString("cloud_model"))
    }

    @Test
    fun explicitlySelectedVisionAndNonDeepSeekModelsRemainUnchanged() {
        val vision = CloudModelRequestRoutingPolicy.resolve(
            deepSeekContact(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_FLASH_VISION),
            requestedModelId = CloudModelRequestRoutingPolicy.DEEPSEEK_V4_FLASH_VISION,
            hasImageInput = true
        )
        val qwen = JSONObject()
            .put("cloud_provider", "Qwen")
            .put("cloud_model", "qwen3.7-max")
            .put("selected_cloud_model", "qwen3.7-max")

        assertEquals(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_FLASH_VISION, vision.getString("cloud_model"))
        assertEquals(
            "qwen3.7-max",
            CloudModelRequestRoutingPolicy.resolve(qwen, "qwen3.7-max", true).getString("cloud_model")
        )
        assertFalse(CloudModelRequestRoutingPolicy.invocationProfile(qwen).models.any {
            it.id == CloudModelRequestRoutingPolicy.DEEPSEEK_V4_FLASH_VISION
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
            .put(model(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_FLASH, "flash-key"))
            .put(model(CloudModelRequestRoutingPolicy.DEEPSEEK_V4_FLASH_VISION, "vision-key")))

    private fun model(id: String, apiKey: String): JSONObject = JSONObject()
        .put("name", id)
        .put("model_id", id)
        .put("endpoint", "https://api.deepseek.com/chat/completions")
        .put("api_key", apiKey)
        .put("api_style", "openai")
}
