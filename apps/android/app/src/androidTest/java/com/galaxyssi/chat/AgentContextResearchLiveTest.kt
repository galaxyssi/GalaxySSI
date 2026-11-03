package com.galaxyssi.chat

import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Public research only, submitted through the real composer and phone Agent Loop. */
@RunWith(AndroidJUnit4::class)
class AgentContextResearchLiveTest {
    @Test fun inspectRecordedInvocation() {
        val args = InstrumentationRegistry.getArguments()
        val turn = args.getString("inspect_turn").orEmpty()
        assumeTrue(turn.isNotBlank())
        val state = SharedPreferencesAgentSessionStore(InstrumentationRegistry.getInstrumentation().targetContext, "task:$turn").load()
        val keys = setOf("connector_id", "agent_model_id", "manual_model_id", "agent_reasoning_effort",
            AgentInvocationBinding.TARGET, INTERNAL_CONVERSATION_ID, INTERNAL_TURN_ID)
        state?.currentPlan?.let { it.actions + it.actionHistory }.orEmpty().filter(AgentAction::isSupervisedProjectConnector)
            .forEach { println("INVOCATION_AUDIT ${it.id}: ${it.parameters.filterKeys(keys::contains)}") }
    }

    @Test fun realResearchFollowUpsKeepChangedRequirements() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("live_context_research") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val key = "context-research-${UUID.randomUUID()}"
        val transcript = AgentTranscriptStore(context, key)
        val target = AppStoreAgentConnectorRegistry(context).availableTargets().first {
            it.id.endsWith(":codex") && AgentConnectorRouteSelector.isDeliverable(it)
        }
        val conversation = transcript.createConversation("连续研究上下文回归", privateMode = true)
        transcript.append(AgentTranscriptRole.PROCESS, "公开资料连续研究测试", conversationId = conversation.id)
        val model = args.getString("expected_agent_model", "gpt-6-astra")
        val effort = AgentModelReasoningEffort.fromWireValue(args.getString("expected_agent_effort", "high"))
        AgentModelSelectionSettings.selectManual(context, conversation.id, target.id, model, target.title,
            effort, rememberAsDefault = false)
        AgentModelSelectionSettings.selectAutoForConversation(context, conversation.id)
        val monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
        val report = JSONObject().put("conversation", conversation.id).put("model", model).put("effort", effort.wireValue)
        val rounds = JSONArray()
        report.put("rounds", rounds)
        var window: MainActivity? = null
        var completed = false
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
            val queries = listOf(
                "请联网查找两个在线博士项目，专业限定计算机或人工智能。列中文校名、学费和官方来源链接；不确定的明确标注，不要自行加国家、预算或排名条件。请简明回答。",
                "调整一下，只看英国，其他要求保持不变，请实际查找并给出结果。",
                "继续找一个，不要重复前面已经给过的，也不要增加条件。",
                "不用联网，复述当前的学位、专业、学习方式、国家和要求的输出字段，说明有哪些条件是我后来修改的。"
            )
            queries.forEachIndexed { index, query ->
                val seen = transcript.page(conversation.id, pageSize = 100).entries.map { it.id }.toSet()
                val started = SystemClock.elapsedRealtime()
                instrumentation.runOnMainSync {
                    activity.agentGoalInput.setText(query)
                    assertTrue(activity.agentSubmitButton.performClick())
                }
                var reply: AgentTranscriptEntry? = null
                while (reply == null && SystemClock.elapsedRealtime() - started < 240_000) {
                    reply = transcript.page(conversation.id, pageSize = 100).entries.lastOrNull {
                        it.id !in seen && it.role == AgentTranscriptRole.ASSISTANT && !AgentTranscriptRenderPolicy.isLiveStream(it)
                    }
                    if (reply == null) SystemClock.sleep(500)
                }
                val record = JSONObject().put("round", index + 1).put("query", query)
                    .put("elapsed_ms", SystemClock.elapsedRealtime() - started).put("reply", reply?.text).put("turn", reply?.turnId)
                rounds.put(record)
                File(context.filesDir, "context-research-live.json").writeText(report.toString(2))
                assertNotNull("Round ${index + 1}: no final answer within four minutes", reply)
                val state = SharedPreferencesAgentSessionStore(context, "task:${reply!!.turnId}").load()
                record.put("phase", state?.phase?.name)
                assertEquals(AgentPhase.COMPLETED, state?.phase)
                val actions = state?.currentPlan?.let { it.actionHistory + it.actions }.orEmpty()
                    .filter(AgentAction::isSupervisedProjectConnector)
                record.put("invocations", JSONArray(actions.map { action -> JSONObject(action.parameters.filterKeys {
                    it in setOf("connector_id", "agent_model_id", "agent_reasoning_effort", AgentInvocationBinding.TARGET)
                }) }))
                assertTrue(actions.isNotEmpty())
                assertTrue(actions.all { it.parameters["agent_model_id"] == model && it.parameters["agent_reasoning_effort"] == effort.wireValue })
                if (index == 3) listOf("博士", "英国", "学费", "中文").forEach {
                    assertTrue("Missing changed requirement $it", reply!!.text.contains(it))
                }
                println("LIVE_RESEARCH conversation=${conversation.id} round=${index + 1} turn=${reply!!.turnId} " +
                    "elapsed_ms=${SystemClock.elapsedRealtime() - started}")
            }
            completed = true
        } catch (failure: Throwable) {
            report.put("failure", failure.message)
            throw failure
        } finally {
            report.put("completed", completed)
            File(context.filesDir, "context-research-live.json").writeText(report.toString(2))
            instrumentation.removeMonitor(monitor)
            if (!completed) AgentTaskRuntime.supervisor(context).activeWorkspaces()
                .filter { it.conversationId == conversation.id }.forEach {
                    AgentCloudDispatchRegistry.cancel(SharedPreferencesAgentSessionStore(context, "task:${it.workspaceId}").load()?.lastActionResult)
                    AgentTaskRuntime.supervisor(context).cancelWorkspace(it.workspaceId, "Context research test deadline or assertion failure")
                }
            window?.let { activity -> instrumentation.runOnMainSync { activity.finish() } }
        }
    }
}
