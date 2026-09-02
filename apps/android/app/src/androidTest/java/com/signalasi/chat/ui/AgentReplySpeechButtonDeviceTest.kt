package com.signalasi.chat.ui

import android.widget.TextView
import androidx.test.platform.app.InstrumentationRegistry
import com.signalasi.chat.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentReplySpeechButtonDeviceTest {
    @Test
    fun labelAndAccessibilityStateFollowPlayback() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        instrumentation.runOnMainSync {
            val button = AgentReplySpeechButton(context)

            assertFalse(button.isPlayingSpeech)
            assertEquals(context.getString(R.string.agent_reply_speech_idle_label), button.labelText())
            assertEquals(
                context.getString(R.string.agent_reply_speech_enable),
                button.contentDescription
            )

            button.setPlaying(true)
            assertTrue(button.isPlayingSpeech)
            assertEquals(
                context.getString(R.string.agent_reply_speech_playing_label),
                button.labelText()
            )
            assertEquals(
                context.getString(R.string.agent_reply_speech_disable),
                button.contentDescription
            )

            button.setPlaying(false)
            assertFalse(button.isPlayingSpeech)
            assertEquals(context.getString(R.string.agent_reply_speech_idle_label), button.labelText())
        }
    }

    private fun AgentReplySpeechButton.labelText(): String =
        (getChildAt(1) as TextView).text.toString()
}
