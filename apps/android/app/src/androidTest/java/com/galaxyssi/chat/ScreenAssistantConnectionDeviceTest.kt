package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class ScreenAssistantConnectionDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun connectionRefreshRetainsTheSettingsDestinationAcrossEventsAndResume() {
        ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)).use { scenario ->
            scenario.onActivity {
                it.openControlCenterDestination(ControlCenterDestination(ControlCenterRoute.SCREEN_ASSISTANT))
            }
            repeat(3) {
                ScreenAssistantConnection.changed()
                instrumentation.waitForIdleSync()
                scenario.onActivity { activity ->
                    assertEquals(ControlCenterRoute.SCREEN_ASSISTANT, activity.controlCenterDestination?.route)
                }
            }
            scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
            scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
            scenario.onActivity {
                assertEquals(ControlCenterRoute.SCREEN_ASSISTANT, it.controlCenterDestination?.route)
            }
        }
    }

    @Test fun disconnectedSettingsHaveARecoveryActionAndNeverClaimTheIconIsVisible() {
        val rows = screenAssistantSettingsSpec(context, ScreenAssistantAccessState.DISCONNECTED, true)
            .sections.single().rows
        assertEquals(true, rows.first().switchValue)
        assertEquals(context.getString(R.string.screen_assistant_disconnected), rows.first().subtitle)
        assertEquals("screen_assistant.reconnect", rows.last().actionId)
        assertEquals(context.getString(R.string.screen_assistant_reconnect), rows.last().title)
    }

    @Test fun missingPermissionAndDisabledAreDifferentStates() {
        val missing = screenAssistantSettingsSpec(context, ScreenAssistantAccessState.PERMISSION_REQUIRED, true)
            .sections.single().rows
        assertEquals(true, missing.first().switchValue)
        assertEquals(context.getString(R.string.screen_assistant_permission), missing.last().title)
        val disabled = screenAssistantSettingsSpec(context, ScreenAssistantAccessState.DISABLED, true)
            .sections.single().rows
        assertEquals(1, disabled.size)
        assertEquals(false, disabled.single().switchValue)
    }

    @Test fun connectedOrUnsupportedDoesNotOfferRedundantAuthorization() {
        val connected = screenAssistantSettingsSpec(context, ScreenAssistantAccessState.CONNECTED, true)
            .sections.single().rows
        assertEquals(1, connected.size)
        assertEquals(context.getString(R.string.screen_assistant_enabled_summary), connected.single().subtitle)
        val unsupported = screenAssistantSettingsSpec(context, ScreenAssistantAccessState.PERMISSION_REQUIRED, false)
            .sections.single().rows
        assertEquals(1, unsupported.size)
        assertFalse(unsupported.single().enabled)
    }

    @Test fun creatingOrUnbindingAnotherServiceDoesNotPublishAFalseConnection() {
        instrumentation.runOnMainSync {
            val connected = GalaxySSIAccessibilityService.targetService()
            val unbound = GalaxySSIAccessibilityService()
            unbound.onCreate()
            assertSame(connected, GalaxySSIAccessibilityService.targetService())
            unbound.onUnbind(Intent())
            assertSame(connected, GalaxySSIAccessibilityService.targetService())
        }
    }

    @Test fun checkingAccessDoesNotEraseUserIntentOrPendingTaskPreferences() {
        val name = "screen_connection_test_" + UUID.randomUUID()
        val isolated = object : ContextWrapper(context) {
            override fun getSharedPreferences(key: String, mode: Int) = context.getSharedPreferences(name, mode)
        }
        val prefs = isolated.getSharedPreferences("screen_assistant_v1", Context.MODE_PRIVATE)
        try {
            prefs.edit().putBoolean("enabled", true).putString("conversation", "preserved")
                .putString("last_turn", "unchanged").commit()
            val before = prefs.all.toMap()
            ScreenAssistantSettings.accessState(isolated)
            assertEquals(before, prefs.all)
        } finally { context.deleteSharedPreferences(name) }
    }

    @Test fun connectionEventsNotifyOnceWithoutPolling() {
        var calls = 0
        val listener: () -> Unit = { calls++ }
        try {
            instrumentation.runOnMainSync {
                ScreenAssistantConnection.addListener(listener)
                ScreenAssistantConnection.addListener(listener)
                ScreenAssistantConnection.changed()
            }
            instrumentation.waitForIdleSync()
            assertEquals(1, calls)
        } finally { ScreenAssistantConnection.removeListener(listener) }
    }

    @Test fun leavingSettingsCancelsQueuedUiCallbacks() {
        var calls = 0
        val listener: () -> Unit = { calls++ }
        instrumentation.runOnMainSync {
            ScreenAssistantConnection.addListener(listener)
            ScreenAssistantConnection.changed()
            ScreenAssistantConnection.removeListener(listener)
        }
        instrumentation.waitForIdleSync()
        assertEquals(0, calls)
    }
}
