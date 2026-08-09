package com.signalasi.chat

import android.content.Context

enum class AgentModelSelectionMode {
    AUTO,
    MANUAL
}

data class AgentModelSelection(
    val mode: AgentModelSelectionMode = AgentModelSelectionMode.AUTO,
    val targetId: String = "",
    val modelId: String = "",
    val displayName: String = ""
)

object AgentModelSelectionPolicy {
    fun preferredTargetId(
        selection: AgentModelSelection,
        targets: List<AgentCallableTarget>
    ): String {
        if (selection.mode != AgentModelSelectionMode.MANUAL) return ""
        return targets.firstOrNull { target ->
            target.id == selection.targetId && AgentConnectorRouteSelector.isDeliverable(target)
        }?.id.orEmpty()
    }

    fun selectedTarget(
        selection: AgentModelSelection,
        targets: List<AgentCallableTarget>
    ): AgentCallableTarget? = preferredTargetId(selection, targets)
        .takeIf(String::isNotBlank)
        ?.let { preferredId -> targets.firstOrNull { it.id == preferredId } }
}

object AgentModelSelectionSettings {
    fun selection(context: Context): AgentModelSelection {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val mode = runCatching {
            AgentModelSelectionMode.valueOf(
                preferences.getString(KEY_MODE, AgentModelSelectionMode.AUTO.name).orEmpty()
            )
        }.getOrDefault(AgentModelSelectionMode.AUTO)
        return AgentModelSelection(
            mode = mode,
            targetId = preferences.getString(KEY_TARGET_ID, "").orEmpty(),
            modelId = preferences.getString(KEY_MODEL_ID, "").orEmpty(),
            displayName = preferences.getString(KEY_DISPLAY_NAME, "").orEmpty()
        )
    }

    fun selectAuto(context: Context) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_MODE, AgentModelSelectionMode.AUTO.name)
            .remove(KEY_TARGET_ID)
            .remove(KEY_MODEL_ID)
            .remove(KEY_DISPLAY_NAME)
            .apply()
    }

    fun selectManual(
        context: Context,
        targetId: String,
        modelId: String,
        displayName: String
    ) {
        require(targetId.isNotBlank()) { "A model target is required" }
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_MODE, AgentModelSelectionMode.MANUAL.name)
            .putString(KEY_TARGET_ID, targetId)
            .putString(KEY_MODEL_ID, modelId)
            .putString(KEY_DISPLAY_NAME, displayName)
            .apply()
    }

    fun preferredTargetId(context: Context, targets: List<AgentCallableTarget>): String =
        AgentModelSelectionPolicy.preferredTargetId(selection(context), targets)

    private const val PREFERENCES = "signalasi_agent_model_selection_v1"
    private const val KEY_MODE = "mode"
    private const val KEY_TARGET_ID = "target_id"
    private const val KEY_MODEL_ID = "model_id"
    private const val KEY_DISPLAY_NAME = "display_name"
}
