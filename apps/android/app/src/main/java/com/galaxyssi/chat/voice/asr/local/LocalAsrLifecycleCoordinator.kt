package com.galaxyssi.chat.voice.asr.local

class LocalAsrLifecycleCoordinator(
    private val engine: LocalAsrEngine,
    private val autoResumeAfterTransientInterruption: Boolean = true
) {
    private val lock = Any()
    private val blockers = linkedSetOf<LocalAsrPauseReason>()
    private var resumeEligible = false

    fun onAppForegroundChanged(foreground: Boolean) = updateTransient(
        LocalAsrPauseReason.APP_BACKGROUND,
        active = !foreground
    )

    fun onPhoneCallChanged(inCall: Boolean) = updateTransient(LocalAsrPauseReason.PHONE_CALL, inCall)

    fun onAudioFocusChanged(hasFocus: Boolean) = updateTransient(
        LocalAsrPauseReason.AUDIO_FOCUS_LOST,
        active = !hasFocus
    )

    fun onThermalLimitChanged(limited: Boolean) = updateTransient(LocalAsrPauseReason.THERMAL_LIMIT, limited)

    fun onMicrophonePermissionChanged(granted: Boolean) {
        if (!granted) {
            synchronized(lock) {
                blockers += LocalAsrPauseReason.MICROPHONE_PERMISSION_REVOKED
                resumeEligible = false
            }
            engine.cancel()
            return
        }
        synchronized(lock) { blockers -= LocalAsrPauseReason.MICROPHONE_PERMISSION_REVOKED }
    }

    fun activeBlockers(): Set<LocalAsrPauseReason> = synchronized(lock) { blockers.toSet() }

    private fun updateTransient(reason: LocalAsrPauseReason, active: Boolean) {
        val action = synchronized(lock) {
            if (active) {
                val first = blockers.isEmpty()
                if (!blockers.add(reason)) return@synchronized Action.NO_OP
                if (first && engine.state.value.let {
                        it is LocalAsrState.Listening || it is LocalAsrState.Starting
                    }
                ) resumeEligible = true
                Action.PAUSE
            } else {
                if (!blockers.remove(reason)) return@synchronized Action.NO_OP
                if (blockers.isEmpty() && resumeEligible && autoResumeAfterTransientInterruption) {
                    resumeEligible = false
                    Action.RESUME
                } else Action.REMOVE_ONLY
            }
        }
        when (action) {
            Action.PAUSE -> engine.pause(reason)
            Action.RESUME -> engine.resume(reason)
            Action.REMOVE_ONLY -> engine.resume(reason)
            Action.NO_OP -> Unit
        }
    }

    private enum class Action {
        PAUSE,
        RESUME,
        REMOVE_ONLY,
        NO_OP
    }
}

class LocalAsrEngineRegistry(
    private val factory: () -> LocalAsrEngine
) : AutoCloseable {
    private val lock = Any()
    private var engine: LocalAsrEngine? = null

    fun get(): LocalAsrEngine = synchronized(lock) {
        engine ?: factory().also { engine = it }
    }

    override fun close() {
        val current = synchronized(lock) {
            engine.also { engine = null }
        }
        current?.close()
    }
}
