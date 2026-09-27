package com.galaxyssi.chat

import android.content.Intent
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Explicitly invoked acceptance test; uses the configured home Agent on disposable UI. */
@RunWith(AndroidJUnit4::class)
class PhoneAssistantLiveDeviceTest {
    @Test fun configuredHomeAgentInspectsClicksAndTypesOnThePhone() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        SystemClock.sleep(3_000)
        val deadline = SystemClock.elapsedRealtime() + 30_000
        while (!GalaxySSIAccessibilityService.isActive() && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(100)
        val service = requireNotNull(GalaxySSIAccessibilityService.targetService())
        instrumentation.startActivitySync(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val initialized = SystemClock.elapsedRealtime() + 30_000
        while (AgentConversationWindows.screenAssistantRunner() == null && SystemClock.elapsedRealtime() < initialized) SystemClock.sleep(100)
        val runner = requireNotNull(AgentConversationWindows.screenAssistantRunner()) { "Main runtime did not initialize" }
        val store = runner.agentTranscriptStore
        val oldActive = store.activeConversation().id
        val oldConversation = ScreenAssistantSettings.conversation(context)
        val oldTurn = ScreenAssistantSettings.lastTurn(context)
        val testConversation = store.createAgentConversation("Phone control acceptance fixture")
        ScreenAssistantSettings.saveConversation(context, testConversation.id)
        val overlay = ScreenAssistantOverlay(service)
        var turn = ""
        var attempt: ScreenAssistantAnalysisRequest? = null
        try {
            instrumentation.context.startActivity(Intent().setClassName(instrumentation.context.packageName,
                PhoneUiFixtureActivity::class.java.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
            SystemClock.sleep(1_000)
            instrumentation.runOnMainSync {
                val goal = service.getString(R.string.screen_assistant_phone_goal,
                    "Inspect the current test App, click only the button labeled Fixture click, then put Fixture live in the field labeled Fixture input. Verify both the text Fixture clicked and the field value Fixture live, then finish. Use only these two named controls and do not open other Apps.")
                ScreenAssistantOverlay::class.java.getDeclaredMethod("startPhoneTask", String::class.java)
                    .apply { isAccessible = true }.invoke(overlay, goal)
                attempt = ScreenAssistantOverlay::class.java.getDeclaredField("request")
                    .apply { isAccessible = true }.get(overlay) as? ScreenAssistantAnalysisRequest
                if (ScreenAssistantSettings.conversation(context) == testConversation.id) {
                    ScreenAssistantSettings.saveConversation(context, oldConversation)
                }
                if (store.activeConversation().id == testConversation.id) store.switchConversation(oldActive)
            }
            val ownedRequest = requireNotNull(attempt) { "The fixture task was not submitted" }
            val limit = SystemClock.elapsedRealtime() + 600_000
            var verified = false
            while (SystemClock.elapsedRealtime() < limit) {
                turn = ownedRequest.turnId
                val snapshot = GalaxySSIAccessibilityService.readTargetUi()
                check(snapshot == null || snapshot.packageName == instrumentation.context.packageName) {
                    "The user left the fixture; stop only this acceptance task"
                }
                verified = snapshot?.nodes?.any { it.text == "Fixture clicked" } == true && snapshot.nodes.any { it.text == "Fixture live" }
                val workspace = turn.takeIf { it.isNotBlank() }?.let { AgentTaskRuntime.supervisor(context).findWorkspace(it) }
                if (verified && workspace?.status?.isTerminal == true) break
                if (workspace?.status in setOf(AgentWorkspaceStatus.FAILED, AgentWorkspaceStatus.CANCELLED)) break
                SystemClock.sleep(250)
            }
            val result = AgentTaskRuntime.supervisor(context).findWorkspace(turn)
            val targets = AppStoreAgentConnectorRegistry(context).planningSnapshot().targets.joinToString {
                "${it.id}:${it.status}:${it.capabilities}"
            }
            val routes = result?.currentPlanSnapshot?.take(1000)
            val nativeFailures = runner.agentRuntimeTurnIds.entries.firstOrNull { it.value == turn }
                ?.key?.snapshot()?.plan?.let { it.actionHistory + it.actions }
                ?.filter { it.kind == AgentActionKind.CALL_NATIVE_TOOL && it.status == AgentActionStatus.FAILED }
                ?.joinToString { "${it.parameters["tool_id"]}:${it.result.take(500)}" }
            assertTrue("Home Agent did not verify UI mutations; turn=$turn status=${result?.status} error=${result?.errorMessage} targets=$targets routes=$routes nativeFailures=$nativeFailures result=${result?.resultJson?.take(1000)}", verified)
            assertEquals(AgentWorkspaceStatus.COMPLETED, AgentTaskRuntime.supervisor(context).findWorkspace(turn)?.status)
        } finally {
            attempt?.cancel()
            val ownedTurns = attempt?.turnIds.orEmpty()
            ownedTurns.forEach { ownedTurn ->
                ScreenAssistantTaskCancellation.cancel(context, testConversation.id, ownedTurn, runner)
                PhoneAssistantTaskControl.finish(ownedTurn)
            }
            instrumentation.runOnMainSync { overlay.close() }
            val restoreActive = store.activeConversation().id == testConversation.id
            store.deleteConversation(testConversation.id)
            if (restoreActive) store.switchConversation(oldActive)
            if (ScreenAssistantSettings.conversation(context) == testConversation.id) {
                ScreenAssistantSettings.saveConversation(context, oldConversation)
            }
            if (ScreenAssistantSettings.lastTurn(context) in ownedTurns) {
                ScreenAssistantSettings.saveLastTurn(context, oldTurn)
            }
        }
    }
}
