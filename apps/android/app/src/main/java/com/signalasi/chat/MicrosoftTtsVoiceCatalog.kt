package com.signalasi.chat

internal object MicrosoftTtsVoiceCatalog {
    const val XIAOXIAO = "zh-CN-XiaoxiaoNeural"
    const val XIAOXIAO_DRAGON_HD_FLASH = "zh-CN-Xiaoxiao:DragonHDFlashLatestNeural"
    const val XIAOXIAO2_DRAGON_HD_FLASH = "zh-CN-Xiaoxiao2:DragonHDFlashLatestNeural"

    val voices: List<String> = listOf(
        XIAOXIAO,
        XIAOXIAO_DRAGON_HD_FLASH,
        XIAOXIAO2_DRAGON_HD_FLASH
    )

    fun canonical(value: String?): String {
        val candidate = value.orEmpty().trim()
        return voices.firstOrNull { it.equals(candidate, ignoreCase = true) } ?: XIAOXIAO
    }
}
