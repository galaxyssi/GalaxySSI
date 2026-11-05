package com.galaxyssi.chat

import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset

internal data class HealthOcrSampleTime(val millis: Long, val zone: String)
internal data class HealthOcrSourceContext(
    val owners: List<String> = emptyList(),
    val times: List<String> = emptyList(),
    val sample: HealthOcrSampleTime? = null,
) {
    companion object {
        private val owner = Regex(
            """^(?:patient(?:'s)?\s+name|(?:\u60a3\u8005|\u53d7\u68c0\u8005|\u75c5\u4eba)?\u59d3\u540d)\s*[:\uff1a]\s*(.+)$""",
            RegexOption.IGNORE_CASE,
        )
        private val collected = Regex(
            """^(?:(?:(?:sample|specimen)\s+)?collect(?:ed(?:\s+at)?|ion\s+(?:date(?:\s*/\s*time)?|time))|measured\s+at|measurement\s+(?:date\s*/\s*time|time)|(?:\u91c7\u6837|\u91c7\u96c6|\u6d4b\u91cf)(?:\u65f6\u95f4|\u65e5\u671f))\s*[:\uff1a]\s*(.+)$""",
            RegexOption.IGNORE_CASE,
        )
        private val timestamp = Regex(
            """^([0-9]{4})[-/.\u5e74]([0-9]{1,2})[-/.\u6708]([0-9]{1,2})\u65e5?[ Tt]+([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?\s*(Z|[+-][0-9]{2}:[0-9]{2})?$""",
        )

        fun inspect(page: HealthOcrPage, localZone: ZoneId): HealthOcrSourceContext {
            fun values(pattern: Regex) = page.lines.asSequence().flatMap { it.text.lineSequence() }
                .mapNotNull { pattern.matchEntire(it.trim())?.groupValues?.get(1)?.trim() }
                .filter { it.isNotBlank() && it.length <= 200 && it.none(Char::isISOControl) }
                .distinct().take(4).toList()
            val owners = values(owner)
            val times = values(collected)
            val sample = if (owners.size <= 1) times.singleOrNull()?.let { readTimestamp(it, localZone) } else null
            return HealthOcrSourceContext(owners, times, sample)
        }

        private fun readTimestamp(value: String, localZone: ZoneId): HealthOcrSampleTime? {
            val fields = timestamp.matchEntire(value)?.groupValues ?: return null
            return runCatching {
                val date = LocalDateTime.of(fields[1].toInt(), fields[2].toInt(), fields[3].toInt(),
                    fields[4].toInt(), fields[5].toInt(), fields[6].ifBlank { "0" }.toInt())
                val explicit = fields[7].takeIf(String::isNotEmpty)?.let(ZoneOffset::of)
                val offset = explicit ?: localZone.rules.getValidOffsets(date).singleOrNull() ?: return null
                val zone = when (explicit) { null -> localZone.id; ZoneOffset.UTC -> "UTC"; else -> "UTC" + explicit.id }
                HealthOcrSampleTime(date.toInstant(offset).toEpochMilli(), zone)
            }.getOrNull()
        }
    }
}
