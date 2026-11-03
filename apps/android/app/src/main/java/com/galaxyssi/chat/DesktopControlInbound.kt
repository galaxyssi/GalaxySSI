package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import org.json.JSONObject

internal object DesktopControlInbound {
    fun dispatch(context: Context, payload: JSONObject, listeners: Iterable<GalaxySSIMqttClient.Listener>): Boolean {
        if (!DesktopRemoteControl.handleInbound(context, payload)) return false
        GalaxySSILinkDeliveryStore.completeIncoming(context, payload)
        val desktopId = payload.optString("desktop_id")
        if (desktopId.isBlank()) return true
        val streamFrame = payload.optString("type") == "desktop_action_receipt" &&
            payload.optJSONObject("output")?.optBoolean("stream_frame", false) == true
        // State is already applied. Notify the UI without routing screenshots into chat or replay.
        listeners.forEach { listener ->
            runCatching { listener.onDesktopControlChanged(desktopId, streamFrame) }
                .onFailure { Log.w("GalaxySSILink", "Desktop control UI update failed: ${it.javaClass.simpleName}") }
        }
        return true
    }
}
