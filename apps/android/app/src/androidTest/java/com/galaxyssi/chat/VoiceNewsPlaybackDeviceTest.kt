package com.galaxyssi.chat

import android.content.ComponentName
import android.content.pm.ServiceInfo
import android.media.session.MediaSessionManager
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class VoiceNewsPlaybackDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun newsServiceIsPrivatePlaybackOnly() {
        assumeTrue(android.os.Build.VERSION.SDK_INT >= 29)
        val info = context.packageManager.getServiceInfo(ComponentName(context, VoiceNewsPlaybackService::class.java), 0)
        assertFalse(info.exported)
        assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK, info.foregroundServiceType)
        assertEquals(0, info.foregroundServiceType and ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
    }

    @Test fun paragraphHighlightDoesNotRelayoutOrFollowAnotherArticle() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val parent = activity.findViewById<ViewGroup>(android.R.id.content)
                val body = AttentionArticleBodyView(activity, AttentionArticleDocument.plain(
                    "这是第一段，用于检查朗读时的高亮。\n\n这是第二段，不应该同时高亮。"), "test-highlight")
                parent.addView(body)
                val width = activity.resources.displayMetrics.widthPixels
                fun height(): Int {
                    body.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(5000, View.MeasureSpec.AT_MOST))
                    return body.measuredHeight
                }
                val initial = height()
                try {
                    VoiceNewsPlaybackBus.publish(VoiceNewsPlaybackState("test-highlight", "playing", "这是第一段，用于检查朗读时的高亮。"))
                    assertEquals(1, (0 until body.childCount).count { body.getChildAt(it).isSelected })
                    assertEquals(initial, height())
                    VoiceNewsPlaybackBus.publish(VoiceNewsPlaybackState("another-article", "playing", "这是第一段，用于检查朗读时的高亮。"))
                    assertEquals(0, (0 until body.childCount).count { body.getChildAt(it).isSelected })
                    assertEquals(initial, height())
                } finally { parent.removeView(body); VoiceNewsPlaybackBus.publish(VoiceNewsPlaybackState()) }
            }
        }
    }

    @Test fun liveNewsContinuesInBackgroundAndAcceptsSystemMediaControls() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("run_live_audio") == "true")
        val ids = AttentionArticleStore(context).voiceArticles("", 0, 2).map { it["article_id"].toString() }
        assertEquals("Two downloaded articles are required for real playback", 2, ids.size)
        val preferences = context.getSharedPreferences("voice_news_bookmark", 0)
        val oldIds = preferences.getString("ids", "[]")
        val oldIndex = preferences.getInt("index", 0)
        val oldOffset = preferences.getInt("offset", 0)
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    activity.agentVoiceConversation?.end()
                    VoiceNewsPlaybackService.command(activity, "replace", ids)
                }
                await("first real audio", 60_000) { it.articleId == ids[0] && it.state == "playing" }
                val manager = context.getSystemService(MediaSessionManager::class.java)
                // Only discovery needs shell access. Playback must use the app's own identity.
                val controller = try {
                    instrumentation.uiAutomation.adoptShellPermissionIdentity("android.permission.MEDIA_CONTENT_CONTROL")
                    manager.getActiveSessions(null).first { it.packageName == context.packageName }
                } finally { instrumentation.uiAutomation.dropShellPermissionIdentity() }
                scenario.moveToState(Lifecycle.State.CREATED)
                Thread.sleep(2500)
                assertTrue("Activity backgrounding must not stop speech", snapshot().playing)
                assertEquals(ids[0], snapshot().articleId)
                controller.transportControls.pause()
                await("system pause") { it.state == "paused" }
                assertEquals("", snapshot().paragraph)
                controller.transportControls.play()
                await("system resume", 60_000) { it.state == "playing" }
                controller.transportControls.skipToNext()
                await("system next", 60_000) { it.articleId == ids[1] && it.state == "playing" }
                instrumentation.runOnMainSync {
                    VoiceNewsPlaybackService.pauseForInput()
                    assertEquals("paused", VoiceNewsPlaybackBus.current.state)
                }
                controller.transportControls.play()
                await("resume after capture handoff", 60_000) { it.state == "playing" }
                scenario.moveToState(Lifecycle.State.RESUMED)
                scenario.onActivity { activity -> assertFalse(activity.isVoiceCaptureActive()) }
                controller.transportControls.stop()
                await("system stop") { it.articleId.isBlank() && it.state == "stopped" }
                assertTrue(VoiceNewsPlaybackService.readCheckpoint(context).ids.isEmpty())
            }
        } finally {
            context.stopService(android.content.Intent(context, VoiceNewsPlaybackService::class.java))
            instrumentation.waitForIdleSync()
            preferences.edit().putString("ids", oldIds).putInt("index", oldIndex).putInt("offset", oldOffset).commit()
            instrumentation.uiAutomation.dropShellPermissionIdentity()
        }
    }

    private fun snapshot(): VoiceNewsPlaybackState {
        var value = VoiceNewsPlaybackState()
        instrumentation.runOnMainSync { value = VoiceNewsPlaybackBus.current }
        return value
    }
    private fun await(label: String, timeout: Long = 10_000, predicate: (VoiceNewsPlaybackState) -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < deadline) {
            val state = snapshot()
            if (predicate(state)) return
            assertNotEquals("$label: ${state.error}", "failed", state.state)
            Thread.sleep(50)
        }
        fail("$label timed out: ${snapshot().state}")
    }
}
