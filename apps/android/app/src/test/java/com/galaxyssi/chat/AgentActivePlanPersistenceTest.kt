package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentActivePlanPersistenceTest {
    @Test fun restoresAll2048ExecutableNodesAndDependencies() {
        val storage = MemoryStorage()
        val initial = snapshot(2048)
        SharedPreferencesAgentSessionStore(storage).save(initial)
        val restored = SharedPreferencesAgentSessionStore(storage).load()!!
        assertEquals(initial.currentPlan!!.actions, restored.currentPlan!!.actions)
        assertEquals(initial.currentPlan.checkpoints, restored.currentPlan.checkpoints)
        assertEquals(initial.currentGoal, restored.currentGoal)
        assertTrue(storage.values.getValue("session").length < AgentSessionPersistencePolicy.MAX_SESSION_JSON_CHARACTERS)
        assertTrue(storage.values.filterKeys { it.startsWith("active-plan:") }.values.all {
            it.length <= AgentActivePlanPersistence.PAGE_CHARS
        })
    }

    @Test fun toolArgumentsAndRollbackRemainLosslessAcrossChunkBoundaries() {
        val storage = MemoryStorage()
        val original = snapshot(1)
        val text = ("\u0000\"\\\u4e2d\uD83D\uDE80").repeat(12000)
        val action = original.currentPlan!!.actions.single().copy(description = text,
            parameters = (0..90).associate { "param-$it" to "value-$it" } + ("input_json" to text), result = text, evidence = text)
        val plan = original.currentPlan.copy(actions = listOf(action), checkpoints = listOf(
            original.currentPlan.checkpoints.single().copy(rollbackAction = action)))
        val store = SharedPreferencesAgentSessionStore(storage)
        store.save(original.copy(currentPlan = plan))
        assertEquals(plan.actions, store.load()!!.currentPlan!!.actions)
        assertEquals(plan.checkpoints, store.load()!!.currentPlan!!.checkpoints)
    }

    @Test fun rootFailureKeepsPreviousRevisionAndItsPages() {
        val storage = MemoryStorage()
        val store = SharedPreferencesAgentSessionStore(storage)
        val first = snapshot(90)
        store.save(first)
        storage.failKey = "session"
        assertThrows(IllegalStateException::class.java) { store.save(snapshot(130)) }
        assertEquals(first.currentPlan!!.actions, store.load()!!.currentPlan!!.actions)
    }

    @Test fun pageFailureNeverPublishesPartialGraph() {
        val storage = MemoryStorage()
        val store = SharedPreferencesAgentSessionStore(storage)
        val first = snapshot(1)
        store.save(first)
        storage.failPages = true
        assertThrows(IllegalStateException::class.java) { store.save(snapshot(150)) }
        assertEquals(first.currentPlan!!.actions, store.load()!!.currentPlan!!.actions)
    }

    @Test fun missingPagePausesWithConcreteErrorAndNoTruncatedExecutableFallback() {
        val storage = MemoryStorage()
        val store = SharedPreferencesAgentSessionStore(storage)
        store.save(snapshot(120))
        storage.values.remove(storage.values.keys.first { it.startsWith("active-plan:") })
        val restored = store.load()!!
        assertEquals(AgentPhase.PAUSED, restored.phase)
        assertNull(restored.currentPlan)
        assertEquals("true", restored.lastActionResult!!.metadata["active_plan_recovery_error"])
        assertTrue(restored.lastActionResult.message.contains("missing or invalid"))
    }

    @Test fun modifiedPageIsNotAccepted() {
        val storage = MemoryStorage()
        val store = SharedPreferencesAgentSessionStore(storage)
        store.save(snapshot(100))
        val key = storage.values.keys.first { it.startsWith("active-plan:") }
        storage.values[key] = storage.values.getValue(key).replaceFirst("node", "evil")
        assertNull(store.load()!!.currentPlan)
        assertTrue(store.load()!!.lastActionResult!!.message.contains("integrity"))
    }

    @Test fun sessionAndStorageScopeRejectAnotherRootReference() {
        val storage = MemoryStorage()
        val first = SharedPreferencesAgentSessionStore(storage)
        first.save(snapshot(2))
        storage.values["task:other"] = storage.values.getValue("session")
        val other = SharedPreferencesAgentSessionStore(storage, "task:other").load()!!
        assertNull(other.currentPlan)
        assertTrue(other.lastActionResult!!.message.contains("another session"))
        val root = JSONObject(storage.values.getValue("session")).put("session_id", "other")
        storage.values["session"] = root.toString()
        assertNull(first.load()!!.currentPlan)
    }

    @Test fun changedRootRevisionCannotSelectUnrelatedGraph() {
        val storage = MemoryStorage()
        val store = SharedPreferencesAgentSessionStore(storage)
        store.save(snapshot(2))
        val root = JSONObject(storage.values.getValue("session"))
        root.getJSONObject(AgentActivePlanPersistence.ROOT_KEY).put("revision", 999)
        storage.values["session"] = root.toString()
        assertTrue(store.load()!!.lastActionResult!!.message.contains("revision mismatch"))
    }

    @Test fun unchangedPlanReusesPagesAndReplacementCollectsObsoletePages() {
        val storage = MemoryStorage()
        val store = SharedPreferencesAgentSessionStore(storage)
        val original = snapshot(100)
        store.save(original)
        val writes = storage.pageWrites
        store.save(original)
        assertEquals(writes, storage.pageWrites)
        store.save(snapshot(1))
        assertEquals(1, storage.values.keys.count { it.startsWith("active-plan:") })
        store.clear()
        assertFalse(storage.values.keys.any { it.startsWith("active-plan:") })
        assertNull(store.load())
    }

    @Test fun legacyCheckpointLoadsWithoutFabricatingMissingNodes() {
        val storage = MemoryStorage()
        val store = SharedPreferencesAgentSessionStore(storage)
        storage.values["session"] = store.encodeSession(snapshot(4)).toString()
        assertEquals(4, store.load()!!.currentPlan!!.actions.size)
    }

    @Test fun deletedPlanDoesNotRestorePreviousGraph() {
        val storage = MemoryStorage()
        val store = SharedPreferencesAgentSessionStore(storage)
        store.save(snapshot(4))
        store.save(snapshot(4).copy(currentPlan = null))
        assertNull(store.load()!!.currentPlan)
        assertFalse(storage.values.keys.any { it.startsWith("active-plan:") })
    }

    @Test fun corruptTerminalPlanDoesNotReactivateCancelledTask() {
        val storage = MemoryStorage()
        val store = SharedPreferencesAgentSessionStore(storage)
        store.save(snapshot(4).copy(phase = AgentPhase.CANCELLED))
        storage.values.remove(storage.values.keys.first { it.startsWith("active-plan:") })
        assertEquals(AgentPhase.CANCELLED, store.load()!!.phase)
    }

    @Test fun failedDurableRootRemovalKeepsTheReferencedPagesReadable() {
        val storage = MemoryStorage()
        val store = SharedPreferencesAgentSessionStore(storage)
        val original = snapshot(100)
        store.save(original)
        storage.failRemoval = true
        assertThrows(IllegalStateException::class.java) { store.clear() }
        assertEquals(original.currentPlan!!.actions, store.load()!!.currentPlan!!.actions)
    }

    private fun snapshot(count: Int): AgentSessionSnapshot {
        val screen = ScreenContext(foregroundApp = "Test", pageTitle = "Test")
        val actions = (0 until count).map { index -> AgentAction("node-$index", AgentActionKind.CALL_NATIVE_TOOL,
            "test.read", AgentRisk.LOW, AgentActionStatus.PROPOSED, "Read $index",
            mapOf("input_json" to "{}", "depends_on" to if (index > 0) "node-${index - 1}" else ""),
            requiresConfirmation = false) }
        val plan = AgentPlan("\u4fdd\u5b58\u5b8c\u6574\u4efb\u52a1\u56fe", screen, emptyList(), actions, planId = "plan", revision = 3,
            checkpoints = actions.map { AgentExecutionContinuity.checkpointBefore(it, screen, 3) })
        return AgentSessionSnapshot("session-test", AgentPhase.EXECUTING, plan.goal, screen,
            plan, emptyList(), null, updatedAtMillis = 1000)
    }

    private class MemoryStorage : AgentSessionCheckpointStorage {
        val values = linkedMapOf<String, String>()
        var failKey = ""
        var failPages = false
        var pageWrites = 0
        var failRemoval = false
        override fun encodedValueLength(key: String) = values[key]?.length ?: 0
        override fun readString(key: String, defaultValue: String) = values[key] ?: defaultValue
        override fun writeString(key: String, value: String) {
            check(key != failKey && !(failPages && key.startsWith("active-plan:"))) { "Injected checkpoint write failure" }
            if (key.startsWith("active-plan:")) pageWrites++
            values[key] = value
        }
        override fun remove(key: String) { values.remove(key) }
        override fun removeRoot(key: String) {
            check(!failRemoval) { "Injected durable removal failure" }
            remove(key)
        }
        override fun keys() = values.keys.toSet()
    }
}
