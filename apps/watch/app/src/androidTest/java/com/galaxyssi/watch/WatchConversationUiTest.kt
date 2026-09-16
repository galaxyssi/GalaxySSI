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

    @Test fun generationStaysStillAndSpeechFollowsUntilManualScroll() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        lateinit var ui: WatchConversationView
        lateinit var scroll: android.widget.ScrollView
        val task = WatchTask.create("api", "test", "Test", "请说明").copy(state = TaskState.RUNNING)
        val reply = (1..16).joinToString("\n\n") { "第${it}段：这是用于验证语音和显示同步的说明，生成文字时画面应该保持不动。" }
        try {
            instrumentation.runOnMainSync {
                ui = WatchConversationView(activity, "", {}, {}, {}, {}, {}, {}, {}, {}, {})
                activity.setContentView(ui)
                ui.update(listOf(task), "Test", true, true)
                scroll = views(ui).filterIsInstance<android.widget.ScrollView>().single()
            }
            instrumentation.waitForIdleSync()
            var initial = 0
            instrumentation.runOnMainSync {
                initial = scroll.scrollY
                ui.update(listOf(task.copy(reply = reply)), "Test", true)
            }
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync {
                assertEquals("Generation must not scroll to bottom", initial, scroll.scrollY)
                ui.showSpeaking(task.id, reply.indexOf("第8段"), reply.indexOf("第9段") - 2)
            }
            Thread.sleep(600)
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync {
                assertTrue("Playback should reveal its sentence", scroll.scrollY > initial)
                val event = android.view.MotionEvent.obtain(0, 1, android.view.MotionEvent.ACTION_SCROLL, 1,
                    arrayOf(android.view.MotionEvent.PointerProperties().apply { id = 0 }),
                    arrayOf(android.view.MotionEvent.PointerCoords().apply { setAxisValue(android.view.MotionEvent.AXIS_SCROLL, 1f) }),
                    0, 0, 1f, 1f, 0, 0, android.view.InputDevice.SOURCE_ROTARY_ENCODER, 0)
                scroll.dispatchGenericMotionEvent(event)
                event.recycle()
                initial = scroll.scrollY
                ui.showSpeaking(task.id, 0, 12)
            }
            Thread.sleep(400)
            instrumentation.runOnMainSync {
                assertEquals("Manual reading suspends speech scrolling", initial, scroll.scrollY)
                assertTrue(views(ui).filterIsInstance<TextView>().any { it.text == activity.getString(R.string.follow_speech) && it.visibility == View.VISIBLE })
                ui.resumeSpeechFollow()
            }
            Thread.sleep(600)
            instrumentation.runOnMainSync {
                assertTrue("Resume returns to the spoken sentence", scroll.scrollY < initial)
                initial = scroll.scrollY
                ui.stopSpeaking()
                ui.update(listOf(task.copy(reply = reply + "\n\n最终补充。", state = TaskState.COMPLETED)), "Test", true)
            }
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync { assertEquals("Completion must not jump to the end", initial, scroll.scrollY) }
            capture("conversation-speech-follow.png", ui)
        } finally { instrumentation.runOnMainSync { activity.finish() } }
    }

    @Test fun actualXiaoxiaoPlaybackDrivesDisplayRanges() {
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("speech_follow_diagnostic") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        val finished = java.util.concurrent.CountDownLatch(1)
        val first = java.util.concurrent.CountDownLatch(1)
        val starts = java.util.concurrent.CopyOnWriteArrayList<Int>()
        var failed = false
        lateinit var speech: WatchReplySpeech
        lateinit var ui: WatchConversationView
        val task = WatchTask.create("api", "test", "晓晓", "语音同步显示测试").copy(state = TaskState.RUNNING)
        val reply = "第一句：回复生成时，画面保持不动。\n\n第二句：现在听到哪里，屏幕就跟随显示到哪里。\n\n第三句：手动滑动可暂停跟随，停止播放后保持当前位置。"
        try {
            instrumentation.runOnMainSync {
                ui = WatchConversationView(activity, "", {}, {}, {}, {}, {}, {}, {}, {}, {})
                activity.setContentView(ui)
                ui.update(listOf(task), "晓晓", true, true)
                speech = WatchReplySpeech(activity,
                    onSpeaking = { id, start, end ->
                        starts.add(start)
                        ui.showSpeaking(id, start, end)
                        println("WATCH_SPEECH_FOLLOW start=$start end=$end")
                        first.countDown()
                    }, onSpeechStopped = { if (starts.isNotEmpty()) finished.countDown(); ui.stopSpeaking() },
                    onError = { failed = true; finished.countDown() })
                speech.observe(task, true)
            }
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync {
                val completed = task.copy(reply = reply, state = TaskState.COMPLETED)
                ui.update(listOf(completed), "晓晓", true)
                speech.observe(completed, true)
                assertTrue("Synthesis must not trigger a playback cursor", starts.isEmpty())
            }
            assertTrue("Xiaoxiao playback should start", first.await(40, java.util.concurrent.TimeUnit.SECONDS))
            Thread.sleep(500)
            capture("conversation-live-speech.png", ui)
            assertTrue("Playback should complete", finished.await(60, java.util.concurrent.TimeUnit.SECONDS))
            assertFalse("TTS failed", failed)
            assertEquals(3, starts.size)
            assertEquals(starts.sorted().distinct(), starts.toList())
        } finally { instrumentation.runOnMainSync { speech.shutdown(); activity.finish() } }
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
