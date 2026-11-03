package com.galaxyssi.chat

import java.time.ZoneId

internal enum class ConversationScheduleOperation { SAVE, PAUSE, RESUME, LIST }

internal data class ConversationScheduleCommand(
    val operation: ConversationScheduleOperation,
    val prompt: String = "",
    val trigger: AgentProactiveTrigger? = null,
    val scheduleText: String = "",
    val createNew: Boolean = false
)

/** Recognizes explicit schedule commands only; ordinary quoted/discussed schedules stay in chat. */
internal object ConversationScheduleParser {
    private val interval = Regex("^(?:每隔|每|every\\s+)\\s*([0-9一二两三四五六七八九十百]+)?\\s*(分钟|分鐘|小时|小時|天|minutes?|mins?|hours?|days?)\\s*(?:一次|执行一次|執行一次)?", RegexOption.IGNORE_CASE)
    private val clock = Regex("^(?:(每天|每日|工作日|每个工作日|每週[一二三四五六日天]|每周[一二三四五六日天])\\s*)(?:(早上|上午|下午|晚上|中午)\\s*)?([0-9一二三四五六七八九十]+)(?::([0-9]{1,2})|[点點时時](?:([0-9一二三四五六七八九十]+)分?|(半))?)")
    private val dailyEnglish = Regex("^daily\\s+(?:at\\s+)?([0-9]{1,2}):([0-9]{2})", RegexOption.IGNORE_CASE)
    private val controls = mapOf(
        "停止" to ConversationScheduleOperation.PAUSE, "暂停" to ConversationScheduleOperation.PAUSE,
        "暫停" to ConversationScheduleOperation.PAUSE, "停止定时任务" to ConversationScheduleOperation.PAUSE,
        "暂停定时任务" to ConversationScheduleOperation.PAUSE, "stop" to ConversationScheduleOperation.PAUSE,
        "pause" to ConversationScheduleOperation.PAUSE, "stop scheduled task" to ConversationScheduleOperation.PAUSE,
        "继续定时任务" to ConversationScheduleOperation.RESUME, "恢复定时任务" to ConversationScheduleOperation.RESUME,
        "resume scheduled task" to ConversationScheduleOperation.RESUME,
        "定时任务" to ConversationScheduleOperation.LIST, "定時任務" to ConversationScheduleOperation.LIST,
        "查看定时任务" to ConversationScheduleOperation.LIST, "scheduled tasks" to ConversationScheduleOperation.LIST
    )

    fun parse(input: String, zone: String = ZoneId.systemDefault().id): ConversationScheduleCommand? {
        if (input.trimEnd().endsWith('?') || input.trimEnd().endsWith('？')) return null
        var text = input.trim().trimEnd('。', '.', '！', '!')
        controls[text.lowercase()]?.let { return ConversationScheduleCommand(it) }
        val createNew = Regex("^(新增|新建|另外|add\\s+|new\\s+)", RegexOption.IGNORE_CASE).find(text)
        if (createNew != null) text = text.substring(createNew.range.last + 1).trim()
        val edit = Regex("^(?:改成|改为|改為|更新为|更新為|change to\\s+)", RegexOption.IGNORE_CASE).containsMatchIn(text)
        text = text.replaceFirst(Regex("^(?:请|請|帮我|幫我|改成|改为|改為|更新为|更新為|please\\s+|change to\\s+)", RegexOption.IGNORE_CASE), "").trim()
        parseTime(text, zone)?.let { (trigger, length) ->
            val prompt = text.substring(length).trimStart(' ', '，', ',', '：', ':')
                .replaceFirst(Regex("^(?:帮我|幫我)"), "").trim()
            if (prompt.isNotBlank()) return ConversationScheduleCommand(ConversationScheduleOperation.SAVE,
                prompt, trigger, text.substring(0, length).trim(), createNew != null)
        }
        if (edit && text.isNotBlank() && !Regex("^(每|工作日|every|daily)", RegexOption.IGNORE_CASE).containsMatchIn(text))
            return ConversationScheduleCommand(ConversationScheduleOperation.SAVE, text)
        return null
    }

    fun parseTime(input: String, zone: String = ZoneId.systemDefault().id): Pair<AgentProactiveTrigger, Int>? {
        val text = input.trim()
        val time = clock.find(text)
        if (time != null) {
            var hour = number(time.groupValues[3]) ?: return null
            val minute = if (time.groupValues[6].isNotBlank()) 30 else
                number(time.groupValues[4].ifBlank { time.groupValues[5] }.ifBlank { "0" }) ?: return null
            if (time.groupValues[2] in setOf("下午", "晚上", "中午") && hour in 1..11) hour += 12
            if (hour !in 0..23 || minute !in 0..59) return null
            val day = when (val prefix = time.groupValues[1]) {
                "工作日", "每个工作日" -> "1-5"
                "每天", "每日" -> "*"
                else -> when (prefix.last()) { '日', '天' -> "0"; else -> number(prefix.takeLast(1))?.toString() ?: return null }
            }
            return AgentProactiveTrigger(AgentProactiveTriggerKind.CRON, "$minute $hour * * $day", zone) to time.value.length
        }
        dailyEnglish.find(text)?.let { match ->
            val hour = match.groupValues[1].toInt()
            val minute = match.groupValues[2].toInt()
            if (hour !in 0..23 || minute !in 0..59) return null
            return AgentProactiveTrigger(AgentProactiveTriggerKind.CRON, "$minute $hour * * *", zone) to match.value.length
        }
        interval.find(text)?.let { match ->
            val count = number(match.groupValues[1].ifBlank { "1" })?.toLong() ?: return null
            val multiplier = when (match.groupValues[2].lowercase()) {
                "分钟", "分鐘", "minute", "minutes", "min", "mins" -> 60L
                "小时", "小時", "hour", "hours" -> 3600L
                else -> 86400L
            }
            val seconds = count * multiplier
            if (seconds !in AgentProactiveTrigger.MIN_INTERVAL_SECONDS..AgentProactiveTrigger.MAX_INTERVAL_SECONDS) return null
            return AgentProactiveTrigger(AgentProactiveTriggerKind.INTERVAL, timeZone = zone, intervalSeconds = seconds) to match.value.length
        }
        return null
    }

    private fun number(text: String): Int? {
        text.toIntOrNull()?.let { return it }
        val digits = mapOf('一' to 1, '二' to 2, '两' to 2, '三' to 3, '四' to 4,
            '五' to 5, '六' to 6, '七' to 7, '八' to 8, '九' to 9)
        if (text.length == 1) return if (text == "十") 10 else digits[text[0]]
        if ('十' in text) {
            val parts = text.split('十')
            if (parts.size == 2) return (if (parts[0].isEmpty()) 1 else digits[parts[0].singleOrNull()] ?: return null) * 10 +
                (if (parts[1].isEmpty()) 0 else digits[parts[1].singleOrNull()] ?: return null)
        }
        return null
    }
}
