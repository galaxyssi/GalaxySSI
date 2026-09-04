package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudProviderContactConfigurationTest {
    @Test
    fun replacementCredentialUpdatesEveryProviderModelAndSelectsConfiguredModel() {
        val contact = providerContact()
            .put("selected_cloud_model", "deepseek-v4-flash")
            .put("deleted", true)
            .put("deleted_at", 42L)
        val configured = JSONObject()
            .put("name", "DeepSeek V4 Pro")
            .put("model_id", "deepseek-v4-pro")
            .put("endpoint", "https://api.deepseek.com/chat/completions")
            .put("api_key", "new-provider-key")
            .put("api_style", "openai")

        AppStore.configureCloudProviderModel(
            contact = contact,
            model = configured,
            selectedModelId = "deepseek-v4-pro",
            updatedAt = 100L
        )

        assertEquals("deepseek-v4-pro", contact.getString("selected_cloud_model"))
        assertEquals("deepseek-v4-pro", contact.getString("cloud_model"))
        assertEquals("new-provider-key", contact.getString("cloud_api_key"))
        assertEquals("ready", contact.getString("setup_status"))
        assertFalse(contact.getBoolean("deleted"))
        assertFalse(contact.has("deleted_at"))
        val models = contact.getJSONArray("cloud_models")
        assertEquals(2, models.length())
        repeat(models.length()) { index ->
            assertEquals("new-provider-key", models.getJSONObject(index).getString("api_key"))
            assertEquals(100L, models.getJSONObject(index).getLong("updated_at"))
        }
    }

    @Test
    fun deletingProviderRemovesEveryStoredCredential() {
        val contact = providerContact()
            .put("cloud_api_key", "old-provider-key")
            .put("setup_status", "ready")

        AppStore.clearCloudProviderCredentials(contact)

        assertFalse(contact.has("cloud_api_key"))
        assertEquals("needs_setup", contact.getString("setup_status"))
        val models = contact.getJSONArray("cloud_models")
        repeat(models.length()) { index ->
            assertFalse(models.getJSONObject(index).has("api_key"))
        }
    }

    @Test
    fun placeholderCredentialCannotLeaveProviderReady() {
        val contact = providerContact()
        val configured = JSONObject()
            .put("name", "DeepSeek V4 Pro")
            .put("model_id", "deepseek-v4-pro")
            .put("endpoint", "https://api.deepseek.com/chat/completions")
            .put("api_key", "your-api-key")
            .put("api_style", "openai")

        AppStore.configureCloudProviderModel(contact, configured, "deepseek-v4-pro", 100L)

        assertEquals("needs_setup", contact.getString("setup_status"))
        assertTrue(contact.getString("cloud_api_key").isNotBlank())
    }

    private fun providerContact(): JSONObject = JSONObject()
        .put("id", "cloud:deepseek")
        .put("cloud_provider", "DeepSeek")
        .put("delivery_mode", "cloud_api")
        .put("cloud_models", JSONArray()
            .put(model("DeepSeek V4 Pro", "deepseek-v4-pro", "old-pro-key"))
            .put(model("DeepSeek V4 Flash", "deepseek-v4-flash", "old-flash-key")))

    private fun model(name: String, id: String, key: String): JSONObject = JSONObject()
        .put("name", name)
        .put("model_id", id)
        .put("endpoint", "https://api.deepseek.com/chat/completions")
        .put("api_key", key)
        .put("api_style", "openai")
        .put("updated_at", 1L)
}
