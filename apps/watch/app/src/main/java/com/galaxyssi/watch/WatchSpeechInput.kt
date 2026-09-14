package com.galaxyssi.watch

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.speech.RecognizerIntent
import java.util.Locale

/** Use Samsung's public speech activity when available, preserving the standard result contract. */
object WatchSpeechInput {
    const val SAMSUNG_PACKAGE = "com.samsung.android.honeyboard"

    fun launch(context: Context, start: (Intent) -> Unit): Boolean {
        val standard = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_PROMPT, context.getString(R.string.speech_prompt))
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
        val samsung = Intent(standard).setPackage(SAMSUNG_PACKAGE)
        if (samsung.resolveActivity(context.packageManager) != null && tryStart(samsung, start)) return true
        return tryStart(standard, start)
    }

    private fun tryStart(intent: Intent, start: (Intent) -> Unit): Boolean = try {
        start(intent); true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }
}
