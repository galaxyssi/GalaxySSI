package com.galaxyssi.chat

import java.net.URI
import org.json.JSONObject

internal object CloudModelRequestRoutingPolicy {
    const val DEEPSEEK_V4_PRO = "deepseek-v4-pro"
    const val DEEPSEEK_FLASH = "deepseek-flash"

    private const val LEGACY_FLASH = "deepseek-v4-flash"
    private const val LEGACY_VISION = "deepseek-v4-flash-vision-exp"
    private val deepSeekAliases = mapOf(LEGACY_FLASH to DEEPSEEK_FLASH, LEGACY_VISION to DEEPSEEK_FLASH)

    private val deepSeekModels = listOf(
        AgentModelOption(DEEPSEEK_V4_PRO),
        AgentModelOption(DEEPSEEK_FLASH)
    )

    fun invocationProfile(contact: JSONObject): AgentInvocationProfile {
        val useDeepSeekCatalog = isDirectDeepSeek(contact.optString("cloud_endpoint"))
        val aliases = if (useDeepSeekCatalog) deepSeekAliases else emptyMap()
        val current = contact.optString("selected_cloud_model")
            .ifBlank { contact.optString("cloud_model") }.let { aliases[it] ?: it }
        val configured = buildList<AgentModelOption> {
            val models = contact.optJSONArray("cloud_models")
            if (models != null) {
                for (index in 0 until models.length()) {
                    val model = models.optJSONObject(index) ?: continue
                    val modelId = model.optString("model_id").trim()
                    if (modelId.isBlank() || modelId in aliases || any { it.id == modelId }) continue
                    add(AgentModelOption(
                        id = modelId,
                        displayName = modelId
                    ))
                }
            }
            if (current.isNotBlank() && none { it.id == current }) add(AgentModelOption(current))
        }
        val presets = if (useDeepSeekCatalog) deepSeekModels else providerPresets(contact).map {
            AgentModelOption(it.modelId, it.name)
        }
        val models = (presets + configured)
            .distinctBy(AgentModelOption::id)
        return AgentInvocationProfile(
            defaultModelId = current.takeIf { selected -> models.any { it.id == selected } }
                ?: models.firstOrNull()?.id.orEmpty(),
            models = models,
            modelAliases = aliases
        )
    }

    fun resolve(
        contact: JSONObject,
        requestedModelId: String,
        hasImageInput: Boolean
    ): JSONObject {
        val resolved = JSONObject(contact.toString())
        val profile = invocationProfile(resolved)
        val current = resolved.optString("selected_cloud_model").ifBlank { resolved.optString("cloud_model") }
        val aliases = profile.modelAliases
        val rawRequest = requestedModelId.trim()
        val requested = (aliases[rawRequest] ?: rawRequest).takeIf { candidate ->
            profile.models.any { it.id == candidate }
        }
        val selectedModelId = requested ?: aliases[current] ?: current
        val isDirect = aliases.isNotEmpty()
        val effectiveModelId = if (isDirect && hasImageInput && selectedModelId == DEEPSEEK_V4_PRO) {
            DEEPSEEK_FLASH
        } else selectedModelId
        val legacyModelIds = if (isDirect && effectiveModelId == DEEPSEEK_FLASH) {
            listOf(rawRequest, current, LEGACY_VISION, LEGACY_FLASH).filter { it in aliases }
        } else emptyList()
        val credentialModelIds = (listOf(effectiveModelId) + legacyModelIds + selectedModelId).distinct()
        if (!credentialModelIds.any { applyConfiguredModel(resolved, it, isDirect && (it == DEEPSEEK_FLASH || it in aliases)) }) {
            providerPresets(contact).firstOrNull { it.modelId == effectiveModelId }?.let {
                resolved.put("cloud_endpoint", it.endpoint)
            }
        }
        resolved.put("selected_cloud_model", selectedModelId)
        resolved.put("cloud_model", effectiveModelId)
        return resolved
    }

    private fun applyConfiguredModel(contact: JSONObject, modelId: String, requireDirect: Boolean): Boolean {
        val models = contact.optJSONArray("cloud_models") ?: return false
        for (index in 0 until models.length()) {
            val model = models.optJSONObject(index) ?: continue
            if (model.optString("model_id") != modelId) continue
            val endpoint = model.optString("endpoint").ifBlank {
                contact.optString("cloud_endpoint")
            }
            if (requireDirect && !isDirectDeepSeek(endpoint)) continue
            contact.put("cloud_endpoint", endpoint)
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

    private fun isDirectDeepSeek(endpoint: String): Boolean = runCatching {
        val uri = URI(endpoint)
        uri.scheme.equals("https", ignoreCase = true) && uri.host.equals("api.deepseek.com", ignoreCase = true)
    }.getOrDefault(false)

    private fun providerPresets(contact: JSONObject): List<CloudModelPreset> {
        val provider = contact.optString("cloud_provider")
        if (provider.isBlank() || provider == "Custom") return emptyList()
        val style = contact.optString("cloud_api_style", "openai")
        val endpoint = contact.optString("cloud_endpoint")
        val matchingPresets = CLOUD_MODEL_PRESETS.filter { it.provider == provider && it.apiStyle == style }
        // A shared provider key is valid only on the configured official endpoint.
        // Gemini embeds the current model in its path; verify that path before swapping it.
        val official = matchingPresets.any { preset ->
            val expected = if (style == "gemini") preset.endpoint.replace(
                "/models/${preset.modelId}:generateContent",
                "/models/${contact.optString("cloud_model")}:generateContent"
            ) else preset.endpoint
            endpoint == expected
        }
        return if (official) matchingPresets else emptyList()
    }
}
