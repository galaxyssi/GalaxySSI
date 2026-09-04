package com.galaxyssi.chat

import java.util.UUID
import java.util.Locale

const val AGENT_TOOL_HANDLE_CONTRACT = "galaxyssi.tool-handle/1.0"

class AgentExplicitToolHandleException(
    val code: String,
    override val message: String,
    val retryable: Boolean = false
) : RuntimeException(message)

data class AgentExplicitToolHandleScope(
    val ownerId: String,
    val contextId: String = ""
) {
    init {
        require(ownerId.isNotBlank()) { "Tool handle owner must not be blank" }
    }

    companion object {
        fun from(context: AgentNativeToolInvocationContext) = AgentExplicitToolHandleScope(
            ownerId = context.callerId,
            contextId = context.conversationId.ifBlank { context.sessionId }
        )
    }
}

data class AgentExplicitToolHandleResolution(
    val handleId: String,
    val kind: String,
    val capabilities: Set<String>,
    val resourceId: String,
    val resource: Any,
    val expiresAtEpochMillis: Long
)

class AgentExplicitToolHandleRegistry(
    private val clock: AgentNativeClock = AgentNativeClock.SYSTEM,
    private val maxHandles: Int = 512
) {
    private data class Entry(
        val handleId: String,
        val kind: String,
        val resourceId: String,
        val ownerId: String,
        val contextId: String,
        val capabilities: Set<String>,
        val resource: Any,
        val metadata: Map<String, Any?>,
        val createdAtEpochMillis: Long,
        var lastUsedAtEpochMillis: Long,
        val expiresAtEpochMillis: Long,
        val idleTimeoutMillis: Long,
        var useCount: Long = 0
    )

    private val lock = Any()
    private val entries = linkedMapOf<String, Entry>()

    fun create(
        kind: String,
        resourceId: String,
        scope: AgentExplicitToolHandleScope,
        capabilities: Set<String>,
        resource: Any,
        ttlMillis: Long = DEFAULT_TTL_MILLIS,
        idleTimeoutMillis: Long = DEFAULT_IDLE_TIMEOUT_MILLIS,
        metadata: Map<String, Any?> = emptyMap()
    ): Map<String, Any?> {
        val normalizedKind = checked(kind, "kind", 80).lowercase(Locale.ROOT)
        val normalizedResourceId = checked(resourceId, "resource_id", 512)
        if (!KIND_PATTERN.matches(normalizedKind)) {
            fail("tool_handle_kind_invalid", "Tool handle kind is invalid")
        }
        if (normalizedResourceId.isBlank()) {
            fail("tool_handle_resource_required", "Tool handle resource is required")
        }
        val normalizedOwner = checked(scope.ownerId, "owner_id", 240)
        val normalizedContext = checked(scope.contextId, "context_id", 240)
        val normalizedCapabilities = capabilities
            .map { checked(it, "capability", 160) }
            .filter(String::isNotBlank)
            .toSet()
        if (normalizedCapabilities.isEmpty()) {
            throw AgentExplicitToolHandleException(
                "tool_handle_capability_required",
                "Tool handle requires at least one capability"
            )
        }
        val now = clock.nowEpochMillis()
        val ttl = ttlMillis.coerceIn(1L, MAX_TTL_MILLIS)
        val idle = idleTimeoutMillis.coerceIn(0L, ttl)
        synchronized(lock) {
            pruneLocked(now)
            while (entries.size >= maxHandles.coerceAtLeast(1)) {
                val oldest = entries.values.minByOrNull { it.lastUsedAtEpochMillis } ?: break
                entries.remove(oldest.handleId)
            }
            val handleId = newHandleId(normalizedKind)
            val entry = Entry(
                handleId = handleId,
                kind = normalizedKind,
                resourceId = normalizedResourceId,
                ownerId = normalizedOwner,
                contextId = normalizedContext,
                capabilities = normalizedCapabilities,
                resource = resource,
                metadata = publicMetadata(metadata),
                createdAtEpochMillis = now,
                lastUsedAtEpochMillis = now,
                expiresAtEpochMillis = now + ttl,
                idleTimeoutMillis = idle
            )
            entries[handleId] = entry
            return public(entry)
        }
    }

    fun resolve(
        handleId: String,
        kind: String,
        scope: AgentExplicitToolHandleScope,
        requiredCapability: String
    ): AgentExplicitToolHandleResolution {
        val normalizedId = checked(handleId, "handle_id", 240)
        val normalizedKind = checked(kind, "kind", 80).lowercase(Locale.ROOT)
        val normalizedOwner = checked(scope.ownerId, "owner_id", 240)
        val normalizedContext = checked(scope.contextId, "context_id", 240)
        val capability = checked(requiredCapability, "required_capability", 160)
        val now = clock.nowEpochMillis()
        synchronized(lock) {
            val entry = entries[normalizedId] ?: fail(
                "tool_handle_not_found",
                "Tool handle is missing, expired, or was released",
                retryable = true
            )
            if (expired(entry, now)) {
                entries.remove(normalizedId)
                fail(
                    "tool_handle_expired",
                    "Tool handle expired; create a new handle and retry",
                    retryable = true
                )
            }
            if (entry.kind != normalizedKind) {
                fail("tool_handle_kind_mismatch", "Tool handle belongs to a different resource type")
            }
            if (entry.ownerId != normalizedOwner) {
                fail("tool_handle_owner_mismatch", "Tool handle belongs to a different caller")
            }
            if (entry.contextId.isNotBlank() && entry.contextId != normalizedContext) {
                fail(
                    "tool_handle_context_mismatch",
                    "Tool handle belongs to a different conversation context"
                )
            }
            if (capability !in entry.capabilities) {
                fail(
                    "tool_handle_capability_denied",
                    "Tool handle does not grant the requested capability"
                )
            }
            entry.lastUsedAtEpochMillis = now
            entry.useCount += 1
            return AgentExplicitToolHandleResolution(
                handleId = entry.handleId,
                kind = entry.kind,
                capabilities = entry.capabilities,
                resourceId = entry.resourceId,
                resource = entry.resource,
                expiresAtEpochMillis = entry.expiresAtEpochMillis
            )
        }
    }

    fun release(handleId: String, scope: AgentExplicitToolHandleScope): Boolean {
        val normalizedId = checked(handleId, "handle_id", 240)
        val normalizedOwner = checked(scope.ownerId, "owner_id", 240)
        val normalizedContext = checked(scope.contextId, "context_id", 240)
        synchronized(lock) {
            val entry = entries[normalizedId] ?: return false
            if (entry.ownerId != normalizedOwner) {
                fail("tool_handle_owner_mismatch", "Tool handle belongs to a different caller")
            }
            if (entry.contextId.isNotBlank() && entry.contextId != normalizedContext) {
                fail(
                    "tool_handle_context_mismatch",
                    "Tool handle belongs to a different conversation context"
                )
            }
            entries.remove(normalizedId)
            return true
        }
    }

    fun revokeResource(kind: String, resourceId: String): Int {
        synchronized(lock) {
            val targets = entries.values
                .filter { it.kind == kind && it.resourceId == resourceId }
                .map { it.handleId }
            targets.forEach(entries::remove)
            return targets.size
        }
    }

    fun status(): Map<String, Any?> = synchronized(lock) {
        pruneLocked(clock.nowEpochMillis())
        mapOf(
            "contract" to AGENT_TOOL_HANDLE_CONTRACT,
            "active_count" to entries.size,
            "by_kind" to entries.values.groupingBy { it.kind }.eachCount()
        )
    }

    private fun pruneLocked(now: Long) {
        entries.values.filter { expired(it, now) }.map { it.handleId }.forEach(entries::remove)
    }

    private fun expired(entry: Entry, now: Long): Boolean =
        now >= entry.expiresAtEpochMillis ||
            entry.idleTimeoutMillis > 0L &&
            now >= entry.lastUsedAtEpochMillis + entry.idleTimeoutMillis

    private fun public(entry: Entry): Map<String, Any?> = linkedMapOf(
        "contract" to AGENT_TOOL_HANDLE_CONTRACT,
        "handle_id" to entry.handleId,
        "kind" to entry.kind,
        "capabilities" to entry.capabilities.sorted(),
        "owner_id" to entry.ownerId,
        "context_id" to entry.contextId,
        "metadata" to entry.metadata,
        "created_at_epoch_ms" to entry.createdAtEpochMillis,
        "last_used_at_epoch_ms" to entry.lastUsedAtEpochMillis,
        "expires_at_epoch_ms" to entry.expiresAtEpochMillis,
        "use_count" to entry.useCount
    )

    private fun checked(value: String, field: String, maxLength: Int): String {
        val normalized = value.trim()
        if (normalized.length > maxLength || normalized.any { it.code < 32 }) {
            fail("tool_handle_input_invalid", "$field exceeds its safe limit")
        }
        return normalized
    }

    private fun fail(code: String, message: String, retryable: Boolean = false): Nothing =
        throw AgentExplicitToolHandleException(code, message, retryable)

    private fun newHandleId(kind: String): String {
        val prefix = kind.filter(Char::isLetterOrDigit).take(8)
        return "sth_${prefix}_${UUID.randomUUID().toString().replace("-", "")}"
    }

    private fun publicMetadata(values: Map<String, Any?>): Map<String, Any?> {
        if (values.size > MAX_METADATA_ITEMS) {
            fail("tool_handle_input_invalid", "Tool handle metadata has too many entries")
        }
        return buildMap {
            values.forEach { (key, value) ->
                val normalizedKey = checked(key, "metadata key", 80)
                when (value) {
                    null, is Boolean, is Number -> put(normalizedKey, value)
                    is String -> put(normalizedKey, checked(value, "metadata $normalizedKey", 240))
                }
            }
        }
    }

    companion object {
        const val DEFAULT_TTL_MILLIS = 30L * 60L * 1_000L
        const val DEFAULT_IDLE_TIMEOUT_MILLIS = 10L * 60L * 1_000L
        const val MAX_TTL_MILLIS = 24L * 60L * 60L * 1_000L
        private const val MAX_METADATA_ITEMS = 32
        private val KIND_PATTERN = Regex("[a-z0-9][a-z0-9._-]{0,79}")

        val SHARED: AgentExplicitToolHandleRegistry by lazy {
            AgentExplicitToolHandleRegistry()
        }
    }
}
