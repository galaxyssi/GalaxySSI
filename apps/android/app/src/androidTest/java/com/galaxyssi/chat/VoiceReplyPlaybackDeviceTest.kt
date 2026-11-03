package com.galaxyssi.chat

import android.app.NotificationManager
import android.media.session.MediaSessionManager
import android.os.SystemClock
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class VoiceReplyPlaybackDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun cancelledPendingRequestCannotStartLater() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                VoiceReplyPlayback.start(activity, VoiceReplySelection("test", "missing"))
                assertTrue(VoiceReplyPlayback.stop())
            }
            Thread.sleep(1000)
            assertFalse(snapshot().playing)
            assertNull(snapshot().selection)
        }
    }

    @Test fun wrongConversationCannotReadAnotherReply() = withReply { selection ->
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { VoiceReplyPlayback.start(it, selection.copy(conversationId = "unrelated")) }
            await("ownership rejection") { it.status == "failed" }
            assertFalse(snapshot().playing)
        }
    }

    @Test fun liveReplySurvivesActivityDestructionAndMediaControls() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("run_live_audio") == "true")
        withReply { selection ->
            val bookmark = VoiceNewsPlaybackService.readCheckpoint(context)
            val entry = requireNotNull(AgentTranscriptStore(context).fullEntry(selection.entryId))
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity {
                    it.agentVoiceConversation?.end(preserveNews = true)
                    val previous = it.renderedAgentTranscriptSourceEntries
                    try {
                        it.renderedAgentTranscriptSourceEntries = listOf(entry)
                        val footer = it.agentReplySpeechFooter(entry) as android.widget.LinearLayout
                        assertTrue(footer.getChildAt(0).performClick())
                        assertEquals(selection, VoiceReplyPlayback.state.selection)
                    } finally { it.renderedAgentTranscriptSourceEntries = previous }
                }
                await("real Edge reply audio", 60_000) { it.status == "playing" }
                val controller = try {
                    instrumentation.uiAutomation.adoptShellPermissionIdentity("android.permission.MEDIA_CONTENT_CONTROL")
                    context.getSystemService(MediaSessionManager::class.java).getActiveSessions(null)
                        .first { it.packageName == context.packageName }
                } finally { instrumentation.uiAutomation.dropShellPermissionIdentity() }
                scenario.moveToState(Lifecycle.State.DESTROYED)
                Thread.sleep(2000)
                assertTrue("Speech must not own the Activity", snapshot().playing)
                assertEquals(selection, snapshot().selection)
                assertTrue(context.cacheDir.listFiles().orEmpty().none { it.name.startsWith("galaxyssi_tts_") })
                val notifications = context.getSystemService(NotificationManager::class.java).activeNotifications
                val notice = notifications.first { it.id == 7813 }.notification
                assertFalse(notice.extras.toString().contains("后台朗读测试"))
                controller.transportControls.pause()
                await("media pause") { it.status == "paused" }
                controller.transportControls.play()
                await("media resume", 60_000) { it.status == "playing" }
                instrumentation.runOnMainSync { VoiceNewsPlaybackService.pauseForInput() }
                assertEquals("paused", snapshot().status)
                controller.transportControls.stop()
                await("media stop") { !it.playing && it.status == "stopped" }
                assertEquals("Reply speech must not overwrite the news bookmark", bookmark,
                    VoiceNewsPlaybackService.readCheckpoint(context))
            }
        }
    }

    @Test fun liveReplyCompletionClearsPlaybackState() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("run_live_audio") == "true")
        withReply("测试完成。") { selection ->
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { VoiceReplyPlayback.start(it, selection) }
                await("short audio started", 60_000) { it.status == "playing" }
                await("natural completion", 30_000) { it.status == "stopped" && it.selection == null }
            }
        }
    }

    private fun withReply(text: String = (1..12).joinToString("\n\n") {
        "这是后台朗读测试的第${it}段。退出页面后，语音应继续播放。点击停止后，不会继续读取消息。"
    }, block: (VoiceReplySelection) -> Unit) {
        val store = AgentTranscriptStore(context)
        val conversation = store.createAgentConversation("后台朗读测试")
        val turn = UUID.randomUUID().toString()
        try {
            store.append(AgentTranscriptRole.ASSISTANT, text, "assistant-final:$turn",
                conversationId = conversation.id, turnId = turn)
            val entry = store.entriesForTurn(turn).single()
            block(VoiceReplySelection(conversation.id, entry.id))
        } finally {
            instrumentation.runOnMainSync { VoiceReplyPlayback.stop() }
            context.stopService(android.content.Intent(context, VoiceNewsPlaybackService::class.java))
            instrumentation.waitForIdleSync()
            store.deleteConversation(conversation.id)
        }
    }

    private fun snapshot(): VoiceReplyPlaybackState {
        var result = VoiceReplyPlaybackState()
        instrumentation.runOnMainSync { result = VoiceReplyPlayback.state }
        return result
    }
    private fun await(label: String, timeout: Long = 10_000, predicate: (VoiceReplyPlaybackState) -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < deadline) {
            if (predicate(snapshot())) return
            Thread.sleep(50)
        }
        fail("$label timed out: ${snapshot().status}")
    }
}
