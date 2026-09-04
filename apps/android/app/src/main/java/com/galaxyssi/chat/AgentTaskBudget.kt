package com.galaxyssi.chat

import android.app.ActivityManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Debug
import org.json.JSONObject

enum class AgentTaskBudgetProfile(val wireValue: String) {
    ADAPTIVE("adaptive"),
    FAST("fast"),
    ECONOMY("economy"),
    PRIVATE("private"),
    CUSTOM("custom");

    companion object {
        fun fromWireValue(value: String): AgentTaskBudgetProfile =
            entries.firstOrNull {
                it.wireValue.equals(value.trim(), ignoreCase = true) ||
                    it.name.equals(value.trim(), ignoreCase = true)
            } ?: ADAPTIVE
    }
}

enum class AgentTaskNetworkPolicy(val wireValue: String) {
    ANY("any"),
    UNMETERED_ONLY("unmetered_only"),
    TRUSTED_ONLY("trusted_only"),
    OFFLINE_ONLY("offline_only");

    companion object {
        fun fromWireValue(value: String): AgentTaskNetworkPolicy =
            entries.firstOrNull {
                it.wireValue.equals(value.trim(), ignoreCase = true) ||
                    it.name.equals(value.trim(), ignoreCase = true)
            } ?: ANY
    }
}

data class AgentTaskBudget(
    val profile: AgentTaskBudgetProfile = AgentTaskBudgetProfile.ADAPTIVE,
    val maxElapsedSeconds: Long = 0L,
    val maxCostMicros: Long = 0L,
    val maxInputTokens: Long = 0L,
    val maxOutputTokens: Long = 0L,
    val maxNetworkBytes: Long = 0L,
    val minimumBatteryPercent: Int = 0,
    val maxMemoryBytes: Long = 0L,
    val networkPolicy: AgentTaskNetworkPolicy = AgentTaskNetworkPolicy.ANY,
    val allowCloud: Boolean = true,
    val allowPaidProviders: Boolean = true
) {
    fun normalized(): AgentTaskBudget = copy(
        maxElapsedSeconds = maxElapsedSeconds.coerceIn(0L, MAX_ELAPSED_SECONDS),
        maxCostMicros = maxCostMicros.coerceIn(0L, MAX_COST_MICROS),
        maxInputTokens = maxInputTokens.coerceIn(0L, MAX_TOKENS),
        maxOutputTokens = maxOutputTokens.coerceIn(0L, MAX_TOKENS),
        maxNetworkBytes = maxNetworkBytes.coerceIn(0L, MAX_NETWORK_BYTES),
        minimumBatteryPercent = minimumBatteryPercent.coerceIn(0, 100),
        maxMemoryBytes = maxMemoryBytes.coerceIn(0L, MAX_MEMORY_BYTES)
    )

    companion object {
        const val MIB = 1_048_576L
        const val GIB = 1_073_741_824L
        const val MAX_ELAPSED_SECONDS = 7L * 24L * 60L * 60L
        const val MAX_COST_MICROS = 1_000_000_000L
        const val MAX_TOKENS = 10_000_000L
        const val MAX_NETWORK_BYTES = 10L * GIB
        const val MAX_MEMORY_BYTES = 16L * GIB

        fun forProfile(profile: AgentTaskBudgetProfile): AgentTaskBudget = when (profile) {
            AgentTaskBudgetProfile.ADAPTIVE -> AgentTaskBudget(profile = profile)
            AgentTaskBudgetProfile.FAST -> AgentTaskBudget(profile = profile)
            AgentTaskBudgetProfile.ECONOMY -> AgentTaskBudget(profile = profile)
            AgentTaskBudgetProfile.PRIVATE -> AgentTaskBudget(
                profile = profile,
                networkPolicy = AgentTaskNetworkPolicy.TRUSTED_ONLY,
                allowCloud = false,
                allowPaidProviders = false
            )
            AgentTaskBudgetProfile.CUSTOM -> AgentTaskBudget(
                profile = AgentTaskBudgetProfile.CUSTOM
            )
        }
    }
}

data class AgentTaskBudgetUsage(
    val elapsedMillis: Long = 0L,
    val inputTokens: Long = 0L,
    val outputTokens: Long = 0L,
    val costMicros: Long = 0L,
    val networkBytes: Long = 0L,
    val peakMemoryBytes: Long = 0L,
    val usageEstimated: Boolean = false
) {
    fun add(
        elapsedMillis: Long = 0L,
        inputTokens: Long = 0L,
        outputTokens: Long = 0L,
        costMicros: Long = 0L,
        networkBytes: Long = 0L,
        memoryBytes: Long = 0L,
        estimated: Boolean = false
    ): AgentTaskBudgetUsage = copy(
        elapsedMillis = saturatingAdd(this.elapsedMillis, elapsedMillis),
        inputTokens = saturatingAdd(this.inputTokens, inputTokens),
        outputTokens = saturatingAdd(this.outputTokens, outputTokens),
        costMicros = saturatingAdd(this.costMicros, costMicros),
        networkBytes = saturatingAdd(this.networkBytes, networkBytes),
        peakMemoryBytes = maxOf(peakMemoryBytes, memoryBytes.coerceAtLeast(0L)),
        usageEstimated = usageEstimated || estimated
    )

    private fun saturatingAdd(left: Long, right: Long): Long {
        val safe = right.coerceAtLeast(0L)
        return if (Long.MAX_VALUE - left.coerceAtLeast(0L) < safe) {
            Long.MAX_VALUE
        } else {
            left.coerceAtLeast(0L) + safe
        }
    }
}

data class AgentTaskBudgetEnvironment(
    val batteryPercent: Int = -1,
    val charging: Boolean = false,
    val networkAvailable: Boolean = false,
    val networkMetered: Boolean = false,
    val appMemoryBytes: Long = 0L,
    val availableMemoryBytes: Long = 0L
)

enum class AgentTaskBudgetLimit {
    TIME,
    COST,
    INPUT_TOKENS,
    OUTPUT_TOKENS,
    NETWORK,
    BATTERY,
    MEMORY,
    CLOUD,
    PAID_PROVIDER
}

data class AgentTaskBudgetDecision(
    val allowed: Boolean,
    val limit: AgentTaskBudgetLimit? = null,
    val reason: String = ""
)

object AgentTaskBudgetPolicy {
    fun evaluate(
        budget: AgentTaskBudget,
        usage: AgentTaskBudgetUsage,
        environment: AgentTaskBudgetEnvironment = AgentTaskBudgetEnvironment(),
        networkRequired: Boolean = false,
        trustedNetworkTarget: Boolean = false,
        cloudProvider: Boolean = false,
        paidProvider: Boolean = false
    ): AgentTaskBudgetDecision {
        val limits = budget.normalized()
        // Resource counters are telemetry. They must never reject or terminate a user task.
        // Actual memory, thermal and connectivity failures are handled by their runtime owners.
        if (cloudProvider && !limits.allowCloud) {
            return denied(AgentTaskBudgetLimit.CLOUD, "Cloud resources are disabled for this task")
        }
        if (paidProvider && !limits.allowPaidProviders) {
            return denied(AgentTaskBudgetLimit.PAID_PROVIDER, "Paid resources are disabled for this task")
        }
        if (networkRequired) {
            if (!environment.networkAvailable) {
                return denied(AgentTaskBudgetLimit.NETWORK, "Network is unavailable")
            }
            when (limits.networkPolicy) {
                AgentTaskNetworkPolicy.ANY -> Unit
                AgentTaskNetworkPolicy.UNMETERED_ONLY -> if (environment.networkMetered) {
                    return denied(AgentTaskBudgetLimit.NETWORK, "Task requires an unmetered network")
                }
                AgentTaskNetworkPolicy.TRUSTED_ONLY -> if (!trustedNetworkTarget) {
                    return denied(AgentTaskBudgetLimit.NETWORK, "Task allows trusted network targets only")
                }
                AgentTaskNetworkPolicy.OFFLINE_ONLY ->
                    return denied(AgentTaskBudgetLimit.NETWORK, "Task is limited to offline resources")
            }
        }
        return AgentTaskBudgetDecision(true)
    }

    fun estimateProviderCostMicros(
        profile: ProviderProfile?,
        inputTokens: Long,
        outputTokens: Long
    ): Long {
        val pricing = profile?.pricing ?: return 0L
        val inputRate = pricing.inputMicrosPerMillionTokens ?: 0L
        val outputRate = pricing.outputMicrosPerMillionTokens ?: 0L
        return saturatingAdd(
            multiplyPerMillion(inputTokens, inputRate),
            multiplyPerMillion(outputTokens, outputRate)
        )
    }

    private fun multiplyPerMillion(tokens: Long, rate: Long): Long {
        if (tokens <= 0L || rate <= 0L) return 0L
        val whole = tokens / 1_000_000L
        val remainder = tokens % 1_000_000L
        return saturatingAdd(
            saturatingMultiply(whole, rate),
            saturatingMultiply(remainder, rate) / 1_000_000L
        )
    }

    private fun saturatingMultiply(left: Long, right: Long): Long =
        if (left <= 0L || right <= 0L) 0L
        else if (left > Long.MAX_VALUE / right) Long.MAX_VALUE
        else left * right

    private fun saturatingAdd(left: Long, right: Long): Long =
        if (Long.MAX_VALUE - left.coerceAtLeast(0L) < right.coerceAtLeast(0L)) {
            Long.MAX_VALUE
        } else {
            left.coerceAtLeast(0L) + right.coerceAtLeast(0L)
        }

    private fun denied(limit: AgentTaskBudgetLimit, reason: String) =
        AgentTaskBudgetDecision(false, limit, reason)
}

object AgentTaskBudgetProbe {
    fun environment(context: Context): AgentTaskBudgetEnvironment {
        val appContext = context.applicationContext
        val battery = appContext.getSystemService(BatteryManager::class.java)
        val connectivity = appContext.getSystemService(ConnectivityManager::class.java)
        val activity = appContext.getSystemService(ActivityManager::class.java)
        val memory = ActivityManager.MemoryInfo()
        runCatching { activity?.getMemoryInfo(memory) }
        val capabilities = connectivity?.getNetworkCapabilities(connectivity.activeNetwork)
        return AgentTaskBudgetEnvironment(
            batteryPercent = battery?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1,
            charging = battery?.isCharging == true,
            networkAvailable = capabilities?.hasCapability(
                NetworkCapabilities.NET_CAPABILITY_INTERNET
            ) == true,
            networkMetered = connectivity?.isActiveNetworkMetered == true,
            appMemoryBytes = Debug.getPss().coerceAtLeast(0L) * 1_024L,
            availableMemoryBytes = memory.availMem.coerceAtLeast(0L)
        )
    }
}

object AgentTaskBudgetJsonCodec {
    fun encode(budget: AgentTaskBudget): JSONObject {
        val value = budget.normalized()
        return JSONObject()
            .put("version", 1)
            .put("profile", value.profile.wireValue)
            .put("max_elapsed_seconds", value.maxElapsedSeconds)
            .put("max_cost_micros", value.maxCostMicros)
            .put("max_input_tokens", value.maxInputTokens)
            .put("max_output_tokens", value.maxOutputTokens)
            .put("max_network_bytes", value.maxNetworkBytes)
            .put("minimum_battery_percent", value.minimumBatteryPercent)
            .put("max_memory_bytes", value.maxMemoryBytes)
            .put("network_policy", value.networkPolicy.wireValue)
            .put("allow_cloud", value.allowCloud)
            .put("allow_paid_providers", value.allowPaidProviders)
    }

    fun decode(value: JSONObject?): AgentTaskBudget {
        val source = value ?: return AgentTaskBudget.forProfile(AgentTaskBudgetProfile.ADAPTIVE)
        val profile = AgentTaskBudgetProfile.fromWireValue(source.optString("profile"))
        val fallback = AgentTaskBudget.forProfile(profile)
        return fallback.copy(
            maxElapsedSeconds = source.optLong("max_elapsed_seconds", fallback.maxElapsedSeconds),
            maxCostMicros = source.optLong("max_cost_micros", fallback.maxCostMicros),
            maxInputTokens = source.optLong("max_input_tokens", fallback.maxInputTokens),
            maxOutputTokens = source.optLong("max_output_tokens", fallback.maxOutputTokens),
            maxNetworkBytes = source.optLong("max_network_bytes", fallback.maxNetworkBytes),
            minimumBatteryPercent = source.optInt(
                "minimum_battery_percent",
                fallback.minimumBatteryPercent
            ),
            maxMemoryBytes = source.optLong("max_memory_bytes", fallback.maxMemoryBytes),
            networkPolicy = AgentTaskNetworkPolicy.fromWireValue(
                source.optString("network_policy", fallback.networkPolicy.wireValue)
            ),
            allowCloud = source.optBoolean("allow_cloud", fallback.allowCloud),
            allowPaidProviders = source.optBoolean(
                "allow_paid_providers",
                fallback.allowPaidProviders
            )
        ).normalized()
    }

    fun encodeUsage(usage: AgentTaskBudgetUsage): JSONObject = JSONObject()
        .put("elapsed_ms", usage.elapsedMillis)
        .put("input_tokens", usage.inputTokens)
        .put("output_tokens", usage.outputTokens)
        .put("cost_micros", usage.costMicros)
        .put("network_bytes", usage.networkBytes)
        .put("peak_memory_bytes", usage.peakMemoryBytes)
        .put("usage_estimated", usage.usageEstimated)

    fun decodeUsage(value: JSONObject?): AgentTaskBudgetUsage {
        val source = value ?: return AgentTaskBudgetUsage()
        return AgentTaskBudgetUsage(
            elapsedMillis = source.optLong("elapsed_ms").coerceAtLeast(0L),
            inputTokens = source.optLong("input_tokens").coerceAtLeast(0L),
            outputTokens = source.optLong("output_tokens").coerceAtLeast(0L),
            costMicros = source.optLong("cost_micros").coerceAtLeast(0L),
            networkBytes = source.optLong("network_bytes").coerceAtLeast(0L),
            peakMemoryBytes = source.optLong("peak_memory_bytes").coerceAtLeast(0L),
            usageEstimated = source.optBoolean("usage_estimated")
        )
    }
}

class AgentTaskBudgetStore(context: Context) {
    private val preferences = AgentEncryptedPreferences(
        context.applicationContext,
        "galaxyssi_agent_task_budget"
    )

    fun load(): AgentTaskBudget {
        val json = runCatching { JSONObject(preferences.readString(KEY_BUDGET, "{}")) }
            .getOrDefault(JSONObject())
        return if (json.length() == 0) {
            AgentTaskBudget.forProfile(AgentTaskBudgetProfile.ADAPTIVE)
        } else {
            AgentTaskBudgetJsonCodec.decode(json)
        }
    }

    fun save(budget: AgentTaskBudget) {
        preferences.writeString(KEY_BUDGET, AgentTaskBudgetJsonCodec.encode(budget).toString())
    }

    fun select(profile: AgentTaskBudgetProfile): AgentTaskBudget =
        AgentTaskBudget.forProfile(profile).also(::save)

    fun clear() = preferences.clear()

    companion object {
        private const val KEY_BUDGET = "task_budget"
    }
}
