package com.signalasi.chat

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.util.Log
import com.signalasi.chat.voice.VoiceFeatureFlags
import com.signalasi.chat.voice.agent.VoiceAgentRunBridge
import com.signalasi.chat.voice.agent.VoiceAgentRunRequest
import com.signalasi.chat.voice.metrics.VoiceLatencyTraceContext
import com.signalasi.chat.voice.modelstream.ModelStreamEvent
import com.signalasi.chat.voice.modelstream.ModelStreamUiMerger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale
import java.util.Date
import java.text.SimpleDateFormat
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit

interface AgentMemoryStore {
    fun remember(item: AgentMemoryItem): AgentMemoryWriteResult
    fun recall(query: String): List<AgentMemoryItem>
    fun recent(limit: Int = 10): List<AgentMemoryItem>
    fun count(): Int
    fun rebindConversationScope(sourceConversationId: String, targetConversationId: String): Int
    fun delete(query: String): Int
    fun snapshot(): AgentMemorySnapshot
    fun update(itemId: String, value: String, key: String = ""): AgentMemoryWriteResult?
    fun deleteById(itemId: String): Boolean
    fun setImportant(itemId: String, important: Boolean): Boolean
    fun setPrivate(itemId: String, privateMemory: Boolean): Boolean
    fun deprecateById(itemId: String): Boolean
    fun resolveConflict(groupId: String, selectedItemId: String, mergedValue: String? = null): AgentMemoryItem?
}

class InMemoryAgentMemoryStore : AgentMemoryStore {
    internal val items = mutableListOf<AgentMemoryItem>()

    override fun remember(item: AgentMemoryItem): AgentMemoryWriteResult {
        val clean = item.copy(
            value = item.value.trim(),
            key = item.key.trim().lowercase(Locale.US),
            status = AgentMemoryStatus.ACTIVE,
            conflictGroupId = ""
        )
        if (clean.value.isBlank()) return AgentMemoryWriteResult(null)
        val duplicate = items.firstOrNull {
            it.status != AgentMemoryStatus.SUPERSEDED &&
                it.kind == clean.kind &&
                it.key == clean.key &&
                it.value.equals(clean.value, ignoreCase = true)
        }
        if (duplicate != null) return AgentMemoryWriteResult(duplicate, duplicate = true)
        val competing = if (clean.key.isBlank()) emptyList() else items.filter {
            it.status != AgentMemoryStatus.SUPERSEDED && it.kind == clean.kind && it.key == clean.key
        }
        if (competing.isNotEmpty()) {
            val groupId = competing.firstNotNullOfOrNull { candidate ->
                candidate.conflictGroupId.takeIf { it.isNotBlank() }
            }
                ?: UUID.randomUUID().toString()
            competing.forEach { existing ->
                val index = items.indexOfFirst { it.id == existing.id }
                items[index] = existing.copy(status = AgentMemoryStatus.CONFLICTED, conflictGroupId = groupId)
            }
            val conflicted = clean.copy(
                version = (competing.maxOfOrNull { it.version } ?: 0) + 1,
                status = AgentMemoryStatus.CONFLICTED,
                conflictGroupId = groupId
            )
            items.add(conflicted)
            return AgentMemoryWriteResult(
                conflicted,
                AgentMemoryConflict(groupId, clean.kind, clean.key, (competing + conflicted).sortedBy { it.version })
            )
        }
        items.add(clean)
        return AgentMemoryWriteResult(clean)
    }

    override fun recall(query: String): List<AgentMemoryItem> = items
        .filter { it.status == AgentMemoryStatus.ACTIVE && !it.privateMemory }
        .filter { it.value.contains(query, ignoreCase = true) || query.contains(it.value, ignoreCase = true) }
        .takeLast(5)

    override fun recent(limit: Int): List<AgentMemoryItem> = items
        .filter { it.status == AgentMemoryStatus.ACTIVE && !it.privateMemory }
        .takeLast(limit.coerceAtLeast(0))
        .asReversed()

    override fun count(): Int = items.count { it.status == AgentMemoryStatus.ACTIVE }

    override fun rebindConversationScope(sourceConversationId: String, targetConversationId: String): Int {
        val source = sourceConversationId.trim()
        val target = targetConversationId.trim()
        if (source.isBlank() || target.isBlank() || source == target) return 0
        var changed = 0
        items.indices.forEach { index ->
            val item = items[index]
            if (item.scope == AgentMemoryScope.CONVERSATION && item.scopeId == source) {
                items[index] = item.copy(scopeId = target)
                changed += 1
            }
        }
        return changed
    }

    override fun delete(query: String): Int {
        val before = items.size
        items.removeAll { it.value.contains(query, ignoreCase = true) || query.contains(it.value, ignoreCase = true) }
        return before - items.size
    }

    override fun snapshot(): AgentMemorySnapshot {
        val conflicts = items
            .filter { it.status == AgentMemoryStatus.CONFLICTED && it.conflictGroupId.isNotBlank() }
            .groupBy { it.conflictGroupId }
            .values
            .filter { it.size > 1 }
            .map { candidates ->
                AgentMemoryConflict(
                    candidates.first().conflictGroupId,
                    candidates.first().kind,
                    candidates.first().key,
                    candidates.sortedBy { it.version }
                )
            }
        return AgentMemorySnapshot(
            activeItems = items.filter { it.status == AgentMemoryStatus.ACTIVE }.sortedByDescending { it.timestampMillis },
            conflicts = conflicts,
            historyItems = items
                .filter { it.status == AgentMemoryStatus.SUPERSEDED }
                .sortedByDescending { it.timestampMillis }
        )
    }

    override fun update(itemId: String, value: String, key: String): AgentMemoryWriteResult? {
        val index = items.indexOfFirst { it.id == itemId }
        if (index < 0 || value.isBlank()) return null
        val previous = items[index]
        items[index] = previous.copy(status = AgentMemoryStatus.SUPERSEDED)
        return remember(previous.copy(
            id = UUID.randomUUID().toString(),
            value = value.trim(),
            key = key.trim().ifBlank { previous.key },
            version = previous.version + 1,
            supersedesId = previous.id,
            source = "memory_edit",
            timestampMillis = System.currentTimeMillis()
        ))
    }

    override fun deleteById(itemId: String): Boolean {
        val target = items.firstOrNull { it.id == itemId } ?: return false
        val relatedIds = memoryLineageIds(items, target)
        items.removeAll { candidate ->
            candidate.id in relatedIds ||
                (target.key.isNotBlank() && candidate.kind == target.kind && candidate.key == target.key)
        }
        if (target.conflictGroupId.isNotBlank()) {
            val remaining = items.filter {
                it.conflictGroupId == target.conflictGroupId && it.status == AgentMemoryStatus.CONFLICTED
            }
            if (remaining.size == 1) {
                val index = items.indexOfFirst { it.id == remaining.first().id }
                items[index] = remaining.first().copy(status = AgentMemoryStatus.ACTIVE, conflictGroupId = "")
            }
        }
        return true
    }

    internal fun memoryLineageIds(allItems: List<AgentMemoryItem>, target: AgentMemoryItem): Set<String> {
        val relatedIds = mutableSetOf(target.id)
        var changed: Boolean
        do {
            changed = false
            allItems.forEach { item ->
                if (item.id in relatedIds && item.supersedesId.isNotBlank()) {
                    changed = relatedIds.add(item.supersedesId) || changed
                }
                if (item.supersedesId in relatedIds) {
                    changed = relatedIds.add(item.id) || changed
                }
            }
        } while (changed)
        return relatedIds
    }

    override fun setImportant(itemId: String, important: Boolean): Boolean {
        val index = items.indexOfFirst { it.id == itemId }
        if (index < 0) return false
        items[index] = items[index].copy(important = important)
        return true
    }

    override fun setPrivate(itemId: String, privateMemory: Boolean): Boolean {
        val index = items.indexOfFirst { it.id == itemId && it.status == AgentMemoryStatus.ACTIVE }
        if (index < 0) return false
        items[index] = items[index].copy(privateMemory = privateMemory)
        return true
    }

    override fun deprecateById(itemId: String): Boolean {
        val index = items.indexOfFirst { it.id == itemId && it.status == AgentMemoryStatus.ACTIVE }
        if (index < 0) return false
        items[index] = items[index].copy(status = AgentMemoryStatus.SUPERSEDED)
        return true
    }

    override fun resolveConflict(
        groupId: String,
        selectedItemId: String,
        mergedValue: String?
    ): AgentMemoryItem? {
        val candidates = items.filter {
            it.conflictGroupId == groupId && it.status == AgentMemoryStatus.CONFLICTED
        }
        val selected = candidates.firstOrNull { it.id == selectedItemId } ?: return null
        if (candidates.size < 2) return null
        candidates.forEach { candidate ->
            val index = items.indexOfFirst { it.id == candidate.id }
            items[index] = candidate.copy(status = AgentMemoryStatus.SUPERSEDED)
        }
        val resolved = selected.copy(
            id = UUID.randomUUID().toString(),
            value = mergedValue?.trim().orEmpty().ifBlank { selected.value },
            version = candidates.maxOf { it.version } + 1,
            supersedesId = selected.id,
            source = if (mergedValue.isNullOrBlank()) "memory_conflict_selection" else "memory_conflict_merge",
            status = AgentMemoryStatus.ACTIVE,
            conflictGroupId = "",
            timestampMillis = System.currentTimeMillis()
        )
        items.add(resolved)
        return resolved
    }
}

class EncryptedAgentMemoryStore(context: Context) : AgentMemoryStore {
    internal val appContext = context.applicationContext
    internal val database = AgentEncryptedDatabase(context, DATABASE)
    internal val deletionIndex = EncryptedAgentMemoryDeletionIndex(context)
    internal var suppressObservations = false

    override fun remember(item: AgentMemoryItem): AgentMemoryWriteResult = synchronized(PROCESS_LOCK) {
        val cleanValue = item.value.trim()
        if (cleanValue.isBlank()) return AgentMemoryWriteResult(null)
        val normalizedKey = normalizeKey(item.key.ifBlank { inferKey(cleanValue) })
        val nextItem = item.copy(
            value = cleanValue,
            key = normalizedKey,
            status = AgentMemoryStatus.ACTIVE,
            conflictGroupId = ""
        )
        val previous = loadItems()
        val items = previous.toMutableList()
        val sameValue = items.firstOrNull { existing ->
            existing.status != AgentMemoryStatus.SUPERSEDED &&
                existing.kind == nextItem.kind &&
                existing.key == nextItem.key &&
                existing.value.equals(nextItem.value, ignoreCase = true)
        }
        if (sameValue != null) {
            val merged = sameValue.copy(
                confidence = maxOf(sameValue.confidence, nextItem.confidence),
                evidenceCount = (sameValue.evidenceCount + nextItem.evidenceCount).coerceAtMost(MAX_EVIDENCE_COUNT),
                lastConfirmedAtMillis = maxOf(
                    sameValue.lastConfirmedAtMillis,
                    nextItem.lastConfirmedAtMillis,
                    System.currentTimeMillis()
                ),
                expiresAtMillis = maxOf(sameValue.expiresAtMillis, nextItem.expiresAtMillis)
            )
            items[items.indexOfFirst { it.id == sameValue.id }] = merged
            val stored = trimHistory(items)
            saveItems(stored)
            publishMutation(previous, stored)
            return AgentMemoryWriteResult(merged, duplicate = true)
        }
        if (normalizedKey.isBlank()) {
            items.add(nextItem)
            val stored = trimHistory(items)
            saveItems(stored)
            publishMutation(previous, stored)
            return AgentMemoryWriteResult(nextItem)
        }

        val competing = items.filter { existing ->
            existing.kind == nextItem.kind &&
                existing.key == normalizedKey &&
                existing.status != AgentMemoryStatus.SUPERSEDED
        }
        if (competing.isEmpty()) {
            items.add(nextItem)
            val stored = trimHistory(items)
            saveItems(stored)
            publishMutation(previous, stored)
            return AgentMemoryWriteResult(nextItem)
        }

        val groupId = competing.firstNotNullOfOrNull { candidate ->
            candidate.conflictGroupId.takeIf { it.isNotBlank() }
        }
            ?: UUID.randomUUID().toString()
        val latest = competing.maxByOrNull { it.version }
        val maxVersion = competing.maxOfOrNull { it.version } ?: 0
        competing.forEach { existing ->
            val index = items.indexOfFirst { it.id == existing.id }
            if (index >= 0) {
                items[index] = existing.copy(
                    status = AgentMemoryStatus.CONFLICTED,
                    conflictGroupId = groupId
                )
            }
        }
        val conflictedItem = nextItem.copy(
            version = maxVersion + 1,
            supersedesId = latest?.id.orEmpty(),
            status = AgentMemoryStatus.CONFLICTED,
            conflictGroupId = groupId
        )
        items.add(conflictedItem)
        val stored = trimHistory(items)
        saveItems(stored)
        publishMutation(previous, stored)
        return AgentMemoryWriteResult(
            item = conflictedItem,
            conflict = buildConflict(groupId, items)
        )
    }

    override fun recall(query: String): List<AgentMemoryItem> = synchronized(PROCESS_LOCK) {
        val cleanQuery = query.trim()
        if (cleanQuery.isBlank()) return emptyList()
        val now = System.currentTimeMillis()
        val items = loadItems()
        val recalled = items
            .filter { it.status == AgentMemoryStatus.ACTIVE && !it.privateMemory && !it.isExpired(now) }
            .map { item -> item to score(item, cleanQuery) }
            .filter { (_, score) -> score > 0 }
            .sortedWith(
                compareByDescending<Pair<AgentMemoryItem, Double>> { it.second }
                    .thenByDescending { it.first.important }
                    .thenByDescending { it.first.timestampMillis }
            )
            .map { it.first }
            .take(MAX_RECALL_ITEMS)
        if (recalled.isNotEmpty()) {
            val recalledIds = recalled.mapTo(hashSetOf()) { it.id }
            AgentMemoryAccessTracker.refresh(items, recalledIds, now).takeIf { it.changed }?.let { refresh ->
                saveItems(refresh.items)
            }
        }
        return recalled
    }

    override fun recent(limit: Int): List<AgentMemoryItem> = synchronized(PROCESS_LOCK) {
        loadItems()
            .filter { it.status == AgentMemoryStatus.ACTIVE && !it.privateMemory && !it.isExpired(System.currentTimeMillis()) }
            .sortedWith(compareByDescending<AgentMemoryItem> { it.important }.thenByDescending { it.timestampMillis })
            .take(limit.coerceAtLeast(0))
    }

    override fun count(): Int = synchronized(PROCESS_LOCK) {
        loadItems().count { it.status == AgentMemoryStatus.ACTIVE }
    }

    override fun rebindConversationScope(sourceConversationId: String, targetConversationId: String): Int =
        synchronized(PROCESS_LOCK) {
        val source = sourceConversationId.trim()
        val target = targetConversationId.trim()
        if (source.isBlank() || target.isBlank() || source == target) return 0
        val items = loadItems()
        var changed = 0
        val rebound = items.map { item ->
            if (item.scope == AgentMemoryScope.CONVERSATION && item.scopeId == source) {
                changed += 1
                item.copy(scopeId = target)
            } else item
        }
        if (changed > 0) saveItems(rebound)
        return changed
    }

    override fun delete(query: String): Int = synchronized(PROCESS_LOCK) {
        val cleanQuery = query.trim()
        if (cleanQuery.isBlank()) return 0
        val items = loadItems()
        val kept = items.filter { item -> score(item, cleanQuery) <= 0 }
        if (kept.size != items.size) {
            val deleted = items.filterNot { candidate -> kept.any { it.id == candidate.id } }
            saveItems(kept)
            val tombstone = runCatching { deletionIndex.record(deleted) }.getOrElse {
                saveItems(items)
                throw it
            }
            publishMutation(items, kept)
            tombstone?.let(deletionIndex::publishRetraction)
        }
        return items.size - kept.size
    }

    override fun snapshot(): AgentMemorySnapshot = synchronized(PROCESS_LOCK) {
        val items = loadItems()
        return AgentMemorySnapshot(
            activeItems = items
                .filter { it.status == AgentMemoryStatus.ACTIVE }
                .sortedWith(compareByDescending<AgentMemoryItem> { it.important }.thenByDescending { it.timestampMillis }),
            conflicts = items
                .filter { it.status == AgentMemoryStatus.CONFLICTED && it.conflictGroupId.isNotBlank() }
                .groupBy { it.conflictGroupId }
                .values
                .filter { it.size > 1 }
                .map { candidates ->
                    AgentMemoryConflict(
                        groupId = candidates.first().conflictGroupId,
                        kind = candidates.first().kind,
                        key = candidates.first().key,
                        candidates = candidates.sortedBy { it.version }
                    )
                }
                .sortedByDescending { conflict -> conflict.candidates.maxOf { it.timestampMillis } },
            historyItems = items
                .filter { it.status == AgentMemoryStatus.SUPERSEDED }
                .sortedByDescending { it.timestampMillis }
        )
    }

    override fun update(itemId: String, value: String, key: String): AgentMemoryWriteResult? =
        synchronized(PROCESS_LOCK) {
        val cleanValue = value.trim()
        if (cleanValue.isBlank()) return null
        val previousItems = loadItems()
        val items = previousItems.toMutableList()
        val index = items.indexOfFirst { it.id == itemId && it.status == AgentMemoryStatus.ACTIVE }
        if (index < 0) return null
        val previous = items[index]
        items[index] = previous.copy(status = AgentMemoryStatus.SUPERSEDED)
        saveItems(trimHistory(items))
        suppressObservations = true
        val result = try {
            remember(
                previous.copy(
                    id = UUID.randomUUID().toString(),
                    value = cleanValue,
                    key = key.trim().ifBlank { previous.key },
                    timestampMillis = System.currentTimeMillis(),
                    version = previous.version + 1,
                    supersedesId = previous.id,
                    source = "memory_edit",
                    status = AgentMemoryStatus.ACTIVE,
                    conflictGroupId = ""
                )
            )
        } catch (error: Throwable) {
            saveItems(previousItems)
            throw error
        } finally {
            suppressObservations = false
        }
        publishMutation(previousItems, loadItems())
        return result
    }

    override fun deleteById(itemId: String): Boolean = synchronized(PROCESS_LOCK) {
        val previous = loadItems()
        val items = previous.toMutableList()
        val target = items.firstOrNull { it.id == itemId } ?: return false
        val relatedIds = memoryLineageIds(items, target)
        items.removeAll { candidate ->
            candidate.id in relatedIds ||
                (target.key.isNotBlank() && candidate.kind == target.kind && candidate.key == target.key)
        }
        if (target.conflictGroupId.isNotBlank()) {
            val remaining = items.filter {
                it.conflictGroupId == target.conflictGroupId && it.status == AgentMemoryStatus.CONFLICTED
            }
            if (remaining.size == 1) {
                val remainingIndex = items.indexOfFirst { it.id == remaining.first().id }
                items[remainingIndex] = remaining.first().copy(
                    status = AgentMemoryStatus.ACTIVE,
                    conflictGroupId = ""
                )
            }
        }
        val stored = trimHistory(items)
        saveItems(stored)
        val deleted = previous.filterNot { candidate -> stored.any { it.id == candidate.id } }
        val tombstone = runCatching { deletionIndex.record(deleted) }.getOrElse {
            saveItems(previous)
            throw it
        }
        publishMutation(previous, stored)
        tombstone?.let(deletionIndex::publishRetraction)
        return true
    }

    internal fun memoryLineageIds(allItems: List<AgentMemoryItem>, target: AgentMemoryItem): Set<String> {
        val relatedIds = mutableSetOf(target.id)
        var changed: Boolean
        do {
            changed = false
            allItems.forEach { item ->
                if (item.id in relatedIds && item.supersedesId.isNotBlank()) {
                    changed = relatedIds.add(item.supersedesId) || changed
                }
                if (item.supersedesId in relatedIds) {
                    changed = relatedIds.add(item.id) || changed
                }
            }
        } while (changed)
        return relatedIds
    }

    override fun setImportant(itemId: String, important: Boolean): Boolean = synchronized(PROCESS_LOCK) {
        val previous = loadItems()
        val items = previous.toMutableList()
        val index = items.indexOfFirst { it.id == itemId && it.status == AgentMemoryStatus.ACTIVE }
        if (index < 0) return false
        items[index] = items[index].copy(important = important)
        saveItems(items)
        publishMutation(previous, items)
        return true
    }

    override fun setPrivate(itemId: String, privateMemory: Boolean): Boolean = synchronized(PROCESS_LOCK) {
        val previous = loadItems()
        val index = previous.indexOfFirst { it.id == itemId && it.status == AgentMemoryStatus.ACTIVE }
        if (index < 0) return false
        val updated = previous.toMutableList().apply {
            this[index] = this[index].copy(privateMemory = privateMemory)
        }
        saveItems(updated)
        publishMutation(previous, updated)
        return true
    }

    override fun deprecateById(itemId: String): Boolean = synchronized(PROCESS_LOCK) {
        val previous = loadItems()
        val index = previous.indexOfFirst { it.id == itemId && it.status == AgentMemoryStatus.ACTIVE }
        if (index < 0) return false
        val updated = previous.toMutableList().apply {
            this[index] = this[index].copy(status = AgentMemoryStatus.SUPERSEDED)
        }
        val stored = trimHistory(updated)
        saveItems(stored)
        publishMutation(previous, stored)
        return true
    }

    override fun resolveConflict(
        groupId: String,
        selectedItemId: String,
        mergedValue: String?
    ): AgentMemoryItem? = synchronized(PROCESS_LOCK) {
        val previous = loadItems()
        val items = previous.toMutableList()
        val candidates = items.filter {
            it.conflictGroupId == groupId && it.status == AgentMemoryStatus.CONFLICTED
        }
        if (candidates.size < 2) return null
        val selected = candidates.firstOrNull { it.id == selectedItemId } ?: return null
        val cleanMergedValue = mergedValue?.trim().orEmpty()
        val resolvedValue = cleanMergedValue.ifBlank { selected.value }
        candidates.forEach { candidate ->
            val index = items.indexOfFirst { it.id == candidate.id }
            if (index >= 0) items[index] = candidate.copy(status = AgentMemoryStatus.SUPERSEDED)
        }
        val resolved = selected.copy(
            id = UUID.randomUUID().toString(),
            value = resolvedValue,
            timestampMillis = System.currentTimeMillis(),
            version = candidates.maxOf { it.version } + 1,
            supersedesId = selected.id,
            source = if (cleanMergedValue.isBlank()) "memory_conflict_selection" else "memory_conflict_merge",
            status = AgentMemoryStatus.ACTIVE,
            conflictGroupId = ""
        )
        items.add(resolved)
        val stored = trimHistory(items)
        saveItems(stored)
        publishMutation(previous, stored)
        return resolved
    }

    internal fun score(item: AgentMemoryItem, query: String): Double {
        val value = item.value.lowercase()
        val cleanQuery = query.lowercase()
        var lexicalScore = 0.0
        if (value == cleanQuery) lexicalScore += 12.0
        if (value.contains(cleanQuery) || cleanQuery.contains(value)) lexicalScore += 8.0
        queryTokens(cleanQuery).forEach { token -> if (value.contains(token)) lexicalScore += 1.0 }
        val ageDays = ((System.currentTimeMillis() - item.timestampMillis).coerceAtLeast(0L) / DAY_MILLIS.toDouble())
        val recency = 1.0 / (1.0 + ageDays / 30.0)
        val evidence = kotlin.math.ln(1.0 + item.evidenceCount.coerceAtLeast(1))
        return lexicalScore * (0.5 + item.confidence.coerceIn(0.0, 1.0)) +
            recency + evidence + if (item.important) 2.0 else 0.0
    }

    internal fun queryTokens(value: String): Set<String> {
        val wordTokens = value.split(Regex("[^\\p{L}\\p{N}]+"))
            .filter { it.length >= MIN_TOKEN_LENGTH }
        val cjkBigrams = value.filter { it.code in 0x3400..0x9FFF }.windowed(2)
        return (wordTokens + cjkBigrams).toSet()
    }

    internal fun loadItems(): List<AgentMemoryItem> {
        val raw = database.readString(KEY_ITEMS, "[]")
        return SNAPSHOTS.get(raw, ::decodeItems)
    }

    internal fun decodeItems(raw: String): List<AgentMemoryItem> = runCatching {
        val array = JSONArray(raw)
        buildList {
            for (index in 0 until array.length()) {
                decodeMemoryItem(array.optJSONObject(index) ?: continue)?.let { add(it) }
            }
        }
    }.getOrDefault(emptyList())

    internal fun saveItems(items: List<AgentMemoryItem>) {
        val array = JSONArray()
        items.forEach { array.put(encodeMemoryItem(it)) }
        val raw = array.toString()
        database.writeString(KEY_ITEMS, raw)
        SNAPSHOTS.put(raw, items)
    }

    internal fun publishMutation(before: List<AgentMemoryItem>, after: List<AgentMemoryItem>) {
        if (suppressObservations || before == after) return
        GlobalConversationEventBus.publishMemoryMutations(appContext, before, after)
    }

    internal fun encodeMemoryItem(item: AgentMemoryItem): JSONObject = JSONObject()
        .put("id", item.id)
        .put("kind", item.kind.name)
        .put("value", item.value)
        .put("key", item.key)
        .put("source", item.source)
        .put("timestamp_millis", item.timestampMillis)
        .put("version", item.version)
        .put("supersedes_id", item.supersedesId)
        .put("important", item.important)
        .put("status", item.status.name)
        .put("conflict_group_id", item.conflictGroupId)
        .put("scope", item.scope.name)
        .put("scope_id", item.scopeId)
        .put("confidence", item.confidence)
        .put("evidence_count", item.evidenceCount)
        .put("auto_learned", item.autoLearned)
        .put("last_confirmed_at_millis", item.lastConfirmedAtMillis)
        .put("last_accessed_at_millis", item.lastAccessedAtMillis)
        .put("expires_at_millis", item.expiresAtMillis)
        .put("why_remembered", item.whyRemembered)
        .put("origin_conversation_id", item.originConversationId)
        .put("origin_event_id", item.originEventId)
        .put("private_memory", item.privateMemory)

    internal fun decodeMemoryItem(json: JSONObject): AgentMemoryItem? {
        val value = json.optString("value").trim()
        if (value.isBlank()) return null
        return AgentMemoryItem(
            kind = enumOrDefault(json.optString("kind"), AgentMemoryKind.TASK),
            value = value,
            timestampMillis = json.optLong("timestamp_millis", System.currentTimeMillis()),
            id = json.optString("id").ifBlank { UUID.randomUUID().toString() },
            source = json.optString("source", "agent"),
            key = normalizeKey(json.optString("key")),
            version = json.optInt("version", 1).coerceAtLeast(1),
            supersedesId = json.optString("supersedes_id"),
            important = json.optBoolean("important", false),
            status = enumOrDefault(json.optString("status"), AgentMemoryStatus.ACTIVE),
            conflictGroupId = json.optString("conflict_group_id"),
            scope = enumOrDefault(json.optString("scope"), AgentMemoryScope.GLOBAL),
            scopeId = json.optString("scope_id"),
            confidence = json.optDouble("confidence", 0.65).coerceIn(0.0, 1.0),
            evidenceCount = json.optInt("evidence_count", 1).coerceIn(1, MAX_EVIDENCE_COUNT),
            autoLearned = json.optBoolean("auto_learned", false),
            lastConfirmedAtMillis = json.optLong("last_confirmed_at_millis", 0L).coerceAtLeast(0L),
            lastAccessedAtMillis = json.optLong("last_accessed_at_millis", 0L).coerceAtLeast(0L),
            expiresAtMillis = json.optLong("expires_at_millis", 0L).coerceAtLeast(0L),
            whyRemembered = json.optString("why_remembered").take(1_000),
            originConversationId = json.optString("origin_conversation_id").take(160),
            originEventId = json.optString("origin_event_id").take(160),
            privateMemory = json.optBoolean("private_memory")
        )
    }

    internal fun buildConflict(groupId: String, items: List<AgentMemoryItem>): AgentMemoryConflict? {
        val candidates = items
            .filter { it.conflictGroupId == groupId && it.status == AgentMemoryStatus.CONFLICTED }
            .sortedBy { it.version }
        if (candidates.size < 2) return null
        return AgentMemoryConflict(
            groupId = groupId,
            kind = candidates.first().kind,
            key = candidates.first().key,
            candidates = candidates
        )
    }

    internal fun inferKey(value: String): String {
        val separatorIndex = listOf(value.indexOf('='), value.indexOf(':'))
            .filter { it in 1..MAX_KEY_PREFIX_LENGTH }
            .minOrNull()
        if (separatorIndex != null) return value.substring(0, separatorIndex)
        val patterns = listOf(
            Regex("^my\\s+([a-z0-9 _-]{2,40})\\s+is\\s+", RegexOption.IGNORE_CASE),
            Regex("^preferred\\s+([a-z0-9 _-]{2,40})\\s+is\\s+", RegexOption.IGNORE_CASE),
            Regex("^default\\s+([a-z0-9 _-]{2,40})\\s+is\\s+", RegexOption.IGNORE_CASE)
        )
        return patterns.firstNotNullOfOrNull { pattern -> pattern.find(value)?.groupValues?.getOrNull(1) }.orEmpty()
    }

    internal fun normalizeKey(value: String): String = value
        .trim()
        .lowercase(Locale.US)
        .replace(Regex("[^\\p{L}\\p{N} _:.-]"), "")
        .replace(Regex("\\s+"), " ")
        .take(MAX_KEY_LENGTH)

    internal fun trimHistory(items: List<AgentMemoryItem>): List<AgentMemoryItem> {
        val unresolved = items.filter { it.status != AgentMemoryStatus.SUPERSEDED }
        val historySlots = (MAX_ITEMS - unresolved.size).coerceAtLeast(0)
        val history = items
            .filter { it.status == AgentMemoryStatus.SUPERSEDED }
            .sortedByDescending { it.timestampMillis }
            .take(historySlots)
        return (unresolved + history).sortedBy { it.timestampMillis }
    }

    companion object {
        private val PROCESS_LOCK = Any()
        private val SNAPSHOTS = AgentPersistentSnapshotCache<AgentMemoryItem>()
        private const val DATABASE = "signalasi_agent_memory_v2"
        private const val KEY_ITEMS = "items"
        private const val MAX_ITEMS = 1_000
        private const val MAX_RECALL_ITEMS = 8
        private const val MAX_EVIDENCE_COUNT = 10_000
        private const val MIN_TOKEN_LENGTH = 3
        private const val MAX_KEY_PREFIX_LENGTH = 64
        private const val MAX_KEY_LENGTH = 80
        private const val DAY_MILLIS = 86_400_000L
    }
}
