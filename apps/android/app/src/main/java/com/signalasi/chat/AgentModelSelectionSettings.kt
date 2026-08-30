package com.signalasi.chat

import android.content.Context
import org.json.JSONObject

enum class AgentModelSelectionMode {
    AUTO,
    MANUAL
}

data class AgentModelSelection(
    val mode: AgentModelSelectionMode = AgentModelSelectionMode.AUTO,
    val targetId: String = "",
    val modelId: String = "",
    val displayName: String = "",
    val reasoningEffort: AgentModelReasoningEffort = AgentModelReasoningEffort.AUTO
)

enum class AgentModelReasoningEffort(val wireValue: String) {
    AUTO("auto"),
    LOW("low"),
    MEDIUM("medium"),
    HIGH("high"),
    XHIGH("xhigh");

    companion object {
        fun fromWireValue(value: String?): AgentModelReasoningEffort = entries.firstOrNull {
            it.wireValue.equals(value?.trim(), ignoreCase = true)
        } ?: AUTO
    }
}

data class AgentModelOption(
    val id: String,
    val displayName: String = id
)

data class AgentInvocationProfile(
    val defaultModelId: String = "",
    val models: List<AgentModelOption> = emptyList(),
    val reasoningEfforts: List<AgentModelReasoningEffort> = emptyList()
) {
    val configurable: Boolean
        get() = models.isNotEmpty() || reasoningEfforts.isNotEmpty()

    fun normalizedModelId(requested: String): String {
        val clean = requested.trim()
        return models.firstOrNull { it.id == clean }?.id
            ?: models.firstOrNull { it.id == defaultModelId }?.id
            ?: models.firstOrNull()?.id
            ?: ""
    }
}

object AgentInvocationProfileJsonCodec {
    fun decode(value: JSONObject?): AgentInvocationProfile {
        val root = value ?: return AgentInvocationProfile()
        val models = buildList<AgentModelOption> {
            val values = root.optJSONArray("models") ?: return@buildList
            for (index in 0 until values.length()) {
                val item = values.optJSONObject(index)
                val id = item?.optString("id").orEmpty().trim()
                    .ifBlank { values.optString(index).trim() }
                if (id.isBlank() || any { it.id == id }) continue
                add(AgentModelOption(id, item?.optString("display_name").orEmpty().ifBlank { id }))
            }
        }
        val efforts = buildList<AgentModelReasoningEffort> {
            val values = root.optJSONArray("reasoning_efforts") ?: return@buildList
            for (index in 0 until values.length()) {
                val effort = AgentModelReasoningEffort.fromWireValue(values.optString(index))
                if (effort != AgentModelReasoningEffort.AUTO && effort !in this) add(effort)
            }
        }
        return AgentInvocationProfile(
            defaultModelId = root.optString("default_model").trim(),
            models = models,
            reasoningEfforts = efforts
        )
    }
}

object AgentInvocationRequestJsonCodec {
    fun encode(modelId: String, effort: AgentModelReasoningEffort): JSONObject? {
        val cleanModel = modelId.trim()
        if (cleanModel.isBlank() && effort == AgentModelReasoningEffort.AUTO) return null
        return JSONObject()
            .put("model_id", cleanModel)
            .put("reasoning_effort", effort.wireValue)
    }
}

object AgentModelSelectionPolicy {
    fun preferredTargetId(
        selection: AgentModelSelection,
        targets: List<AgentCallableTarget>
    ): String {
        if (selection.mode != AgentModelSelectionMode.MANUAL) return ""
        return selection.targetId.trim()
    }

    fun selectedTarget(
        selection: AgentModelSelection,
        targets: List<AgentCallableTarget>
    ): AgentCallableTarget? = preferredTargetId(selection, targets)
        .takeIf(String::isNotBlank)
        ?.let { preferredId -> targets.firstOrNull { it.id == preferredId } }

    fun selectableAgentTargets(targets: List<AgentCallableTarget>): List<AgentCallableTarget> {
        val availableAgents = targets.filter { target ->
            target.kind == AgentConnectorKind.AGENT &&
                AgentConnectorRouteSelector.isDeliverable(target)
        }
        val concreteAgentIds = availableAgents
            .asSequence()
            .filter { ':' in it.id }
            .map { it.id.substringAfterLast(':') }
            .toSet()
        return availableAgents
            .filter { target ->
                ':' in target.id || target.id.substringAfterLast(':') !in concreteAgentIds
            }
            .distinctBy(AgentCallableTarget::id)
    }
}

object AgentExecutionTargetStatusPolicy {
    fun resolveTarget(
        connectorId: String,
        contactId: String,
        targets: List<AgentCallableTarget>
    ): AgentCallableTarget? {
        val identities = listOf(contactId, connectorId)
            .map(String::trim)
            .filter(String::isNotBlank)
        identities.forEach { identity ->
            targets.firstOrNull { it.id == identity }?.let { return it }
        }
        identities.forEach { identity ->
            targets.firstOrNull { target ->
                target.id.endsWith(":$identity") || identity.endsWith(":${target.id}")
            }?.let { return it }
        }
        return null
    }
}

object AgentModelSelectionSettings {
    fun selection(context: Context, conversationId: String): AgentModelSelection {
        val scope = normalizedConversationId(conversationId)
        if (scope.isBlank()) return AgentModelSelection()
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val mode = runCatching {
            AgentModelSelectionMode.valueOf(
                preferences.getString(key(scope, KEY_MODE), AgentModelSelectionMode.AUTO.name).orEmpty()
            )
        }.getOrDefault(AgentModelSelectionMode.AUTO)
        return AgentModelSelection(
            mode = mode,
            targetId = preferences.getString(key(scope, KEY_TARGET_ID), "").orEmpty(),
            modelId = preferences.getString(key(scope, KEY_MODEL_ID), "").orEmpty(),
            displayName = preferences.getString(key(scope, KEY_DISPLAY_NAME), "").orEmpty(),
            reasoningEffort = AgentModelReasoningEffort.fromWireValue(
                preferences.getString(key(scope, KEY_REASONING_EFFORT), AgentModelReasoningEffort.AUTO.wireValue)
            )
        )
    }

    fun selectAuto(context: Context, conversationId: String) {
        val scope = requireConversationId(conversationId)
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(key(scope, KEY_MODE), AgentModelSelectionMode.AUTO.name)
            .remove(key(scope, KEY_TARGET_ID))
            .remove(key(scope, KEY_MODEL_ID))
            .remove(key(scope, KEY_DISPLAY_NAME))
            .remove(key(scope, KEY_REASONING_EFFORT))
            .apply()
    }

    fun selectManual(
        context: Context,
        conversationId: String,
        targetId: String,
        modelId: String,
        displayName: String,
        reasoningEffort: AgentModelReasoningEffort = AgentModelReasoningEffort.AUTO
    ) {
        val scope = requireConversationId(conversationId)
        require(targetId.isNotBlank()) { "A model target is required" }
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(key(scope, KEY_MODE), AgentModelSelectionMode.MANUAL.name)
            .putString(key(scope, KEY_TARGET_ID), targetId)
            .putString(key(scope, KEY_MODEL_ID), modelId)
            .putString(key(scope, KEY_DISPLAY_NAME), displayName)
            .putString(key(scope, KEY_REASONING_EFFORT), reasoningEffort.wireValue)
            .apply()
    }

    fun updateAgentConfiguration(
        context: Context,
        conversationId: String,
        modelId: String,
        reasoningEffort: AgentModelReasoningEffort
    ) {
        val scope = requireConversationId(conversationId)
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(key(scope, KEY_MODEL_ID), modelId.trim())
            .putString(key(scope, KEY_REASONING_EFFORT), reasoningEffort.wireValue)
            .apply()
    }

    fun clearConversation(context: Context, conversationId: String) {
        val scope = normalizedConversationId(conversationId)
        if (scope.isBlank()) return
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .remove(key(scope, KEY_MODE))
            .remove(key(scope, KEY_TARGET_ID))
            .remove(key(scope, KEY_MODEL_ID))
            .remove(key(scope, KEY_DISPLAY_NAME))
            .remove(key(scope, KEY_REASONING_EFFORT))
            .apply()
    }

    fun preferredTargetId(
        context: Context,
        conversationId: String,
        targets: List<AgentCallableTarget>
    ): String = AgentModelSelectionPolicy.preferredTargetId(
        selection(context, conversationId),
        targets
    )

    internal fun conversationPreferenceKey(conversationId: String, field: String): String =
        key(requireConversationId(conversationId), field)

    private fun key(conversationId: String, field: String): String =
        "$KEY_CONVERSATION_PREFIX$conversationId.$field"

    private fun requireConversationId(conversationId: String): String =
        normalizedConversationId(conversationId).also {
            require(it.isNotBlank()) { "A conversation id is required" }
        }

    private fun normalizedConversationId(conversationId: String): String =
        conversationId.trim().take(MAX_CONVERSATION_ID_LENGTH)

    private const val PREFERENCES = "signalasi_agent_model_selection_v2"
    private const val KEY_CONVERSATION_PREFIX = "conversation."
    private const val KEY_MODE = "mode"
    private const val KEY_TARGET_ID = "target_id"
    private const val KEY_MODEL_ID = "model_id"
    private const val KEY_DISPLAY_NAME = "display_name"
    private const val KEY_REASONING_EFFORT = "reasoning_effort"
    private const val MAX_CONVERSATION_ID_LENGTH = 160
}
