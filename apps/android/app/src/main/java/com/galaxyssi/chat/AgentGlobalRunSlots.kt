package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.Locale
import java.util.UUID

internal object AgentConnectorCapacityPolicy {
    const val MAX_PARALLEL_RUNS = 10

    fun normalize(value: Int): Int = value.coerceIn(1, MAX_PARALLEL_RUNS)
}

internal object AgentRuntimeIdentity {
    fun key(registration: AgentRegistration): String = registration.runtimeFailureDomain
        .ifBlank { registration.failureDomain }
        .ifBlank {
            listOf(registration.installationId, registration.adapterType)
                .filter(String::isNotBlank)
                .joinToString(":")
        }
        .ifBlank { registration.agentId }
        .trim()
        .lowercase(Locale.ROOT)
}

internal object AgentMentionCandidatePolicy {
    private val genericAliases = setOf("codex", "hermes", "claude-code", "openclaw")

    fun select(
        targets: List<AgentCallableTarget>,
        registrations: List<AgentRegistration>,
        reservedByAgentId: Map<String, Int>,
        limit: Int
    ): List<AgentRegistration> {
        val availableTargetIds = targets
            .filter { target ->
                target.status == AgentConnectorStatus.AVAILABLE &&
                    target.kind in setOf(AgentConnectorKind.AGENT, AgentConnectorKind.MODEL)
            }
            .mapTo(linkedSetOf(), AgentCallableTarget::id)
        val reachable = registrations
            .filter { registration ->
                registration.agentId in availableTargetIds &&
                    registration.kind in setOf(AgentConnectorKind.AGENT, AgentConnectorKind.MODEL) &&
                    registration.status in setOf(
                        AgentEndpointStatus.ONLINE,
                        AgentEndpointStatus.IDLE,
                        AgentEndpointStatus.BUSY
                    )
            }
            .distinctBy(AgentRegistration::agentId)
        val concreteProductIds = reachable
            .filterNot { it.agentId in genericAliases }
            .mapTo(linkedSetOf(), ::productId)
        return reachable
            .filterNot { registration ->
                registration.agentId in genericAliases &&
                    productId(registration) in concreteProductIds
            }
            .filter { registration ->
                registration.activeRuns + reservedByAgentId.getOrDefault(registration.agentId, 0) <
                    registration.maxParallelRuns.coerceAtLeast(1)
            }
            .sortedWith(
                compareBy<AgentRegistration> { it.activeRuns }
                    .thenBy(String.CASE_INSENSITIVE_ORDER, AgentRegistration::displayName)
            )
            .take(limit)
    }

    private fun productId(registration: AgentRegistration): String {
        val raw = registration.providerProfile?.metadata
            ?.get("native_product_identity").orEmpty()
            .ifBlank { registration.providerProfile?.productId.orEmpty() }
            .ifBlank { registration.agentId.substringAfterLast(':') }
            .trim()
            .lowercase(Locale.ROOT)
            .replace('_', '-')
        return when (raw) {
            "claude-code" -> "claude"
            else -> raw
        }
    }
}

internal data class AgentGlobalRunSlot(
    val ownerId: String,
    val runtimeKey: String,
    val sourceMessageId: Long = 0L,
    val startedAtMillis: Long,
    val lastActivityAtMillis: Long = startedAtMillis
)

internal class AgentGlobalRunSlotLedger(
    records: Collection<AgentGlobalRunSlot> = emptyList()
) {
    private val slots = records.associateByTo(linkedMapOf(), AgentGlobalRunSlot::ownerId)

    fun acquire(ownerId: String, runtimeKey: String, maxParallelRuns: Int, nowMillis: Long): Boolean {
        if (ownerId.isBlank() || runtimeKey.isBlank()) return false
        slots[ownerId]?.let { return it.runtimeKey == runtimeKey }
        val limit = AgentConnectorCapacityPolicy.normalize(maxParallelRuns)
        if (activeCount(runtimeKey) >= limit) return false
        slots[ownerId] = AgentGlobalRunSlot(ownerId, runtimeKey, startedAtMillis = nowMillis)
        return true
    }

    fun bindSourceMessage(ownerId: String, sourceMessageId: Long): Boolean {
        if (sourceMessageId <= 0L) return false
        val current = slots[ownerId] ?: return false
        slots[ownerId] = current.copy(sourceMessageId = sourceMessageId)
        return true
    }

    fun release(ownerId: String): Boolean = slots.remove(ownerId) != null

    fun releaseBySourceMessageId(sourceMessageId: Long): Boolean {
        if (sourceMessageId <= 0L) return false
        val owners = slots.values
            .filter { it.sourceMessageId == sourceMessageId }
            .map(AgentGlobalRunSlot::ownerId)
        owners.forEach(slots::remove)
        return owners.isNotEmpty()
    }

    fun touchBySourceMessageId(sourceMessageId: Long, nowMillis: Long): Boolean {
        if (sourceMessageId <= 0L || nowMillis <= 0L) return false
        val owners = slots.values
            .filter { it.sourceMessageId == sourceMessageId }
            .map(AgentGlobalRunSlot::ownerId)
        owners.forEach { ownerId ->
            slots[ownerId]?.let { slots[ownerId] = it.copy(lastActivityAtMillis = nowMillis) }
        }
        return owners.isNotEmpty()
    }

    fun activeCount(runtimeKey: String): Int = slots.values.count { it.runtimeKey == runtimeKey }

    fun activeCounts(): Map<String, Int> = slots.values
        .groupingBy(AgentGlobalRunSlot::runtimeKey)
        .eachCount()

    fun pruneBefore(cutoffMillis: Long): Boolean {
        val expired = slots.values
            .filter { it.lastActivityAtMillis < cutoffMillis }
            .map(AgentGlobalRunSlot::ownerId)
        expired.forEach(slots::remove)
        return expired.isNotEmpty()
    }

    fun records(): List<AgentGlobalRunSlot> = slots.values.toList()
}

/**
 * One encrypted task-slot ledger shared by every conversation and Agent runtime in the app process.
 * The short lease also prevents a lost terminal envelope from reserving capacity forever.
 */
internal class AgentGlobalRunSlotStore(context: Context) {
    private val preferences = AgentEncryptedPreferences(context.applicationContext, PREFERENCES_NAME)

    fun acquire(registration: AgentRegistration, ownerId: String): Boolean = synchronized(LOCK) {
        val ledger = loadPruned()
        val acquired = ledger.acquire(
            ownerId = ownerId,
            runtimeKey = AgentRuntimeIdentity.key(registration),
            maxParallelRuns = registration.maxParallelRuns,
            nowMillis = System.currentTimeMillis()
        )
        if (acquired) persist(ledger)
        acquired
    }

    fun bindSourceMessage(ownerId: String, sourceMessageId: Long) = synchronized(LOCK) {
        val ledger = loadPruned()
        if (terminalSources.remove(sourceMessageId) != null) {
            if (ledger.release(ownerId)) persist(ledger)
            return@synchronized
        }
        if (ledger.bindSourceMessage(ownerId, sourceMessageId)) persist(ledger)
    }

    fun release(ownerId: String) = synchronized(LOCK) {
        val ledger = loadPruned()
        if (ledger.release(ownerId)) persist(ledger)
    }

    fun releaseBySourceMessageId(sourceMessageId: Long) = synchronized(LOCK) {
        if (sourceMessageId <= 0L) return@synchronized
        val now = System.currentTimeMillis()
        terminalSources.entries.removeIf { now - it.value > TERMINAL_SOURCE_TTL_MILLIS }
        val ledger = loadPruned(now)
        if (ledger.releaseBySourceMessageId(sourceMessageId)) {
            persist(ledger)
        } else {
            // Covers a very fast response that reaches the bus before dispatch binds its source id.
            terminalSources[sourceMessageId] = now
        }
    }

    fun touchBySourceMessageId(sourceMessageId: Long, nowMillis: Long = System.currentTimeMillis()) = synchronized(LOCK) {
        val ledger = loadPruned(nowMillis)
        if (ledger.touchBySourceMessageId(sourceMessageId, nowMillis)) persist(ledger)
    }

    fun activeCounts(): Map<String, Int> = synchronized(LOCK) {
        loadPruned().activeCounts()
    }

    private fun loadPruned(nowMillis: Long = System.currentTimeMillis()): AgentGlobalRunSlotLedger {
        val raw = preferences.readString(RECORDS_KEY, "[]")
        val array = runCatching { JSONArray(raw) }.getOrElse { JSONArray() }
        val records = buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                val ownerId = item.optString("owner_id")
                val runtimeKey = item.optString("runtime_key")
                val startedAt = item.optLong("started_at_millis")
                if (ownerId.isBlank() || runtimeKey.isBlank() || startedAt <= 0L) continue
                add(
                    AgentGlobalRunSlot(
                        ownerId = ownerId,
                        runtimeKey = runtimeKey,
                        sourceMessageId = item.optLong("source_message_id"),
                        startedAtMillis = startedAt,
                        lastActivityAtMillis = item.optLong("last_activity_at_millis", startedAt)
                    )
                )
            }
        }
        return AgentGlobalRunSlotLedger(records).also { ledger ->
            if (ledger.pruneBefore(nowMillis - SLOT_LEASE_MILLIS)) persist(ledger)
        }
    }

    private fun persist(ledger: AgentGlobalRunSlotLedger) {
        val array = JSONArray()
        ledger.records().forEach { slot ->
            array.put(
                JSONObject()
                    .put("owner_id", slot.ownerId)
                    .put("runtime_key", slot.runtimeKey)
                    .put("source_message_id", slot.sourceMessageId)
                    .put("started_at_millis", slot.startedAtMillis)
                    .put("last_activity_at_millis", slot.lastActivityAtMillis)
            )
        }
        preferences.writeString(RECORDS_KEY, array.toString())
    }

    companion object {
        private val LOCK = Any()
        private val terminalSources = linkedMapOf<Long, Long>()
        private const val PREFERENCES_NAME = "galaxyssi_agent_global_run_slots"
        private const val RECORDS_KEY = "active_slots"
        private const val SLOT_LEASE_MILLIS = 20L * 60L * 1_000L
        private const val TERMINAL_SOURCE_TTL_MILLIS = 60_000L

        fun ownerId(action: AgentAction, connectorId: String): String {
            val source = listOf(
                action.parameters["_galaxyssi_conversation_id"].orEmpty(),
                action.parameters["_galaxyssi_turn_id"].orEmpty(),
                action.id,
                connectorId
            ).joinToString("\u001f")
            return UUID.nameUUIDFromBytes(source.toByteArray(StandardCharsets.UTF_8)).toString()
        }
    }
}
