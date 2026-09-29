package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Explicit, checkpoint-scoped cleanup; never silently cancel after observation expiry. */
@RunWith(AndroidJUnit4::class)
class BusinessScenarioTaskCleanupTest {
    @Test fun cancelRecordedTimedOutTask() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("business_cancel_recorded") == "true")
        requireBusinessDevice(args.getString("business_device_model", "SM-T575"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val run = requireNotNull(args.getString("business_run"))
        val case = requireNotNull(args.getString("business_cases"))
        require(run.matches(Regex("[A-Za-z0-9_-]{1,64}")) && case.matches(Regex("A[0-9]{3}")))
        val index = requireNotNull(args.getString("business_capture_turn")).toInt()
        val directory = File(context.getExternalFilesDir(null), "business-eval/$run")
        val report = JSONObject(File(directory, "$case.json").readText())
        val catalog = JSONObject(File(directory, "catalog.json").readText())
        val turn = report.getJSONArray("turns").getJSONObject(index)
        val id = turn.getString("turn_id")
        val store = EncryptedAgentWorkspaceStore(context)
        val before = requireNotNull(store.find(id))
        requireBusinessCleanupScope(run, case, report, catalog, turn, before)
        val supervisor = AgentTaskRuntime.supervisor(context)
        val receipt = JSONObject().put("workspace_id", id).put("conversation", before.conversationId)
            .put("original_state", turn.getString("state")).put("status_before", before.status.name)
            .put("requested_at", System.currentTimeMillis())
        val file = File(directory, "$case-$index-cleanup-${System.currentTimeMillis()}.json")
        file.writeText(receipt.toString(2))
        if (!before.status.isTerminal) {
            receipt.put("cancel_requested", supervisor.cancelWorkspace(id, "Explicit cleanup of retained synthetic business timeout"))
        }
        val deadline = SystemClock.elapsedRealtime() + 30_000L
        while (id in supervisor.activeTaskIds() && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(100)
        val after = requireNotNull(store.find(id))
        val stopped = after.status.isTerminal && id !in supervisor.activeTaskIds()
        receipt.put("status_after", after.status.name).put("execution_stopped", stopped)
        file.writeText(receipt.toString(2))
        assertTrue("Only the recorded task may be cancelled; it must stop before a replacement test", stopped)
    }
}

internal fun requireBusinessCleanupScope(
    run: String, case: String, report: JSONObject, catalog: JSONObject,
    turn: JSONObject, workspace: AgentWorkspace
) {
    require(report.getString("catalog_sha256") == catalog.getString("catalog_sha256"))
    require(report.getString("case_id") == case)
    require(report.getString("window_key") == "business-$run-$case")
    require(turn.getString("state") == "observation_timeout")
    require(workspace.conversationId == report.getString("conversation"))
    require(workspace.workspaceId == turn.getString("turn_id") && workspace.goal == turn.getString("prompt"))
}

@RunWith(AndroidJUnit4::class)
class BusinessScenarioCleanupScopeTest {
    private fun report() = JSONObject().put("catalog_sha256", "frozen").put("case_id", "A005")
        .put("window_key", "business-run-A005").put("conversation", "conversation")
    private fun turn() = JSONObject().put("state", "observation_timeout").put("turn_id", "turn").put("prompt", "synthetic")
    private fun workspace() = AgentWorkspace("turn", "session", "conversation", "task", goal = "synthetic")
    private fun validate(report: JSONObject = report(), turn: JSONObject = turn(), workspace: AgentWorkspace = workspace()) =
        requireBusinessCleanupScope("run", "A005", report, JSONObject().put("catalog_sha256", "frozen"), turn, workspace)
    private fun rejected(block: () -> Unit) {
        org.junit.Assert.assertThrows(IllegalArgumentException::class.java) { block() }
    }

    @Test fun acceptsOnlyMatchingFrozenScope() = validate()

    @Test fun rejectsOtherRunCaseCatalogAndConversation() {
        listOf("catalog_sha256", "case_id", "window_key", "conversation").forEach { key ->
            rejected { validate(report = report().put(key, "other")) }
        }
    }

    @Test fun rejectsOtherTaskGoalAndNonTimeoutRecords() {
        rejected { validate(workspace = workspace().copy(workspaceId = "other")) }
        rejected { validate(workspace = workspace().copy(goal = "other")) }
        listOf("submitted", "completed", "failed", "").forEach { state ->
            rejected { validate(turn = turn().put("state", state)) }
        }
    }
}
