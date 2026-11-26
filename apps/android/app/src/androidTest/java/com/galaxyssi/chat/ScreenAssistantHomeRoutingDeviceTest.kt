package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Isolated preference namespace; no user selection or real Agent requests are changed. */
@RunWith(AndroidJUnit4::class)
class ScreenAssistantHomeRoutingDeviceTest {
    private val codex = AgentCallableTarget("test:codex", "Codex", AgentConnectorKind.AGENT,
        AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.CHAT, AgentCapability.REASONING))
    private val cloud = codex.copy(id = "cloud:deepseek", title = "DeepSeek", kind = AgentConnectorKind.MODEL)
    private val targets = listOf(cloud, codex)

    @Test fun newUserConversationSnapshotsTheRememberedTargetModelAndEffort() = isolated { context ->
        val app = object : ContextWrapper(context) {
            override fun getApplicationContext(): Context = this
        }
        val store = AgentTranscriptStore(app, "remember-model-${UUID.randomUUID()}")
        val ids = mutableListOf<String>()
        try {
            val initial = store.createConversation("Initial fixture").id.also(ids::add)
            assertEquals(AgentModelSelection(), AgentModelSelectionSettings.selection(app, initial))
            manual(app, initial, codex)
            AgentModelSelectionSettings.updateAgentConfiguration(app, initial, "gpt-6-astra", AgentModelReasoningEffort.XHIGH)
            val remembered = AgentModelSelectionSettings.selection(app, initial)
            val next = store.createConversation("Next fixture").id.also(ids::add)
            assertEquals(remembered, AgentModelSelectionSettings.selection(app, next))
            assertEquals(AgentTargetConfiguration("gpt-6-astra", AgentModelReasoningEffort.XHIGH),
                AgentModelSelectionSettings.configurationForTarget(app, next, codex.id))

            val programmatic = store.createAgentConversation("Independently routed fixture").id.also(ids::add)
            assertEquals(AgentModelSelection(), AgentModelSelectionSettings.selection(app, programmatic))
            manual(app, programmatic, cloud, remember = false)
            assertEquals(remembered, AgentModelSelectionSettings.defaultSelection(app))

            AgentModelSelectionSettings.selectAuto(app, next)
            val afterAuto = store.createConversation("Auto fixture").id.also(ids::add)
            assertEquals(AgentModelSelection(), AgentModelSelectionSettings.selection(app, afterAuto))
            assertEquals(remembered, AgentModelSelectionSettings.selection(app, initial))
        } finally {
            ids.asReversed().forEach(store::deleteConversation)
        }
    }

    @Test fun changingTheRememberedSelectionDoesNotOverwriteExistingChats() = isolated { context ->
        manual(context, "first", codex)
        AgentModelSelectionSettings.initializeConversation(context, "second", useRememberedSelection = true)
        manual(context, "third", cloud)
        AgentModelSelectionSettings.initializeConversation(context, "fourth", useRememberedSelection = true)
        assertEquals(codex.id, AgentModelSelectionSettings.selection(context, "second").targetId)
        assertEquals(cloud.id, AgentModelSelectionSettings.selection(context, "fourth").targetId)
        AgentModelSelectionSettings.selectAutoForConversation(context, "fourth")
        assertEquals(cloud.id, AgentModelSelectionSettings.defaultSelection(context).targetId)
    }

    @Test fun currentManualCodexWinsOverOldDefaultAndPreservesModelEffort() = isolated { context ->
        manual(context, "previous-default", cloud)
        manual(context, "home", codex, remember = false)
        val route = ScreenAssistantHomeRouting.capture(context, "home", targets)
        ScreenAssistantHomeRouting.apply(context, "screen", route)
        val actual = AgentModelSelectionSettings.selection(context, "screen")
        assertEquals(codex.id, actual.targetId)
        assertEquals("gpt-6-sol", actual.modelId)
        assertEquals(AgentModelReasoningEffort.HIGH, actual.reasoningEffort)
        assertEquals(AgentModelSelectionSettings.selection(context, "home"), actual)
    }

    @Test fun currentManualCloudRemainsCloudDespiteNewCodexDefault() = isolated { context ->
        manual(context, "home", cloud, remember = false)
        ScreenAssistantHomeRouting.apply(context, "screen", ScreenAssistantHomeRouting.capture(context, "home", targets))
        assertEquals(cloud.id, AgentModelSelectionSettings.selection(context, "screen").targetId)
    }

    @Test fun currentAutoCodexReplacesScreenConversationsOldCloudPreference() = isolated { context ->
        auto(context, "home", codex)
        auto(context, "screen", cloud)
        ScreenAssistantHomeRouting.apply(context, "screen", ScreenAssistantHomeRouting.capture(context, "home", targets))
        assertEquals(AgentModelSelectionMode.AUTO, AgentModelSelectionSettings.selection(context, "screen").mode)
        assertEquals(codex.id, AgentStableAutoRouteStore.target(context, "screen", targets)?.id)
        assertEquals(codex.id, AgentStableAutoRouteStore.target(context, "home", targets)?.id)
    }

    @Test fun currentAutoCloudAlsoFollowsHomeInsteadOfForcingCodex() = isolated { context ->
        auto(context, "home", cloud)
        ScreenAssistantHomeRouting.apply(context, "screen", ScreenAssistantHomeRouting.capture(context, "home", targets))
        assertEquals(cloud.id, AgentStableAutoRouteStore.target(context, "screen", targets)?.id)
    }

    @Test fun followUpCanRefreshHomeSelectionWithoutChangingAnotherConversation() = isolated { context ->
        manual(context, "other", cloud, remember = false)
        manual(context, "home", cloud, remember = false)
        ScreenAssistantHomeRouting.apply(context, "screen", ScreenAssistantHomeRouting.capture(context, "home", targets))
        manual(context, "home", codex, remember = false)
        ScreenAssistantHomeRouting.apply(context, "screen", ScreenAssistantHomeRouting.capture(context, "home", targets))
        assertEquals(codex.id, AgentModelSelectionSettings.selection(context, "screen").targetId)
        assertEquals(cloud.id, AgentModelSelectionSettings.selection(context, "other").targetId)
    }

    private fun manual(context: Context, scope: String, target: AgentCallableTarget, remember: Boolean = true) {
        AgentModelSelectionSettings.selectManual(context, scope, target.id,
            if (target == codex) "gpt-6-sol" else "deepseek-chat", target.title,
            AgentModelReasoningEffort.HIGH, rememberAsDefault = remember)
    }

    private fun auto(context: Context, scope: String, target: AgentCallableTarget) {
        AgentModelSelectionSettings.selectAutoForConversation(context, scope)
        AgentStableAutoRouteStore.beginTurn(context, scope, "turn-$scope")
        AgentStableAutoRouteStore.recordDispatch(context, scope, "turn-$scope", target.id)
    }

    private fun isolated(test: (Context) -> Unit) {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val prefix = "screen-route-test-${UUID.randomUUID()}-"
        val names = mutableSetOf<String>()
        val context = object : ContextWrapper(base) {
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
                val isolatedName = prefix + name
                names.add(isolatedName)
                return base.getSharedPreferences(isolatedName, mode)
            }
        }
        try { test(context) } finally { names.forEach { base.deleteSharedPreferences(it) } }
    }
}
