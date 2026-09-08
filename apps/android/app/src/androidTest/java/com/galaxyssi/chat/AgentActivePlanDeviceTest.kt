package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentActivePlanDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun sqliteReopenRestores2048NodesAndSelectsTheFinalDependencyReadyNode() = isolated { scope ->
        val original = snapshot(scope, 2048)
        SharedPreferencesAgentSessionStore(context, scope).save(original)
        val restored = SharedPreferencesAgentSessionStore(context, scope).load()!!
        assertEquals(original.currentPlan!!.actions, restored.currentPlan!!.actions)
        assertEquals(original.currentPlan.checkpoints, restored.currentPlan.checkpoints)
        assertEquals("node-2047", restored.currentPlan.runnableActions().single().id)
        val reference = reference(scope)
        android.database.sqlite.SQLiteDatabase.openDatabase(
            context.getDatabasePath("agent_active_plans.db.db").absolutePath, null,
            android.database.sqlite.SQLiteDatabase.OPEN_READONLY).use { db ->
            db.rawQuery("SELECT max(length(encrypted_value)),count(*) FROM encrypted_values WHERE storage_key LIKE ?",
                arrayOf("active-plan:${AgentNativeJsonCodec.sha256(scope)}:%")).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertTrue(cursor.getInt(0) < 256 * 1024)
                assertEquals(reference.getInt("pages"), cursor.getInt(1))
            }
        }
    }

    @Test fun preservesLargeUnicodeToolArgumentsAndMoreThan128Checkpoints() = isolated { scope ->
        val original = snapshot(scope, 260)
        val text = "\u4e2d\u6587\uD83D\uDE80\"\\".repeat(20000)
        val plan = original.currentPlan!!.copy(actions = original.currentPlan.actions.mapIndexed { index, action ->
            if (index == 259) action.copy(parameters = action.parameters + ("input_json" to text)) else action
        })
        SharedPreferencesAgentSessionStore(context, scope).save(original.copy(currentPlan = plan))
        val restored = SharedPreferencesAgentSessionStore(context, scope).load()!!.currentPlan!!
        assertEquals(text, restored.actions.last().parameters["input_json"])
        assertEquals(260, restored.checkpoints.size)
        assertEquals("node-259", restored.runnableActions().single().id)
    }

    @Test fun missingEncryptedPageDoesNotExposeCompactFallbackAsExecutable() = isolated { scope ->
        val store = SharedPreferencesAgentSessionStore(context, scope)
        store.save(snapshot(scope, 100))
        val ref = reference(scope)
        AgentEncryptedDatabase(context, "agent_active_plans.db").remove(
            "active-plan:${AgentNativeJsonCodec.sha256(scope)}:${ref.getString("generation")}:0")
        val restored = store.load()!!
        assertEquals(AgentPhase.PAUSED, restored.phase)
        assertNull(restored.currentPlan)
        assertTrue(restored.lastActionResult!!.message.contains("page 0 is missing"))
    }

    @Test fun clearingOneSessionKeepsAnotherSessionsGraph() {
        val first = "task:test-active-${UUID.randomUUID()}"
        val second = "task:test-active-${UUID.randomUUID()}"
        val one = SharedPreferencesAgentSessionStore(context, first)
        val two = SharedPreferencesAgentSessionStore(context, second)
        try {
            one.save(snapshot(first, 100))
            two.save(snapshot(second, 110))
            one.clear()
            assertNull(one.load())
            assertEquals(110, two.load()!!.currentPlan!!.actions.size)
        } finally { one.clear(); two.clear() }
    }

    @Test fun publishPlanThenTerminateActualProcess() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("active_plan_crash") == "true")
        val store = SharedPreferencesAgentSessionStore(context, CRASH_SCOPE)
        check(store.load() == null) { "Inspect prior crash evidence before repeating setup" }
        store.save(snapshot(CRASH_SCOPE, 2048))
        android.os.Process.killProcess(android.os.Process.myPid())
        fail("Process did not terminate")
    }

    @Test fun recoverFullPlanAfterActualProcessDeath() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("active_plan_crash") == "true")
        val store = SharedPreferencesAgentSessionStore(context, CRASH_SCOPE)
        val restored = store.load()!!
        assertEquals(2048, restored.currentPlan!!.actions.size)
        assertEquals(2048, restored.currentPlan.checkpoints.size)
        assertEquals("node-2047", restored.currentPlan.runnableActions().single().id)
        store.clear()
    }

    @Test fun clearPublishedPlanThenTerminateActualProcess() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("active_plan_clear") == "true")
        SharedPreferencesAgentSessionStore(context, CRASH_SCOPE).clear()
        android.os.Process.killProcess(android.os.Process.myPid())
        fail("Process did not terminate")
    }

    @Test fun clearedPlanDoesNotReturnInANewProcess() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("active_plan_clear") == "true")
        assertNull(SharedPreferencesAgentSessionStore(context, CRASH_SCOPE).load())
        assertTrue(AgentEncryptedDatabase(context, "agent_active_plans.db").keys(
            "active-plan:${AgentNativeJsonCodec.sha256(CRASH_SCOPE)}:").isEmpty())
    }

    private fun reference(scope: String) = org.json.JSONObject(AgentEncryptedPreferences(context,
        SharedPreferencesAgentSessionStore.PREFS).readString(scope, "")).getJSONObject(AgentActivePlanPersistence.ROOT_KEY)

    private fun isolated(block: (String) -> Unit) {
        val scope = "task:test-active-${UUID.randomUUID()}"
        try { block(scope) } finally { SharedPreferencesAgentSessionStore(context, scope).clear() }
    }

    private fun snapshot(scope: String, count: Int): AgentSessionSnapshot {
        val screen = ScreenContext(foregroundApp = "Test", pageTitle = "Test")
        val actions = (0 until count).map { index -> AgentAction("node-$index", AgentActionKind.CALL_NATIVE_TOOL,
            "test.read", AgentRisk.LOW, if (index == count - 1) AgentActionStatus.PROPOSED else AgentActionStatus.COMPLETED,
            "\u8bfb\u53d6\u8282\u70b9 $index", mapOf("input_json" to "{}",
                "depends_on" to if (index > 0) "node-${index - 1}" else ""), requiresConfirmation = false) }
        val plan = AgentPlan("\u6062\u590d\u5b8c\u6574\u4efb\u52a1\u56fe", screen, emptyList(), actions,
            planId = scope, revision = 5,
            checkpoints = actions.map { AgentExecutionContinuity.checkpointBefore(it, screen, 5) })
        return AgentSessionSnapshot(scope, AgentPhase.EXECUTING, plan.goal, screen, plan,
            emptyList(), null, processInstanceId = "prior-process", updatedAtMillis = System.currentTimeMillis())
    }

    private companion object { const val CRASH_SCOPE = "task:test-active-plan-process-death" }
}
