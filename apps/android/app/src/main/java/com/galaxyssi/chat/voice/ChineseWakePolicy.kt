package com.galaxyssi.chat.voice

import java.util.Locale

internal enum class LocalWakeAvailability {
    UNCHECKED, CHECKING, NEEDS_DOWNLOAD, DOWNLOAD_PENDING, READY, LISTENING, UNAVAILABLE, FAILED
}

internal data class LocalWakeSnapshot(
    val availability: LocalWakeAvailability = LocalWakeAvailability.UNCHECKED,
    val languageTag: String = "zh-CN",
    val errorCode: Int? = null
)

internal object ChineseWakePolicy {
    private val simplifiedChinese = setOf("zh", "zh-cn", "zh-hans", "zh-hans-cn", "cmn-cn", "cmn-hans-cn")
    private val phrase = Regex(
        "^\\s*你\\s*好[\\s,，。.!！:：、]*(?:galaxy|ｇａｌａｘｙ|盖乐世)(?![a-zA-Zａ-ｚＡ-Ｚ])[\\s,，。.!！?？:：、]*(.*)$",
        setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)
    )

    fun languageSupport(installed: List<String>, pending: List<String>, downloadable: List<String>): LocalWakeSnapshot {
        fun List<String>.chinese() = firstOrNull {
            it.replace('_', '-').lowercase(Locale.ROOT) in simplifiedChinese
        }
        installed.chinese()?.let { return LocalWakeSnapshot(LocalWakeAvailability.READY, it) }
        pending.chinese()?.let { return LocalWakeSnapshot(LocalWakeAvailability.DOWNLOAD_PENDING, it) }
        downloadable.chinese()?.let { return LocalWakeSnapshot(LocalWakeAvailability.NEEDS_DOWNLOAD, it) }
        return LocalWakeSnapshot(LocalWakeAvailability.UNAVAILABLE)
    }

    // Only a direct address at the start can wake the app; quoted mentions cannot.
    fun commandAfterWake(text: String): String? =
        phrase.matchEntire(text)?.groupValues?.get(1)?.trim()
}
