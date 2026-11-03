package com.galaxyssi.chat

import org.json.JSONObject
import java.util.ArrayDeque
import java.util.UUID

data class DesktopInputFocus(val available: Boolean, val editable: Boolean, val password: Boolean,
    val targetId: String, val left: Int, val top: Int, val width: Int, val height: Int)

data class DesktopInputResult(val actionId: String, val succeeded: Boolean,
    val focus: DesktopInputFocus?, val error: String) {
    companion object {
        fun fromReceipt(receipt: JSONObject): DesktopInputResult {
            val focus = receipt.optJSONObject("output")?.optJSONObject("input_focus")
            val bounds = focus?.optJSONObject("bounds")
            return DesktopInputResult(receipt.optString("action_id"), receipt.optString("status") == "succeeded",
                focus?.let { DesktopInputFocus(it.optBoolean("available"), it.optBoolean("editable"),
                    it.optBoolean("password"), it.optString("target_id"), bounds?.optInt("left") ?: 0,
                    bounds?.optInt("top") ?: 0, bounds?.optInt("width") ?: 0, bounds?.optInt("height") ?: 0) },
                receipt.optJSONObject("error")?.optString("message").orEmpty())
        }
    }
}

internal data class DesktopInputCommand(val tool: String, val input: JSONObject,
    val id: String = UUID.randomUUID().toString())

/** Keep input in order; never replay an uncertain keystroke after a timeout or reconnect. */
internal class DesktopInputQueue {
    private val pending = ArrayDeque<DesktopInputCommand>()
    var active: DesktopInputCommand? = null
        private set

    fun add(command: DesktopInputCommand): Boolean {
        if (pending.size >= 128) return false
        pending.addLast(command)
        return true
    }

    fun next(): DesktopInputCommand? {
        if (active != null) return null
        return pending.pollFirst()?.also { active = it }
    }

    fun complete(result: DesktopInputResult): Boolean {
        if (active?.id != result.actionId) return false
        active = null
        if (!result.succeeded) pending.clear()
        return true
    }

    fun clear() { pending.clear(); active = null }
}

/** Receipts must survive intervening screenshot events until the UI consumes them. */
internal class DesktopInputMailbox {
    private data class Entry(val desktopId: String, var result: DesktopInputResult? = null)
    private val entries = mutableMapOf<String, Entry>()
    @Synchronized fun register(desktopId: String, actionId: String) {
        entries[actionId] = Entry(desktopId)
    }
    @Synchronized fun record(desktopId: String, result: DesktopInputResult) {
        entries[result.actionId]?.takeIf { it.desktopId == desktopId }?.result = result
    }
    @Synchronized fun consume(actionId: String): DesktopInputResult? {
        val result = entries[actionId]?.result ?: return null
        entries.remove(actionId)
        return result
    }
    @Synchronized fun clear(desktopId: String) { entries.entries.removeAll { it.value.desktopId == desktopId } }
}
