package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import android.content.Context
import android.content.ContextWrapper
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentPlannerModelSnapshotDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun contact() = JSONObject().put("id", "fixture-provider").put("delivery_mode", "cloud_api")
        .put("cloud_provider", "test-provider").put("cloud_endpoint", "https://provider.invalid/v1")
        .put("cloud_model", "original-model").put("cloud_api_style", "openai")
        .put("cloud_api_key", "not-a-real-credential-original").put("setup_status", "ready")
    private fun settings() = AgentModelPlannerSettings(true, true, 11, "fixture-provider", true, 4, false,
        true, 7, 29, 19, 4, 333)
    private fun snapshot() = AgentPlannerModelSnapshot(settings(), AgentPlannerProviderRoute.capture(contact()))

    @Test fun capturedRouteDoesNotRetainCredentialsOrUnrelatedContactFields() {
        val source = contact().put("private_notes", "not-planning-input")
        val captured = AgentPlannerModelSnapshot(settings(), AgentPlannerProviderRoute.capture(source))
        val encoded = captured.toJson().toString()
        assertFalse(encoded.contains("not-a-real-credential"))
        assertFalse(encoded.contains("cloud_api_key"))
        assertFalse(encoded.contains("private_notes"))
        assertEquals(captured, AgentPlannerModelSnapshot.fromJson(JSONObject(encoded)))
    }

    @Test fun originalModelUsesRotatedCredentialWithoutChangingTheContact() {
        val saved = snapshot().route!!
        val current = contact().put("cloud_model", "new-task-model").put("cloud_api_key", "not-a-real-credential-rotated")
        val resolved = saved.resolve(current)
        assertEquals("original-model", resolved.getString("cloud_model"))
        assertEquals("not-a-real-credential-rotated", resolved.getString("cloud_api_key"))
        assertEquals("new-task-model", current.getString("cloud_model"))
    }

    @Test fun originalModelResolvesItsOwnEntryWhenAnotherModelUsesADifferentEndpoint() {
        val current = contact().put("cloud_model", "later-model").put("selected_cloud_model", "later-model")
            .put("cloud_endpoint", "https://later.invalid/v1").put("cloud_api_key", "later-model-credential")
            .put("cloud_models", JSONArray().put(modelEntry()).put(modelEntry().put("model_id", "later-model")
                .put("endpoint", "https://later.invalid/v1").put("api_key", "later-model-credential")))
        val resolved = snapshot().route!!.resolve(current)
        assertEquals("original-model", resolved.getString("cloud_model"))
        assertEquals("https://provider.invalid/v1", resolved.getString("cloud_endpoint"))
        assertEquals("original-model-rotated-credential", resolved.getString("cloud_api_key"))
        assertEquals("later-model", current.getString("selected_cloud_model"))
    }

    @Test fun missingOriginalEntryOrItsCredentialCannotBorrowFromAnotherModel() {
        val current = contact().put("cloud_models", JSONArray().put(modelEntry().put("model_id", "later-model")))
        rejected("model_unavailable") { snapshot().route!!.resolve(current) }
        current.put("cloud_models", JSONArray().put(modelEntry().put("api_key", "")))
        rejected("credentials_unavailable") { snapshot().route!!.resolve(current) }
    }

    @Test fun freezeCapturesSettingsOnceButNewTaskReadsNewSettings() {
        val prefix = "test-provider-settings-${UUID.randomUUID()}-"
        val isolated = object : ContextWrapper(context) {
            override fun getApplicationContext(): Context = this
            override fun getSharedPreferences(name: String, mode: Int) = context.getSharedPreferences(prefix + name, mode)
        }
        val store = AgentModelPlannerSettingsStore(isolated)
        try {
            val first = settings().copy(enabled = false)
            store.save(first)
            val source = GuardedModelAgentPlanner(context, settingsStore = store)
            val frozen = source.freezeForTask()
            store.save(first.copy(maxActions = 3))
            assertEquals(first, frozen.recoverySpec().modelSnapshot!!.settings)
            assertEquals(3, source.freezeForTask().recoverySpec().modelSnapshot!!.settings.maxActions)
        } finally { store.clear() }
    }

    @Test fun changedEndpointProviderIdentityAndProtocolDoNotReceiveOldTaskContext() {
        for ((key, value) in mapOf("id" to "another-contact", "cloud_provider" to "another-provider",
            "cloud_endpoint" to "https://another.invalid/v1", "cloud_api_style" to "anthropic",
            "delivery_mode" to "desktop")) {
            rejected("route_changed") { snapshot().route!!.resolve(contact().put(key, value)) }
        }
    }

    @Test fun removedContactDoesNotFallBackToAnAvailableProvider() {
        rejected("contact_unavailable") { snapshot().route!!.resolve(null) }
        rejected("contact_unavailable") { snapshot().route!!.resolve(contact().put("deleted", true)) }
    }

    @Test fun removedCredentialAndDisabledContactAreExplicitRecoveryFailures() {
        rejected("credentials_unavailable") { snapshot().route!!.resolve(contact().put("cloud_api_key", "")) }
        rejected("credentials_unavailable") { snapshot().route!!.resolve(contact().put("setup_status", "disabled")) }
    }

    @Test fun allPlannerSettingsAndNoProviderStateRoundTripWithoutDefaults() {
        val source = AgentPlannerModelSnapshot(settings(), null)
        assertEquals(source, AgentPlannerModelSnapshot.fromJson(JSONObject(source.toJson().toString())))
        val spec = GuardedModelAgentPlanner(context, modelSnapshot = source).recoverySpec()
        assertEquals(spec, spec.restore(context) { error("No tool execution") }.recoverySpec())
    }

    @Test fun encryptedPlanningJournalKeepsTheProviderAndEveryParameter() {
        val name = "test-provider-journal-${UUID.randomUUID()}"
        val ledger = AgentRunEventStore(context, "$name.db")
        try {
            val journal = AgentPlanningJournal(context, EncryptedAgentModelLoopJournal(context, ledger))
            val spec = GuardedModelAgentPlanner(context, modelSnapshot = snapshot()).recoverySpec()
            val input = AgentPlanningInput("\u6062\u590d\u539f\u4efb\u52a1", AgentConversationContext(name, "", emptyList(), true),
                name, emptyList(), AgentTaskExecutionMode.AUTO_COMPLETE, spec)
            lateinit var ref: AgentPlanningReference
            journal.begin(name, input) { ref = it }
            journal.restore(ref) { assertEquals(input, it) }
        } finally { ledger.close(); context.deleteDatabase("$name.db") }
    }

    @Test fun sessionRetainsTaskModelAfterPlanningReferenceIsClearedAndRuntimeIsRecreated() {
        val name = "test-provider-task-${UUID.randomUUID()}"
        val store = SharedPreferencesAgentSessionStore(context, name)
        val first = snapshot()
        val original = GuardedModelAgentPlanner(context, modelSnapshot = first).recoverySpec()
        val later = first.copy(settings = first.settings.copy(maxActions = 3), route = first.route!!.copy(model = "later-model"))
        try {
            val session = AgentSessionSnapshot(name, AgentPhase.OBSERVING, "\u539f\u4efb\u52a1",
                ScreenContext("Test", pageTitle = "Provider recovery"), null, emptyList(), null,
                updatedAtMillis = 1, taskPlannerSpec = original)
            store.save(session)
            assertNull(store.load()!!.pendingPlanning)
            assertEquals(original, store.load()!!.taskPlannerSpec)
            assertEquals(original, store.decodeSession(store.encodeRecoverySession(session, minimal = true)).taskPlannerSpec)
            val restored = runtime(name, store, later)
            assertEquals(original, restored.taskScopedPlanner().recoverySpec())
            restored.persistSession()
            assertEquals(original, store.load()!!.taskPlannerSpec)
            restored.startNewConversation("$name-new")
            assertNull(store.load()!!.taskPlannerSpec)
            assertEquals(later, restored.taskScopedPlanner().recoverySpec()!!.modelSnapshot)
            restored.cancelCurrentTask()
            assertNull(store.load()!!.taskPlannerSpec)
            // New task state must use the newly selected model, not a process-wide cached binding.
            store.clear()
            assertEquals(later, runtime(name, store, later).taskScopedPlanner().recoverySpec()!!.modelSnapshot)
        } finally { store.clear() }
    }

    @Test fun changedSnapshotCannotReuseTheOriginalConfigurationHash() {
        val original = GuardedModelAgentPlanner(context, modelSnapshot = snapshot()).recoverySpec()
        val modified = original.copy(modelSnapshot = snapshot().copy(route = snapshot().route!!.copy(model = "another-model")))
        rejected("configuration_changed") { modified.restore(context) { error("No tools") } }
    }

    private fun runtime(name: String, store: AgentSessionStore, selected: AgentPlannerModelSnapshot) =
        MobileNativeAgent(context, planner = GuardedModelAgentPlanner(context, modelSnapshot = selected), sessionStore = store,
            memoryStore = InMemoryAgentMemoryStore(), taskStore = SQLiteAgentTaskStore(context, "$name-tasks.db"),
            knowledgeStore = SQLiteAgentKnowledgeStore(context, "$name-knowledge.db", "$name-legacy") { _, _ -> },
            screenObservationOverride = false, perceptionProvider = object : ScreenPerceptionProvider {
                override fun capture() = ScreenContext("Test", pageTitle = "Provider recovery")
                override fun capture(foregroundApp: String, pageTitle: String) = capture()
            }, connectorRegistry = object : AgentConnectorRegistry {
                override fun availableTargets() = emptyList<AgentCallableTarget>()
            }, actionExecutor = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult = error("No execution")
            })

    private fun rejected(code: String, block: () -> Unit) {
        try { block(); fail("Expected $code") }
        catch (error: AgentModelLoopRecoveryException) { assertTrue(error.message.orEmpty().contains(code)) }
    }

    private fun modelEntry() = JSONObject().put("model_id", "original-model")
        .put("endpoint", "https://provider.invalid/v1").put("api_style", "openai")
        .put("api_key", "original-model-rotated-credential")
}
