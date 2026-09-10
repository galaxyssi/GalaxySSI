package com.galaxyssi.chat

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
import com.galaxyssi.chat.voice.VoiceFeatureFlags
import com.galaxyssi.chat.voice.agent.VoiceAgentRunBridge
import com.galaxyssi.chat.voice.agent.VoiceAgentRunRequest
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTraceContext
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import com.galaxyssi.chat.voice.modelstream.ModelStreamUiMerger
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
    fun browse(request: AgentMemoryBrowseRequest): AgentMemoryBrowsePage = snapshot().browseInMemory(request)
    fun browseCounts(kinds: Set<AgentMemoryKind> = emptySet()): AgentMemoryBrowseCounts = browse(AgentMemoryBrowseRequest(kinds = kinds, limit = 1)).counts
    fun browseKindCounts(): Map<AgentMemoryKind, Long> = snapshot().activeItems.groupingBy { it.kind }.eachCount().mapValues { it.value.toLong() }
    fun browseConflict(item: AgentMemoryItem): AgentMemoryConflict? = snapshot().conflicts.firstOrNull {
        it.groupId == item.conflictGroupId && it.candidates.any { candidate -> candidate.id == item.id }
    }
    fun update(itemId: String, value: String, key: String = ""): AgentMemoryWriteResult?
    fun deleteById(itemId: String): Boolean
    fun setImportant(itemId: String, important: Boolean): Boolean
    fun setPrivate(itemId: String, privateMemory: Boolean): Boolean
    fun deprecateById(itemId: String): Boolean
    fun resolveConflict(groupId: String, selectedItemId: String, mergedValue: String? = null): AgentMemoryItem?
}

class InMemoryAgentMemoryStore : AgentMemoryStore {
    internal val items = mutableListOf<AgentMemoryItem>()

    private fun normalizeConflicts() {
        val normalized = AgentMemoryIdentity.normalizeConflicts(items)
        if (normalized !== items) {
            items.clear()
            items.addAll(normalized)
        }
    }

    override fun remember(item: AgentMemoryItem): AgentMemoryWriteResult {
        normalizeConflicts()
        val clean = item.copy(
            value = item.value.trim(),
            key = item.key.trim().lowercase(Locale.US),
            status = AgentMemoryStatus.ACTIVE,
            conflictGroupId = ""
        )
        if (clean.value.isBlank()) return AgentMemoryWriteResult(null)
        val duplicate = items.firstOrNull {
            it.status != AgentMemoryStatus.SUPERSEDED &&
                AgentMemoryIdentity.sameKey(it, clean) &&
                it.value.equals(clean.value, ignoreCase = true)
        }
        if (duplicate != null) return AgentMemoryWriteResult(duplicate, duplicate = true)
        val competing = if (clean.key.isBlank()) emptyList() else items.filter {
            it.status != AgentMemoryStatus.SUPERSEDED && AgentMemoryIdentity.sameKey(it, clean)
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

    override fun recall(query: String): List<AgentMemoryItem> {
        normalizeConflicts()
        return items
            .filter { it.status == AgentMemoryStatus.ACTIVE && !it.privateMemory }
            .filter { it.value.contains(query, ignoreCase = true) || query.contains(it.value, ignoreCase = true) }
            .takeLast(5)
    }

    override fun recent(limit: Int): List<AgentMemoryItem> {
        normalizeConflicts()
        return items
            .filter { it.status == AgentMemoryStatus.ACTIVE && !it.privateMemory }
            .takeLast(limit.coerceAtLeast(0))
            .asReversed()
    }

    override fun count(): Int {
        normalizeConflicts()
        return items.count { it.status == AgentMemoryStatus.ACTIVE }
    }

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
        normalizeConflicts()
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
        normalizeConflicts()
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
        normalizeConflicts()
        val target = items.firstOrNull { it.id == itemId } ?: return false
        val relatedIds = memoryLineageIds(items, target)
        items.removeAll { candidate ->
            candidate.id in relatedIds ||
                (target.key.isNotBlank() && AgentMemoryIdentity.sameKey(candidate, target))
        }
        if (target.conflictGroupId.isNotBlank()) {
            val remaining = items.filter {
                it.conflictGroupId == target.conflictGroupId && it.status == AgentMemoryStatus.CONFLICTED &&
                    AgentMemoryIdentity.sameKey(it, target)
            }
            if (remaining.size == 1) {
                val index = items.indexOfFirst { it.id == remaining.first().id }
                items[index] = remaining.first().copy(status = AgentMemoryStatus.ACTIVE, conflictGroupId = "")
            }
        }
        return true
    }

    internal fun memoryLineageIds(allItems: List<AgentMemoryItem>, target: AgentMemoryItem): Set<String> =
        AgentMemoryIdentity.lineageIds(allItems, target)

    override fun setImportant(itemId: String, important: Boolean): Boolean {
        val index = items.indexOfFirst { it.id == itemId }
        if (index < 0) return false
        items[index] = items[index].copy(important = important)
        return true
    }

    override fun setPrivate(itemId: String, privateMemory: Boolean): Boolean {
        val index = items.indexOfFirst { it.id == itemId }
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
        normalizeConflicts()
        val candidates = AgentMemoryIdentity.conflictCandidates(items, groupId, selectedItemId)
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
    private val rows = AgentPersonalMemoryRows(database)
    internal var suppressObservations = false

    override fun remember(item: AgentMemoryItem): AgentMemoryWriteResult = synchronized(PROCESS_LOCK) {
        val cleanValue = item.value.trim()
        if (cleanValue.isBlank()) return AgentMemoryWriteResult(null)
        val normalizedKey = normalizeKey(item.key.ifBlank { inferKey(cleanValue) })
        val prepared = item.copy(
            value = cleanValue,
            key = normalizedKey,
            status = AgentMemoryStatus.ACTIVE,
            conflictGroupId = ""
        )
        val nextItem = requireNotNull(AgentMemoryItemCodec.decode(AgentMemoryItemCodec.encode(prepared)))
        val change = AgentMemoryRememberMutation.plan(nextItem, rows.candidates(nextItem), System.currentTimeMillis())
        rows.applyRemember(change)
        publishMutation(change.before, change.after)
        return change.result
    }

    override fun recall(query: String): List<AgentMemoryItem> = synchronized(PROCESS_LOCK) {
        val cleanQuery = query.trim()
        if (cleanQuery.isBlank()) return emptyList()
        val now = System.currentTimeMillis()
        val items = loadItems()
        val recalled = items
            .filter { it.status == AgentMemoryStatus.ACTIVE && !it.privateMemory && !it.isExpired(now) }
            .filter { lexicalScore(it, cleanQuery) > 0.0 }
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
        if (limit <= 0) return@synchronized emptyList()
        val result = mutableListOf<AgentMemoryItem>()
        var cursor: AgentMemoryBrowseCursor? = null
        val now = System.currentTimeMillis()
        do {
            val page = rows.browse(AgentMemoryBrowseRequest(cursor = cursor, limit = minOf(100, limit - result.size),
                publicOnly = true, nowMillis = now))
            result += page.entries.map { it.item }
            cursor = page.next
        } while (cursor != null && result.size < limit)
        result
    }

    override fun browse(request: AgentMemoryBrowseRequest): AgentMemoryBrowsePage = rows.browse(request)
    override fun browseCounts(kinds: Set<AgentMemoryKind>): AgentMemoryBrowseCounts = rows.browseCounts(kinds)
    override fun browseKindCounts(): Map<AgentMemoryKind, Long> = rows.browseKindCounts()
    override fun browseConflict(item: AgentMemoryItem): AgentMemoryConflict? = synchronized(PROCESS_LOCK) {
        rows.find(item.id)?.let { current ->
            if (current.status != AgentMemoryStatus.CONFLICTED) null
            else buildConflict(current.conflictGroupId, AgentMemoryBrowseQuery(database).conflictCandidates(current))
        }
    }

    override fun count(): Int = synchronized(PROCESS_LOCK) {
        rows.activeCount()
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
        val kept = items.filter { item -> lexicalScore(item, cleanQuery) <= 0.0 }
        if (kept.size != items.size) {
            val keptIds = kept.mapTo(hashSetOf()) { it.id }
            val deleted = items.filterNot { it.id in keptIds }
            val tombstone = saveDeletion(kept, deleted)
            publishMutation(items, kept)
            if (!suppressObservations) tombstone?.let(deletionIndex::publishRetraction)
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
        val observationsAlreadySuppressed = suppressObservations
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
            suppressObservations = observationsAlreadySuppressed
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
                (target.key.isNotBlank() && AgentMemoryIdentity.sameKey(candidate, target))
        }
        if (target.conflictGroupId.isNotBlank()) {
            val remaining = items.filter {
                it.conflictGroupId == target.conflictGroupId && it.status == AgentMemoryStatus.CONFLICTED &&
                    AgentMemoryIdentity.sameKey(it, target)
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
        val storedIds = stored.mapTo(hashSetOf()) { it.id }
        val deleted = previous.filterNot { it.id in storedIds }
        val tombstone = saveDeletion(stored, deleted)
        publishMutation(previous, stored)
        if (!suppressObservations) tombstone?.let(deletionIndex::publishRetraction)
        return true
    }

    internal fun memoryLineageIds(allItems: List<AgentMemoryItem>, target: AgentMemoryItem): Set<String> =
        AgentMemoryIdentity.lineageIds(allItems, target)

    override fun setImportant(itemId: String, important: Boolean): Boolean = synchronized(PROCESS_LOCK) {
        val (before, after) = rows.updateFlags(itemId, important = important) ?: return false
        publishMutation(listOf(before), listOf(after))
        return true
    }

    override fun setPrivate(itemId: String, privateMemory: Boolean): Boolean = synchronized(PROCESS_LOCK) {
        val (before, after) = rows.updateFlags(itemId, privateMemory = privateMemory) ?: return false
        publishMutation(listOf(before), listOf(after))
        return true
    }

    internal fun findById(itemId: String): AgentMemoryItem? = rows.find(itemId)

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
        val candidates = AgentMemoryIdentity.conflictCandidates(items, groupId, selectedItemId)
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
        val lexicalScore = lexicalScore(item, query)
        val ageDays = ((System.currentTimeMillis() - item.timestampMillis).coerceAtLeast(0L) / DAY_MILLIS.toDouble())
        val recency = 1.0 / (1.0 + ageDays / 30.0)
        val evidence = kotlin.math.ln(1.0 + item.evidenceCount.coerceAtLeast(1))
        return lexicalScore * (0.5 + item.confidence.coerceIn(0.0, 1.0)) +
            recency + evidence + if (item.important) 2.0 else 0.0
    }

    internal fun lexicalScore(item: AgentMemoryItem, query: String): Double {
        val value = item.value.lowercase()
        val searchable = "${item.key} $value".lowercase()
        val cleanQuery = query.lowercase()
        if (cleanQuery.isBlank()) return 0.0
        var lexicalScore = 0.0
        if (value == cleanQuery) lexicalScore += 12.0
        if (value.contains(cleanQuery) || cleanQuery.contains(value)) lexicalScore += 8.0
        structuredTokens(cleanQuery).forEach { token ->
            if (searchable.contains(token)) lexicalScore += STRUCTURED_TOKEN_WEIGHT
        }
        queryTokens(cleanQuery).forEach { token -> if (searchable.contains(token)) lexicalScore += 1.0 }
        return lexicalScore
    }

    internal fun queryTokens(value: String): Set<String> {
        val wordTokens = value.split(Regex("[^\\p{L}\\p{N}]+"))
            .filter { it.length >= MIN_TOKEN_LENGTH }
        val cjkBigrams = value.filter { it.code in 0x3400..0x9FFF }.windowed(2)
        return (wordTokens + cjkBigrams).toSet()
    }

    private fun structuredTokens(value: String): Set<String> = STRUCTURED_TOKEN_PATTERN
        .findAll(value)
        .map { it.value.lowercase() }
        .toSet()

    internal fun loadItems(): List<AgentMemoryItem> {
        return AgentMemoryIdentity.normalizeConflicts(rows.read().map {
            decodeMemoryItem(it) ?: error("Personal memory row cannot be decoded")
        })
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
        val normalized = AgentMemoryIdentity.normalizeConflicts(items)
        rows.replace(normalized.asSequence().map(::encodeMemoryItem))
    }

    private fun saveDeletion(remaining: List<AgentMemoryItem>, deleted: List<AgentMemoryItem>): AgentMemoryDeletionTombstone? {
        val normalized = AgentMemoryIdentity.normalizeConflicts(remaining)
        return deletionIndex.commitDeletion(deleted, normalized.asSequence().map(::encodeMemoryItem))
    }

    internal fun publishMutation(before: List<AgentMemoryItem>, after: List<AgentMemoryItem>) {
        if (suppressObservations || before == after) return
        GlobalConversationEventBus.publishMemoryMutations(appContext, before, after)
    }

    internal fun encodeMemoryItem(item: AgentMemoryItem): JSONObject = AgentMemoryItemCodec.encode(item)

    internal fun decodeMemoryItem(json: JSONObject): AgentMemoryItem? = AgentMemoryItemCodec.decode(json)

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

    internal fun normalizeKey(value: String): String = AgentMemoryItemCodec.normalizeKey(value)

    internal fun trimHistory(items: List<AgentMemoryItem>): List<AgentMemoryItem> {
        // Retention is explicit; unrelated writes must never evict historical evidence.
        return items.sortedBy { it.timestampMillis }
    }

    companion object {
        private val PROCESS_LOCK = AgentMemoryStorage.lock
        private const val DATABASE = AgentMemoryStorage.DATABASE
        private const val MAX_RECALL_ITEMS = 8
        private const val MIN_TOKEN_LENGTH = 3
        private const val STRUCTURED_TOKEN_WEIGHT = 6.0
        private const val MAX_KEY_PREFIX_LENGTH = 64
        private const val MAX_KEY_LENGTH = 80
        private const val DAY_MILLIS = 86_400_000L
        private val STRUCTURED_TOKEN_PATTERN = Regex("[\\p{L}\\p{N}]+(?:[-_.:][\\p{L}\\p{N}]+)+")
    }
}
