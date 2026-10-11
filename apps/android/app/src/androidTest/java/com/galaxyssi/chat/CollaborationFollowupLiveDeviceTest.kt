package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in acceptance on the selected group, without deleting history or replacing its background run. */
@RunWith(AndroidJUnit4::class)
class CollaborationFollowupLiveDeviceTest {
    @Test fun aQuestionStartsItsOwnResponseTurnWhileTheOriginalRunIsInterrupted() {
        val args = InstrumentationRegistry.getArguments()
        val group = args.getString("collaboration_followup_group").orEmpty()
        assumeTrue(group.isNotBlank())
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = AgentTranscriptStore(context)
        requireNotNull(CollaborationGroupStore(context).load(group))
        val runtime = GlobalSuperAgentRuntime.get(context)
        val original = runtime.agentTeamSnapshots().filter { it.conversationId == group }
            .maxByOrNull { it.createdAtMillis }
        val prior = runtime.agentTeamSnapshots().map { it.supervisorRunId }.toSet()
        val report = JSONObject().put("group", group).put("original_run", original?.supervisorRunId)
        val file = File(context.cacheDir, "collaboration-followup-live.json")
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        var questionTurn = ""
        val started = SystemClock.elapsedRealtime()
        try {
            await("activity hydration", 60_000) {
                var ready = false
                scenario.onActivity { ready = !it.initialAgentHydrationPending }
                ready
            }
            scenario.onActivity { it.openAgentConversation(group) }
            await("selected group", 30_000) {
                var ready = false
                scenario.onActivity { ready = it.agentRenderedConversationId == group }
                ready
            }
            scenario.onActivity {
                it.agentGoalInput.setText("请给出蛋白质系列。请先根据本群已有结果，用中文简要列出系列名称和各自用途；未验证的明确标注，不启动新实验或采购。")
                it.submitAgentGoal()
            }
            await("independent follow-up team", 60_000) {
                val next = runtime.agentTeamSnapshots().firstOrNull {
                    it.conversationId == group && it.supervisorRunId !in prior
                } ?: return@await false
                questionTurn = store.turnIdForTask(next.taskId).orEmpty()
                report.put("followup_run", next.supervisorRunId).put("followup_task", next.taskId)
                    .put("turn", questionTurn).put("member_count", next.members.size)
                    .put("research_stage_count", next.members.count { it.researchStage.isNotBlank() })
                assertEquals(1, next.members.size)
                assertTrue(next.members.all { it.researchStage.isBlank() })
                questionTurn.isNotBlank()
            }
            await("actual assistant answer", 240_000) {
                val team = runtime.agentTeamSnapshots().firstOrNull {
                    it.supervisorRunId == report.optString("followup_run")
                } ?: return@await false
                report.put("state", team.state).put("member_errors", team.members.joinToString { it.errorMessage })
                if (!team.state.isTerminal) return@await false
                assertEquals(team.members.joinToString { it.errorMessage }, AgentTeamExecutionState.SUCCEEDED, team.state)
                val rows = store.page(group, pageSize = 80).entries
                val answer = rows.lastOrNull { it.turnId == questionTurn && it.role == AgentTranscriptRole.ASSISTANT &&
                    !it.dedupeKey.startsWith("collaboration-update:") } ?: return@await false
                report.put("answer", answer.text).put("elapsed_ms", SystemClock.elapsedRealtime() - started)
                assertEquals(group, store.conversationIdForTurn(questionTurn))
                assertTrue(answer.text.isNotBlank())
                true
            }
            scenario.recreate()
            await("restored group", 60_000) {
                var ready = false
                scenario.onActivity { ready = !it.initialAgentHydrationPending && it.agentRenderedConversationId == group }
                ready
            }
            assertTrue(store.page(group, pageSize = 80).entries.none { entry ->
                entry.turnId.isNotBlank() && store.conversationIdForTurn(entry.turnId)?.let { owner ->
                    store.resolveMergedConversationId(owner) != store.resolveMergedConversationId(group)
                } == true
            })
            report.put("passed", true)
        } catch (error: Throwable) {
            report.put("passed", false).put("error", error.toString())
            throw error
        } finally {
            report.put("elapsed_ms", SystemClock.elapsedRealtime() - started)
            file.writeText(report.toString(2))
            scenario.close()
        }
    }

    private fun await(label: String, timeout: Long, condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < until) {
            if (condition()) return
            SystemClock.sleep(300)
        }
        fail("Timed out: $label")
    }
}
