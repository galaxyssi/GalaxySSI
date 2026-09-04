package com.galaxyssi.chat

import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Test

class MicrosoftTtsVoiceSettingsDeviceTest {
    @Test
    fun providerPageListsEverySupportedMicrosoftVoiceId() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ) as MainActivity
        try {
            val visibleText = mutableListOf<String>()
            instrumentation.runOnMainSync {
                activity.showTtsProviderPage()
                activity.featureContent.collectText(visibleText)
            }

            MicrosoftTtsVoiceCatalog.voices.forEach { voiceId ->
                assertTrue("Missing Microsoft voice: $voiceId", voiceId in visibleText)
            }
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    private fun View.collectText(destination: MutableList<String>) {
        if (this is TextView) destination += text.toString()
        if (this is ViewGroup) {
            for (index in 0 until childCount) getChildAt(index).collectText(destination)
        }
    }
}
