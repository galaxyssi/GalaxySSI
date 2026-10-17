package com.galaxyssi.chat

import java.util.Locale
import java.net.URI

/** Only harmless framing is normalized; negation, conditions and extra steps remain significant. */
internal object AgentLocalCommandText {
    fun withoutPolitePrefix(value: String): String = value.trim().replaceFirst(POLITE_PREFIX, "").trim()

    fun matches(value: String, vararg commands: String): Boolean {
        val command = withoutPolitePrefix(value).trimEnd('.', '!', '\u3002', '\uff01').trim()
            .lowercase(Locale.ROOT)
        return commands.any { command == it }
    }

    fun httpUrl(value: String): String? {
        if (value.isBlank() || value.any(Char::isWhitespace)) return null
        if ("://" in value && !value.startsWith("http://", true) && !value.startsWith("https://", true)) return null
        val normalized = if (value.startsWith("http://", true) || value.startsWith("https://", true)) value else "https://$value"
        val uri = runCatching { URI(normalized) }.getOrNull() ?: return null
        return normalized.takeIf { uri.scheme.lowercase(Locale.ROOT) in setOf("http", "https") && !uri.host.isNullOrBlank() }
    }

    fun downloadUrl(goal: String): String? = DOWNLOAD.matchEntire(goal)?.groupValues?.get(1)
        ?.let(::httpUrl)?.takeIf { it.startsWith("https://", true) }

    fun dialNumber(goal: String): String? = DIAL.matchEntire(goal)?.groupValues?.get(1)?.takeIf { it.count(Char::isDigit) >= 3 }

    fun smsNumber(goal: String): String? = SMS_COMPOSER.matchEntire(goal)?.groupValues?.get(1)?.takeIf { it.count(Char::isDigit) >= 3 }

    fun sensorType(goal: String): String? {
        val name = SENSOR.matchEntire(goal)?.groupValues?.let { it[1].ifBlank { it[2] } }?.lowercase(Locale.ROOT) ?: return null
        return sensorTypes[name]
    }

    private const val NUMBER = "(\\+?\\d[\\d ()-]{1,30}\\d)"
    private val DIAL = Regex("(?:dial|call|\u62e8\u53f7|\u64a5\u865f|\u6253\u7535\u8bdd\u7ed9)\\s*$NUMBER", RegexOption.IGNORE_CASE)
    private val SMS_COMPOSER = Regex("(?:sms|message)\\s+$NUMBER", RegexOption.IGNORE_CASE)
    private val DOWNLOAD = Regex("(?:download|\u4e0b\u8f7d|\u4e0b\u8f09)\\s*(https://\\S+)", RegexOption.IGNORE_CASE)
    private val sensorTypes = mapOf("accelerometer" to "accelerometer", "gyroscope" to "gyroscope",
        "gravity" to "gravity", "light" to "light", "proximity" to "proximity", "pressure" to "pressure",
        "magnetic" to "magnetic_field", "compass" to "magnetic_field", "rotation" to "rotation_vector",
        "temperature" to "ambient_temperature", "humidity" to "relative_humidity",
        "\u52a0\u901f\u5ea6" to "accelerometer", "\u9640\u87ba\u4eea" to "gyroscope", "\u91cd\u529b" to "gravity",
        "\u5149\u7ebf" to "light", "\u5149\u7167" to "light", "\u8ddd\u79bb" to "proximity", "\u6c14\u538b" to "pressure",
        "\u78c1\u573a" to "magnetic_field", "\u6307\u5357\u9488" to "magnetic_field", "\u65cb\u8f6c" to "rotation_vector",
        "\u6e29\u5ea6" to "ambient_temperature", "\u6e7f\u5ea6" to "relative_humidity")
    private val SENSOR = Regex("(?:(?:read|sample) (?:sensor )?(${sensorTypes.keys.joinToString("|")})(?: sensor)?|" +
        "(?:\u8bfb\u53d6|\u91c7\u6837)(${sensorTypes.keys.joinToString("|")})(?:\u4f20\u611f\u5668)?(?:\u6570\u636e)?)", RegexOption.IGNORE_CASE)

    private val POLITE_PREFIX = Regex(
        "^(?:please\\s+|(?:\u8bf7|\u8acb)(?!\u6c42)(?:\u5e2e\u6211|\u5e6b\u6211)?\\s*)", RegexOption.IGNORE_CASE)
}

internal fun String.matchesCommand(vararg commands: String): Boolean = AgentLocalCommandText.matches(this, *commands)
