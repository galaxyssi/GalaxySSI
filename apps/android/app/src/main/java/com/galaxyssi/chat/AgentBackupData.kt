package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object AgentBackupData {
    private const val MEMORY_DATABASE = "galaxyssi_agent_memory_v2"
    private const val KNOWLEDGE_PREFS = "galaxyssi_agent_knowledge"
    private const val WORKFLOW_PREFS = "galaxyssi_agent_workflows"
    private const val SCHEDULE_PREFS = "galaxyssi_agent_workflow_schedules"
    private const val TRIGGER_PREFS = "galaxyssi_agent_workflow_triggers"
    private const val TRANSCRIPT_PREFS = AgentTranscriptStore.PREFS
    private const val ITEMS_KEY = "items"

    fun export(context: Context, includeSessionHistory: Boolean = true): JSONObject {
        val safety = SharedPreferencesAgentSafetySettingsStore(context).load()
        val taskBudget = AgentTaskBudgetStore(context).load()
        val modelPlanner = AgentModelPlannerSettingsStore(context).load()
        val preferenceMode = AgentPreferenceModeStore(context).load()
        val voiceAssistant = VoiceAssistantSettings.get(context)
        val homeAssistant = HomeAssistantSettingsStore.load(context)
        val customDevices = CustomDeviceConnectorStore(context).exportJson()
        val memoryDeletionIndex = EncryptedAgentMemoryDeletionIndex(context)
        return JSONObject()
            .put("version", 33)
            .put("interface_language", AppLanguage.current(context))
            .put("agent_preference_mode", preferenceMode.wireValue)
            .put("memory", readDatabaseArray(context, MEMORY_DATABASE, MAX_MEMORY_ITEMS, MAX_MEMORY_ITEM_CHARACTERS))
            .put("memory_deletion_index", memoryDeletionIndex.exportJson())
            .put("knowledge", readArray(context, KNOWLEDGE_PREFS, MAX_KNOWLEDGE_ITEMS, MAX_KNOWLEDGE_ITEM_CHARACTERS))
            .put("tasks", if (includeSessionHistory) SQLiteAgentTaskStore(context).exportJson() else JSONArray())
            .put("transcript", if (includeSessionHistory) readAgentTranscriptArray(context) else JSONArray())
            .put("agent_conversations", if (includeSessionHistory) readAgentConversationArray(context) else JSONArray())
            .put(
                "active_agent_conversation",
                if (includeSessionHistory) {
                    AgentEncryptedDatabase(context, TRANSCRIPT_PREFS)
                        .readString(AgentTranscriptStore.KEY_ACTIVE_CONVERSATION, "")
                } else ""
            )
            .put("workflows", readArray(context, WORKFLOW_PREFS, MAX_WORKFLOW_ITEMS, MAX_WORKFLOW_ITEM_CHARACTERS))
            .put("workflow_schedules", readArray(context, SCHEDULE_PREFS, MAX_SCHEDULE_ITEMS, MAX_SCHEDULE_ITEM_CHARACTERS))
            .put("workflow_triggers", readArray(context, TRIGGER_PREFS, MAX_TRIGGER_ITEMS, MAX_TRIGGER_ITEM_CHARACTERS))
            .put("workflow_execution_history", AgentWorkflowExecutionHistoryStore(context).exportJson())
            .put(
                "safety",
                JSONObject()
                    .put("task_execution_mode", safety.taskExecutionMode.name)
                    .put("permission_mode", safety.permissionMode.name)
                    .put("high_risk_guard", safety.highRiskGuard)
                    .put("memory_capture", safety.memoryCapture)
                    .put("screen_observation_allowed", safety.screenObservationAllowed)
                    .put("local_actions_allowed", safety.localActionsAllowed)
                    .put("connector_calls_allowed", safety.connectorCallsAllowed)
                    .put("device_control_allowed", safety.deviceControlAllowed)
                    .put("execution_paused", safety.executionPaused)
            )
            .put("task_budget", AgentTaskBudgetJsonCodec.encode(taskBudget))
            .put("custom_device_connectors", customDevices)
            .put("global_super_agent", GlobalAgentRepository(context).exportSnapshot())
            .put("agent_self_model", AgentSelfModelStore(context).exportJson())
            .put(
                "model_planner",
                JSONObject()
                    .put("enabled", modelPlanner.enabled)
                    .put("share_screen_text", modelPlanner.shareScreenText)
                    .put("max_actions", modelPlanner.maxActions)
                    .put("cloud_contact_id", modelPlanner.cloudContactId)
                    .put("dynamic_replanning", modelPlanner.dynamicReplanning)
                    .put("max_replans", modelPlanner.maxReplans)
                    .put("multi_agent_coordination", modelPlanner.multiAgentCoordination)
                    .put("share_agent_outputs_with_planner", modelPlanner.shareAgentOutputsWithPlanner)
                    .put("max_agent_hops", modelPlanner.maxAgentHops)
                    .put("max_tool_calls", modelPlanner.maxToolCalls)
                    .put("max_loop_iterations", modelPlanner.maxLoopIterations)
                    .put("max_phase_retries", modelPlanner.maxPhaseRetries)
                    .put("no_progress_timeout_seconds", modelPlanner.noProgressTimeoutSeconds)
            )
            .put(
                "voice_assistant",
                JSONObject()
                    .put("enabled", voiceAssistant.enabled)
                    .put("wake_provider", voiceAssistant.wakeProvider)
                    .put("wake_model", voiceAssistant.wakeModel)
                    .put("wake_threshold", voiceAssistant.wakeThreshold.toDouble())
                    .put("asr_provider", voiceAssistant.asrProvider)
                    .put("asr_recognition_preference", voiceAssistant.recognitionPreference.name)
                    .put("online_asr_allowed", voiceAssistant.onlineAsrPrivacy.allowOnlineVoice)
                    .put("online_asr_wifi_only", voiceAssistant.onlineAsrPrivacy.wifiOnly)
                    .put("online_asr_mobile_allowed", voiceAssistant.onlineAsrPrivacy.allowMobileNetwork)
                    .put("online_asr_audio_upload_allowed", voiceAssistant.onlineAsrPrivacy.allowRawAudioUpload)
                    .put("online_asr_delete_server_data", voiceAssistant.onlineAsrPrivacy.requestServerDataDeletion)
                    .put("local_asr_always_preferred", voiceAssistant.onlineAsrPrivacy.localAlwaysPreferred)
                    .put("asr_model", voiceAssistant.asrModel)
                    .put("asr_acceleration", voiceAssistant.asrAcceleration)
                    .put("asr_runtime_mode", voiceAssistant.asrRuntimeMode.name)
                    .put("asr_language", voiceAssistant.asrLanguage)
                    .put("tts_provider", voiceAssistant.ttsProvider)
                    .put("tts_language", voiceAssistant.ttsLanguage)
                    .put("response_language", voiceAssistant.responseLanguage)
                    .put("microsoft_voice", voiceAssistant.microsoftVoice)
                    .put("welcome_text", voiceAssistant.welcomeText)
                    .put("target_contact_id", voiceAssistant.targetContactId)
                    .put("speak_replies", voiceAssistant.speakReplies)
                    .put("routing_mode", voiceAssistant.routingMode)
            )
            .put(
                "home_assistant",
                JSONObject()
                    .put("enabled", homeAssistant.enabled)
                    .put("base_url", homeAssistant.baseUrl)
                    .put("access_token", homeAssistant.accessToken)
                    .put("default_entity_id", homeAssistant.defaultEntityId)
            )
    }

    fun restore(context: Context, payload: JSONObject) {
        val memoryDeletionIndex = EncryptedAgentMemoryDeletionIndex(context)
        memoryDeletionIndex.mergeBackup(payload.optJSONArray("memory_deletion_index"))
        if (payload.has("interface_language")) {
            AppLanguage.set(context, payload.optString("interface_language", AppLanguage.AUTO))
        }
        if (payload.has("agent_preference_mode")) {
            AgentPreferenceModeStore(context).save(
                AgentPreferenceMode.fromWireValue(payload.optString("agent_preference_mode"))
            )
        }
        payload.optJSONArray("memory")?.let { input ->
            val sanitized = sanitizeArray(input, MAX_MEMORY_ITEMS, MAX_MEMORY_ITEM_CHARACTERS)
            AgentEncryptedDatabase(context, MEMORY_DATABASE)
                .writeString(ITEMS_KEY, memoryDeletionIndex.filterBackupItems(sanitized).toString())
        }
        payload.optJSONArray("knowledge")?.let { input ->
            val sanitized = sanitizeArray(input, MAX_KNOWLEDGE_ITEMS, MAX_KNOWLEDGE_ITEM_CHARACTERS)
            AgentEncryptedPreferences(context, KNOWLEDGE_PREFS).writeString(ITEMS_KEY, sanitized.toString())
        }
        payload.optJSONArray("tasks")?.let { input ->
            SQLiteAgentTaskStore(context).replaceAllJson(copyObjectArray(input))
        }
        payload.optJSONArray("transcript")?.let { input ->
            AgentTranscriptStore(context).restoreEntriesJson(copyObjectArray(input))
        }
        payload.optJSONArray("agent_conversations")?.let { input ->
            AgentEncryptedDatabase(context, TRANSCRIPT_PREFS)
                .writeString(AgentTranscriptStore.KEY_CONVERSATIONS, copyObjectArray(input).toString())
        }
        payload.optString("active_agent_conversation").takeIf { it.isNotBlank() }?.let { activeId ->
            AgentEncryptedDatabase(context, TRANSCRIPT_PREFS)
                .writeString(AgentTranscriptStore.KEY_ACTIVE_CONVERSATION, activeId.take(120))
        }
        payload.optJSONArray("workflows")?.let { input ->
            val sanitized = sanitizeArray(input, MAX_WORKFLOW_ITEMS, MAX_WORKFLOW_ITEM_CHARACTERS)
            AgentEncryptedPreferences(context, WORKFLOW_PREFS).writeString(ITEMS_KEY, sanitized.toString())
        }
        payload.optJSONArray("workflow_schedules")?.let { input ->
            val sanitized = sanitizeArray(input, MAX_SCHEDULE_ITEMS, MAX_SCHEDULE_ITEM_CHARACTERS)
            AgentEncryptedPreferences(context, SCHEDULE_PREFS).writeString(ITEMS_KEY, sanitized.toString())
        }
        payload.optJSONArray("workflow_triggers")?.let { input ->
            val sanitized = sanitizeArray(input, MAX_TRIGGER_ITEMS, MAX_TRIGGER_ITEM_CHARACTERS)
            AgentEncryptedPreferences(context, TRIGGER_PREFS).writeString(ITEMS_KEY, sanitized.toString())
        }
        payload.optJSONArray("workflow_execution_history")?.let { input ->
            AgentWorkflowExecutionHistoryStore(context).replaceAllJson(copyObjectArray(input))
        }
        payload.optJSONObject("safety")?.let { json ->
            SharedPreferencesAgentSafetySettingsStore(context).save(
                AgentSafetySettings(
                    taskExecutionMode = enumOrDefault(
                        json.optString("task_execution_mode"),
                        AgentTaskExecutionMode.AUTO_COMPLETE
                    ),
                    permissionMode = enumOrDefault(
                        json.optString("permission_mode"),
                        PermissionMode.ASK_BEFORE_ACTION
                    ),
                    highRiskGuard = json.optBoolean("high_risk_guard", true),
                    memoryCapture = json.optBoolean("memory_capture", true),
                    screenObservationAllowed = json.optBoolean("screen_observation_allowed", true),
                    localActionsAllowed = json.optBoolean("local_actions_allowed", true),
                    connectorCallsAllowed = json.optBoolean("connector_calls_allowed", true),
                    deviceControlAllowed = json.optBoolean("device_control_allowed", true),
                    executionPaused = json.optBoolean("execution_paused", false)
                )
            )
        }
        payload.optJSONObject("task_budget")?.let { json ->
            AgentTaskBudgetStore(context).save(AgentTaskBudgetJsonCodec.decode(json))
        }
        payload.optJSONObject("home_assistant")?.let { json ->
            HomeAssistantSettingsStore.save(
                context,
                HomeAssistantSettings(
                    enabled = json.optBoolean("enabled"),
                    baseUrl = json.optString("base_url").take(MAX_URL_CHARACTERS),
                    accessToken = json.optString("access_token").take(MAX_SECRET_CHARACTERS),
                    defaultEntityId = json.optString("default_entity_id").take(MAX_ENTITY_ID_CHARACTERS)
                )
            )
        }
        payload.optJSONArray("custom_device_connectors")?.let { array ->
            CustomDeviceConnectorStore(context).restoreJson(array)
        }
        payload.optJSONObject("global_super_agent")?.let { snapshot ->
            GlobalAgentRepository(context).restoreSnapshot(snapshot)
        }
        payload.optJSONObject("agent_self_model")?.let { snapshot ->
            AgentSelfModelStore(context).restoreJson(snapshot)
        }
        payload.optJSONObject("model_planner")?.let { json ->
            AgentModelPlannerSettingsStore(context).save(
                AgentModelPlannerSettings(
                    enabled = json.optBoolean("enabled", false),
                    shareScreenText = json.optBoolean("share_screen_text", false),
                    maxActions = json.optInt("max_actions", 8).coerceIn(1, 12),
                    cloudContactId = json.optString("cloud_contact_id").take(120),
                    dynamicReplanning = json.optBoolean("dynamic_replanning", true),
                    maxReplans = json.optInt("max_replans", 3).coerceIn(1, 5),
                    multiAgentCoordination = json.optBoolean("multi_agent_coordination", true),
                    shareAgentOutputsWithPlanner = json.optBoolean("share_agent_outputs_with_planner", false),
                    maxAgentHops = json.optInt("max_agent_hops", 4).coerceIn(1, 8),
                    maxToolCalls = json.optInt("max_tool_calls", 16).coerceIn(4, 32),
                    maxLoopIterations = json.optInt("max_loop_iterations", 8).coerceIn(1, 24),
                    maxPhaseRetries = json.optInt("max_phase_retries", 2).coerceIn(0, 5),
                    noProgressTimeoutSeconds = json.optInt(
                        "no_progress_timeout_seconds",
                        180
                    ).coerceIn(60, 3_600)
                )
            )
        }
        payload.optJSONObject("voice_assistant")?.let { json ->
            VoiceAssistantSettings.setEnabled(context, json.optBoolean("enabled", true))
            VoiceAssistantSettings.setWakeProvider(context, json.optString("wake_provider"))
            VoiceAssistantSettings.setWakeModel(context, json.optString("wake_model"))
            VoiceAssistantSettings.setWakeThreshold(context, json.optDouble("wake_threshold", 0.5).toFloat())
            VoiceAssistantSettings.setAsrProvider(context, json.optString("asr_provider"))
            VoiceAssistantSettings.setRecognitionPreference(
                context,
                runCatching {
                    enumValueOf<com.galaxyssi.chat.voice.asr.VoiceRecognitionPreference>(
                        json.optString(
                            "asr_recognition_preference",
                            com.galaxyssi.chat.voice.asr.VoiceRecognitionPreference.AUTO.name
                        )
                    )
                }.getOrDefault(com.galaxyssi.chat.voice.asr.VoiceRecognitionPreference.AUTO)
            )
            VoiceAssistantSettings.setOnlineAsrPrivacy(
                context,
                com.galaxyssi.chat.voice.asr.AsrPrivacyPolicy(
                    allowOnlineVoice = json.optBoolean("online_asr_allowed", false),
                    wifiOnly = json.optBoolean("online_asr_wifi_only", true),
                    allowMobileNetwork = json.optBoolean("online_asr_mobile_allowed", false),
                    allowRawAudioUpload = json.optBoolean("online_asr_audio_upload_allowed", false),
                    requestServerDataDeletion = json.optBoolean("online_asr_delete_server_data", true),
                    localAlwaysPreferred = json.optBoolean("local_asr_always_preferred", false)
                )
            )
            VoiceAssistantSettings.setAsrModel(context, json.optString("asr_model", "tiny"))
            VoiceAssistantSettings.setAsrAcceleration(
                context,
                json.optString(
                    "asr_acceleration",
                    VoiceAssistantSettings.ASR_ACCELERATION_GGML
                )
            )
            VoiceAssistantSettings.setAsrRuntimeMode(
                context,
                runCatching {
                    enumValueOf<com.galaxyssi.chat.voice.benchmark.WhisperUserVoiceMode>(
                        json.optString(
                            "asr_runtime_mode",
                            com.galaxyssi.chat.voice.benchmark.WhisperUserVoiceMode.AUTOMATIC.name
                        )
                    )
                }.getOrDefault(com.galaxyssi.chat.voice.benchmark.WhisperUserVoiceMode.AUTOMATIC)
            )
            VoiceAssistantSettings.setAsrLanguage(context, json.optString("asr_language"))
            VoiceAssistantSettings.setTtsProvider(context, json.optString("tts_provider"))
            VoiceAssistantSettings.setTtsLanguage(context, json.optString("tts_language"))
            VoiceAssistantSettings.setResponseLanguage(context, json.optString("response_language"))
            VoiceAssistantSettings.setMicrosoftVoice(context, json.optString("microsoft_voice"))
            VoiceAssistantSettings.setWelcomeText(context, json.optString("welcome_text"))
            VoiceAssistantSettings.setTargetContact(context, json.optString("target_contact_id"))
            VoiceAssistantSettings.setSpeakReplies(context, json.optBoolean("speak_replies", true))
            VoiceAssistantSettings.setRoutingMode(context, json.optString("routing_mode"))
        }
        memoryDeletionIndex.publishRetractions()
        GlobalConversationEventBus.requestProcessing(context)
    }

    private fun decodeStringList(array: JSONArray?): List<String> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                array.optString(index).takeIf { it.isNotBlank() }?.let(::add)
            }
        }
    }

    private fun readArray(context: Context, preferencesName: String, maxItems: Int, maxItemCharacters: Int): JSONArray {
        val raw = AgentEncryptedPreferences(context, preferencesName).readString(ITEMS_KEY, "[]")
        val array = runCatching { JSONArray(raw) }.getOrDefault(JSONArray())
        return sanitizeArray(array, maxItems, maxItemCharacters)
    }

    private fun readDatabaseArray(
        context: Context,
        databaseName: String,
        maxItems: Int,
        maxItemCharacters: Int
    ): JSONArray {
        val raw = AgentEncryptedDatabase(context, databaseName).readString(ITEMS_KEY, "[]")
        return sanitizeArray(runCatching { JSONArray(raw) }.getOrDefault(JSONArray()), maxItems, maxItemCharacters)
    }

    private fun readAgentConversationArray(context: Context): JSONArray {
        val raw = AgentEncryptedDatabase(context, TRANSCRIPT_PREFS)
            .readString(AgentTranscriptStore.KEY_CONVERSATIONS, "[]")
        return copyObjectArray(runCatching { JSONArray(raw) }.getOrDefault(JSONArray()))
    }

    private fun readAgentTranscriptArray(context: Context): JSONArray =
        AgentTranscriptStore(context).exportEntriesJson()

    private fun copyObjectArray(input: JSONArray): JSONArray {
        val output = JSONArray()
        for (index in 0 until input.length()) {
            input.optJSONObject(index)?.let(output::put)
        }
        return output
    }

    private fun sanitizeArray(input: JSONArray, maxItems: Int, maxItemCharacters: Int): JSONArray {
        val output = JSONArray()
        val start = (input.length() - maxItems).coerceAtLeast(0)
        for (index in start until input.length()) {
            val item = input.optJSONObject(index) ?: continue
            if (item.toString().length <= maxItemCharacters) output.put(item)
        }
        return output
    }

    private inline fun <reified T : Enum<T>> enumOrDefault(value: String, default: T): T =
        runCatching { enumValueOf<T>(value) }.getOrElse { default }

    private const val MAX_MEMORY_ITEMS = 200
    private const val MAX_MEMORY_ITEM_CHARACTERS = 24_000
    private const val MAX_KNOWLEDGE_ITEMS = 500
    private const val MAX_KNOWLEDGE_ITEM_CHARACTERS = 20_000
    private const val MAX_WORKFLOW_ITEMS = 100
    private const val MAX_WORKFLOW_ITEM_CHARACTERS = 4_000
    private const val MAX_SCHEDULE_ITEMS = 100
    private const val MAX_SCHEDULE_ITEM_CHARACTERS = 4_000
    private const val MAX_TRIGGER_ITEMS = 100
    private const val MAX_TRIGGER_ITEM_CHARACTERS = 20_000
    private const val MAX_URL_CHARACTERS = 2_000
    private const val MAX_SECRET_CHARACTERS = 8_000
    private const val MAX_ENTITY_ID_CHARACTERS = 240
}
