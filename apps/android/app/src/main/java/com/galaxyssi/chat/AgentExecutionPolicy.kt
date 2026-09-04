package com.galaxyssi.chat

import java.util.Locale

enum class AgentExecutionTaskKind {
    CHAT,
    RESEARCH,
    ARTIFACT,
    BUILD,
    INSTALL,
    DEVICE
}

enum class AgentExecutionReasoningEffort {
    LOW,
    MEDIUM,
    HIGH
}

data class AgentExecutionProfile(
    val taskKind: AgentExecutionTaskKind,
    val reasoningEffort: AgentExecutionReasoningEffort,
    val noProgressTimeoutMillis: Long,
    val maxSameFailureAttempts: Int = 2,
    val requiresArtifact: Boolean = false,
    val targetPlatform: String = "",
    val verifyInstallation: Boolean = false,
    val taskIntent: AgentTaskIntent = AgentTaskIntent.CHAT,
    val taskIntentConfidence: Int = 100,
    val taskIntentSignals: List<String> = emptyList()
) {
    companion object {
        fun forGoal(goal: String, hasAttachments: Boolean = false): AgentExecutionProfile {
            val normalized = goal.lowercase(Locale.US).replace(Regex("\\s+"), " ").trim()
            val install = normalized.containsAny(INSTALL_TERMS)
            val build = normalized.containsAny(BUILD_TERMS)
            val artifactRequest = normalized.containsAny(ARTIFACT_TERMS)
            val research = normalized.containsAny(RESEARCH_TERMS)
            val device = normalized.containsAny(DEVICE_TERMS)
            val intent = AgentTaskIntentClassifier.classify(
                goal = normalized,
                hasAttachments = hasAttachments
            )
            val taskKind = when {
                install -> AgentExecutionTaskKind.INSTALL
                build -> AgentExecutionTaskKind.BUILD
                artifactRequest || hasAttachments -> AgentExecutionTaskKind.ARTIFACT
                research -> AgentExecutionTaskKind.RESEARCH
                device -> AgentExecutionTaskKind.DEVICE
                else -> AgentExecutionTaskKind.CHAT
            }
            val complex = taskKind in setOf(
                AgentExecutionTaskKind.RESEARCH,
                AgentExecutionTaskKind.ARTIFACT,
                AgentExecutionTaskKind.BUILD,
                AgentExecutionTaskKind.INSTALL
            )
            val timeoutMillis = when (taskKind) {
                AgentExecutionTaskKind.CHAT -> 180_000L
                AgentExecutionTaskKind.DEVICE -> 120_000L
                AgentExecutionTaskKind.RESEARCH -> 300_000L
                AgentExecutionTaskKind.ARTIFACT -> 360_000L
                AgentExecutionTaskKind.BUILD,
                AgentExecutionTaskKind.INSTALL -> 420_000L
            }
            return AgentExecutionProfile(
                taskKind = taskKind,
                reasoningEffort = if (complex) {
                    AgentExecutionReasoningEffort.MEDIUM
                } else {
                    AgentExecutionReasoningEffort.LOW
                },
                noProgressTimeoutMillis = timeoutMillis,
                requiresArtifact = artifactRequest || taskKind in setOf(
                    AgentExecutionTaskKind.BUILD,
                    AgentExecutionTaskKind.INSTALL
                ),
                targetPlatform = if (normalized.containsAny(ANDROID_TERMS)) "android" else "",
                verifyInstallation = taskKind == AgentExecutionTaskKind.INSTALL,
                taskIntent = intent.intent,
                taskIntentConfidence = intent.confidence,
                taskIntentSignals = intent.matchedSignals
            )
        }

        private val BUILD_TERMS = listOf(
            "build", "compile", "implement", "develop", "write a program", "create an app",
            "create a game", "fix bug", "run tests", "improve", "upgrade", "update", "refactor",
            "\u7f16\u8bd1", "\u6784\u5efa", "\u5f00\u53d1", "\u5b9e\u73b0",
            "\u5199\u4e00\u4e2a\u7a0b\u5e8f", "\u505a\u4e00\u4e2a\u6e38\u620f",
            "\u751f\u6210\u7a0b\u5e8f", "\u4fee\u590d bug", "\u8fd0\u884c\u6d4b\u8bd5",
            "\u6539\u8fdb", "\u5347\u7ea7", "\u66f4\u65b0", "\u91cd\u6784"
        )
        private val INSTALL_TERMS = listOf(
            "install", "install and open", "install apk", "deploy to phone", "launch the app",
            "\u5b89\u88c5", "\u5b89\u88c5\u5e76\u6253\u5f00", "\u5b89\u88c5 apk",
            "\u5b89\u88c5\u5230\u624b\u673a", "\u7f16\u8bd1\u5e76\u5b89\u88c5"
        )
        private val ARTIFACT_TERMS = listOf(
            "return the file", "send the file", "export", "generate image", "create file",
            "downloadable", "zip project", "apk",
            "\u53d1\u56de\u6587\u4ef6", "\u8fd4\u56de\u6587\u4ef6", "\u5bfc\u51fa",
            "\u751f\u6210\u56fe\u7247", "\u6253\u5305", "\u538b\u7f29\u5305"
        )
        private val RESEARCH_TERMS = listOf(
            "latest", "today", "news", "weather", "research", "search the web",
            "\u6700\u65b0", "\u4eca\u5929", "\u65b0\u95fb", "\u5929\u6c14",
            "\u8c03\u67e5", "\u641c\u7d22", "\u8054\u7f51"
        )
        private val DEVICE_TERMS = listOf(
            "battery", "flashlight", "camera", "alarm", "timer", "phone setting",
            "\u7535\u91cf", "\u624b\u7535\u7b52", "\u6444\u50cf\u5934", "\u62cd\u7167",
            "\u95f9\u949f", "\u8ba1\u65f6\u5668", "\u624b\u673a\u8bbe\u7f6e"
        )
        private val ANDROID_TERMS = listOf(
            "android", "apk", "mobile app", "phone game", "on the phone",
            "\u5b89\u5353", "\u624b\u673a app", "\u624b\u673a\u4e0a\u73a9",
            "\u624b\u673a\u6e38\u620f", "\u5b89\u88c5\u5230\u624b\u673a"
        )
    }
}

internal fun String.containsAny(terms: Iterable<String>): Boolean =
    terms.any(::contains)

internal fun AgentExecutionProfile.contract(): String = buildString {
    append("GalaxySSI execution contract: task=")
        .append(taskKind.name.lowercase(Locale.US))
        .append(", intent=")
        .append(taskIntent.name.lowercase(Locale.US))
        .append(", reasoning_effort=")
        .append(reasoningEffort.name.lowercase(Locale.US))
        .append(". Use Plan -> Act -> Observe -> Replan -> Verify -> Finalize. ")
    append("Checkpoint useful work before long or risky actions. ")
    append("Do not repeat an unchanged failing approach. ")
    if (requiresArtifact) {
        append("A single deliverable remains in its native format; package a directory or multi-file project as ZIP. ")
    }
    if (verifyInstallation) {
        append("Only report installation or launch after Android returns a verified execution receipt. ")
    }
    append("Do not report success without verification evidence.")
}
