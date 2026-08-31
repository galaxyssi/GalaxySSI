package com.signalasi.chat

import android.content.Context
import android.content.SharedPreferences
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

data class AgentTargetConfiguration(
    val modelId: String = "",
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
    val displayName: String = id,
    val description: String = ""
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
                add(AgentModelOption(
                    id = id,
                    displayName = item?.optString("display_name").orEmpty().ifBlank { id },
                    description = item?.optString("description").orEmpty().trim()
                ))
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
        return readSelection(preferences) { field -> key(scope, field) }
    }

    fun inheritDefault(context: Context, conversationId: String) {
        val scope = requireConversationId(conversationId)
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val inherited = readSelection(preferences, ::defaultKey)
        writeSelection(preferences.edit(), { field -> key(scope, field) }, inherited).apply()
    }

    private fun readSelection(
        preferences: SharedPreferences,
        keyFor: (String) -> String
    ): AgentModelSelection {
        val mode = runCatching {
            AgentModelSelectionMode.valueOf(
                preferences.getString(keyFor(KEY_MODE), AgentModelSelectionMode.AUTO.name).orEmpty()
            )
        }.getOrDefault(AgentModelSelectionMode.AUTO)
        return AgentModelSelection(
            mode = mode,
            targetId = preferences.getString(keyFor(KEY_TARGET_ID), "").orEmpty(),
            modelId = preferences.getString(keyFor(KEY_MODEL_ID), "").orEmpty(),
            displayName = preferences.getString(keyFor(KEY_DISPLAY_NAME), "").orEmpty(),
            reasoningEffort = AgentModelReasoningEffort.fromWireValue(
                preferences.getString(keyFor(KEY_REASONING_EFFORT), AgentModelReasoningEffort.AUTO.wireValue)
            )
        )
    }

    fun selectAuto(context: Context, conversationId: String) {
        val scope = requireConversationId(conversationId)
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val previous = readSelection(preferences) { field -> key(scope, field) }
        val selection = AgentModelSelection()
        val editor = preferences.edit()
        rememberActiveTarget(editor, scope, previous)
        writeSelection(editor, { field -> key(scope, field) }, selection)
        writeSelection(editor, ::defaultKey, selection)
        editor.apply()
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
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val selection = AgentModelSelection(
            mode = AgentModelSelectionMode.MANUAL,
            targetId = targetId.trim(),
            modelId = modelId.trim(),
            displayName = displayName.trim(),
            reasoningEffort = reasoningEffort
        )
        val editor = preferences.edit()
        rememberActiveTarget(
            editor,
            scope,
            readSelection(preferences) { field -> key(scope, field) }
        )
        writeSelection(editor, { field -> key(scope, field) }, selection)
        writeSelection(editor, ::defaultKey, selection)
        writeTargetConfiguration(editor, scope, selection.targetId, selection.targetConfiguration())
        writeDefaultTargetConfiguration(editor, selection.targetId, selection.targetConfiguration())
        editor.apply()
    }

    fun configurationForTarget(
        context: Context,
        conversationId: String,
        targetId: String
    ): AgentTargetConfiguration? {
        val scope = requireConversationId(conversationId)
        val normalizedTargetId = targetId.trim()
        if (normalizedTargetId.isBlank()) return null
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val active = readSelection(preferences) { field -> key(scope, field) }
        if (active.mode == AgentModelSelectionMode.MANUAL && active.targetId == normalizedTargetId) {
            return active.targetConfiguration()
        }
        return readTargetConfiguration(preferences) { field ->
            targetKey(scope, normalizedTargetId, field)
        } ?: readTargetConfiguration(preferences) { field ->
            defaultTargetKey(normalizedTargetId, field)
        }
    }

    fun updateAgentConfiguration(
        context: Context,
        conversationId: String,
        modelId: String,
        reasoningEffort: AgentModelReasoningEffort
    ) {
        val scope = requireConversationId(conversationId)
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val updated = selection(context, scope).copy(
            modelId = modelId.trim(),
            reasoningEffort = reasoningEffort
        )
        require(updated.mode == AgentModelSelectionMode.MANUAL && updated.targetId.isNotBlank()) {
            "An active agent target is required"
        }
        val editor = preferences.edit()
        writeSelection(editor, { field -> key(scope, field) }, updated)
        writeSelection(editor, ::defaultKey, updated)
        writeTargetConfiguration(editor, scope, updated.targetId, updated.targetConfiguration())
        writeDefaultTargetConfiguration(editor, updated.targetId, updated.targetConfiguration())
        editor.apply()
    }

    fun clearConversation(context: Context, conversationId: String) {
        val scope = normalizedConversationId(conversationId)
        if (scope.isBlank()) return
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val editor = preferences.edit()
            .remove(key(scope, KEY_MODE))
            .remove(key(scope, KEY_TARGET_ID))
            .remove(key(scope, KEY_MODEL_ID))
            .remove(key(scope, KEY_DISPLAY_NAME))
            .remove(key(scope, KEY_REASONING_EFFORT))
        preferences.all.keys
            .filter { it.startsWith(targetKeyPrefix(scope)) }
            .forEach(editor::remove)
        editor.apply()
    }

    fun clearConversations(context: Context, conversationIds: Collection<String>) {
        val scopes = conversationIds.map(::normalizedConversationId)
            .filter(String::isNotBlank)
            .toSet()
        if (scopes.isEmpty()) return
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val editor = preferences.edit()
        preferences.all.keys.forEach { storedKey ->
            if (!storedKey.startsWith(KEY_CONVERSATION_PREFIX)) return@forEach
            val scope = storedKey.removePrefix(KEY_CONVERSATION_PREFIX).substringBefore('.')
            if (scope in scopes) editor.remove(storedKey)
        }
        editor.apply()
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

    internal fun defaultPreferenceKey(field: String): String = defaultKey(field)

    internal fun conversationTargetPreferenceKey(
        conversationId: String,
        targetId: String,
        field: String
    ): String = targetKey(requireConversationId(conversationId), targetId.trim(), field)

    internal fun defaultTargetPreferenceKey(targetId: String, field: String): String =
        defaultTargetKey(targetId.trim(), field)

    private fun writeSelection(
        editor: SharedPreferences.Editor,
        keyFor: (String) -> String,
        selection: AgentModelSelection
    ): SharedPreferences.Editor {
        editor.putString(keyFor(KEY_MODE), selection.mode.name)
        if (selection.mode == AgentModelSelectionMode.AUTO) {
            return editor
                .remove(keyFor(KEY_TARGET_ID))
                .remove(keyFor(KEY_MODEL_ID))
                .remove(keyFor(KEY_DISPLAY_NAME))
                .remove(keyFor(KEY_REASONING_EFFORT))
        }
        return editor
            .putString(keyFor(KEY_TARGET_ID), selection.targetId)
            .putString(keyFor(KEY_MODEL_ID), selection.modelId)
            .putString(keyFor(KEY_DISPLAY_NAME), selection.displayName)
            .putString(keyFor(KEY_REASONING_EFFORT), selection.reasoningEffort.wireValue)
    }

    private fun rememberActiveTarget(
        editor: SharedPreferences.Editor,
        conversationId: String,
        selection: AgentModelSelection
    ) {
        if (selection.mode != AgentModelSelectionMode.MANUAL || selection.targetId.isBlank()) return
        val configuration = selection.targetConfiguration()
        writeTargetConfiguration(editor, conversationId, selection.targetId, configuration)
        writeDefaultTargetConfiguration(editor, selection.targetId, configuration)
    }

    private fun AgentModelSelection.targetConfiguration(): AgentTargetConfiguration =
        AgentTargetConfiguration(modelId = modelId, reasoningEffort = reasoningEffort)

    private fun readTargetConfiguration(
        preferences: SharedPreferences,
        keyFor: (String) -> String
    ): AgentTargetConfiguration? {
        if (!preferences.contains(keyFor(KEY_MODEL_ID)) &&
            !preferences.contains(keyFor(KEY_REASONING_EFFORT))) return null
        return AgentTargetConfiguration(
            modelId = preferences.getString(keyFor(KEY_MODEL_ID), "").orEmpty(),
            reasoningEffort = AgentModelReasoningEffort.fromWireValue(
                preferences.getString(keyFor(KEY_REASONING_EFFORT), AgentModelReasoningEffort.AUTO.wireValue)
            )
        )
    }

    private fun writeTargetConfiguration(
        editor: SharedPreferences.Editor,
        conversationId: String,
        targetId: String,
        configuration: AgentTargetConfiguration
    ) {
        editor.putString(targetKey(conversationId, targetId, KEY_MODEL_ID), configuration.modelId)
        editor.putString(
            targetKey(conversationId, targetId, KEY_REASONING_EFFORT),
            configuration.reasoningEffort.wireValue
        )
    }

    private fun writeDefaultTargetConfiguration(
        editor: SharedPreferences.Editor,
        targetId: String,
        configuration: AgentTargetConfiguration
    ) {
        editor.putString(defaultTargetKey(targetId, KEY_MODEL_ID), configuration.modelId)
        editor.putString(
            defaultTargetKey(targetId, KEY_REASONING_EFFORT),
            configuration.reasoningEffort.wireValue
        )
    }

    private fun key(conversationId: String, field: String): String =
        "$KEY_CONVERSATION_PREFIX$conversationId.$field"

    private fun defaultKey(field: String): String = "$KEY_DEFAULT_PREFIX$field"

    private fun targetKey(conversationId: String, targetId: String, field: String): String =
        "${targetKeyPrefix(conversationId)}${targetIdKey(targetId)}.$field"

    private fun defaultTargetKey(targetId: String, field: String): String =
        "$KEY_DEFAULT_TARGET_PREFIX${targetIdKey(targetId)}.$field"

    private fun targetKeyPrefix(conversationId: String): String =
        "$KEY_CONVERSATION_PREFIX$conversationId.$KEY_TARGET_CONFIG_SEGMENT"

    private fun targetIdKey(targetId: String): String = targetId
        .trim()
        .take(MAX_TARGET_ID_LENGTH)
        .encodeToByteArray()
        .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

    private fun requireConversationId(conversationId: String): String =
        normalizedConversationId(conversationId).also {
            require(it.isNotBlank()) { "A conversation id is required" }
        }

    private fun normalizedConversationId(conversationId: String): String =
        conversationId.trim().take(MAX_CONVERSATION_ID_LENGTH)

    private const val PREFERENCES = "signalasi_agent_model_selection_v2"
    private const val KEY_CONVERSATION_PREFIX = "conversation."
    private const val KEY_DEFAULT_PREFIX = "default."
    private const val KEY_DEFAULT_TARGET_PREFIX = "default.target."
    private const val KEY_TARGET_CONFIG_SEGMENT = "target."
    private const val KEY_MODE = "mode"
    private const val KEY_TARGET_ID = "target_id"
    private const val KEY_MODEL_ID = "model_id"
    private const val KEY_DISPLAY_NAME = "display_name"
    private const val KEY_REASONING_EFFORT = "reasoning_effort"
    private const val MAX_CONVERSATION_ID_LENGTH = 160
    private const val MAX_TARGET_ID_LENGTH = 160
}
