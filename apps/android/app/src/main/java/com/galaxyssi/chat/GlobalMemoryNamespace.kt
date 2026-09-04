package com.galaxyssi.chat

import java.util.Locale

enum class GlobalMemoryNamespace {
    GENERAL,
    USER,
    PROJECT,
    DEVICE,
    SECURITY
}

data class GlobalMemoryNamespaceRef(
    val namespace: GlobalMemoryNamespace,
    val scopeId: String = ""
) {
    val key: String
        get() = namespace.name.lowercase(Locale.ROOT) +
            scopeId.takeIf(String::isNotBlank)?.let { ":$it" }.orEmpty()
}

object GlobalMemoryNamespacePolicy {
    fun resolve(
        event: GlobalConversationEvent,
        understanding: GlobalUnderstanding,
        kind: GlobalWorldItemKind,
        layer: GlobalWorldLayer
    ): GlobalMemoryNamespaceRef {
        parseExplicit(event.metadata["memory_namespace"])?.let { explicit ->
            val explicitScope = event.metadata["memory_namespace_id"].orEmpty()
                .ifBlank { explicit.scopeId }
            return explicit.copy(scopeId = normalizeScope(explicitScope))
        }
        val memoryKind = runCatching {
            AgentMemoryKind.valueOf(event.metadata["memory_kind"].orEmpty())
        }.getOrNull()
        val namespace = when {
            event.type in AUTHORIZATION_EVENTS || memoryKind == AgentMemoryKind.SAFETY ->
                GlobalMemoryNamespace.SECURITY
            isDeviceEvidence(event) -> GlobalMemoryNamespace.DEVICE
            memoryKind in setOf(
                AgentMemoryKind.IDENTITY,
                AgentMemoryKind.CONTACT,
                AgentMemoryKind.PREFERENCE
            ) || kind == GlobalWorldItemKind.PREFERENCE || layer == GlobalWorldLayer.USER ->
                GlobalMemoryNamespace.USER
            memoryKind in setOf(AgentMemoryKind.TASK, AgentMemoryKind.WORKFLOW) ||
                event.type == GlobalConversationEventType.TASK_UPDATED ||
                kind in setOf(GlobalWorldItemKind.GOAL, GlobalWorldItemKind.TASK) ||
                understanding.project.isNotBlank() ->
                GlobalMemoryNamespace.PROJECT
            else -> GlobalMemoryNamespace.GENERAL
        }
        return GlobalMemoryNamespaceRef(namespace, scopeId(namespace, event, understanding))
    }

    fun same(left: GlobalWorldItem, right: GlobalWorldItem): Boolean =
        left.memoryNamespaceKey() == right.memoryNamespaceKey()

    fun itemKey(item: GlobalWorldItem): String =
        "${item.memoryNamespaceKey()}\u0000${item.stableKey}"

    private fun parseExplicit(value: String?): GlobalMemoryNamespaceRef? {
        val clean = value.orEmpty().trim()
        if (clean.isBlank()) return null
        val namespaceName = clean.substringBefore(':').uppercase(Locale.ROOT)
        val namespace = GlobalMemoryNamespace.entries.firstOrNull { it.name == namespaceName } ?: return null
        return GlobalMemoryNamespaceRef(namespace, normalizeScope(clean.substringAfter(':', "")))
    }

    private fun scopeId(
        namespace: GlobalMemoryNamespace,
        event: GlobalConversationEvent,
        understanding: GlobalUnderstanding
    ): String {
        val keys = when (namespace) {
            GlobalMemoryNamespace.USER -> listOf("user_id", "profile_id")
            GlobalMemoryNamespace.PROJECT -> listOf("project_id", "workspace_id", "repository_id")
            GlobalMemoryNamespace.DEVICE -> listOf(
                "device_id",
                "target_device_id",
                "resource_id_hash",
                "client_route_id"
            )
            GlobalMemoryNamespace.SECURITY -> listOf("policy_id", "authorization_id")
            GlobalMemoryNamespace.GENERAL -> emptyList()
        }
        val explicit = keys.firstNotNullOfOrNull { key ->
            event.metadata[key]?.takeIf(String::isNotBlank)
        }.orEmpty()
        val inferred = when (namespace) {
            GlobalMemoryNamespace.PROJECT -> understanding.project.ifBlank {
                projectName("${event.conversationTitle} ${understanding.topic} ${event.content}")
            }.ifBlank { "default" }
            GlobalMemoryNamespace.DEVICE -> "local"
            GlobalMemoryNamespace.USER -> "self"
            GlobalMemoryNamespace.SECURITY -> "policy"
            GlobalMemoryNamespace.GENERAL -> ""
        }
        return normalizeScope(explicit.ifBlank { inferred })
    }

    private fun isDeviceEvidence(event: GlobalConversationEvent): Boolean {
        val resourceKind = event.metadata["resource_kind"].orEmpty().lowercase(Locale.ROOT)
        if (resourceKind in DEVICE_RESOURCE_KINDS || resourceKind.endsWith("_device")) return true
        val toolKey = event.metadata["tool_key"].orEmpty().lowercase(Locale.ROOT)
        if (DEVICE_TOOL_PREFIXES.any(toolKey::startsWith)) return true
        return DEVICE_METADATA_KEYS.any { event.metadata[it].isNullOrBlank().not() }
    }

    private fun projectName(value: String): String = PROJECT_NAME_PATTERN
        .find(value)
        ?.groupValues
        ?.getOrNull(1)
        .orEmpty()

    private fun normalizeScope(value: String): String = value
        .trim()
        .lowercase(Locale.ROOT)
        .replace(Regex("[^\\p{L}\\p{N}._-]+"), "-")
        .trim('-')
        .take(MAX_SCOPE_LENGTH)

    private val AUTHORIZATION_EVENTS = setOf(
        GlobalConversationEventType.AUTHORIZATION_GRANTED,
        GlobalConversationEventType.AUTHORIZATION_REVOKED,
        GlobalConversationEventType.AUTHORIZATION_POLICY_CHANGED
    )
    private val DEVICE_RESOURCE_KINDS = setOf(
        "android_device",
        "custom_device",
        "home_assistant",
        "phone",
        "smart_device"
    )
    private val DEVICE_TOOL_PREFIXES = listOf(
        "android.",
        "battery.",
        "bluetooth.",
        "camera.",
        "device.",
        "location.",
        "nfc.",
        "phone.",
        "sensor.",
        "telephony.",
        "wifi."
    )
    private val DEVICE_METADATA_KEYS = listOf(
        "device_id",
        "target_device_id",
        "client_route_id"
    )
    private val PROJECT_NAME_PATTERN =
        Regex("(?i)(?:\\bproject\\s+|\\u9879\\u76ee\\s*)([\\p{L}\\p{N}_.-]{2,64})")
    private const val MAX_SCOPE_LENGTH = 96
}

fun GlobalWorldItem.memoryNamespaceKey(): String =
    GlobalMemoryNamespaceRef(namespace, namespaceId).key
