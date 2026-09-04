package com.galaxyssi.chat

import java.util.Locale

enum class AgentTaskExecutionMode(val wireValue: String) {
    PLAN_ONLY("plan_only"),
    AUTO_COMPLETE("auto_complete");

    companion object {
        fun fromWireValue(value: String?): AgentTaskExecutionMode =
            entries.firstOrNull { it.wireValue == value?.trim()?.lowercase(Locale.ROOT) }
                ?: runCatching {
                    valueOf(value.orEmpty().trim().uppercase(Locale.ROOT))
                }.getOrDefault(AUTO_COMPLETE)
    }
}

data class AgentTaskExecutionModeResolution(
    val mode: AgentTaskExecutionMode,
    val explicitlyRequested: Boolean = false,
    val matchedSignal: String = ""
)

object AgentTaskExecutionModePolicy {
    private val planOnlySignals = listOf(
        "\u5148\u7ed9\u65b9\u6848",
        "\u5148\u7ed9\u6211\u65b9\u6848",
        "\u53ea\u7ed9\u65b9\u6848",
        "\u4ec5\u7ed9\u65b9\u6848",
        "\u4ec5\u63d0\u4f9b\u65b9\u6848",
        "\u53ea\u5236\u5b9a\u8ba1\u5212",
        "\u5148\u5236\u5b9a\u8ba1\u5212",
        "\u5148\u5217\u51fa\u8ba1\u5212",
        "\u6682\u4e0d\u6267\u884c",
        "\u5148\u4e0d\u8981\u6267\u884c",
        "\u4e0d\u8981\u5b9e\u9645\u6267\u884c",
        "\u4e0d\u8981\u6267\u884c\u4efb\u4f55\u64cd\u4f5c",
        "\u4e0d\u8981\u6267\u884c\u4efb\u4f55\u52a8\u4f5c",
        "plan only",
        "proposal only",
        "show me the plan first",
        "give me a plan first",
        "do not execute",
        "don't execute",
        "without executing",
        "without making changes"
    )
    private val autoCompleteSignals = listOf(
        "\u81ea\u52a8\u6267\u884c\u5230\u5b8c\u6210",
        "\u76f4\u63a5\u6267\u884c\u5230\u5b8c\u6210",
        "\u4e00\u76f4\u6267\u884c\u5230\u5b8c\u6210",
        "\u6267\u884c\u8fd9\u4e2a\u65b9\u6848",
        "\u6309\u8fd9\u4e2a\u65b9\u6848\u6267\u884c",
        "\u7ee7\u7eed\u6267\u884c\u5230\u5b8c\u6210",
        "go ahead and execute",
        "execute until complete",
        "carry this through to completion",
        "implement this plan",
        "proceed with the plan"
    )

    private val scopedEnglishExecutionTargets = Regex(
        "^(?:on|in|via|using|through|from)\\s+(?:the\\s+)?" +
            "(?:desktop|pc|computer|server|cloud|remote(?:\\s+machine)?)(?:\\b|$)"
    )

    fun resolve(
        request: String,
        configuredMode: AgentTaskExecutionMode = AgentTaskExecutionMode.AUTO_COMPLETE
    ): AgentTaskExecutionModeResolution {
        val normalized = request
            .lowercase(Locale.ROOT)
            .replace(Regex("\\s+"), " ")
            .trim()
        planOnlySignals.firstOrNull { signal ->
            normalized.contains(signal) && !isScopedExecutionRestriction(normalized, signal)
        }?.let { signal ->
            return AgentTaskExecutionModeResolution(
                mode = AgentTaskExecutionMode.PLAN_ONLY,
                explicitlyRequested = true,
                matchedSignal = signal
            )
        }
        autoCompleteSignals.firstOrNull(normalized::contains)?.let { signal ->
            return AgentTaskExecutionModeResolution(
                mode = AgentTaskExecutionMode.AUTO_COMPLETE,
                explicitlyRequested = true,
                matchedSignal = signal
            )
        }
        return AgentTaskExecutionModeResolution(configuredMode)
    }

    private fun isScopedExecutionRestriction(request: String, signal: String): Boolean {
        if (signal !in setOf("do not execute", "don't execute", "without executing")) return false
        var matchAt = request.indexOf(signal)
        while (matchAt >= 0) {
            val suffix = request.substring(matchAt + signal.length).trimStart()
            if (scopedEnglishExecutionTargets.containsMatchIn(suffix)) return true
            matchAt = request.indexOf(signal, matchAt + signal.length)
        }
        return false
    }
}
