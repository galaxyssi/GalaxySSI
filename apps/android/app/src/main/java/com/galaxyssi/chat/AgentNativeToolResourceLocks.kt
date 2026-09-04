package com.galaxyssi.chat

import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.Lock
import java.util.concurrent.locks.ReentrantReadWriteLock
import org.json.JSONArray
import org.json.JSONObject

internal enum class AgentNativeResourceLockMode {
    READ,
    WRITE
}

internal data class AgentNativeResourceLockRequest(
    val key: String,
    val mode: AgentNativeResourceLockMode
)

internal data class AgentNativeResourceLockPlan(
    val requests: List<AgentNativeResourceLockRequest>,
    val resourceScoped: Boolean
) {
    fun conflictsWith(other: AgentNativeResourceLockPlan): Boolean {
        val right = other.requests.associateBy(AgentNativeResourceLockRequest::key)
        return requests.any { left ->
            val matching = right[left.key] ?: return@any false
            left.mode == AgentNativeResourceLockMode.WRITE ||
                matching.mode == AgentNativeResourceLockMode.WRITE
        }
    }
}

/** Resolves workspace and hierarchical path locks without exposing local path names. */
internal object AgentNativeToolResourcePolicy {
    fun resolve(
        descriptor: AgentNativeToolDescriptor,
        input: AgentNativeJsonObject,
        fallbackWorkspaceId: String = ""
    ): AgentNativeResourceLockPlan {
        val operationMode = if (
            descriptor.concurrency == AgentNativeToolConcurrency.PARALLEL_READ_ONLY
        ) {
            AgentNativeResourceLockMode.READ
        } else {
            AgentNativeResourceLockMode.WRITE
        }
        if (input.requiresExclusiveVerification() || descriptor.requiresExclusiveGlobalMutation()) {
            return globalPlan(AgentNativeResourceLockMode.WRITE)
        }
        if (!descriptor.supportsWorkspaceScoping()) {
            return globalPlan(operationMode)
        }
        val workspaceId = descriptor.workspaceIdentity(input, fallbackWorkspaceId)
        if (workspaceId.isBlank()) return globalPlan(operationMode)

        val workspaceKey = "workspace:${stableSegment(workspaceId)}"
        val pathAccesses = if (descriptor.capabilities.any { "workspace" in it }) {
            collectPathAccesses(descriptor, input, operationMode)
        } else {
            emptyList()
        }
        val requests = mutableListOf(
            AgentNativeResourceLockRequest(GLOBAL_KEY, AgentNativeResourceLockMode.READ)
        )
        if (pathAccesses.isEmpty()) {
            requests += AgentNativeResourceLockRequest(workspaceKey, operationMode)
        } else {
            requests += AgentNativeResourceLockRequest(workspaceKey, AgentNativeResourceLockMode.READ)
            pathAccesses.forEach { access ->
                val components = normalizePath(access.path)
                if (components.isEmpty()) {
                    requests += AgentNativeResourceLockRequest(workspaceKey, access.mode)
                } else {
                    components.indices.forEach { index ->
                        val prefix = components.take(index + 1).joinToString("/")
                        requests += AgentNativeResourceLockRequest(
                            key = "path:${stableSegment(workspaceId)}:${stableSegment(prefix)}",
                            mode = if (index == components.lastIndex) {
                                access.mode
                            } else {
                                AgentNativeResourceLockMode.READ
                            }
                        )
                    }
                }
            }
        }
        return AgentNativeResourceLockPlan(normalizeRequests(requests), resourceScoped = true)
    }

    fun resolveAction(
        descriptor: AgentNativeToolDescriptor,
        action: AgentAction,
        fallbackWorkspaceId: String = ""
    ): AgentNativeResourceLockPlan? {
        val input = parseInput(action.parameters["input_json"].orEmpty()) ?: return null
        return resolve(descriptor, input, fallbackWorkspaceId)
    }

    private fun globalPlan(mode: AgentNativeResourceLockMode) = AgentNativeResourceLockPlan(
        requests = listOf(AgentNativeResourceLockRequest(GLOBAL_KEY, mode)),
        resourceScoped = false
    )

    private fun AgentNativeToolDescriptor.supportsWorkspaceScoping(): Boolean =
        capabilities.any { capability ->
            "workspace" in capability || capability.startsWith("runtime.") ||
                capability.startsWith("project.")
        }

    private fun AgentNativeToolDescriptor.requiresExclusiveGlobalMutation(): Boolean =
        id in EXCLUSIVE_GLOBAL_MUTATION_TOOL_IDS

    private val EXCLUSIVE_GLOBAL_MUTATION_TOOL_IDS = setOf(
        AgentMobileProjectNativeTools.COMMIT,
        AgentMobileProjectNativeTools.PUSH,
        AgentMobileProjectNativeTools.CREATE_PULL_REQUEST,
        AgentMobileProjectNativeTools.PUBLISH_PULL_REQUEST,
        AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST
    )

    private fun AgentNativeToolDescriptor.workspaceIdentity(
        input: AgentNativeJsonObject,
        fallbackWorkspaceId: String
    ): String {
        val explicit = input.stringValue("workspace_id")
        if (explicit.isNotBlank()) return "${location.wireValue}:$explicit"
        val desktopId = input.stringValue("desktop_id")
        if (desktopId.isNotBlank()) {
            return "${location.wireValue}:$desktopId:${fallbackWorkspaceId.ifBlank { "default" }}"
        }
        return fallbackWorkspaceId.trim().take(MAX_ID_CHARS)
            .takeIf(String::isNotBlank)
            ?.let { "${location.wireValue}:$it" }
            .orEmpty()
    }

    private fun collectPathAccesses(
        descriptor: AgentNativeToolDescriptor,
        input: AgentNativeJsonObject,
        operationMode: AgentNativeResourceLockMode
    ): List<PathAccess> = buildList {
        fun visit(key: String, value: Any?) {
            when (value) {
                is String -> if (key.isPathKey()) {
                    add(PathAccess(value, pathMode(descriptor.id, key, input, operationMode)))
                }
                is Map<*, *> -> value.forEach { (childKey, childValue) ->
                    if (childKey is String) visit(childKey, childValue)
                }
                is Iterable<*> -> value.forEach { child ->
                    if (key.isPathCollectionKey() && child is String) {
                        add(PathAccess(child, pathMode(descriptor.id, key, input, operationMode)))
                    } else {
                        visit(key, child)
                    }
                }
                is Array<*> -> value.forEach { child -> visit(key, child) }
            }
        }
        input.forEach { (key, value) -> visit(key, value) }
    }.filter { it.path.isNotBlank() }

    private fun pathMode(
        toolId: String,
        key: String,
        input: AgentNativeJsonObject,
        operationMode: AgentNativeResourceLockMode
    ): AgentNativeResourceLockMode {
        if (operationMode == AgentNativeResourceLockMode.READ) return operationMode
        val normalizedKey = key.lowercase(Locale.ROOT)
        if (normalizedKey == "source_path" || normalizedKey == "source_paths") {
            return if (toolId.endsWith(".move")) operationMode else AgentNativeResourceLockMode.READ
        }
        if (normalizedKey == "paths") return AgentNativeResourceLockMode.READ
        if (normalizedKey == "archive_path" &&
            (toolId.endsWith(".zip.extract") || toolId.endsWith(".zip.list"))
        ) {
            return AgentNativeResourceLockMode.READ
        }
        if (normalizedKey == "path" && input.containsKey("output_path")) {
            return AgentNativeResourceLockMode.READ
        }
        return operationMode
    }

    private fun String.isPathKey(): Boolean {
        val normalized = lowercase(Locale.ROOT)
        return normalized == "path" || normalized.endsWith("_path")
    }

    private fun String.isPathCollectionKey(): Boolean {
        val normalized = lowercase(Locale.ROOT)
        return normalized == "paths" || normalized.endsWith("_paths")
    }

    private fun normalizePath(value: String): List<String> {
        val normalized = mutableListOf<String>()
        value.replace('\\', '/').split('/').forEach { component ->
            when (component.trim()) {
                "", "." -> Unit
                ".." -> if (normalized.isNotEmpty()) normalized.removeAt(normalized.lastIndex)
                else -> normalized += component.trim().take(MAX_PATH_COMPONENT_CHARS)
            }
        }
        return normalized.take(MAX_PATH_COMPONENTS)
    }

    private fun normalizeRequests(
        requests: List<AgentNativeResourceLockRequest>
    ): List<AgentNativeResourceLockRequest> = requests
        .groupBy(AgentNativeResourceLockRequest::key)
        .map { (key, grouped) ->
            AgentNativeResourceLockRequest(
                key,
                if (grouped.any { it.mode == AgentNativeResourceLockMode.WRITE }) {
                    AgentNativeResourceLockMode.WRITE
                } else {
                    AgentNativeResourceLockMode.READ
                }
            )
        }
        .sortedBy(AgentNativeResourceLockRequest::key)

    private fun parseInput(raw: String): AgentNativeJsonObject? = runCatching {
        JSONObject(raw.ifBlank { "{}" }).toNativeJsonObject()
    }.getOrNull()

    private fun JSONObject.toNativeJsonObject(): AgentNativeJsonObject = keys().asSequence()
        .associateWith { key -> get(key).toNativeJsonValue() }

    private fun Any?.toNativeJsonValue(): Any? = when (this) {
        JSONObject.NULL -> null
        is JSONObject -> toNativeJsonObject()
        is JSONArray -> (0 until length()).map { index -> get(index).toNativeJsonValue() }
        else -> this
    }

    private fun AgentNativeJsonObject.stringValue(key: String): String =
        (this[key] as? String).orEmpty().trim().take(MAX_ID_CHARS)

    private fun AgentNativeJsonObject.requiresExclusiveVerification(): Boolean =
        stringValue("verification_kind")
            .lowercase(Locale.ROOT)
            .let { it.isNotBlank() && it != "none" }

    private fun stableSegment(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .take(16)
        .joinToString("") { byte -> "%02x".format(Locale.ROOT, byte.toInt() and 0xff) }

    private data class PathAccess(
        val path: String,
        val mode: AgentNativeResourceLockMode
    )

    private const val GLOBAL_KEY = "global"
    private const val MAX_ID_CHARS = 512
    private const val MAX_PATH_COMPONENTS = 256
    private const val MAX_PATH_COMPONENT_CHARS = 512
}

/** Fair, reference-counted lock table shared by all native-tool registries. */
internal object AgentNativeToolResourceLockTable {
    private val tableGuard = Any()
    private val entries = mutableMapOf<String, Entry>()

    fun <T> execute(
        plan: AgentNativeResourceLockPlan,
        checkpoint: () -> Unit,
        block: () -> T
    ): T {
        val reservations = reserve(plan.requests)
        val acquired = mutableListOf<Lock>()
        try {
            reservations.forEach { reservation ->
                val lock = when (reservation.request.mode) {
                    AgentNativeResourceLockMode.READ -> reservation.entry.lock.readLock()
                    AgentNativeResourceLockMode.WRITE -> reservation.entry.lock.writeLock()
                }
                acquire(lock, checkpoint)
                acquired += lock
            }
            checkpoint()
            return block()
        } finally {
            acquired.asReversed().forEach(Lock::unlock)
            release(reservations)
        }
    }

    private fun reserve(requests: List<AgentNativeResourceLockRequest>): List<Reservation> =
        synchronized(tableGuard) {
            requests.map { request ->
                val entry = entries.getOrPut(request.key) { Entry() }
                entry.references += 1
                Reservation(request, entry)
            }
        }

    private fun release(reservations: List<Reservation>) = synchronized(tableGuard) {
        reservations.forEach { reservation ->
            reservation.entry.references -= 1
            check(reservation.entry.references >= 0) { "Resource lock reference count underflow" }
            if (reservation.entry.references == 0) {
                entries.remove(reservation.request.key, reservation.entry)
            }
        }
    }

    private fun acquire(lock: Lock, checkpoint: () -> Unit) {
        while (true) {
            checkpoint()
            val acquired = try {
                lock.tryLock(POLL_MILLIS, TimeUnit.MILLISECONDS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                throw AgentNativeToolCancelledException()
            }
            if (acquired) return
        }
    }

    private class Entry(
        val lock: ReentrantReadWriteLock = ReentrantReadWriteLock(true),
        var references: Int = 0
    )

    private data class Reservation(
        val request: AgentNativeResourceLockRequest,
        val entry: Entry
    )

    private const val POLL_MILLIS = 100L
}
