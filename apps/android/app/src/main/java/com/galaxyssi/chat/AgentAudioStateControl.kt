package com.galaxyssi.chat

import kotlin.math.roundToInt

internal data class AgentAudioState(
    val volume: Int, val maximum: Int, val minimum: Int, val muted: Boolean,
    val observedAtMillis: Long
) {
    init {
        require(minimum >= 0 && maximum >= minimum && volume in 0..maximum)
        require(observedAtMillis > 0)
    }
}

internal interface AgentAudioControlPort {
    fun read(): AgentAudioState
    fun setVolume(value: Int)
    fun setMuted(value: Boolean)
}

/** Inspect before one mutation and read back after it; API acceptance is not state evidence. */
internal object AgentAudioStateControl {
    val streams = setOf("music", "ring", "alarm", "notification", "voice_call", "system")

    fun outputSchema(volume: Boolean) = AgentNativeJsonSchema.objectSchema(
        properties = mapOf(
            "stream" to AgentNativeJsonSchema.string(streams),
            "dispatch_attempted" to AgentNativeJsonSchema.boolean(),
            "request_accepted" to AgentNativeJsonSchema.boolean(),
            "state_verified" to AgentNativeJsonSchema.boolean(),
            "observation_scope" to AgentNativeJsonSchema.string(listOf("android_audio_stream")),
            "volume" to AgentNativeJsonSchema.integer(0),
            "max" to AgentNativeJsonSchema.integer(0),
            "min" to AgentNativeJsonSchema.integer(0),
            "muted" to AgentNativeJsonSchema.boolean(),
            "observed_at_epoch_millis" to AgentNativeJsonSchema.integer(1),
            "dispatch_error" to AgentNativeJsonSchema.string(),
            "observation_error" to AgentNativeJsonSchema.string(),
            "state_constraint" to AgentNativeJsonSchema.string()
        ) + if (volume) mapOf("requested_percent" to AgentNativeJsonSchema.integer(0, 100),
            "target_volume" to AgentNativeJsonSchema.integer(0))
            else mapOf("requested_muted" to AgentNativeJsonSchema.boolean()),
        required = setOf("stream", "dispatch_attempted", "request_accepted", "state_verified", "observation_scope") +
            if (volume) setOf("requested_percent", "target_volume") else setOf("requested_muted"),
        additionalProperties = false
    )

    fun volume(stream: String, percent: Int, port: AgentAudioControlPort): AgentNativeJsonObject {
        require(stream in streams && percent in 0..100)
        val before = port.read()
        val target = (percent / 100.0 * before.maximum).roundToInt()
        val supported = target >= before.minimum
        val request = mapOf("requested_percent" to percent, "target_volume" to target) +
            if (supported) emptyMap() else mapOf("state_constraint" to "requested_step_below_minimum")
        return change(stream, before, port, request, canMutate = supported,
            matches = { target >= it.minimum && it.volume == target &&
                it.maximum == before.maximum && it.minimum == before.minimum },
            mutate = { port.setVolume(target) })
    }

    fun mute(stream: String, muted: Boolean, port: AgentAudioControlPort): AgentNativeJsonObject {
        require(stream in streams)
        val before = port.read()
        return change(stream, before, port, mapOf("requested_muted" to muted),
            matches = { it.muted == muted }, mutate = { port.setMuted(muted) })
    }

    private fun change(stream: String, before: AgentAudioState, port: AgentAudioControlPort,
        request: AgentNativeJsonObject, canMutate: Boolean = true,
        matches: (AgentAudioState) -> Boolean, mutate: () -> Unit
    ): AgentNativeJsonObject {
        val needed = canMutate && !matches(before)
        val dispatch = if (needed) runCatching(mutate) else Result.success(Unit)
        // Even an API exception can follow an applied effect. Observe instead of blindly replaying it.
        val observation = if (needed) runCatching { port.read() } else Result.success(before)
        val observed = observation.getOrNull()
        return buildMap {
            putAll(request)
            put("stream", stream)
            put("dispatch_attempted", needed)
            put("request_accepted", needed && dispatch.isSuccess)
            put("state_verified", observed?.let(matches) == true)
            put("observation_scope", "android_audio_stream")
            observed?.let {
                put("volume", it.volume)
                put("max", it.maximum)
                put("min", it.minimum)
                put("muted", it.muted)
                put("observed_at_epoch_millis", it.observedAtMillis)
            }
            dispatch.exceptionOrNull()?.let { put("dispatch_error", it.javaClass.simpleName) }
            observation.exceptionOrNull()?.let { put("observation_error", it.javaClass.simpleName) }
        }
    }
}
