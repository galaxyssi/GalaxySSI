package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

enum class ProviderProfileKind {
    AGENT,
    CLOUD_MODEL,
    LOCAL_MODEL
}

data class ProviderPricingProfile(
    val tier: AgentResourceCost,
    val inputMicrosPerMillionTokens: Long? = null,
    val outputMicrosPerMillionTokens: Long? = null,
    val currency: String = "USD",
    val source: String = "catalog_tier"
)

data class ProviderPerformanceProfile(
    val attempts: Int = 0,
    val successes: Int = 0,
    val failures: Int = 0,
    val consecutiveFailures: Int = 0,
    val failureRate: Double = 0.0,
    val ewmaLatencyMs: Double = 0.0,
    val lastObservedAtMillis: Long = 0L
) {
    companion object {
        fun fromHealth(health: AgentResourceHealth): ProviderPerformanceProfile {
            val attempts = (health.successes + health.failures).coerceAtLeast(0)
            return ProviderPerformanceProfile(
                attempts = attempts,
                successes = health.successes.coerceAtLeast(0),
                failures = health.failures.coerceAtLeast(0),
                consecutiveFailures = health.consecutiveFailures.coerceAtLeast(0),
                failureRate = if (attempts == 0) 0.0 else health.failures.toDouble() / attempts,
                ewmaLatencyMs = health.averageLatencyMs.coerceAtLeast(0).toDouble(),
                lastObservedAtMillis = health.lastUpdatedAt.coerceAtLeast(0)
            )
        }
    }
}

data class ProviderProfile(
    val profileId: String,
    val resourceId: String,
    val providerId: String,
    val productId: String,
    val displayName: String,
    val kind: ProviderProfileKind,
    val location: AgentResourceLocation,
    val status: AgentConnectorStatus,
    val protocolFamily: String,
    val adapterType: String,
    val modelId: String = "",
    val capabilities: Set<AgentCapability> = emptySet(),
    val toolIds: Set<String> = emptySet(),
    val contextWindowTokens: Int = 8_192,
    val maxOutputTokens: Int = 4_096,
    val maxParallelRuns: Int = 1,
    val supportsTools: Boolean = false,
    val supportsStreaming: Boolean = false,
    val supportsBackground: Boolean = false,
    val latency: AgentResourceLatency = AgentResourceLatency.NORMAL,
    val quality: AgentResourceQuality = AgentResourceQuality.STANDARD,
    val trust: AgentResourceTrust = AgentResourceTrust.UNKNOWN,
    val failureDomain: String = "",
    val endpointConfigured: Boolean = false,
    val credentialConfigured: Boolean = false,
    val pricing: ProviderPricingProfile = ProviderPricingProfile(AgentResourceCost.FREE),
    val performance: ProviderPerformanceProfile = ProviderPerformanceProfile(),
    val schemaVersion: Int = SCHEMA_VERSION,
    val metadata: Map<String, String> = emptyMap()
) {
    fun withHealth(health: AgentResourceHealth): ProviderProfile =
        copy(performance = ProviderPerformanceProfile.fromHealth(health))

    companion object {
        const val SCHEMA_VERSION = 1
    }
}

data class ModelProviderProfileDefinition(
    val providerId: String,
    val displayName: String,
    val protocolFamily: String,
    val location: AgentResourceLocation,
    val cost: AgentResourceCost,
    val latency: AgentResourceLatency,
    val quality: AgentResourceQuality,
    val contextWindowTokens: Int,
    val supportsTools: Boolean,
    val supportsStreaming: Boolean
)

object ProviderProfileCatalog {
    val modelProviders: List<ModelProviderProfileDefinition> = listOf(
        ModelProviderProfileDefinition(
            "openai", "OpenAI", "openai", AgentResourceLocation.CLOUD,
            AgentResourceCost.MEDIUM, AgentResourceLatency.NORMAL, AgentResourceQuality.FRONTIER,
            128_000, true, true
        ),
        ModelProviderProfileDefinition(
            "anthropic", "Claude", "anthropic", AgentResourceLocation.CLOUD,
            AgentResourceCost.MEDIUM, AgentResourceLatency.NORMAL, AgentResourceQuality.FRONTIER,
            200_000, true, true
        ),
        ModelProviderProfileDefinition(
            "gemini", "Gemini", "gemini", AgentResourceLocation.CLOUD,
            AgentResourceCost.MEDIUM, AgentResourceLatency.FAST, AgentResourceQuality.FRONTIER,
            1_000_000, true, true
        ),
        ModelProviderProfileDefinition(
            "deepseek", "DeepSeek", "openai", AgentResourceLocation.CLOUD,
            AgentResourceCost.LOW, AgentResourceLatency.NORMAL, AgentResourceQuality.FRONTIER,
            128_000, true, true
        ),
        ModelProviderProfileDefinition(
            "qwen", "Qwen", "openai", AgentResourceLocation.CLOUD,
            AgentResourceCost.LOW, AgentResourceLatency.NORMAL, AgentResourceQuality.STRONG,
            131_072, true, true
        ),
        ModelProviderProfileDefinition(
            "ollama", "Ollama", "ollama", AgentResourceLocation.PRIVATE_NETWORK,
            AgentResourceCost.FREE, AgentResourceLatency.FAST, AgentResourceQuality.STANDARD,
            32_768, false, true
        ),
        ModelProviderProfileDefinition(
            "lm-studio", "LM Studio", "openai", AgentResourceLocation.PRIVATE_NETWORK,
            AgentResourceCost.FREE, AgentResourceLatency.FAST, AgentResourceQuality.STANDARD,
            32_768, false, true
        ),
        ModelProviderProfileDefinition(
            "openrouter", "OpenRouter", "openai", AgentResourceLocation.CLOUD,
            AgentResourceCost.MEDIUM, AgentResourceLatency.NORMAL, AgentResourceQuality.FRONTIER,
            128_000, true, true
        )
    )

    fun fromCloudContact(
        contact: JSONObject,
        status: AgentConnectorStatus,
        performance: ProviderPerformanceProfile = ProviderPerformanceProfile()
    ): ProviderProfile {
        val providerId = normalizeProviderId(
            contact.optString("cloud_provider").ifBlank { contact.optString("name") }
        )
        val definition = definition(providerId)
        val endpoint = contact.optString("cloud_endpoint")
        val resourceId = contact.optString("id")
            .ifBlank { contact.optString("signalasi_id") }
            .ifBlank { "cloud:$providerId" }
        val local = isLocalEndpoint(endpoint) ||
            definition.location == AgentResourceLocation.PRIVATE_NETWORK
        val capabilities = buildSet {
            add(AgentCapability.CHAT)
            add(AgentCapability.REASONING)
            if (definition.supportsTools) {
                add(AgentCapability.TOOL_USE)
                add(AgentCapability.LIVE_DATA)
            }
            if (local) add(AgentCapability.LOCAL_INFERENCE)
        }
        return ProviderProfile(
            profileId = "model:$providerId",
            resourceId = resourceId,
            providerId = providerId,
            productId = providerId,
            displayName = contact.optString("cloud_provider")
                .ifBlank { definition.displayName },
            kind = if (local) ProviderProfileKind.LOCAL_MODEL else ProviderProfileKind.CLOUD_MODEL,
            location = if (local) AgentResourceLocation.PRIVATE_NETWORK else definition.location,
            status = status,
            protocolFamily = contact.optString("cloud_api_style")
                .ifBlank { definition.protocolFamily },
            adapterType = "${definition.protocolFamily}-model-api",
            modelId = contact.optString("cloud_model"),
            capabilities = capabilities,
            contextWindowTokens = contact.optInt(
                "cloud_context_window_tokens",
                definition.contextWindowTokens
            ).coerceAtLeast(4_096),
            maxOutputTokens = contact.optInt("cloud_max_output_tokens", 4_096).coerceAtLeast(512),
            maxParallelRuns = if (local) 2 else AgentConnectorCapacityPolicy.MAX_PARALLEL_RUNS,
            supportsTools = definition.supportsTools,
            supportsStreaming = definition.supportsStreaming,
            supportsBackground = true,
            latency = definition.latency,
            quality = definition.quality,
            trust = if (local) AgentResourceTrust.PRIVATE_CONFIGURED else AgentResourceTrust.CLOUD_CONFIGURED,
            failureDomain = if (local) "private-model:$providerId" else "cloud-model:$providerId",
            endpointConfigured = endpoint.isNotBlank(),
            credentialConfigured = local || contact.optString("cloud_api_key").isNotBlank(),
            pricing = ProviderPricingProfile(definition.cost),
            performance = performance,
            metadata = mapOf("native_product_identity" to providerId)
        )
    }

    fun fromRegistration(
        registration: AgentRegistration,
        existing: ProviderProfile? = registration.providerProfile
    ): ProviderProfile {
        val base = existing ?: agentProfile(
            resourceId = registration.agentId,
            displayName = registration.displayName,
            providerId = registration.providerId.ifBlank { registration.agentId },
            adapterType = registration.adapterType,
            location = registration.location,
            status = registration.status.toConnectorStatus(),
            capabilities = registration.capabilities,
            toolIds = registration.toolIds,
            cost = registration.cost,
            latency = registration.latency,
            trust = registration.trust,
            failureDomain = registration.failureDomain,
            maxParallelRuns = registration.maxParallelRuns
        )
        return base.copy(
            resourceId = registration.agentId,
            displayName = registration.displayName,
            status = registration.status.toConnectorStatus(),
            capabilities = registration.capabilities,
            toolIds = registration.toolIds,
            adapterType = registration.adapterType.ifBlank { base.adapterType },
            location = registration.location,
            latency = registration.latency,
            trust = registration.trust,
            failureDomain = registration.failureDomain.ifBlank { base.failureDomain },
            maxParallelRuns = registration.maxParallelRuns.coerceAtLeast(1),
            pricing = base.pricing.copy(tier = registration.cost)
        )
    }

    fun fromTarget(target: AgentCallableTarget): ProviderProfile {
        target.providerProfile?.let { return it }
        if (target.kind == AgentConnectorKind.MODEL) {
            val pseudoContact = JSONObject()
                .put("id", target.id)
                .put("name", target.title)
                .put("cloud_provider", providerIdForTarget(target))
                .put("cloud_model", "")
            return fromCloudContact(pseudoContact, target.status).copy(
                adapterType = target.adapterType.ifBlank { "model-api" },
                failureDomain = target.failureDomain.ifBlank {
                    "model:${providerIdForTarget(target)}"
                }
            )
        }
        return agentProfile(
            resourceId = target.id,
            displayName = target.title,
            providerId = providerIdForTarget(target),
            adapterType = target.adapterType,
            location = when {
                target.kind == AgentConnectorKind.AGENT -> AgentResourceLocation.TRUSTED_DESKTOP
                target.failureDomain.startsWith("desktop") -> AgentResourceLocation.TRUSTED_DESKTOP
                else -> AgentResourceLocation.CLOUD
            },
            status = target.status,
            capabilities = target.capabilities.toSet(),
            failureDomain = target.failureDomain,
            maxParallelRuns = AgentConnectorCapacityPolicy.MAX_PARALLEL_RUNS
        )
    }

    fun decode(json: JSONObject?): ProviderProfile? {
        val source = json ?: return null
        if (source.optInt("schema_version", 0) != ProviderProfile.SCHEMA_VERSION) return null
        val profileId = source.optString("profile_id")
        val resourceId = source.optString("resource_id")
        if (profileId.isBlank() || resourceId.isBlank()) return null
        val pricing = source.optJSONObject("pricing") ?: JSONObject()
        val performance = source.optJSONObject("performance") ?: JSONObject()
        val metadata = source.optJSONObject("metadata") ?: JSONObject()
        return runCatching {
            ProviderProfile(
                profileId = profileId,
                resourceId = resourceId,
                providerId = source.optString("provider_id"),
                productId = source.optString("product_id"),
                displayName = source.optString("display_name"),
                kind = enumValue(source.optString("kind"), ProviderProfileKind.AGENT),
                location = enumValue(source.optString("location"), AgentResourceLocation.CLOUD),
                status = connectorStatus(source.optString("status")),
                protocolFamily = source.optString("protocol_family"),
                adapterType = source.optString("adapter_type"),
                modelId = source.optString("model_id"),
                capabilities = source.optJSONArray("capabilities").enumSet(enumValues<AgentCapability>()),
                toolIds = source.optJSONArray("tool_ids").strings(),
                contextWindowTokens = source.optInt("context_window_tokens", 8_192).coerceAtLeast(0),
                maxOutputTokens = source.optInt("max_output_tokens", 4_096).coerceAtLeast(0),
                maxParallelRuns = source.optInt("max_parallel_runs", 1).coerceAtLeast(1),
                supportsTools = source.optBoolean("supports_tools"),
                supportsStreaming = source.optBoolean("supports_streaming"),
                supportsBackground = source.optBoolean("supports_background"),
                latency = enumValue(source.optString("latency_tier"), AgentResourceLatency.NORMAL),
                quality = enumValue(source.optString("quality_tier"), AgentResourceQuality.STANDARD),
                trust = enumValue(source.optString("trust"), AgentResourceTrust.UNKNOWN),
                failureDomain = source.optString("failure_domain"),
                endpointConfigured = source.optBoolean("endpoint_configured"),
                credentialConfigured = source.optBoolean("credential_configured"),
                pricing = ProviderPricingProfile(
                    tier = enumValue(pricing.optString("tier"), AgentResourceCost.FREE),
                    inputMicrosPerMillionTokens = pricing.optionalLong("input_micros_per_million_tokens"),
                    outputMicrosPerMillionTokens = pricing.optionalLong("output_micros_per_million_tokens"),
                    currency = pricing.optString("currency", "USD"),
                    source = pricing.optString("source", "catalog_tier")
                ),
                performance = ProviderPerformanceProfile(
                    attempts = performance.optInt("attempts"),
                    successes = performance.optInt("successes"),
                    failures = performance.optInt("failures"),
                    consecutiveFailures = performance.optInt("consecutive_failures"),
                    failureRate = performance.optDouble("failure_rate"),
                    ewmaLatencyMs = performance.optDouble("ewma_latency_ms"),
                    lastObservedAtMillis = performance.optLong("last_observed_at_millis")
                ),
                metadata = metadata.keys().asSequence().associateWith(metadata::optString)
            )
        }.getOrNull()
    }

    fun encode(profile: ProviderProfile): JSONObject = JSONObject()
        .put("schema_version", profile.schemaVersion)
        .put("profile_id", profile.profileId)
        .put("resource_id", profile.resourceId)
        .put("provider_id", profile.providerId)
        .put("product_id", profile.productId)
        .put("display_name", profile.displayName)
        .put("kind", profile.kind.name.lowercase(Locale.ROOT))
        .put("location", profile.location.name.lowercase(Locale.ROOT))
        .put("status", profile.status.name.lowercase(Locale.ROOT))
        .put("protocol_family", profile.protocolFamily)
        .put("adapter_type", profile.adapterType)
        .put("model_id", profile.modelId)
        .put("capabilities", JSONArray(profile.capabilities.map { it.name.lowercase(Locale.ROOT) }))
        .put("tool_ids", JSONArray(profile.toolIds.sorted()))
        .put("context_window_tokens", profile.contextWindowTokens)
        .put("max_output_tokens", profile.maxOutputTokens)
        .put("max_parallel_runs", profile.maxParallelRuns)
        .put("supports_tools", profile.supportsTools)
        .put("supports_streaming", profile.supportsStreaming)
        .put("supports_background", profile.supportsBackground)
        .put("latency_tier", profile.latency.name.lowercase(Locale.ROOT))
        .put("quality_tier", profile.quality.name.lowercase(Locale.ROOT))
        .put("trust", profile.trust.name.lowercase(Locale.ROOT))
        .put("failure_domain", profile.failureDomain)
        .put("endpoint_configured", profile.endpointConfigured)
        .put("credential_configured", profile.credentialConfigured)
        .put("pricing", JSONObject()
            .put("tier", profile.pricing.tier.name.lowercase(Locale.ROOT))
            .put("input_micros_per_million_tokens", profile.pricing.inputMicrosPerMillionTokens)
            .put("output_micros_per_million_tokens", profile.pricing.outputMicrosPerMillionTokens)
            .put("currency", profile.pricing.currency)
            .put("source", profile.pricing.source))
        .put("performance", JSONObject()
            .put("attempts", profile.performance.attempts)
            .put("successes", profile.performance.successes)
            .put("failures", profile.performance.failures)
            .put("consecutive_failures", profile.performance.consecutiveFailures)
            .put("failure_rate", profile.performance.failureRate)
            .put("ewma_latency_ms", profile.performance.ewmaLatencyMs)
            .put("last_observed_at_millis", profile.performance.lastObservedAtMillis))
        .put("metadata", JSONObject(profile.metadata))

    fun normalizeProviderId(value: String): String {
        val normalized = value.trim().lowercase(Locale.ROOT)
            .replace("_", "-")
            .replace(" ", "-")
        return when (normalized) {
            "claude", "anthropic-claude" -> "anthropic"
            "google", "google-gemini" -> "gemini"
            "lmstudio" -> "lm-studio"
            "open-router" -> "openrouter"
            "dashscope" -> "qwen"
            else -> normalized.ifBlank { "custom" }
        }
    }

    private fun agentProfile(
        resourceId: String,
        displayName: String,
        providerId: String,
        adapterType: String,
        location: AgentResourceLocation,
        status: AgentConnectorStatus,
        capabilities: Set<AgentCapability>,
        toolIds: Set<String> = emptySet(),
        cost: AgentResourceCost = AgentResourceCost.FREE,
        latency: AgentResourceLatency = AgentResourceLatency.NORMAL,
        trust: AgentResourceTrust = AgentResourceTrust.VERIFIED_PAIRED,
        failureDomain: String,
        maxParallelRuns: Int
    ): ProviderProfile {
        val productId = normalizeProductId(resourceId)
        return ProviderProfile(
            profileId = "agent:$resourceId",
            resourceId = resourceId,
            providerId = providerId.ifBlank { productId },
            productId = productId,
            displayName = displayName,
            kind = ProviderProfileKind.AGENT,
            location = location,
            status = status,
            protocolFamily = "signalasi-agent-adapter",
            adapterType = adapterType.ifBlank { "$productId-native-adapter" },
            capabilities = capabilities,
            toolIds = toolIds,
            contextWindowTokens = 64_000,
            maxOutputTokens = 16_000,
            maxParallelRuns = maxParallelRuns.coerceAtLeast(1),
            supportsTools = capabilities.any {
                it in setOf(AgentCapability.TOOL_USE, AgentCapability.CODE, AgentCapability.TASK_EXECUTION)
            },
            supportsStreaming = true,
            supportsBackground = AgentCapability.TASK_EXECUTION in capabilities,
            latency = latency,
            quality = AgentResourceQuality.STRONG,
            trust = trust,
            failureDomain = failureDomain.ifBlank { "agent:$resourceId" },
            endpointConfigured = true,
            credentialConfigured = true,
            pricing = ProviderPricingProfile(cost),
            metadata = mapOf("native_product_identity" to productId)
        )
    }

    private fun providerIdForTarget(target: AgentCallableTarget): String {
        val identity = "${target.id} ${target.title}".lowercase(Locale.ROOT)
        return when {
            "openrouter" in identity -> "openrouter"
            "deepseek" in identity -> "deepseek"
            "qwen" in identity -> "qwen"
            "gemini" in identity -> "gemini"
            "claude" in identity || "anthropic" in identity -> "anthropic"
            "ollama" in identity -> "ollama"
            "lm studio" in identity || "lm-studio" in identity -> "lm-studio"
            "openai" in identity || target.id == "cloud-models" -> "openai"
            else -> normalizeProductId(target.id)
        }
    }

    private fun normalizeProductId(resourceId: String): String =
        resourceId.substringAfterLast(':').lowercase(Locale.ROOT).let { id ->
            when (id) {
                "claude-code" -> "claude"
                else -> id
            }
        }

    private fun definition(providerId: String): ModelProviderProfileDefinition =
        modelProviders.firstOrNull { it.providerId == providerId }
            ?: ModelProviderProfileDefinition(
                providerId.ifBlank { "custom" },
                providerId.ifBlank { "Custom" },
                "openai",
                AgentResourceLocation.CLOUD,
                AgentResourceCost.MEDIUM,
                AgentResourceLatency.NORMAL,
                AgentResourceQuality.STRONG,
                64_000,
                true,
                true
            )

    private fun isLocalEndpoint(endpoint: String): Boolean {
        val value = endpoint.lowercase(Locale.ROOT)
        return listOf("127.0.0.1", "localhost", "192.168.", "10.", "172.16.").any(value::contains)
    }

    private fun AgentEndpointStatus.toConnectorStatus(): AgentConnectorStatus = when (this) {
        AgentEndpointStatus.ONLINE,
        AgentEndpointStatus.IDLE,
        AgentEndpointStatus.BUSY -> AgentConnectorStatus.AVAILABLE
        AgentEndpointStatus.PERMISSION_REQUIRED,
        AgentEndpointStatus.UPDATING -> AgentConnectorStatus.NEEDS_SETUP
        else -> AgentConnectorStatus.DISCONNECTED
    }

    private fun connectorStatus(value: String): AgentConnectorStatus = when (value.lowercase(Locale.ROOT)) {
        "ready", "configured", "online", "available", "busy", "idle", "degraded" ->
            AgentConnectorStatus.AVAILABLE
        "needs_setup", "not_configured", "permission_required", "updating" ->
            AgentConnectorStatus.NEEDS_SETUP
        else -> AgentConnectorStatus.DISCONNECTED
    }

    private inline fun <reified T : Enum<T>> enumValue(value: String, fallback: T): T =
        enumValues<T>().firstOrNull { it.name.equals(value, ignoreCase = true) } ?: fallback

    private fun JSONArray?.strings(): Set<String> = buildSet {
        val source = this@strings ?: return@buildSet
        for (index in 0 until source.length()) {
            source.optString(index).takeIf(String::isNotBlank)?.let(::add)
        }
    }

    private fun <T : Enum<T>> JSONArray?.enumSet(values: Array<T>): Set<T> = buildSet {
        val source = this@enumSet ?: return@buildSet
        for (index in 0 until source.length()) {
            val raw = source.optString(index)
            values.firstOrNull { it.name.equals(raw, ignoreCase = true) }?.let(::add)
        }
    }

    private fun JSONObject.optionalLong(key: String): Long? =
        if (isNull(key) || !has(key)) null else optLong(key)
}
