package com.galaxyssi.chat

import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.Build
import java.util.Locale

object AppLanguage {
    private const val PREFS = "galaxyssi_language"
    private const val KEY = "language"
    const val AUTO = "auto"
    const val ZH_CN = "zh-CN"
    const val EN = "en"

    fun current(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, AUTO) ?: AUTO

    fun set(context: Context, language: String) {
        val normalized = when (language) {
            ZH_CN -> ZH_CN
            EN -> EN
            else -> AUTO
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY, normalized)
            .commit()
    }

    fun wrap(context: Context): Context {
        val locale = localeFor(resolved(context))
        Locale.setDefault(locale)
        val config = Configuration(context.resources.configuration)
        config.setLocale(locale)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            config.setLocales(android.os.LocaleList(locale))
        }
        return context.createConfigurationContext(config)
    }

    @Suppress("DEPRECATION")
    fun applyToResources(context: Context) {
        val locale = localeFor(resolved(context))
        Locale.setDefault(locale)
        val config = Configuration(context.resources.configuration)
        config.setLocale(locale)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            config.setLocales(android.os.LocaleList(locale))
        }
        context.resources.updateConfiguration(config, context.resources.displayMetrics)
    }

    fun resolved(context: Context): String = when (current(context)) {
        ZH_CN -> ZH_CN
        EN -> EN
        else -> {
            val configuration = Resources.getSystem().configuration
            val locale = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                configuration.locales.get(0)
            } else {
                @Suppress("DEPRECATION")
                configuration.locale
            }
            if (locale?.language.equals("zh", true)) ZH_CN else EN
        }
    }

    fun displayName(context: Context): String = when (current(context)) {
        EN -> context.getString(R.string.settings_language_en)
        ZH_CN -> context.getString(R.string.settings_language_zh)
        else -> context.getString(R.string.settings_language_auto)
    }

    private fun localeFor(language: String): Locale =
        if (language == EN) Locale.ENGLISH else Locale.SIMPLIFIED_CHINESE
}
