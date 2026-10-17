package com.galaxyssi.chat

/** Exact shortcuts are optional; partial understanding must go to the selected reasoning provider. */
internal object AgentDeviceIntent {
    private val duration = Regex("(\\d+(?:\\.\\d+)?|[\u96f6〇\u4e00\u4e8c\u4e24\u4e09\u56db\u4e94\u516d\u4e03\u516b\u4e5d\u5341\u767e\u5343]+|\u534a|one|two|three|four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty|forty-five|forty|fifty|sixty)\\s*(\u5c0f\u65f6|\u5c0f\u6642|\u5206\u949f|\u5206\u9418|\u79d2\u949f|\u79d2\u9418|\u5206|\u79d2|hours?|hrs?|minutes?|mins?|seconds?|secs?|h\\b|m\\b|s\\b)(\u534a)?", RegexOption.IGNORE_CASE)
    private val englishNumbers = mapOf("one" to 1, "two" to 2, "three" to 3, "four" to 4,
        "five" to 5, "six" to 6, "seven" to 7, "eight" to 8, "nine" to 9, "ten" to 10,
        "fifteen" to 15, "twenty" to 20, "thirty" to 30, "forty" to 40, "forty-five" to 45,
        "fifty" to 50, "sixty" to 60)
    private val timer = Regex("\u5012[\u8ba1\u8a08]\u65f6|\u5012\u8a08\u6642|[\u8ba1\u8a08][\u65f6\u6642]\u5668|\\btimers?\\b|\\bcountdown\\b", RegexOption.IGNORE_CASE)
    private val recurring = Regex("\u6bcf|\u5b9a\u65f6\u4efb\u52a1|\u5b9a\u6642\u4efb\u52d9|\\bevery\\b|\\brepeat|\\bschedule", RegexOption.IGNORE_CASE)
    private val mutation = Regex("^(\u8bf7|\u8acb|\u5e2e\u6211|\u5e6b\u6211|\u7ed9\u6211|\u7d66\u6211|\u9ebb\u70e6|\u73b0\u5728|\u73fe\u5728|please\\s+)*(\u8bbe\u7f6e|\u8a2d\u7f6e|\u8bbe\u5b9a|\u8a2d\u5b9a|\u8bbe|\u958b\u59cb|\u5f00\u59cb|\u542f\u52a8|\u555f\u52d5|\u5f00|set\\b|start\\b)", RegexOption.IGNORE_CASE)

    fun seconds(text: String): Int? {
        val matches = duration.findAll(text.lowercase()).toList()
        if (matches.isEmpty()) return null
        // A duration is one contiguous expression; do not add unrelated times in a sentence.
        if (matches.zipWithNext().any { (a, b) ->
            text.substring(a.range.last + 1, b.range.first).trim().let { it !in setOf("", "\u548c", "\u53c8", "and") }
        }) return null
        var total = 0.0
        for (match in matches) {
            val number = number(match.groupValues[1]) ?: return null
            val unit = match.groupValues[2].lowercase()
            val multiplier = when {
                unit.startsWith("\u5c0f") || unit.startsWith("h") -> 3600
                unit.startsWith("\u5206") || unit.startsWith("m") -> 60
                else -> 1
            }
            total += (number + if (match.groupValues[3].isNotEmpty()) 0.5 else 0.0) * multiplier
        }
        // Never silently clamp a requested duration to a different one.
        return total.takeIf { it.isFinite() && it >= 1 && it <= Int.MAX_VALUE && it % 1.0 == 0.0 }?.toInt()
    }

    private fun number(value: String): Double? {
        value.toDoubleOrNull()?.let { return it }
        englishNumbers[value]?.let { return it.toDouble() }
        if (value == "\u534a") return 0.5
        var total = 0
        var digit = 0
        var previousUnit = 10_000
        for (c in value) {
            val d = "\u96f6\u4e00\u4e8c\u4e09\u56db\u4e94\u516d\u4e03\u516b\u4e5d".indexOf(if (c == '\u4e24') '\u4e8c' else if (c == '〇') '\u96f6' else c)
            if (d >= 0) { if (digit != 0) return null; digit = d; continue }
            val unit = when (c) { '\u5341' -> 10; '\u767e' -> 100; '\u5343' -> 1000; else -> return null }
            if (unit >= previousUnit) return null
            total += (if (digit == 0 && unit == 10) 1 else digit) * unit
            digit = 0; previousUnit = unit
        }
        return (total + digit).toDouble()
    }

    fun isTimerRequest(text: String): Boolean = !recurring.containsMatchIn(text) &&
        (timer.containsMatchIn(text) || mutation.containsMatchIn(text) &&
            Regex("[\u8ba1\u8a08][\u65f6\u6642]|\u5206\u949f|\u5206\u9418|seconds?|minutes?", RegexOption.IGNORE_CASE).containsMatchIn(text))

    fun exactTimerSeconds(text: String): Int? {
        if (!isTimerRequest(text) || !timer.containsMatchIn(text)) return null
        val rest = duration.replace(timer.replace(text.trim().lowercase(), ""), "")
            .replace(Regex("^(\u8bf7|\u8acb|\u5e2e\u6211|\u5e6b\u6211|\u7ed9\u6211|\u7d66\u6211|please\\s+)*"), "")
            .replace(Regex("^(\u8bbe\u7f6e|\u8a2d\u7f6e|\u8bbe\u5b9a|\u8a2d\u5b9a|\u5f00\u59cb|\u958b\u59cb|\u542f\u52a8|\u555f\u52d5|set|start)\\s*"), "")
            .replace(Regex("[\\s\u7684。.!！]"), "")
        return seconds(text).takeIf { rest.isEmpty() }
    }

    fun explicitlyOpenTimer(text: String): Boolean = Regex(
        "^(\u8bf7)?(\u6253\u5f00|\u67e5\u770b|\u986f\u793a|\u663e\u793a)(\u8ba1\u65f6\u5668|\u8a08\u6642\u5668|\u5012\u8ba1\u65f6)(\u9875\u9762|\u9801\u9762)?[。！!]?$").matches(text.trim()) ||
        Regex("^(open|show) timers?[.!]?$", RegexOption.IGNORE_CASE).matches(text.trim())

    fun needsOperationContext(text: String): Boolean = !recurring.containsMatchIn(text) &&
        (isTimerRequest(text) || followup(text) != null || Regex(
            "^(\u8bf7|\u8acb|\u5e2e\u6211|\u5e6b\u6211|\u90a3|\u73b0\u5728|\u73fe\u5728)*(\u5f00\u59cb|\u958b\u59cb|\u7ee7\u7eed|\u7e7c\u7e8c|\u6682\u505c|\u66ab\u505c|\u505c\u6b62|\u53d6\u6d88|\u6539\u6210|\u6539\u4e3a|\u6539\u70ba)").containsMatchIn(text.trim()))

    fun requiresReasoning(text: String): Boolean = isTimerRequest(text) &&
        !explicitlyOpenTimer(text) && (mutation.containsMatchIn(text) || exactTimerSeconds(text) != null)

    fun followup(text: String): String? = when (text.trim().lowercase().trimEnd('。', '！', '!', '.')) {
        "\u5f00\u59cb", "\u958b\u59cb", "\u5f00\u59cb\u8ba1\u65f6", "\u958b\u59cb\u8a08\u6642", "start" -> "start"
        "\u6682\u505c", "\u66ab\u505c", "pause" -> "pause"
        "\u7ee7\u7eed", "\u7e7c\u7e8c", "\u6062\u590d", "\u6062\u5fa9", "resume", "continue" -> "resume"
        "\u53d6\u6d88", "\u505c\u6b62", "cancel", "stop" -> "cancel"
        "\u67e5\u770b", "\u8fd8\u6709\u591a\u4e45", "\u9084\u6709\u591a\u4e45", "status" -> "inspect"
        else -> if (exactReplacement(text)) "replace" else null
    }

    private fun exactReplacement(text: String): Boolean {
        val command = Regex("^(\u6539\u6210|\u6539\u4e3a|\u6539\u70ba|\u6362\u6210|\u63db\u6210|change to |make it )", RegexOption.IGNORE_CASE)
        if (!command.containsMatchIn(text.trim()) || seconds(text) == null || recurring.containsMatchIn(text)) return false
        val remainder = duration.replace(timer.replace(command.replaceFirst(text.trim(), ""), ""), "")
            .replace(Regex("[\\s\u7684。.!！]"), "")
        return remainder.isEmpty()
    }

    fun action(seconds: Int?, operation: String = "start", operationId: String = ""): AgentAction = AgentAction(
        id = "timer-$operation", kind = AgentActionKind.SET_ALARM, target = "Android Timer",
        risk = AgentRisk.MEDIUM, status = AgentActionStatus.PENDING_CONFIRMATION,
        description = "Control and verify the requested phone timer",
        parameters = buildMap {
            put("timer_operation", operation)
            seconds?.let { put("timer_seconds", it.toString()) }
            if (operationId.isNotEmpty()) put("operation_id", operationId)
        }, requiresConfirmation = false)
}
