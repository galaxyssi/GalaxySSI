package com.signalasi.chat

import org.json.JSONObject

internal object CloudModelRequestRoutingPolicy {
    const val DEEPSEEK_V4_PRO = "deepseek-v4-pro"
    const val DEEPSEEK_V4_FLASH = "deepseek-v4-flash"
    const val DEEPSEEK_V4_FLASH_VISION = "deepseek-v4-flash-vision-exp"

    private val deepSeekModels = listOf(
        AgentModelOption(DEEPSEEK_V4_PRO),
        AgentModelOption(DEEPSEEK_V4_FLASH),
        AgentModelOption(DEEPSEEK_V4_FLASH_VISION)
    )

    fun invocationProfile(contact: JSONObject): AgentInvocationProfile {
        val configured = buildList<AgentModelOption> {
            val models = contact.optJSONArray("cloud_models")
            if (models != null) {
                for (index in 0 until models.length()) {
                    val model = models.optJSONObject(index) ?: continue
                    val modelId = model.optString("model_id").trim()
                    if (modelId.isBlank() || any { it.id == modelId }) continue
                    add(AgentModelOption(
                        id = modelId,
                        displayName = modelId
                    ))
                }
            }
        }
        val models = ((if (isDeepSeek(contact)) deepSeekModels else emptyList()) + configured)
            .distinctBy(AgentModelOption::id)
        val current = contact.optString("selected_cloud_model")
            .ifBlank { contact.optString("cloud_model") }
        return AgentInvocationProfile(
            defaultModelId = current.takeIf { selected -> models.any { it.id == selected } }
                ?: models.firstOrNull()?.id.orEmpty(),
            models = models
        )
    }

    fun resolve(
        contact: JSONObject,
        requestedModelId: String,
        hasImageInput: Boolean
    ): JSONObject {
        val resolved = JSONObject(contact.toString())
        val profile = invocationProfile(resolved)
        val requested = requestedModelId.trim().takeIf { candidate ->
            profile.models.any { it.id == candidate }
        }
        val selectedModelId = requested
            ?: resolved.optString("selected_cloud_model").takeIf(String::isNotBlank)
            ?: resolved.optString("cloud_model")
        val effectiveModelId = effectiveModelId(selectedModelId, hasImageInput)
        if (!applyConfiguredModel(resolved, effectiveModelId)) {
            applyConfiguredModel(resolved, selectedModelId)
        }
        resolved.put("selected_cloud_model", selectedModelId)
        resolved.put("cloud_model", effectiveModelId)
        return resolved
    }

    fun effectiveModelId(selectedModelId: String, hasImageInput: Boolean): String =
        if (hasImageInput && selectedModelId in setOf(DEEPSEEK_V4_PRO, DEEPSEEK_V4_FLASH)) {
            DEEPSEEK_V4_FLASH_VISION
        } else {
            selectedModelId
        }

    private fun applyConfiguredModel(contact: JSONObject, modelId: String): Boolean {
        val models = contact.optJSONArray("cloud_models") ?: return false
        for (index in 0 until models.length()) {
            val model = models.optJSONObject(index) ?: continue
            if (model.optString("model_id") != modelId) continue
            contact.put("cloud_endpoint", model.optString("endpoint").ifBlank {
                contact.optString("cloud_endpoint")
            })
            contact.put("cloud_api_key", model.optString("api_key").ifBlank {
                contact.optString("cloud_api_key")
            })
            contact.put("cloud_api_style", model.optString("api_style").ifBlank {
                contact.optString("cloud_api_style").ifBlank { "openai" }
            })
            return true
        }
        return false
    }

    private fun isDeepSeek(contact: JSONObject): Boolean {
        val identity = buildString {
            append(contact.optString("cloud_provider"))
            append(' ')
            append(contact.optString("name"))
            append(' ')
            append(contact.optString("cloud_endpoint"))
            append(' ')
            append(contact.optString("cloud_model"))
        }.lowercase()
        return "deepseek" in identity
    }
}
