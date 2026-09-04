package com.galaxyssi.chat

import android.content.Context

enum class AgentConfirmationTier {
    DIRECT,
    CONFIRM_ONCE,
    CONFIRM_ALWAYS
}

enum class AgentPermissionChoice(val wireValue: String) {
    ALLOW_ONCE("allow_once"),
    ALLOW_SESSION("allow_session"),
    ALLOW_ALWAYS("allow_always"),
    DENY_ALWAYS("deny_always");

    val approved: Boolean
        get() = this != DENY_ALWAYS

    companion object {
        fun fromWireValue(value: String): AgentPermissionChoice? =
            entries.firstOrNull { it.wireValue == value.trim().lowercase() }
    }
}

data class AgentConfirmationConsentDecision(
    val allowed: Boolean,
    val denied: Boolean,
    val choice: AgentPermissionChoice? = null,
    val grantId: String = "",
    val reason: String = ""
)

interface AgentConfirmationConsentStore {
    fun decision(
        consentKey: String,
        sessionId: String = "",
        consume: Boolean = false
    ): AgentConfirmationConsentDecision
    fun rememberedKeys(): Set<String>
    fun record(
        consentKey: String,
        choice: AgentPermissionChoice,
        sessionId: String = ""
    ): AgentConfirmationConsentDecision
    fun forget(consentKey: String): Boolean
    fun endSession(sessionId: String)
    fun clear()
}

class SharedPreferencesAgentConfirmationConsentStore(context: Context) : AgentConfirmationConsentStore {
    private val appContext = context.applicationContext
    private val grantStore: AgentPermissionGrantStore = EncryptedAgentPermissionGrantStore(appContext)
    private val revocationCoordinator by lazy {
        AgentPermissionRevocationCoordinator(
            grantStore = grantStore,
            workspaceStore = EncryptedAgentWorkspaceStore(appContext),
            runEventStore = AgentRunEventStore(appContext),
            pauseActiveWorkspace = { workspaceId, reason ->
                AgentTaskRuntime.supervisor(appContext).pauseForPermissionRevocation(workspaceId, reason)
            }
        )
    }

    override fun decision(
        consentKey: String,
        sessionId: String,
        consume: Boolean
    ): AgentConfirmationConsentDecision {
        val cleanKey = consentKey.trim()
        if (cleanKey.isBlank()) return AgentConfirmationConsentDecision(
            allowed = false,
            denied = false,
            reason = "invalid_consent_key"
        )
        val result = grantStore.authorize(
            permissionRequest(cleanKey, sessionId),
            consume = consume
        )
        val grant = result.grant
        return AgentConfirmationConsentDecision(
            allowed = result.granted,
            denied = grant?.effect == AgentPermissionGrantEffect.DENY,
            choice = grant?.toPermissionChoice(),
            grantId = grant?.grantId.orEmpty(),
            reason = result.reason
        )
    }

    override fun rememberedKeys(): Set<String> = grantStore.list(includeInactive = false)
        .asSequence()
        .filter { it.subjectType == AgentPermissionSubjectType.CONSEQUENTIAL_ACTION }
        .filter { it.effect == AgentPermissionGrantEffect.ALLOW }
        .map(AgentPermissionGrant::scope)
        .toSet()

    override fun record(
        consentKey: String,
        choice: AgentPermissionChoice,
        sessionId: String
    ): AgentConfirmationConsentDecision {
        val cleanKey = consentKey.trim()
        if (cleanKey.isBlank()) return AgentConfirmationConsentDecision(
            allowed = false,
            denied = false,
            reason = "invalid_consent_key"
        )
        val cleanSessionId = sessionId.trim()
        if (choice == AgentPermissionChoice.ALLOW_SESSION) {
            require(cleanSessionId.isNotBlank()) { "Session permission requires a session id" }
        }
        val before = rememberedKeys()
        grantStore.revokeScope(cleanKey, "user_replaced_permission_decision")
        val lifetime = when (choice) {
            AgentPermissionChoice.ALLOW_ONCE -> AgentPermissionGrantLifetime.SINGLE_USE
            AgentPermissionChoice.ALLOW_SESSION -> AgentPermissionGrantLifetime.SESSION
            AgentPermissionChoice.ALLOW_ALWAYS,
            AgentPermissionChoice.DENY_ALWAYS -> AgentPermissionGrantLifetime.PERMANENT
        }
        val effect = if (choice.approved) {
            AgentPermissionGrantEffect.ALLOW
        } else {
            AgentPermissionGrantEffect.DENY
        }
        val grant = grantStore.grant(
            AgentPermissionGrant(
                subjectType = AgentPermissionSubjectType.CONSEQUENTIAL_ACTION,
                subjectId = HOST_SUBJECT_ID,
                scope = cleanKey,
                action = cleanKey,
                issuer = AgentPermissionGrantIssuer.USER,
                evidence = "user_decision:${choice.wireValue}",
                lifetime = lifetime,
                effect = effect,
                sessionId = if (lifetime == AgentPermissionGrantLifetime.SESSION) cleanSessionId else ""
            )
        )
        val current = if (choice == AgentPermissionChoice.ALLOW_ONCE) {
            grantStore.authorize(permissionRequest(cleanKey, cleanSessionId), consume = true)
        } else {
            AgentPermissionDecision(choice.approved, grant, "user_decision_recorded")
        }
        val after = rememberedKeys()
        GlobalConversationEventBus.publishCapabilityEvents(
            appContext,
            GlobalCapabilityObservationExtractor.authorizationMutations(before, after)
        )
        return AgentConfirmationConsentDecision(
            allowed = current.granted,
            denied = effect == AgentPermissionGrantEffect.DENY,
            choice = choice,
            grantId = grant.grantId,
            reason = current.reason
        )
    }

    override fun forget(consentKey: String): Boolean {
        val cleanKey = consentKey.trim()
        val before = rememberedKeys()
        val revocation = revocationCoordinator.revokeScope(
            cleanKey,
            "user_revoked_remembered_confirmation"
        ).revocation
        if (revocation.revokedGrantIds.isEmpty()) return false
        val after = rememberedKeys()
        GlobalConversationEventBus.publishCapabilityEvents(
            appContext,
            GlobalCapabilityObservationExtractor.authorizationMutations(before, after)
        )
        return true
    }

    override fun endSession(sessionId: String) {
        val cleanSessionId = sessionId.trim()
        if (cleanSessionId.isBlank()) return
        val before = rememberedKeys()
        grantStore.revokeSession(cleanSessionId, "agent_session_ended")
        val after = rememberedKeys()
        GlobalConversationEventBus.publishCapabilityEvents(
            appContext,
            GlobalCapabilityObservationExtractor.authorizationMutations(before, after)
        )
    }

    override fun clear() = grantStore.clear()

    private fun permissionRequest(consentKey: String, sessionId: String) = AgentPermissionRequest(
        subjectType = AgentPermissionSubjectType.CONSEQUENTIAL_ACTION,
        subjectId = HOST_SUBJECT_ID,
        scope = consentKey,
        action = consentKey,
        sessionId = sessionId
    )

    private fun AgentPermissionGrant.toPermissionChoice(): AgentPermissionChoice = when {
        effect == AgentPermissionGrantEffect.DENY -> AgentPermissionChoice.DENY_ALWAYS
        lifetime == AgentPermissionGrantLifetime.SINGLE_USE -> AgentPermissionChoice.ALLOW_ONCE
        lifetime == AgentPermissionGrantLifetime.SESSION -> AgentPermissionChoice.ALLOW_SESSION
        else -> AgentPermissionChoice.ALLOW_ALWAYS
    }

    private companion object {
        const val HOST_SUBJECT_ID = "galaxyssi-host"
    }
}

object AgentConfirmationPolicy {
    fun tier(@Suppress("UNUSED_PARAMETER") action: AgentAction): AgentConfirmationTier =
        AgentConfirmationTier.DIRECT

    fun consentKey(action: AgentAction): String {
        val value = searchableValue(action)
        return when {
            LOCATION_TERMS.any(value::contains) -> "location"
            MICROPHONE_TERMS.any(value::contains) -> "microphone"
            DOWNLOAD_TERMS.any(value::contains) -> "downloads"
            CONTACT_WRITE_TERMS.any(value::contains) -> "contacts_write"
            CALENDAR_WRITE_TERMS.any(value::contains) -> "calendar_write"
            nativeToolId(action) == AgentHardwareNativeTools.BLUETOOTH_DISCOVERY_FOREGROUND -> "bluetooth_discovery"
            nativeToolId(action) == AgentAndroidSystemNativeTools.WIFI_SCAN_START -> "wifi_scan"
            nativeToolId(action) in setOf(
                AgentHardwareNativeTools.INSTALLED_APPS_LIST,
                AgentHardwareNativeTools.PACKAGE_DETAIL
            ) -> "installed_apps_read"
            nativeToolId(action) in setOf(
                AgentHomeAssistantNativeTools.ENTITIES_LIST,
                AgentHomeAssistantNativeTools.ENTITY_READ
            ) -> "home_assistant_read"
            nativeToolId(action) == AgentHomeAssistantNativeTools.SERVICE_CALL ->
                AgentHomeAssistantNativeTools.consentScope(action.parameters["input_json"].orEmpty())
            action.kind == AgentActionKind.CONTROL_DEVICE -> "device_control:${action.target.lowercase().trim()}"
            else -> "action:${action.kind.name.lowercase()}:${action.id.lowercase().trim()}"
        }
    }

    private fun nativeToolId(action: AgentAction): String = action.parameters["tool_id"].orEmpty()

    private fun searchableValue(action: AgentAction): String = buildString {
        append(action.id).append(' ')
        append(action.kind.name).append(' ')
        append(action.target).append(' ')
        append(action.description).append(' ')
        action.parameters.forEach { (key, value) ->
            // Session context is evidence for the model, not part of the current action's risk intent.
            if (!key.startsWith(INTERNAL_PARAMETER_PREFIX)) {
                append(key).append(' ').append(value).append(' ')
            }
        }
    }.lowercase()

    private const val INTERNAL_PARAMETER_PREFIX = "_galaxyssi_"

    private val ALWAYS_CONFIRM_KINDS = setOf(
        AgentActionKind.REPLY_NOTIFICATION,
        AgentActionKind.DELETE_TEXT,
        AgentActionKind.LOCK_SCREEN
    )

    private val DIRECT_ACTION_IDS = setOf(
        "set-timer", "open-timer", "set-alarm", "open-camera", "open-flashlight",
        "battery-status", "device-status"
    )

    private val DIRECT_NATIVE_TOOL_IDS = setOf(
        AgentHardwareNativeTools.BATTERY_STATUS,
        AgentHardwareNativeTools.POWER_STATUS,
        AgentHardwareNativeTools.MEMORY_STATUS,
        AgentHardwareNativeTools.STORAGE_STATUS,
        AgentHardwareNativeTools.NETWORK_STATUS,
        AgentHardwareNativeTools.SENSORS_LIST,
        AgentHardwareNativeTools.SENSOR_SAMPLE,
        AgentHardwareNativeTools.BLUETOOTH_STATUS,
        AgentHardwareNativeTools.NFC_STATUS,
        AgentHardwareNativeTools.FLASHLIGHT_SET,
        AgentVisibleCaptureNativeTools.CAMERA_CAPTURE,
        AgentWebMediaNativeTools.WEB_SEARCH,
        *AgentWebIntelligenceNativeTools.toolIds.toTypedArray(),
        AgentWebMediaNativeTools.MEDIA_FFMPEG_TRANSCODE,
        AgentOnDeviceRuntimeTools.EXECUTE,
        AgentHardwareNativeTools.BLUETOOTH_PAIRING_HANDOFF,
        AgentAndroidSystemNativeTools.AUDIO_STATUS,
        AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET,
        AgentAndroidSystemNativeTools.AUDIO_MUTE_SET,
        AgentAndroidSystemNativeTools.WIFI_PANEL_OPEN,
        AgentAndroidSystemNativeTools.WIFI_HOTSPOT_PANEL_OPEN,
        AgentAndroidSystemNativeTools.BIOMETRIC_ENROLLMENT_OPEN
    )

    private val CONFIRM_ONCE_NATIVE_TOOL_IDS = setOf(
        AgentVisibleCaptureNativeTools.MICROPHONE_RECORD,
        AgentNotificationNativeTools.NOTIFICATIONS_LIST,
        AgentHardwareNativeTools.BLUETOOTH_DISCOVERY_FOREGROUND,
        AgentHardwareNativeTools.INSTALLED_APPS_LIST,
        AgentHardwareNativeTools.PACKAGE_DETAIL,
        AgentAndroidSystemNativeTools.WIFI_SCAN_START,
        AgentOnDeviceRuntimeTools.INSTALL_PACK,
        AgentHomeAssistantNativeTools.ENTITIES_LIST,
        AgentHomeAssistantNativeTools.ENTITY_READ,
        AgentHomeAssistantNativeTools.SERVICE_CALL
    )

    private val ALWAYS_CONFIRM_NATIVE_TOOL_IDS = setOf(
        AgentNotificationNativeTools.NOTIFICATION_REPLY
    )

    private val ALWAYS_CONFIRM_TERMS = listOf(
        "send sms", "sms.send", "reply sms", "send message", "reply message", "reply notification",
        "send email", "reply email", "phone call", "dial", "telephony.dial", "delete", "remove",
        "install", "uninstall", "payment", "purchase", "checkout", "transfer", "grant permission",
        "authorize", "security setting", "system setting", "registry edit", "screen lock", "lock device",
        "device_policy.lock", "reboot", "git commit", "git push", "submit code", "commit code",
        "door lock", "smart lock", "garage door", "alarm panel", "private key", "password",
        "\u53d1\u9001\u77ed\u4fe1", "\u56de\u590d\u77ed\u4fe1", "\u53d1\u6d88\u606f", "\u56de\u590d\u6d88\u606f",
        "\u6253\u7535\u8bdd", "\u62e8\u53f7", "\u5220\u9664", "\u5b89\u88c5", "\u5378\u8f7d", "\u652f\u4ed8",
        "\u8f6c\u8d26", "\u6388\u6743", "\u6743\u9650", "\u5b89\u5168\u8bbe\u7f6e", "\u7cfb\u7edf\u8bbe\u7f6e",
        "\u63d0\u4ea4\u4ee3\u7801", "\u63a8\u9001\u4ee3\u7801", "\u9501\u5c4f", "\u91cd\u542f",
        "\u95e8\u9501", "\u8f66\u5e93\u95e8"
    )

    private val DIRECT_TERMS = listOf(
        "timer", "alarm clock", "set alarm", "camera capture", "take photo", "flashlight", "torch",
        "audio volume", "set volume", "audio mute", "open app", "launch app", "battery status",
        "device status", "read battery", "read device", "\u8ba1\u65f6\u5668", "\u95f9\u949f", "\u62cd\u7167",
        "\u624b\u7535\u7b52", "\u97f3\u91cf", "\u6253\u5f00app", "\u6253\u5f00 app", "\u7535\u91cf", "\u8bbe\u5907\u72b6\u6001"
    )

    private val LOCATION_TERMS = listOf("location", "gps", "\u5b9a\u4f4d", "\u4f4d\u7f6e")
    private val MICROPHONE_TERMS = listOf("microphone", "record audio", "\u9ea6\u514b\u98ce", "\u5f55\u97f3")
    private val DOWNLOAD_TERMS = listOf("download", "\u4e0b\u8f7d")
    private val CONTACT_WRITE_TERMS = listOf(
        "contacts.write", "contact upsert", "create contact", "update contact",
        "\u65b0\u5efa\u8054\u7cfb\u4eba", "\u4fee\u6539\u8054\u7cfb\u4eba", "\u66f4\u65b0\u8054\u7cfb\u4eba"
    )
    private val CALENDAR_WRITE_TERMS = listOf(
        "calendar.write", "calendar event upsert", "create calendar event", "update calendar event",
        "\u65b0\u5efa\u65e5\u7a0b", "\u4fee\u6539\u65e5\u7a0b", "\u66f4\u65b0\u65e5\u7a0b"
    )
    private val CONFIRM_ONCE_TERMS =
        LOCATION_TERMS + MICROPHONE_TERMS + DOWNLOAD_TERMS + CONTACT_WRITE_TERMS + CALENDAR_WRITE_TERMS
}
