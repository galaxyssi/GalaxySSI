package com.galaxyssi.chat

import android.content.Context
import android.content.res.Resources
import java.util.Locale

data class LanguagePolicyConfig(
    val responseLanguage: String,
    val asrLanguage: String,
    val ttsLanguage: String
)

object LanguagePolicySettings {
    private const val PREFS = "galaxyssi_language_policy"
    private const val KEY_RESPONSE_LANGUAGE = "response_language"
    private const val KEY_ASR_LANGUAGE = "asr_language"
    private const val KEY_TTS_LANGUAGE = "tts_language"

    const val AUTO = "auto"
    const val ZH_CN = "zh-CN"
    const val EN_US = "en-US"
    const val ZH_HK = "zh-HK"
    const val ZH_TW = "zh-TW"

    val choices = listOf(AUTO, ZH_CN, EN_US, ZH_HK, ZH_TW)

    fun get(context: Context): LanguagePolicyConfig {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return LanguagePolicyConfig(
            responseLanguage = normalize(prefs.getString(KEY_RESPONSE_LANGUAGE, AUTO)),
            asrLanguage = normalize(prefs.getString(KEY_ASR_LANGUAGE, AUTO)),
            ttsLanguage = normalize(prefs.getString(KEY_TTS_LANGUAGE, AUTO))
        )
    }

    fun setResponseLanguage(context: Context, value: String) =
        set(context, KEY_RESPONSE_LANGUAGE, value)

    fun setAsrLanguage(context: Context, value: String) =
        set(context, KEY_ASR_LANGUAGE, value)

    fun setTtsLanguage(context: Context, value: String) =
        set(context, KEY_TTS_LANGUAGE, value)

    fun resolvedResponseLanguage(context: Context): String =
        resolve(get(context).responseLanguage)

    fun resolvedAsrLanguage(context: Context): String =
        resolve(get(context).asrLanguage)

    fun resolvedTtsLanguage(context: Context): String =
        resolve(get(context).ttsLanguage)

    fun resolve(value: String): String =
        normalize(value).takeUnless { it == AUTO } ?: systemLanguageTag()

    fun systemLanguageTag(): String {
        val configuration = Resources.getSystem().configuration
        val locale = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
            configuration.locales.get(0)
        } else {
            @Suppress("DEPRECATION")
            configuration.locale
        } ?: Locale.getDefault()
        return locale.toLanguageTag().ifBlank { EN_US }
    }

    fun modelLanguageName(languageTag: String): String {
        val locale = Locale.forLanguageTag(resolve(languageTag))
        return locale.getDisplayLanguage(Locale.ENGLISH).ifBlank { "English" }.let { language ->
            when (locale.toLanguageTag()) {
                ZH_CN -> "Simplified Chinese"
                ZH_HK, ZH_TW -> "Traditional Chinese"
                else -> language
            }
        }
    }

    fun microsoftVoice(languageTag: String, configuredVoice: String): String {
        val resolved = resolve(languageTag)
        val expectedPrefix = resolved.lowercase(Locale.ROOT)
        if (configuredVoice.lowercase(Locale.ROOT).startsWith("$expectedPrefix-")) {
            return configuredVoice
        }
        return when {
            resolved.equals(ZH_HK, true) -> "zh-HK-HiuMaanNeural"
            resolved.equals(ZH_TW, true) -> "zh-TW-HsiaoChenNeural"
            resolved.startsWith("zh", true) -> "zh-CN-XiaoxiaoNeural"
            else -> "en-US-JennyNeural"
        }
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().commit()
    }

    private fun normalize(value: String?): String {
        val candidate = value.orEmpty().trim()
        if (candidate.equals(AUTO, true)) return AUTO
        return choices.firstOrNull { it.equals(candidate, true) } ?: AUTO
    }

    private fun set(context: Context, key: String, value: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(key, normalize(value))
            .apply()
    }
}
