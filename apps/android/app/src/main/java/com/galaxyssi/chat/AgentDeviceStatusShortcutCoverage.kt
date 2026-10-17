package com.galaxyssi.chat

import java.util.Locale

/** A status keyword cannot prove that a single read covers the user's whole request. */
internal object AgentDeviceStatusShortcutCoverage {
    fun hasExplicitDesktopTarget(goal: String): Boolean = EXPLICIT_DESKTOP.containsMatchIn(goal)

    fun requiresReasoning(goal: String): Boolean {
        val text = goal.trim().lowercase(Locale.ROOT)
            .trimEnd('.', '!', '?', '\u3002', '\uff01', '\uff1f').trim()
            .replace(SHORT_REPLY, "").trim()
        if (completeQueries.any { it.matches(text) }) return false
        if (subjects.none { it.containsMatchIn(text) }) return false
        if (READ_REQUEST.containsMatchIn(text)) return true
        val list = text.split(LIST_SEPARATOR).map(String::trim)
        return list.size > 1 && list.all { part -> completeQueries.any { it.matches(part) } }
    }

    private val aliases = listOf(
        "(?:phone )?battery(?: status| level| percentage)?|\u624b\u673a\u7535\u91cf|\u624b\u6a5f\u96fb\u91cf|\u7535\u6c60\u7535\u91cf|\u96fb\u6c60\u96fb\u91cf|\u7535\u91cf|\u96fb\u91cf",
        "power status|battery saver(?: status)?|power saving(?: status)?|\u7535\u6e90\u72b6\u6001|\u96fb\u6e90\u72c0\u614b|\u7701\u7535\u6a21\u5f0f(?:\u72b6\u6001)?|\u7701\u96fb\u6a21\u5f0f(?:\u72c0\u614b)?",
        "(?:(?:phone|device) )?(?:memory|ram)(?: status)?|\u8fd0\u884c\u5185\u5b58|\u904b\u884c\u5167\u5b58|\u5185\u5b58(?:\u5360\u7528|\u4f7f\u7528)?|\u5167\u5b58(?:\u4f54\u7528|\u4f7f\u7528)?",
        "(?:phone |internal )?storage(?: status| space)?|\u5b58\u50a8(?:\u72b6\u6001|\u7a7a\u95f4)?|\u5132\u5b58(?:\u72c0\u614b|\u7a7a\u9593)?|\u5269\u4f59\u7a7a\u95f4|\u5269\u9918\u7a7a\u9593",
        "(?:phone |active )?network(?: status)?|\u7f51\u7edc(?:\u8fde\u63a5)?\u72b6\u6001|\u7db2\u8def(?:\u9023\u63a5)?\u72c0\u614b|\u5f53\u524d\u7f51\u7edc|\u7576\u524d\u7db2\u8def",
        "bluetooth status|\u84dd\u7259\u72b6\u6001|\u85cd\u7259\u72c0\u614b",
        "nfc(?: status)?|nfc\u72b6\u6001|nfc\u72c0\u614b",
        "wi-?fi(?: status)?|wifi\u72b6\u6001|wifi\u72c0\u614b|\u65e0\u7ebf\u7f51\u7edc\u72b6\u6001|\u7121\u7dda\u7db2\u8def\u72c0\u614b",
        "(?:audio|volume) status|\u97f3\u91cf\u72b6\u6001|\u97f3\u91cf\u72c0\u614b|\u5f53\u524d\u97f3\u91cf|\u7576\u524d\u97f3\u91cf",
        "vpn(?: status)?|vpn\u72b6\u6001|vpn\u72c0\u614b"
    )
    private val subjects = aliases.map { Regex("(?<![a-z])(?:$it)(?![a-z])") }
    private val completeQueries = aliases.map { subject ->
        Regex("(?:" +
            "(?:please\\s+)?(?:(?:read|check|show|get)\\s+)?(?:(?:the|my)\\s+)?" +
            "(?:(?:current|available|remaining|free)\\s+)?(?:$subject)" +
            "(?:\\s+on\\s+(?:this|my|the)\\s+(?:phone|device))?" +
            "|(?:\u8bf7|\u8acb)?(?:\u5e2e\u6211|\u5e6b\u6211)?(?:\u8bfb\u53d6|\u8b80\u53d6|\u67e5\u770b|\u67e5\u8be2|\u67e5\u8a62|\u67e5\u4e00\u4e0b|\u67e5\u4e0b|\u67e5|\u83b7\u53d6|\u7372\u53d6)?" +
            "(?:\u8fd9\u53f0|\u8fd9\u90e8|\u9019\u53f0|\u9019\u90e8|\u6211\u7684)?(?:\u624b\u673a|\u624b\u6a5f|\u8bbe\u5907|\u8a2d\u5099)?\u7684?" +
            "(?:\u5f53\u524d|\u7576\u524d|\u73b0\u5728|\u73fe\u5728|\u8fd8\u6709\u591a\u5c11|\u9084\u6709\u591a\u5c11|\u5269\u4f59|\u5269\u9918|\u53ef\u7528)?" +
            "(?:$subject)(?:\u591a\u5c11|\u72b6\u6001|\u72c0\u614b)?" +
            ")")
    }
    private val READ_REQUEST = Regex("\\b(?:read|check|show|get|current|available|remaining|free|status|how much|if|when|unless)\\b|\u8bfb|\u8b80|\u67e5|\u5f53\u524d|\u7576\u524d|\u73b0\u5728|\u73fe\u5728|\u5269\u4f59|\u5269\u9918|\u53ef\u7528|\u591a\u5c11|\u72b6\u6001|\u72c0\u614b|\u5982\u679c")
    private val LIST_SEPARATOR = Regex("\\s+and\\s+|[,;\uff0c\uff1b\u3001]|\u4ee5\u53ca|\u548c|\u8207|\u4e0e")
    private val EXPLICIT_DESKTOP = Regex("\\b(?:computer|desktop|windows|macos)\\b|\u7535\u8111|\u96fb\u8166", RegexOption.IGNORE_CASE)
    private val SHORT_REPLY = Regex("(?:[,\uff0c]\\s*(?:\u8bf7|\u8acb)?(?:\u7b80\u77ed\u56de\u7b54|\u7b80\u77ed\u56de\u590d|\u7c21\u77ed\u56de\u7b54)|[,;]\\s*(?:please )?(?:reply briefly|answer briefly))$")
}
