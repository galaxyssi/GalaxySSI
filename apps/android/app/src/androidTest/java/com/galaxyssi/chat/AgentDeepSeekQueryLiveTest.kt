package com.galaxyssi.chat

import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.app.Dialog
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in public query through the real composer, pinned provider and phone Agent Loop. */
@RunWith(AndroidJUnit4::class)
class AgentDeepSeekQueryLiveTest {
    @Test fun configuredDeepSeekCompletesPublicQueryWithoutDesktopFallback() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("live_deepseek_query") == "true")
        val prompt = args.getString("query").orEmpty().ifBlank { "世界上最小的无人机，给出图片" }
        val visual = args.getString("expected_visual_delivery").orEmpty()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val key = "deepseek-query-${UUID.randomUUID()}"
        val transcript = AgentTranscriptStore(context, key)
        val target = AppStoreAgentConnectorRegistry(context).availableTargets()
            .first { it.id == "cloud:deepseek" }
        val conversation = transcript.createConversation("DeepSeek 查询回归", privateMode = true)
        transcript.append(AgentTranscriptRole.PROCESS, "真实查询验证", conversationId = conversation.id)
        AgentModelSelectionSettings.selectManual(context, conversation.id, target.id,
            target.invocationProfile.normalizedModelId(""), target.title, rememberAsDefault = false)
        val monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
        var window: MainActivity? = null
        var started = 0L
        var reply: AgentTranscriptEntry? = null
        var failure = ""
        try {
            context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/$key"))
                .putExtra(AgentConversationWindows.WINDOW_KEY, key)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
            val activity = instrumentation.waitForMonitorWithTimeout(monitor, 30_000) as? MainActivity
                ?: error("Conversation window missing")
            window = activity
            instrumentation.runOnMainSync { activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
            val readyBy = SystemClock.elapsedRealtime() + 30_000
            while (activity.initialAgentHydrationPending && SystemClock.elapsedRealtime() < readyBy) SystemClock.sleep(100)
            assertFalse(activity.initialAgentHydrationPending)
            assertEquals(conversation.id, activity.conversationWindow.conversationId)
            started = SystemClock.elapsedRealtime()
            instrumentation.runOnMainSync {
                activity.agentGoalInput.setText(prompt)
                assertTrue(activity.agentSubmitButton.performClick())
            }
            while (reply == null && SystemClock.elapsedRealtime() - started < 180_000) {
                reply = transcript.page(conversation.id, pageSize = 100).entries.lastOrNull {
                    it.role == AgentTranscriptRole.ASSISTANT && !AgentTranscriptRenderPolicy.isLiveStream(it)
                }
                if (reply == null) SystemClock.sleep(500)
            }
            assertNotNull("No final answer within three minutes", reply)
            val saved = SharedPreferencesAgentSessionStore(context, "task:${reply!!.turnId}").load()
            assertEquals(AgentPhase.COMPLETED, saved?.phase)
            val connectors = saved?.currentPlan?.let { it.actionHistory + it.actions }.orEmpty()
                .filter(AgentAction::isSupervisedProjectConnector)
            assertTrue(connectors.isNotEmpty())
            assertTrue(connectors.all { it.parameters["connector_id"] == target.id })
            assertTrue(reply!!.text.isNotBlank())
            if (visual == "html") {
                val blocks = AgentRichContentCodec.decode(reply!!.richOutputJson)
                val animation = blocks.firstOrNull(AgentHtmlArtifactPreview::supports)
                assertNotNull("Expected a delivered HTML attachment, not source code", animation)
                assertTrue(AgentHtmlArtifactPreview.load(context, animation!!).contains("<canvas", true))
                verifyLiveCanvas(activity, reply!!)
            } else if (visual == "video") {
                val video = AgentRichContentCodec.decode(reply!!.richOutputJson).firstOrNull {
                    it.mimeType == "video/mp4"
                }
                assertNotNull("Expected an exported MP4, not HTML or a promise", video)
                assertTrue(video!!.uri.isNotBlank())
                val media = android.media.MediaMetadataRetriever()
                try {
                    media.setDataSource(context, Uri.parse(video.uri))
                    assertTrue(media.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong() > 0)
                    val frame = media.getFrameAtTime(0)
                    assertNotNull("Exported MP4 must decode a video frame", frame)
                    frame?.recycle()
                } finally { media.release() }
            }
        } catch (error: Throwable) {
            failure = error.message.orEmpty()
            throw error
        } finally {
            File(context.filesDir, "deepseek-query-live.json").writeText(JSONObject()
                .put("conversation", conversation.id).put("elapsed_ms", SystemClock.elapsedRealtime() - started)
                .put("failure", failure).put("reply", reply?.text).put("rich_output", reply?.richOutputJson)
                .put("expected_visual_delivery", visual)
                .put("turn", reply?.turnId).toString(2))
            instrumentation.removeMonitor(monitor)
            if (reply == null) window?.let { activity ->
                // Stop only this fixture if the deadline expires; no background research is left running.
                instrumentation.runOnMainSync { activity.agentGoalInput.setText("") }
                AgentTaskRuntime.supervisor(context).activeWorkspaces().filter { it.conversationId == conversation.id }
                    .forEach {
                        AgentCloudDispatchRegistry.cancel(SharedPreferencesAgentSessionStore(context,
                            "task:${it.workspaceId}").load()?.lastActionResult)
                        AgentTaskRuntime.supervisor(context).cancelWorkspace(it.workspaceId, "Live test deadline reached")
                    }
            }
            window?.let { activity -> instrumentation.runOnMainSync { activity.finish() } }
        }
    }

}

    internal fun verifyLiveCanvas(activity: MainActivity, entry: AgentTranscriptEntry) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        lateinit var dialog: Dialog
        lateinit var root: View
        instrumentation.runOnMainSync {
            activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            root = AgentRichContentView(activity, {}, {}, { _, _ -> }, enableResponseSections = false).create(entry)
            dialog = Dialog(activity).apply { setContentView(root); show()
                window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT) }
        }
        fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
            (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
        fun sample(): String? {
            val done = CountDownLatch(1)
            var result: String? = null
            instrumentation.runOnMainSync {
                val web = views(root).filterIsInstance<WebView>().firstOrNull()
                if (web == null) done.countDown() else web.evaluateJavascript("""
                    (()=>{const c=document.querySelector('canvas');if(!c||!c.width||!c.height)return null;
                    const d=c.getContext('2d').getImageData(0,0,c.width,c.height).data;
                    let sum=0,painted=0;for(let i=0;i<d.length;i+=4){if(d[i+3])painted++;
                    sum=(sum+(i+1)*(d[i]+3*d[i+1]+7*d[i+2]))%1000000007;}return painted?sum:null;})()
                """.trimIndent()) { result = it.takeUnless { value -> value == "null" }; done.countDown() }
            }
            assertTrue(done.await(5, TimeUnit.SECONDS))
            return result
        }
        try {
            val until = SystemClock.elapsedRealtime() + 15_000
            var first: String? = null
            while (first == null && SystemClock.elapsedRealtime() < until) { first = sample(); SystemClock.sleep(150) }
            assertNotNull("No rendered canvas pixels", first)
            var changed = false
            while (!changed && SystemClock.elapsedRealtime() < until) {
                SystemClock.sleep(230)
                changed = sample()?.let { it != first } == true
            }
            assertTrue("Live model animation did not move", changed)
        } finally { instrumentation.runOnMainSync { dialog.dismiss() } }
    }
