package com.galaxyssi.chat

import android.content.Context
import java.util.Locale

enum class AgentPreferenceMode(val wireValue: String) {
    FEWER_QUESTIONS("fewer_questions"),
    CAUTIOUS("cautious"),
    AUTOMATION("automation"),
    DEVELOPER("developer");

    companion object {
        fun fromWireValue(value: String?): AgentPreferenceMode {
            val normalized = value.orEmpty()
                .trim()
                .lowercase(Locale.ROOT)
                .replace('-', '_')
            return entries.firstOrNull {
                it.wireValue == normalized || it.name.lowercase(Locale.ROOT) == normalized
            } ?: CAUTIOUS
        }
    }
}

data class AgentPreferenceProfile(
    val permissionMode: PermissionMode,
    val taskExecutionMode: AgentTaskExecutionMode,
    val highRiskGuard: Boolean = true,
    val minimizeClarifications: Boolean = false,
    val expandStructuredDetails: Boolean = false
)

object AgentPreferenceModePolicy {
    fun profile(mode: AgentPreferenceMode): AgentPreferenceProfile = when (mode) {
        AgentPreferenceMode.FEWER_QUESTIONS -> AgentPreferenceProfile(
            permissionMode = PermissionMode.ASK_BEFORE_ACTION,
            taskExecutionMode = AgentTaskExecutionMode.AUTO_COMPLETE,
            minimizeClarifications = true
        )
        AgentPreferenceMode.CAUTIOUS -> AgentPreferenceProfile(
            permissionMode = PermissionMode.ASK_BEFORE_ACTION,
            taskExecutionMode = AgentTaskExecutionMode.AUTO_COMPLETE
        )
        AgentPreferenceMode.AUTOMATION -> AgentPreferenceProfile(
            permissionMode = PermissionMode.AUTO_LOW_RISK,
            taskExecutionMode = AgentTaskExecutionMode.AUTO_COMPLETE,
            minimizeClarifications = true
        )
        AgentPreferenceMode.DEVELOPER -> AgentPreferenceProfile(
            permissionMode = PermissionMode.AUTO_LOW_RISK,
            taskExecutionMode = AgentTaskExecutionMode.AUTO_COMPLETE,
            expandStructuredDetails = true
        )
    }

    fun resolveClarification(
        mode: AgentPreferenceMode,
        goal: String,
        baseline: AgentClarificationDecision
    ): AgentClarificationDecision {
        val profile = profile(mode)
        return if (
            profile.minimizeClarifications &&
            goal.isNotBlank() &&
            baseline.mode == AgentClarificationMode.ASK_LOCALLY
        ) {
            AgentClarificationDecision(AgentClarificationMode.EXECUTE)
        } else {
            baseline
        }
    }
}

class AgentPreferenceModeStore(context: Context) {
    private val preferences = AgentEncryptedPreferences(
        context.applicationContext,
        PREFERENCES_NAME
    )

    fun load(): AgentPreferenceMode =
        AgentPreferenceMode.fromWireValue(preferences.readString(KEY_MODE, ""))

    fun save(mode: AgentPreferenceMode) {
        preferences.writeString(KEY_MODE, mode.wireValue)
    }

    private companion object {
        const val PREFERENCES_NAME = "galaxyssi_agent_preference"
        const val KEY_MODE = "mode"
    }
}
