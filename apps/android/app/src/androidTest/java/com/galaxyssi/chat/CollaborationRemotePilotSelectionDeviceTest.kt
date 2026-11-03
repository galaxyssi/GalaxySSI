package com.galaxyssi.chat

import android.content.Context
import android.os.Build
import android.util.AtomicFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Creates a model-free experiment selection using the App's conversation-scoped API. */
@RunWith(AndroidJUnit4::class)
class CollaborationRemotePilotSelectionDeviceTest {
    @Test fun prepareConversationSelectionWithoutChangingDefaults() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("remotePilotPrepareSelection") == "true")
        CollaborationTrialDeviceBinding.requireOperatorTarget(Build.MODEL, args.getString("pilotDeviceModel"))
        val context = instrumentation.targetContext
        val selection = CollaborationLiveModelSelection.from(args.getString("remotePilotModel"), args.getString("remotePilotEffort"))
        val targetId = args.getString("remotePilotTarget").orEmpty()
        val target = requireNotNull(AppStoreAgentConnectorRegistry(context).availableTargets().singleOrNull { it.id == targetId })
        CollaborationLiveModelSelection.requireAvailable(target, selection.modelId, selection.reasoningEffort)
        val name = args.getString("remotePilotSelectionOutput").orEmpty()
        require(Regex("[a-zA-Z0-9_-]+\\.json").matches(name))
        val file = File(context.getExternalFilesDir(null), name)
        check(!File(file.path + ".bak").exists() && !File(file.path + ".new").exists() && file.createNewFile())
        val store = AgentTranscriptStore(context)
        val priorWindows = CollaborationPilotWindowSnapshot.read(context)
        val preferences = context.getSharedPreferences("galaxyssi_agent_model_selection_v2", Context.MODE_PRIVATE)
        val defaults = preferences.all.filterKeys { it.startsWith("default.") }
        val conversation = store.createAgentConversation("Remote pilot model selection")
        AgentModelSelectionSettings.selectManual(context, conversation.id, targetId, selection.modelId,
            target.title, selection.reasoningEffort, rememberAsDefault = false)
        // Instrumentation can exit immediately; wait for the App store's asynchronous writes.
        check(preferences.edit().commit()) { "Experiment selection was not durably saved" }
        store.append(AgentTranscriptRole.ASSISTANT, "Local experiment configuration only; no model request dispatched.",
            dedupeKey = "remote-pilot-selection", conversationId = conversation.id)
        val actual = AgentModelSelectionSettings.selection(context, conversation.id)
        assertEquals(AgentModelSelectionMode.MANUAL, actual.mode)
        assertEquals(targetId, actual.targetId)
        assertEquals(selection.modelId, actual.modelId)
        assertEquals(selection.reasoningEffort, actual.reasoningEffort)
        assertEquals(defaults, preferences.all.filterKeys { it.startsWith("default.") })
        assertEquals(priorWindows, CollaborationPilotWindowSnapshot.read(context))
        val value = JSONObject().put("selection_source", "app_conversation_snapshot")
            .put("device_model", Build.MODEL)
            .put("window_selections_preserved", true)
            .put("conversation_id", conversation.id).put("target_id", actual.targetId)
            .put("model_id", actual.modelId).put("reasoning_effort", actual.reasoningEffort.wireValue)
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try { stream.write(value.toString().toByteArray(Charsets.UTF_8)); atomic.finishWrite(stream) }
        catch (failure: Throwable) { atomic.failWrite(stream); throw failure }
    }

    @Test fun removeSelectionAfterConfirmedPilotCleanup() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("remotePilotCleanupSelection") == "true")
        CollaborationTrialDeviceBinding.requireOperatorTarget(Build.MODEL, args.getString("pilotDeviceModel"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        fun read(key: String): JSONObject {
            val name = args.getString(key).orEmpty()
            require(Regex("[a-zA-Z0-9_-]+\\.json").matches(name))
            val file = File(context.getExternalFilesDir(null), name)
            require(file.length() in 1..2_000_000)
            return JSONObject(file.readText())
        }
        val selection = read("remotePilotSelectionOutput")
        val report = read("remotePilotReport")
        require(selection.getString("selection_source") == "app_conversation_snapshot")
        require(report.getString("format") == "galaxyssi.remote-pilot-report.v1" && report.getBoolean("finished"))
        val id = selection.getString("conversation_id")
        require(id == report.getString("selection_conversation_id"))
        val slots = report.getJSONArray("slots")
        require(slots.length() >= 2)
        repeat(slots.length()) { index ->
            val slot = slots.getJSONObject(index)
            require(slot.getBoolean("cleanup_confirmed") && slot.getString("durable_control") == "STOP" &&
                slot.getJSONArray("pending_remote_owners").length() == 0)
        }
        val store = AgentTranscriptStore(context)
        require(store.conversation(id)?.title == "Remote pilot model selection")
        val preferences = context.getSharedPreferences("galaxyssi_agent_model_selection_v2", Context.MODE_PRIVATE)
        val defaults = preferences.all.filterKeys { it.startsWith("default.") }
        check(store.deleteConversation(id))
        check(preferences.edit().commit())
        assertEquals(defaults, preferences.all.filterKeys { it.startsWith("default.") })
        assertEquals(null, store.conversation(id))
    }
}
