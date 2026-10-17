package com.galaxyssi.chat

import kotlin.math.roundToInt

/** One presentation/evidence contract for device mutations, including restored unverified receipts. */
internal object AgentDeviceStateEvidence {
    val tools = setOf(AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET,
        AgentAndroidSystemNativeTools.AUDIO_MUTE_SET, AgentHardwareNativeTools.FLASHLIGHT_SET)

    fun normalize(toolId: String, output: AgentNativeJsonObject, zh: Boolean): AgentNativeJsonObject {
        if (toolId !in tools) return output
        val verified = verified(toolId, output)
        val accepted = output["request_accepted"] == true
        val prior = output["metadata"] as? Map<*, *> ?: emptyMap<Any, Any>()
        val metadata = prior + mapOf(
            "goal_status" to if (verified) "verified" else if (accepted) "dispatched" else "unknown",
            "business_success_verified" to verified.toString(),
            "goal_evidence" to if (verified) "observed_device_state" else "device_state_unverified",
            "next_action" to if (verified) "" else if (toolId == AgentHardwareNativeTools.FLASHLIGHT_SET)
                "observe_torch_state_before_retrying" else "inspect_audio_status_before_retrying"
        ) + if (!verified && toolId == AgentHardwareNativeTools.FLASHLIGHT_SET)
            mapOf("required_capability" to "torch_state_observation") else emptyMap<String, String>()
        return output + mapOf("state_verified" to verified, "message" to message(toolId, output, verified, zh),
            "metadata" to metadata)
    }

    fun verified(toolId: String, output: AgentNativeJsonObject): Boolean {
        if (output["state_verified"] != true || (output["observed_at_epoch_millis"] as? Number)?.toLong()?.let { it > 0 } != true)
            return false
        return when (toolId) {
            AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET -> output["stream"] in AgentAudioStateControl.streams &&
                (output["volume"] as? Number)?.toInt()?.let { actual ->
                    val maximum = (output["max"] as? Number)?.toInt() ?: return false
                    val minimum = (output["min"] as? Number)?.toInt() ?: return false
                    actual in minimum..maximum && minimum >= 0 &&
                        actual == (output["target_volume"] as? Number)?.toInt()
                } == true
            AgentAndroidSystemNativeTools.AUDIO_MUTE_SET -> output["stream"] in AgentAudioStateControl.streams &&
                output["muted"] is Boolean && output["muted"] == output["requested_muted"]
            AgentHardwareNativeTools.FLASHLIGHT_SET -> output["observed_enabled"] is Boolean &&
                output["observed_enabled"] == output["requested_enabled"]
            else -> false
        }
    }

    private fun message(toolId: String, output: AgentNativeJsonObject, verified: Boolean, zh: Boolean): String {
        if (!verified) return if (zh) "\u8bbe\u7f6e\u5c1a\u672a\u786e\u8ba4\u751f\u6548\uff0c\u9700\u8981\u68c0\u67e5\u5b9e\u9645\u72b6\u6001\u3002"
            else "The requested setting is not confirmed; inspect the actual state before retrying."
        return when (toolId) {
            AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET -> {
                val volume = (output["volume"] as Number).toInt()
                val maximum = (output["max"] as Number).toInt()
                val percent = if (maximum > 0) (volume * 100.0 / maximum).roundToInt() else 0
                val name = streamName(output["stream"].toString(), zh)
                if (zh) "$name\u97f3\u91cf\u5df2\u8bbe\u4e3a $percent%\u3002" else "$name volume is now $percent%."
            }
            AgentAndroidSystemNativeTools.AUDIO_MUTE_SET -> {
                val name = streamName(output["stream"].toString(), zh)
                val muted = output["muted"] == true
                if (zh) "$name\u5df2${if (muted) "\u9759\u97f3" else "\u53d6\u6d88\u9759\u97f3"}\u3002"
                else "$name is ${if (muted) "muted" else "unmuted"}."
            }
            else -> if (zh) "\u624b\u7535\u7b52\u72b6\u6001\u5df2\u786e\u8ba4\u3002" else "Flashlight state verified."
        }
    }

    private fun streamName(stream: String, zh: Boolean): String = if (!zh) stream else when (stream) {
        "ring" -> "\u94c3\u58f0"
        "alarm" -> "\u95f9\u949f"
        "notification" -> "\u901a\u77e5"
        "voice_call" -> "\u901a\u8bdd"
        "system" -> "\u7cfb\u7edf"
        else -> "\u5a92\u4f53"
    }
}
