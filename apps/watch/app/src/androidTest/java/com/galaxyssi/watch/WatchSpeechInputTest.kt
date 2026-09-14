package com.galaxyssi.watch

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

class WatchSpeechInputTest {
    @Test fun prefersSamsungAndFallsBackWhenItsLaunchFails() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val available = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .setPackage(WatchSpeechInput.SAMSUNG_PACKAGE).resolveActivity(context.packageManager) != null
        val attempts = mutableListOf<Intent>()
        assertTrue(WatchSpeechInput.launch(context) { attempts.add(it) })
        assertEquals(if (available) WatchSpeechInput.SAMSUNG_PACKAGE else null, attempts.single().`package`)
        assertEquals(java.util.Locale.getDefault().toLanguageTag(), attempts.single().getStringExtra(RecognizerIntent.EXTRA_LANGUAGE))
        attempts.clear()
        assertTrue(WatchSpeechInput.launch(context) {
            attempts.add(it)
            if (it.`package` != null) throw ActivityNotFoundException()
        })
        assertNull(attempts.last().`package`)
        assertEquals(if (available) 2 else 1, attempts.size)
        assertFalse(WatchSpeechInput.launch(context) { throw SecurityException() })
    }

    @Test fun speechResultFillsComposerWithoutSendingAndCancelPreservesDraft() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val repo = (instrumentation.targetContext.applicationContext as WatchApplication).repository
        val originalDraft = repo.store.draft
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        instrumentation.waitForIdleSync()
        val callback = MainActivity::class.java.getDeclaredMethod("onActivityResult", Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType, Intent::class.java).apply { isAccessible = true }
        try {
            instrumentation.runOnMainSync {
                // Use the device's localized resource to exercise non-ASCII result text.
                val phrase = activity.getString(R.string.speech_prompt)
                val before = repo.store.tasks().map { it.id }.toSet()
                callback.invoke(activity, 31, Activity.RESULT_OK, Intent().putStringArrayListExtra(
                    RecognizerIntent.EXTRA_RESULTS, arrayListOf(phrase)))
                assertEquals(phrase, views(activity.window.decorView).filterIsInstance<EditText>().single().text.toString())
                assertEquals(phrase, repo.store.draft)
                callback.invoke(activity, 31, Activity.RESULT_CANCELED, null)
                assertEquals(phrase, repo.store.draft)
                assertEquals(before, repo.store.tasks().map { it.id }.toSet())
            }
        } finally {
            instrumentation.runOnMainSync {
                MainActivity::class.java.getDeclaredField("draft").apply { isAccessible = true }.set(activity, originalDraft)
                repo.store.draft = originalDraft
                activity.finish()
            }
        }
    }

    private fun views(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
}
