package com.galaxyssi.chat

import android.view.ContextThemeWrapper
import android.view.View
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.core.app.ActivityScenario
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.ui.AgentVoicePanel
import com.galaxyssi.chat.ui.PhoneAssistantDisplay
import com.galaxyssi.chat.ui.PhoneAssistantLine
import com.galaxyssi.chat.ui.PhoneAssistantPanel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class VoiceControlDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun compactPanelHasOnlyStatusRouteStopAndTranscriptAtSmallWidths() {
        instrumentation.runOnMainSync {
            val panel = AgentVoicePanel(ContextThemeWrapper(context, R.style.Theme_GalaxySSI))
            panel.status.text = "正在聆听"
            panel.route.text = "蓝牙耳机"
            panel.transcript.text = "给朋友发消息，我十分钟后到。"
            panel.visibility = View.VISIBLE
            for (width in listOf(280, 320, 412, 600)) {
                val px = (width * context.resources.displayMetrics.density).toInt()
                panel.measure(View.MeasureSpec.makeMeasureSpec(px, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(2000, View.MeasureSpec.AT_MOST))
                panel.layout(0, 0, px, panel.measuredHeight)
                assertEquals(2, panel.childCount)
                assertNull(panel.waveform.parent)
                assertNull(panel.keyboard.parent)
                assertTrue(panel.hangup.width >= 48 * context.resources.displayMetrics.density - 1)
                assertTrue(panel.status.right <= panel.route.left)
                assertTrue(panel.route.right <= panel.hangup.left)
                assertTrue(panel.transcript.bottom <= panel.height)
            }
        }
    }

    @Test fun newsSearchUsesReadableRowsBoundedMetadataAndEscapesWildcards() {
        val name = "voice-news-test-${UUID.randomUUID()}.db"
        try {
            val store = AttentionArticleStore(context, name)
            for (i in 1..25) {
                val article = AttentionFeedArticle("voice-$i", "science", "标题 $i", "", "https://example.com/$i", "测试来源", i.toLong(), i.toLong())
                store.enqueue(article, "人工智能")
                if (i != 25) store.ready(article.key,
                    AttentionChineseArticle("中文新闻 $i", "这是用于语音朗读的真实数据库测试正文。".repeat(20), "test"))
            }
            assertEquals(8, store.voiceArticles("人工智能", 0, 8).size)
            assertEquals(20, store.voiceArticles("", 0, 999).size)
            assertEquals(4, store.voiceArticles("", 21, 8).size)
            assertTrue(store.voiceArticles("%", 0, 8).isEmpty())
            assertTrue(store.voiceArticles("_", 0, 8).isEmpty())
            assertFalse(store.voiceArticles("", 0, 8).any { "body" in it })
            assertEquals("voice-24", store.voiceArticles("", 0, 1).single()["article_id"])
        } finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }

    @Test fun simAudioIsNeverAdvertisedByTheAppTools() {
        val definitions = AgentAppControlTools.definitions { _, _, _ -> emptyMap() }
        assertFalse(definitions.any { "sim_audio" in it.descriptor.id })
        val pm = context.packageManager
        val service = pm.getServiceInfo(android.content.ComponentName(context, GalaxySSIInCallService::class.java), 0)
        assertEquals("android.permission.BIND_INCALL_SERVICE", service.permission)
        assertTrue(service.exported)
    }

    @Test fun phoneAssistantMatchesCompactLayoutAndGatesUnverifiedTranscripts() {
        instrumentation.runOnMainSync {
            val panel = PhoneAssistantPanel(ContextThemeWrapper(context, R.style.Theme_GalaxySSI))
            val fixture = PhoneAssistantDisplay("Emma", "通话中 · 00:42", hasCall = true,
                route = "蓝牙耳机", listening = true, lines = listOf(
                    PhoneAssistantLine("你的作业进展怎么样？需要帮助吗？", "How is your assignment going? Do you need any help?"),
                    PhoneAssistantLine("我已经完成了资料查找，但想确认一下展示的具体要求。",
                        "I've finished the research, but I'd like to clarify the presentation requirements.", outgoing = true)))
            panel.render(fixture)
            assertEquals(4, panel.childCount)
            assertEquals("E", panel.avatar.text.toString())
            assertEquals("通话中", panel.footer.status.text.toString())
            assertEquals("", panel.footer.transcript.text.toString())
            assertEquals(1, panel.content.childCount)
            assertEquals(context.getString(R.string.voice_control_call_audio_not_connected),
                (panel.content.getChildAt(0) as android.widget.TextView).text.toString())
            // Renderer fixtures validate bilingual layout, never simulate Telecom audio or call delivery.
            panel.render(fixture.copy(audioAvailable = true))
            assertEquals(2, panel.content.childCount)
            for (width in listOf(280, 320, 412, 600)) {
                val density = context.resources.displayMetrics.density
                val px = (width * density).toInt()
                panel.measure(View.MeasureSpec.makeMeasureSpec(px, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec((720 * density).toInt(), View.MeasureSpec.EXACTLY))
                panel.layout(0, 0, px, panel.measuredHeight)
                assertTrue(panel.avatar.right <= (panel.title.parent as View).left)
                assertTrue(panel.footer.status.right <= panel.footer.route.left)
                assertTrue(panel.footer.route.right <= panel.footer.hangup.left)
                assertTrue(panel.footer.bottom <= panel.height)
                if (width == 412) captureViewFixture(panel, "voice-phone-layout-fixture.png")
            }
            panel.render(fixture.copy(hasCall = false, caller = "电话助手", status = "未在通话"))
            assertFalse(panel.footer.hangup.isEnabled)
            assertEquals(View.GONE, panel.avatar.visibility)
            assertEquals(View.VISIBLE, panel.product.visibility)
        }
    }

    @Test fun phoneAssistantIdleDoesNotExposePersistentDialerOrRequestRole() {
        val telecom = context.getSystemService(android.telecom.TelecomManager::class.java)
        val originalDialer = telecom.defaultDialerPackage
        ActivityScenario.launch(PhoneAssistantActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                fun descendants(view: View): Sequence<View> = sequence {
                    yield(view)
                    if (view is android.view.ViewGroup) for (i in 0 until view.childCount)
                        yieldAll(descendants(view.getChildAt(i)))
                }
                assertFalse(descendants(activity.panel).any { it is android.widget.EditText })
                assertEquals(context.getString(R.string.voice_control_call_idle), activity.panel.status.text.toString())
                assertFalse(activity.panel.footer.hangup.isEnabled)
            }
            captureUi("voice-phone-idle.png")
        }
        assertEquals(originalDialer, telecom.defaultDialerPackage)
    }

    @Test fun mutedVoiceSessionMovesToNewsAndBackWithoutStartingRecording() {
        ActivityScenario.launch(MainActivity::class.java).use { main ->
            var voice: AgentVoiceConversation? = null
            main.onActivity { activity ->
                activity.showMainTab(PAGE_AGENT)
                voice = requireNotNull(activity.agentVoiceConversation)
                voice!!.session.begin(activity.agentTranscriptStore.activeConversation().id)
                voice!!.session.mute(true)
                voice!!.onNavigationChanged()
                assertEquals(View.GONE, activity.agentChatShortcuts.visibility)
                assertEquals(View.GONE, activity.agentComposerRow.visibility)
                assertFalse(activity.isVoiceCaptureActive())
                activity.startActivity(android.content.Intent(activity, ProactiveAttentionActivity::class.java))
            }
            var news: ProactiveAttentionActivity? = null
            try {
                val deadline = android.os.SystemClock.elapsedRealtime() + 5_000
                var shown = false
                while (!shown && android.os.SystemClock.elapsedRealtime() < deadline) {
                    instrumentation.waitForIdleSync()
                    instrumentation.runOnMainSync {
                        news = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED)
                            .filterIsInstance<ProactiveAttentionActivity>().firstOrNull()
                        shown = news != null && voice!!.panel.isShown
                    }
                    if (!shown) Thread.sleep(25)
                }
                instrumentation.runOnMainSync {
                    val activity = requireNotNull(news)
                    assertTrue(voice!!.hasExternalForegroundHost())
                    assertTrue("active=${voice!!.session.active} expanded=${voice!!.session.expanded} " +
                        generateSequence<View>(voice!!.panel) { it.parent as? View }.joinToString(" / ") {
                            "${it.javaClass.simpleName}:${it.visibility}:${it.isAttachedToWindow}"
                        }, voice!!.panel.isShown)
                    assertTrue(voice!!.session.muted)
                    assertEquals(activity.window.decorView.rootView, voice!!.panel.rootView)
                }
                captureUi("voice-news-muted.png")
            } finally {
                instrumentation.runOnMainSync { news?.finish() }
            }
            main.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
            main.onActivity { activity ->
                assertFalse(voice!!.hasExternalForegroundHost())
                assertTrue(voice!!.session.active)
                assertTrue(voice!!.session.muted)
                assertEquals(activity.agentComposerRow.parent, voice!!.panel.parent)
                voice!!.end()
                assertEquals(View.VISIBLE, activity.agentComposerRow.visibility)
                assertEquals(View.VISIBLE, activity.agentChatShortcuts.visibility)
                assertFalse(activity.isVoiceCaptureActive())
                assertEquals("", voice!!.panel.transcript.text.toString())
            }
        }
    }

    @Test fun nativeNavigationKeepsVoiceConversationAndRejectsOlderTurns() {
        val contacts = AppStore.contacts(context)
        val peer = (0 until contacts.length()).asSequence().mapNotNull(contacts::optJSONObject)
            .firstOrNull { AppStore.isDirectPeerContact(context, it.optString("id")) }
        org.junit.Assume.assumeNotNull(peer)
        val peerId = requireNotNull(peer).optString("id")
        val registry = AgentNativeToolRegistry().registerAll(
            AgentAppControlTools.definitions(AndroidAppControlPlatform(context)))
        ActivityScenario.launch(MainActivity::class.java).use { main ->
            var voice: AgentVoiceConversation? = null
            var conversationId = ""
            main.onActivity { activity ->
                activity.showMainTab(PAGE_AGENT)
                voice = requireNotNull(activity.agentVoiceConversation)
                conversationId = activity.agentTranscriptStore.activeConversation().id
                voice!!.session.begin(conversationId)
                voice!!.session.registerTrace("voice-device-navigation")
                voice!!.session.registerTurn("voice-device-navigation", "voice-device-turn")
                voice!!.session.mute(true)
                voice!!.panel.status.setText(R.string.voice_call_muted)
                assertEquals("voice-device-turn", voice!!.session.latestTurnId)
                voice!!.session.registerTrace("passive-capture-after-page-change")
                assertTrue(voice!!.session.acceptsAppControlTurn("voice-device-turn"))
                voice!!.onNavigationChanged()
            }
            val invocation = AgentNativeToolInvocationContext(conversationId = conversationId,
                turnId = "voice-device-turn", idempotencyKey = UUID.randomUUID().toString())
            val opened = registry.invoke("galaxyssi.app.navigate",
                mapOf("destination" to "contact", "contact_id" to peerId), invocation)
            assertTrue(opened.toJson(), opened.isSuccess)
            main.onActivity { activity ->
                assertEquals(peerId, activity.selectedContact?.id)
                assertEquals(conversationId, voice!!.session.conversationId)
                assertTrue(voice!!.panel.isShown)
                assertEquals(View.GONE, activity.findViewById<View>(R.id.chatComposerRow).visibility)
                assertFalse(activity.isVoiceCaptureActive())
                AppVoiceControlBridge.capture(activity, "voice-device-navigation")
                AppVoiceControlBridge.bindTurn("voice-device-navigation", conversationId, "voice-device-turn")
            }
            captureUi("voice-contact-muted.png")
            val origin = registry.invoke("galaxyssi.app.context", emptyMap(), invocation)
            assertTrue(origin.toJson(), origin.isSuccess)
            assertEquals(peerId, origin.output["contact_id"])
            val stale = registry.invoke("galaxyssi.app.navigate", mapOf("destination" to "agent"),
                invocation.copy(turnId = "older-turn", idempotencyKey = UUID.randomUUID().toString()))
            assertFalse(stale.isSuccess)
            assertEquals("voice_turn_changed", stale.error?.code)
            val returned = registry.invoke("galaxyssi.app.navigate", mapOf("destination" to "agent"),
                invocation.copy(idempotencyKey = UUID.randomUUID().toString()))
            assertTrue(returned.toJson(), returned.isSuccess)
            main.onActivity { activity ->
                assertEquals(conversationId, activity.agentTranscriptStore.activeConversation().id)
                assertEquals(activity.agentComposerRow.parent, voice!!.panel.parent)
                voice!!.end()
                assertEquals(View.VISIBLE, activity.agentComposerRow.visibility)
                assertFalse(activity.isVoiceCaptureActive())
            }
            // Returning to the Agent page must not retarget the earlier utterance's contact.
            val retained = registry.invoke("galaxyssi.app.context", emptyMap(), invocation)
            assertEquals(peerId, retained.output["contact_id"])
        }
    }

    private fun captureUi(name: String) {
        if (InstrumentationRegistry.getArguments().getString("capture_ui") != "true") return
        // Activity resume precedes the system window transition's final rendered frame.
        Thread.sleep(600)
        instrumentation.waitForIdleSync()
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try {
            java.io.File(context.getExternalFilesDir(null), name).outputStream().use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
        } finally { bitmap.recycle() }
    }

    private fun captureViewFixture(view: View, name: String) {
        if (InstrumentationRegistry.getArguments().getString("capture_ui") != "true") return
        val bitmap = android.graphics.Bitmap.createBitmap(view.width, view.height, android.graphics.Bitmap.Config.ARGB_8888)
        try {
            view.draw(android.graphics.Canvas(bitmap))
            java.io.File(context.getExternalFilesDir(null), name).outputStream().use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
        } finally { bitmap.recycle() }
    }
}
