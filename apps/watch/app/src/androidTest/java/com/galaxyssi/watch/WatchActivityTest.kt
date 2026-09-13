package com.galaxyssi.watch

import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WatchActivityTest {
    @Test fun providerCatalogOpensNativeGeminiPresetWithoutSavingCredentials() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        instrumentation.waitForIdleSync()
        try {
            instrumentation.runOnMainSync {
                fun click(text: String) = descendants(activity.window.decorView).filterIsInstance<Button>()
                    .first { it.text.toString() == text }.performClick()
                descendants(activity.window.decorView).first { it.contentDescription?.toString() == activity.getString(R.string.home_menu) }.performClick()
                click(activity.getString(R.string.settings))
                click(activity.getString(R.string.api_title))
                if (descendants(activity.window.decorView).filterIsInstance<Button>().none { it.text.toString() == "Google Gemini" }) {
                    click(activity.getString(R.string.api_provider))
                }
                WATCH_MODEL_PRESETS.map { it.provider }.distinct().forEach { provider ->
                    assertTrue(descendants(activity.window.decorView).filterIsInstance<Button>().any { it.text.toString() == provider })
                }
                click("Google Gemini")
                click("Gemini 3.5 Flash")
                assertTrue(descendants(activity.window.decorView).filterIsInstance<TextView>()
                    .any { it.text.toString() == "gemini-3.5-flash" })
            }
        } finally { instrumentation.runOnMainSync { activity.finish() } }
    }
    private fun descendants(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()

    @Test fun launchesAndNavigatesBackToConversationComposer() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        instrumentation.waitForIdleSync()
        try {
            instrumentation.runOnMainSync {
                val controls = descendants(activity.window.decorView)
                val sessions = controls.first { it.contentDescription?.toString() == activity.getString(R.string.recent) }
                assertTrue(sessions.height >= (48 * activity.resources.displayMetrics.density).toInt())
                sessions.performClick()
                assertTrue(descendants(activity.window.decorView).filterIsInstance<TextView>()
                    .any { it.text.toString() == activity.getString(R.string.new_conversation) })
                descendants(activity.window.decorView).filterIsInstance<Button>()
                    .first { it.text.toString() == activity.getString(R.string.back) }.performClick()
                assertTrue(descendants(activity.window.decorView).filterIsInstance<android.widget.EditText>()
                    .any { it.hint?.toString() == activity.getString(R.string.composer_hint) })
            }
        } finally { instrumentation.runOnMainSync { activity.finish() } }
    }
}
