package com.galaxyssi.chat

import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
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
        } catch (error: Throwable) {
            failure = error.message.orEmpty()
            throw error
        } finally {
            File(context.filesDir, "deepseek-query-live.json").writeText(JSONObject()
                .put("conversation", conversation.id).put("elapsed_ms", SystemClock.elapsedRealtime() - started)
                .put("failure", failure).put("reply", reply?.text).put("rich_output", reply?.richOutputJson)
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
        }
    }
}
