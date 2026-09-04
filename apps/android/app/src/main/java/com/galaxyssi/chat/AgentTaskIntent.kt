package com.galaxyssi.chat

import java.util.Locale

enum class AgentTaskIntent {
    CHAT,
    CODE,
    PHONE_CONTROL,
    DESKTOP_CONTROL,
    RESEARCH,
    FILE,
    MEMORY,
    AUTOMATION
}

data class AgentTaskIntentClassification(
    val intent: AgentTaskIntent,
    val confidence: Int,
    val matchedSignals: List<String>
)

object AgentTaskIntentClassifier {
    fun classify(
        goal: String,
        hasAttachments: Boolean = false
    ): AgentTaskIntentClassification {
        val normalized = AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal)
            .lowercase(Locale.US)
            .replace(Regex("\\s+"), " ")
            .trim()
        val scores = mutableMapOf<AgentTaskIntent, Int>()
        val signals = mutableMapOf<AgentTaskIntent, MutableList<String>>()

        RULES.forEach { rule ->
            rule.terms.forEach { term ->
                if (normalized.contains(term)) {
                    scores[rule.intent] = scores.getOrDefault(rule.intent, 0) + rule.weight
                    signals.getOrPut(rule.intent, ::mutableListOf).add(term)
                }
            }
        }
        val automationDiscussion = AUTOMATION_DISCUSSION_PATTERN.containsMatchIn(normalized)
        val scheduledAction = AUTOMATION_FREQUENCY_PATTERN.containsMatchIn(normalized) &&
            AUTOMATION_ACTION_PATTERN.containsMatchIn(normalized)
        if (!automationDiscussion &&
            (scheduledAction || AUTOMATION_COMMAND_PATTERN.containsMatchIn(normalized))
        ) {
            scores[AgentTaskIntent.AUTOMATION] =
                scores.getOrDefault(AgentTaskIntent.AUTOMATION, 0) + 7
            signals.getOrPut(AgentTaskIntent.AUTOMATION, ::mutableListOf)
                .add(if (scheduledAction) "scheduled-action" else "automation-command")
        }
        if (PHONE_CONTROL_ACTION_PATTERN.containsMatchIn(normalized)) {
            scores[AgentTaskIntent.PHONE_CONTROL] =
                scores.getOrDefault(AgentTaskIntent.PHONE_CONTROL, 0) + 3
            signals.getOrPut(AgentTaskIntent.PHONE_CONTROL, ::mutableListOf)
                .add("phone-control-action")
        }
        if (FILE_PATH_PATTERN.containsMatchIn(normalized) &&
            FILE_OPERATION_PATTERN.containsMatchIn(normalized)
        ) {
            scores[AgentTaskIntent.FILE] = scores.getOrDefault(AgentTaskIntent.FILE, 0) + 6
            signals.getOrPut(AgentTaskIntent.FILE, ::mutableListOf).add("file-path-operation")
        }
        if (hasAttachments) {
            scores[AgentTaskIntent.FILE] = scores.getOrDefault(AgentTaskIntent.FILE, 0) + 3
            signals.getOrPut(AgentTaskIntent.FILE, ::mutableListOf).add("attachment")
        }
        if (scores.isEmpty()) {
            return AgentTaskIntentClassification(
                intent = AgentTaskIntent.CHAT,
                confidence = 100,
                matchedSignals = emptyList()
            )
        }

        val ranked = scores.entries.sortedWith(
            compareByDescending<Map.Entry<AgentTaskIntent, Int>> { it.value }
                .thenBy { INTENT_PRIORITY.indexOf(it.key) }
        )
        val winner = ranked.first()
        val runnerUpScore = ranked.getOrNull(1)?.value ?: 0
        val margin = winner.value - runnerUpScore
        val confidence = (55 + winner.value * 4 + margin * 5).coerceIn(55, 98)
        return AgentTaskIntentClassification(
            intent = winner.key,
            confidence = confidence,
            matchedSignals = signals[winner.key].orEmpty().distinct().take(6)
        )
    }

    private data class Rule(
        val intent: AgentTaskIntent,
        val weight: Int,
        val terms: List<String>
    )

    private val INTENT_PRIORITY = listOf(
        AgentTaskIntent.AUTOMATION,
        AgentTaskIntent.MEMORY,
        AgentTaskIntent.DESKTOP_CONTROL,
        AgentTaskIntent.PHONE_CONTROL,
        AgentTaskIntent.CODE,
        AgentTaskIntent.FILE,
        AgentTaskIntent.RESEARCH,
        AgentTaskIntent.CHAT
    )

    private val RULES = listOf(
        Rule(
            AgentTaskIntent.CODE,
            3,
            listOf(
                "build", "compile", "implement", "develop", "code", "program",
                "fix bug", "repository", "pull request", "unit test", "apk",
                "\u7f16\u8bd1", "\u6784\u5efa", "\u5f00\u53d1", "\u5b9e\u73b0",
                "\u4ee3\u7801", "\u7a0b\u5e8f", "\u4fee\u590d bug", "\u9879\u76ee",
                "\u4ed3\u5e93", "\u5355\u5143\u6d4b\u8bd5"
            )
        ),
        Rule(
            AgentTaskIntent.PHONE_CONTROL,
            3,
            listOf(
                "phone setting", "open phone app", "launch the app on my phone",
                "battery", "flashlight", "camera", "take a photo", "sms",
                "text message", "make a call", "timer", "alarm", "volume",
                "\u64cd\u4f5c\u624b\u673a", "\u63a7\u5236\u624b\u673a", "\u624b\u673a\u8bbe\u7f6e",
                "\u5728\u8fd9\u90e8\u624b\u673a\u4e0a\u6253\u5f00", "\u5728\u624b\u673a\u4e0a\u6253\u5f00",
                "\u6253\u5f00\u624b\u673a app",
                "\u7535\u91cf", "\u624b\u7535\u7b52", "\u6444\u50cf\u5934",
                "\u62cd\u7167", "\u77ed\u4fe1", "\u6253\u7535\u8bdd",
                "\u8ba1\u65f6\u5668", "\u95f9\u949f", "\u97f3\u91cf"
            )
        ),
        Rule(
            AgentTaskIntent.DESKTOP_CONTROL,
            3,
            listOf(
                "on my computer", "on the computer", "desktop control",
                "remote desktop", "windows desktop", "open on desktop",
                "on desktop", "on my desktop",
                "computer screen", "mouse click", "keyboard shortcut",
                "\u7535\u8111", "\u8fdc\u7a0b\u684c\u9762", "\u63a7\u5236\u7535\u8111",
                "\u7535\u8111\u5c4f\u5e55", "\u9f20\u6807", "\u952e\u76d8\u5feb\u6377\u952e"
            )
        ),
        Rule(
            AgentTaskIntent.RESEARCH,
            2,
            listOf(
                "research", "search the web", "look up", "latest", "today's news",
                "current news", "weather", "find sources", "compare sources",
                "\u8c03\u67e5", "\u641c\u7d22", "\u67e5\u8d44\u6599", "\u6700\u65b0",
                "\u4eca\u5929\u7684\u65b0\u95fb", "\u65b0\u95fb", "\u5929\u6c14",
                "\u67e5\u627e\u6765\u6e90"
            )
        ),
        Rule(
            AgentTaskIntent.FILE,
            2,
            listOf(
                "file", "pdf", "spreadsheet", "xlsx", "csv", "docx", "image",
                "screenshot", "audio", "video", "archive", "zip", "extract text",
                "convert this", "summarize this document",
                "\u6587\u4ef6", "\u8868\u683c", "\u56fe\u7247", "\u622a\u56fe",
                "\u97f3\u9891", "\u89c6\u9891", "\u538b\u7f29\u5305",
                "\u63d0\u53d6\u6587\u5b57", "\u8f6c\u6362\u8fd9\u4e2a",
                "\u603b\u7ed3\u8fd9\u4efd\u6587\u6863"
            )
        ),
        Rule(
            AgentTaskIntent.MEMORY,
            4,
            listOf(
                "remember that", "remember my", "forget that", "my preference",
                "memory", "knowledge base", "what did i say", "what do you know about me",
                "\u8bb0\u4f4f", "\u5fd8\u8bb0", "\u6211\u7684\u504f\u597d",
                "\u8bb0\u5fc6", "\u77e5\u8bc6\u5e93", "\u6211\u4e4b\u524d\u8bf4",
                "\u4f60\u8bb0\u5f97"
            )
        )
    )

    private val AUTOMATION_COMMAND_PATTERN = Regex(
        "(?:\\b(?:automate|remind me|monitor continuously)\\b|" +
            "\\b(?:create|set up|configure|add|enable)\\b.{0,48}" +
            "\\b(?:automation|workflow|trigger|reminder|cron|recurring|scheduled (?:job|task))\\b|" +
            "\\bwhen this happens\\b.{0,80}" +
            "\\b(?:run|execute|send|open|start|stop|backup|sync|notify)\\b|" +
            "(?:\u6301\u7eed\u76d1\u63a7|\u63d0\u9192\u6211)|" +
            "(?:\u521b\u5efa|\u8bbe\u7f6e|\u914d\u7f6e|\u6dfb\u52a0|\u5f00\u542f|\u5b89\u6392).{0,24}" +
            "(?:\u5de5\u4f5c\u6d41|\u89e6\u53d1\u5668|\u63d0\u9192|\u5b9a\u65f6\u4efb\u52a1|\u81ea\u52a8\u5316)|" +
            "\u5b9a\u65f6.{0,24}(?:\u8fd0\u884c|\u6267\u884c|\u68c0\u67e5|\u76d1\u63a7|\u53d1\u9001|\u5907\u4efd|\u540c\u6b65|\u63d0\u9192))",
        RegexOption.IGNORE_CASE
    )

    private val AUTOMATION_FREQUENCY_PATTERN = Regex(
        "(?:\\bevery\\s+(?:minute|hour|day|week|month|morning|evening)s?\\b|" +
            "\\b(?:hourly|daily|weekly|monthly)\\b|" +
            "(?:\u6bcf\u5206\u949f|\u6bcf\u5c0f\u65f6|\u6bcf\u5929|\u6bcf\u65e5|\u6bcf\u5468|\u6bcf\u6708|\u6bcf\u665a|\u6bcf\u65e9))",
        RegexOption.IGNORE_CASE
    )
    private val AUTOMATION_ACTION_PATTERN = Regex(
        "(?:\\b(?:run|execute|check|monitor|send|open|start|stop|backup|sync|fetch|publish)\\b|" +
            "\\bturn\\s+(?:on|off)\\b|" +
            "(?:\u8fd0\u884c|(?<!\u53ef)\u6267\u884c|\u68c0\u67e5|\u76d1\u63a7|\u53d1\u9001|\u6253\u5f00|\u5f00\u542f|\u5173\u95ed|" +
            "\u5907\u4efd|\u540c\u6b65|\u542f\u52a8|\u505c\u6b62|\u63d0\u9192|\u63a8\u9001|\u62c9\u53d6|\u53d1\u5e03))",
        RegexOption.IGNORE_CASE
    )
    private val AUTOMATION_DISCUSSION_PATTERN = Regex(
        "(?:[?\uff1f]|\\b(?:why|how|whether|compare|difference|does|do|is|are|explain|describe)\\b|" +
            "(?:\u662f\u5426|\u4e3a\u4ec0\u4e48|\u4e3a\u4f55|\u600e\u4e48|\u5982\u4f55|\u6bd4\u8f83|\u533a\u522b|\u89e3\u91ca|\u8bf4\u660e))",
        RegexOption.IGNORE_CASE
    )

    private val PHONE_CONTROL_ACTION_PATTERN = Regex(
        "(?:\\b(?:turn on|turn off|turn up|turn down|open|launch|start|stop|set|adjust|change|take|send|call|dial|" +
            "read|check|get|show|report)\\b.{0,48}\\b(?:phone|battery|flashlight|camera|sms|" +
            "message|call|timer|alarm|volume)s?\\b|" +
            "\\b(?:what(?:'s| is)|how much)\\b.{0,32}\\b(?:battery|volume|phone status)\\b|" +
            "(?:\u64cd\u4f5c\u624b\u673a|\u63a7\u5236\u624b\u673a)|" +
            "(?:\u6253\u5f00|\u5173\u95ed|\u542f\u52a8|\u505c\u6b62|\u8bbe\u7f6e|\u8c03\u6574|" +
            "\u8c03\u9ad8|\u8c03\u4f4e|\u4fee\u6539|\u62cd\u6444|\u62cd\u7167|\u53d1\u9001|" +
            "\u62e8\u6253|\u67e5\u770b|\u68c0\u67e5|\u83b7\u53d6|\u8bfb\u53d6|\u67e5\u8be2).{0,24}" +
            "(?:\u624b\u673a|\u7535\u91cf|\u624b\u7535\u7b52|\u76f8\u673a|\u6444\u50cf\u5934|" +
            "\u77ed\u4fe1|\u7535\u8bdd|\u8ba1\u65f6\u5668|\u95f9\u949f|\u97f3\u91cf)|" +
            "(?:\u624b\u673a|\u7535\u91cf|\u624b\u7535\u7b52|\u76f8\u673a|\u6444\u50cf\u5934|" +
            "\u77ed\u4fe1|\u7535\u8bdd|\u8ba1\u65f6\u5668|\u95f9\u949f|\u97f3\u91cf|\u8bbe\u7f6e).{0,24}" +
            "(?:\u6253\u5f00|\u5173\u95ed|\u542f\u52a8|\u505c\u6b62|\u8bbe\u7f6e|\u8c03\u6574|" +
            "\u67e5\u770b|\u68c0\u67e5|\u83b7\u53d6|\u8bfb\u53d6|\u67e5\u8be2|\u662f\u591a\u5c11|\u591a\u5c11|\u72b6\u6001))",
        RegexOption.IGNORE_CASE
    )

    private val FILE_PATH_PATTERN = Regex(
        "(?:^|\\s)(?:[a-z0-9._-]+[/\\\\])+[a-z0-9._-]+(?:\\.[a-z0-9]{1,12})?(?=\\s|$|[,.;:])",
        RegexOption.IGNORE_CASE
    )
    private val FILE_OPERATION_PATTERN = Regex(
        "\\b(?:create|write|read|edit|modify|delete|rename|move|copy|verify|archive|zip|unzip|extract)\\b|" +
            "(?:\u521b\u5efa|\u5199\u5165|\u8bfb\u53d6|\u7f16\u8f91|\u4fee\u6539|\u5220\u9664|\u91cd\u547d\u540d|\u79fb\u52a8|\u590d\u5236|\u9a8c\u8bc1|\u538b\u7f29|\u89e3\u538b|\u89e3\u538b\u7f29)",
        RegexOption.IGNORE_CASE
    )
}
