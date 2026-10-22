package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.ImageButton
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DesktopRemoteComposerDeviceTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test fun editableClickReceiptOpensTheRealComposerWithoutForwardingEdits() {
        val intent = Intent(context, DesktopRemoteControlActivity::class.java)
            .putExtra(DesktopRemoteControlActivity.EXTRA_DESKTOP_ID, "test-unpaired-draft")
            .putExtra(DesktopRemoteControlActivity.EXTRA_DESKTOP_NAME, "Test computer")
        ActivityScenario.launch<DesktopRemoteControlActivity>(intent).use { scenario ->
            lateinit var editor: com.galaxyssi.chat.ui.ParagraphSelectingEditText
            lateinit var queue: DesktopInputQueue
            scenario.onActivity { activity ->
                queue = DesktopRemoteControlActivity::class.java.getDeclaredField("inputQueue")
                    .apply { isAccessible = true }.get(activity) as DesktopInputQueue
                val command = DesktopInputCommand(DesktopRemoteControl.CLICK_XY, org.json.JSONObject())
                queue.add(command)
                queue.next()
                DesktopRemoteControlActivity::class.java.getDeclaredField("autoInputAction")
                    .apply { isAccessible = true }.set(activity, command.id)
                DesktopRemoteControlActivity::class.java.getDeclaredMethod("inputResult", DesktopInputResult::class.java)
                    .apply { isAccessible = true }.invoke(activity, DesktopInputResult(command.id, true,
                        DesktopInputFocus(true, true, false, "test-target", 0, 0, 200, 40), ""))
                editor = activity.findViewById(R.id.remoteDraftInput)
                assertTrue(editor.isShown)
                assertTrue(editor.hasFocus())
                assertTrue(activity.findViewById<View>(R.id.remoteDraftMore).isShown)
                editor.setText("尚未发送\n第二行")
                assertNull(queue.active)
                assertNull(queue.next())
            }
            val deadline = System.currentTimeMillis() + 5000
            var keyboard = false
            while (!keyboard && System.currentTimeMillis() < deadline) {
                scenario.onActivity { keyboard = ViewCompat.getRootWindowInsets(editor)?.isVisible(WindowInsetsCompat.Type.ime()) == true }
                if (!keyboard) Thread.sleep(50)
            }
            assertTrue(keyboard)
            scenario.onActivity { activity ->
                @Suppress("DEPRECATION")
                activity.onBackPressed()
            }
            val hideDeadline = System.currentTimeMillis() + 5000
            while (keyboard && System.currentTimeMillis() < hideDeadline) {
                scenario.onActivity { keyboard = ViewCompat.getRootWindowInsets(editor)?.isVisible(WindowInsetsCompat.Type.ime()) == true }
                if (keyboard) Thread.sleep(50)
            }
            assertFalse(keyboard)
            scenario.onActivity { activity ->
                val toolbar = DesktopRemoteControlActivity::class.java.getDeclaredField("toolbar")
                    .apply { isAccessible = true }.get(activity) as View
                assertTrue(toolbar.isShown)
                assertTrue(editor.isShown)
                assertEquals("尚未发送\n第二行", editor.text.toString())
            }
        }
    }

    @Test fun entryOpensKeyboardAndExistingMoreIconWithoutAnExtraTap() = withComposer { scenario, composer, sent ->
        val deadline = System.currentTimeMillis() + 5000
        var keyboard = false
        while (!keyboard && System.currentTimeMillis() < deadline) {
            scenario.onActivity { keyboard = ViewCompat.getRootWindowInsets(composer.view)?.isVisible(WindowInsetsCompat.Type.ime()) == true }
            if (!keyboard) Thread.sleep(50)
        }
        assertTrue("Composer did not open the keyboard", keyboard)
        scenario.onActivity {
            assertTrue(composer.view.findViewById<View>(R.id.remoteDraftMore).isShown)
            assertFalse(composer.view.findViewById<View>(R.id.remoteDraftVoice).isShown)
            assertTrue(composer.editor.hasFocus())
            assertTrue(sent.isEmpty())
        }
    }

    @Test fun typingNewlinesAndDictationStayLocalUntilExplicitSend() = withComposer { scenario, composer, sent ->
        scenario.onActivity {
            composer.editor.setText("第一行\n第二行")
            composer.appendTranscript("继续输入")
            assertEquals("第一行\n第二行，继续输入", composer.editor.text.toString())
            assertEquals(8, composer.editor.maxLines)
            val info = EditorInfo()
            val connection = composer.editor.onCreateInputConnection(info)!!
            connection.commitText("\n", 1)
            assertTrue(info.imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION != 0)
            assertTrue(sent.isEmpty())
            val text = composer.editor.text.toString()
            val send = composer.view.findViewById<ImageButton>(R.id.remoteDraftSend)
            send.performClick()
            send.performClick()
            assertEquals(listOf(text), sent)
            composer.received("receipt-1", true)
            assertTrue(composer.editor.text.isNullOrEmpty())
        }
    }

    @Test fun failedSendAndConcurrentEditsPreserveTheDraft() = withComposer { scenario, composer, sent ->
        scenario.onActivity {
            composer.editor.setText("保留这段文字")
            composer.view.findViewById<ImageButton>(R.id.remoteDraftSend).performClick()
            composer.failed("Timeout")
            assertEquals("保留这段文字", composer.editor.text.toString())
            composer.view.findViewById<ImageButton>(R.id.remoteDraftSend).performClick()
            composer.editor.append("，新的内容")
            composer.received("receipt-2", true)
            assertEquals("保留这段文字，新的内容", composer.editor.text.toString())
            assertEquals(2, sent.size)
            composer.background()
            assertTrue(composer.editor.text.isNullOrEmpty())
            assertEquals(View.GONE, composer.view.visibility)
            assertFalse(composer.editor.isSaveEnabled)
        }
    }

    @Test fun permissionPauseKeepsDraftButBackgroundClearsIt() = withComposer { scenario, composer, _ ->
        scenario.onActivity {
            composer.editor.setText("申请权限之前的草稿")
            composer.pause()
            assertEquals("申请权限之前的草稿", composer.editor.text.toString())
            composer.open()
            assertEquals("申请权限之前的草稿", composer.editor.text.toString())
            composer.constrainHeight(180)
            assertTrue(composer.editor.maxLines in 1..8)
            composer.background()
            assertTrue(composer.editor.text.isNullOrEmpty())
        }
    }

    @Test fun movingFromPasswordToPlainInputDoesNotRevealPasswordDraft() = withComposer { scenario, composer, _ ->
        scenario.onActivity {
            composer.open(password = true)
            composer.editor.setText("private-draft")
            composer.hide()
            composer.open(password = false)
            assertTrue(composer.editor.text.isNullOrEmpty())
        }
    }

    @Test fun draftPreviewCanBeInspectedWithoutSendingRemoteInput() = withComposer { scenario, composer, sent ->
        scenario.onActivity { composer.editor.setText("请分析一下这个项目\n先查看代码，再给出建议。") }
        val seconds = InstrumentationRegistry.getArguments().getString("desktop_draft_preview_seconds")?.toLongOrNull() ?: 0
        if (seconds > 0) Thread.sleep(seconds.coerceAtMost(120) * 1000)
        assertTrue(sent.isEmpty())
    }

    private fun withComposer(block: (ActivityScenario<DesktopRemoteControlActivity>, DesktopRemoteComposer, MutableList<String>) -> Unit) {
        val intent = Intent(context, DesktopRemoteControlActivity::class.java)
            .putExtra(DesktopRemoteControlActivity.EXTRA_DESKTOP_ID, "test-unpaired-draft")
            .putExtra(DesktopRemoteControlActivity.EXTRA_DESKTOP_NAME, "Test computer")
        ActivityScenario.launch<DesktopRemoteControlActivity>(intent).use { scenario ->
            lateinit var composer: DesktopRemoteComposer
            val sent = mutableListOf<String>()
            scenario.onActivity { activity ->
                composer = DesktopRemoteComposer(activity) { text ->
                    sent += text
                    composer.beginSend("receipt-${sent.size}")
                }
                val content = activity.findViewById<android.view.ViewGroup>(android.R.id.content)
                (content.getChildAt(0) as android.widget.LinearLayout).addView(
                    composer.view, android.widget.LinearLayout.LayoutParams(-1, -2))
                composer.open()
            }
            try { block(scenario, composer, sent) } finally { scenario.onActivity { composer.close() } }
        }
    }
}
