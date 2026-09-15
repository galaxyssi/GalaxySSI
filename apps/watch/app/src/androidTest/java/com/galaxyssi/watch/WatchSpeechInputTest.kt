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
        assertEquals(WatchSpeechInput.SAMSUNG_PACKAGE, attempts.single().`package`)
        assertEquals(java.util.Locale.getDefault().toLanguageTag(), attempts.single().getStringExtra(RecognizerIntent.EXTRA_LANGUAGE))
        attempts.clear()
        assertTrue(WatchSpeechInput.launch(context) {
            attempts.add(it)
            if (it.`package` != null) throw ActivityNotFoundException()
        })
        assertNull(attempts.last().`package`)
        assertEquals(2, attempts.size)
        assertFalse(WatchSpeechInput.launch(context) { throw SecurityException() })
    }

    @Test fun cancelledSpeechPreservesDraftAndHomeView() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        instrumentation.waitForIdleSync()
        try {
            instrumentation.runOnMainSync {
                val before = views(activity.window.decorView).filterIsInstance<EditText>().single()
                val text = before.text.toString()
                MainActivity::class.java.getDeclaredMethod("onActivityResult", Int::class.javaPrimitiveType,
                    Int::class.javaPrimitiveType, Intent::class.java).apply { isAccessible = true }
                    .invoke(activity, 31, Activity.RESULT_CANCELED, null)
                val after = views(activity.window.decorView).filterIsInstance<EditText>().single()
                assertSame(before, after)
                assertEquals(text, after.text.toString())
            }
        } finally { instrumentation.runOnMainSync { activity.finish() } }
    }

    private fun views(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
}
