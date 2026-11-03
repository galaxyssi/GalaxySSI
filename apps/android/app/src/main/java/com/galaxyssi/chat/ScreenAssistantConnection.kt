package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import java.util.concurrent.CopyOnWriteArraySet

internal enum class ScreenAssistantAccessState {
    DISABLED, PERMISSION_REQUIRED, DISCONNECTED, CONNECTED;

    companion object {
        fun resolve(enabled: Boolean, authorized: Boolean, connected: Boolean): ScreenAssistantAccessState = when {
            !enabled -> DISABLED
            connected -> CONNECTED
            !authorized -> PERMISSION_REQUIRED
            else -> DISCONNECTED
        }
    }
}

internal object ScreenAssistantConnection {
    private val handler by lazy { Handler(Looper.getMainLooper()) }
    private val listeners = CopyOnWriteArraySet<() -> Unit>()

    fun addListener(listener: () -> Unit) { listeners.add(listener) }
    fun removeListener(listener: () -> Unit) { listeners.remove(listener) }

    fun changed() {
        listeners.forEach { listener ->
            handler.post { if (listener in listeners) listener() }
        }
    }

    fun openSystemSettings(activity: Activity) {
        // Only Android can bind this service. Never rewrite the user's secure settings.
        activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
    }
}

internal fun screenAssistantSettingsSpec(
    context: Context,
    state: ScreenAssistantAccessState,
    available: Boolean
): ControlCenterPageSpec {
    val enabled = state != ScreenAssistantAccessState.DISABLED
    val summary = when (state) {
        ScreenAssistantAccessState.DISABLED -> R.string.screen_assistant_disabled_summary
        ScreenAssistantAccessState.PERMISSION_REQUIRED -> R.string.screen_assistant_permission_required
        ScreenAssistantAccessState.DISCONNECTED -> R.string.screen_assistant_disconnected
        ScreenAssistantAccessState.CONNECTED -> R.string.screen_assistant_enabled_summary
    }
    val rows = mutableListOf(ControlCenterRowSpec(
        actionId = "screen_assistant.toggle",
        title = context.getString(R.string.screen_assistant_enable),
        subtitle = context.getString(summary),
        iconRes = R.drawable.ic_agent_screen,
        switchValue = enabled,
        showChevron = false,
        enabled = available
    ))
    if (available && enabled && state != ScreenAssistantAccessState.CONNECTED) {
        rows += ControlCenterRowSpec(
            actionId = "screen_assistant.reconnect",
            title = context.getString(if (state == ScreenAssistantAccessState.DISCONNECTED)
                R.string.screen_assistant_reconnect else R.string.screen_assistant_permission),
            subtitle = context.getString(if (state == ScreenAssistantAccessState.DISCONNECTED)
                R.string.screen_assistant_reconnect_summary else R.string.screen_assistant_permission_summary),
            iconRes = R.drawable.ic_agent_screen
        )
    }
    return ControlCenterPageSpec(
        sections = listOf(ControlCenterSectionSpec("", rows)),
        footer = context.getString(R.string.screen_assistant_privacy_note)
    )
}
