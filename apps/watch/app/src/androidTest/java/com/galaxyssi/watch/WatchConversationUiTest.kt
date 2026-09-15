package com.galaxyssi.watch

import android.content.Intent
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

class WatchConversationUiTest {
    @Test fun richRepliesRenderHeadingsLinksAndCodeWithoutProtocolMarkup() {
        val rendered = WatchRichReply.render("# News\n\n- **Launch** [Source](https://example.com)\n\n```kotlin\nval count = 1\n```") as android.text.Spanned
        assertFalse(rendered.toString().contains("# News"))
        assertFalse(rendered.toString().contains("```"))
        assertTrue(rendered.toString().contains("Launch"))
        assertTrue(rendered.toString().contains("\u2022 Launch"))
        assertFalse(rendered.toString().contains("bullet"))
        assertTrue(rendered.getSpans(0, rendered.length, android.text.style.StyleSpan::class.java).isNotEmpty())
        assertEquals("https://example.com", rendered.getSpans(0, rendered.length, android.text.style.URLSpan::class.java).single().url)
        assertTrue(rendered.getSpans(0, rendered.length, android.text.style.TypefaceSpan::class.java).isNotEmpty())
    }
    private fun views(v: View): List<View> = listOf(v) +
        if (v is ViewGroup) (0 until v.childCount).flatMap { views(v.getChildAt(it)) } else emptyList()

    @Test fun replyUpdatesPreserveDraftAndUseOppositeSides() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        instrumentation.waitForIdleSync()
        try {
            lateinit var ui: WatchConversationView
            val task = WatchTask.create("api", "test-profile", "DeepSeek Flash", "Hello").copy(state = TaskState.RUNNING)
            instrumentation.runOnMainSync {
                var sends = 0
                ui = WatchConversationView(activity, "Unsent draft", {}, { sends++ }, {}, {}, {}, {}, {}, {}, {})
                activity.setContentView(ui)
                ui.update(listOf(task), "DeepSeek Flash", true, true)
                ui.input.setSelection(3)
                ui.update(listOf(task.copy(state = TaskState.COMPLETED, reply = "Reply arrived")), "DeepSeek Flash", true)
                assertEquals("Unsent draft", ui.input.text.toString())
                assertEquals(3, ui.input.selectionStart)
                val text = views(ui).filterIsInstance<TextView>()
                val sent = text.first { it.text.toString() == "Hello" && it.parent is LinearLayout &&
                    ((it.parent as LinearLayout).gravity and Gravity.RELATIVE_HORIZONTAL_GRAVITY_MASK) == Gravity.END }
                val received = text.first { it.text.toString() == "Reply arrived" }
                assertEquals(Gravity.END, (sent.parent as LinearLayout).gravity and Gravity.RELATIVE_HORIZONTAL_GRAVITY_MASK)
                assertEquals(Gravity.START, (received.parent as LinearLayout).gravity and Gravity.RELATIVE_HORIZONTAL_GRAVITY_MASK)
                assertNull(sent.background)
                assertNull(received.background)
                assertNull(ui.input.background)
                assertNull((ui.input.parent as View).background)
                val completed = task.copy(state = TaskState.COMPLETED, reply = "Reply arrived")
                val next = WatchTask.create("api", "test-profile", "DeepSeek Flash", "Next")
                ui.update(listOf(completed, next), "DeepSeek Flash", true)
                assertSame(received, views(ui).filterIsInstance<TextView>().first { it.text.toString() == "Reply arrived" })
                assertEquals(0, sends)
                assertTrue(views(ui).any { it.contentDescription?.toString() == activity.getString(R.string.send) })
                ui.setDraft("")
                assertTrue(views(ui).any { it.contentDescription?.toString() == activity.getString(R.string.home_menu) })
            }
            instrumentation.waitForIdleSync()
            capture("conversation-completed.png", ui)
            instrumentation.runOnMainSync { ui.update(listOf(task), "DeepSeek Flash", true, true) }
            instrumentation.waitForIdleSync()
            capture("conversation-running.png", ui)
            instrumentation.runOnMainSync { ui.update(emptyList(), "", false, true) }
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync {
                assertEquals(0, views(ui).filterIsInstance<android.widget.ScrollView>().single().scrollY)
            }
        } finally { instrumentation.runOnMainSync { activity.finish() } }
    }

    @Test fun sendingTextCannotTurnTheSendClickIntoAMenuClick() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            var sent = 0
            var menus = 0
            lateinit var ui: WatchConversationView
            ui = WatchConversationView(instrumentation.targetContext, "Recognized or typed text", {}, {
                sent++
                ui.setDraft("")
            }, {}, { menus++ }, {}, {}, {}, {}, {})
            val buttons = views(ui).filterIsInstance<android.widget.ImageButton>()
            val send = buttons.first { it.contentDescription == ui.context.getString(R.string.send) }
            send.performClick()
            send.performClick()
            assertEquals(1, sent)
            assertEquals(0, menus)
            assertEquals(View.GONE, send.visibility)
            val menu = buttons.first { it !== send }
            assertEquals(View.VISIBLE, menu.visibility)
            menu.performClick()
            assertEquals(1, menus)
        }
    }

    private fun capture(name: String, view: View) {
        if (InstrumentationRegistry.getArguments().getString("capture_ui") != "true") return
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        lateinit var bitmap: android.graphics.Bitmap
        instrumentation.runOnMainSync {
            check(view.width > 0 && view.height > 0)
            bitmap = android.graphics.Bitmap.createBitmap(view.width, view.height, android.graphics.Bitmap.Config.ARGB_8888)
            view.draw(android.graphics.Canvas(bitmap))
        }
        java.io.File(instrumentation.targetContext.getExternalFilesDir(null), name).outputStream().use {
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        }
        bitmap.recycle()
    }
}
