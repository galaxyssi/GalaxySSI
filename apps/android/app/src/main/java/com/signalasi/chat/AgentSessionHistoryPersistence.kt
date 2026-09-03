package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

internal object AgentLongTaskPersistenceLimits {
    const val MAX_ACTIONS = 1_024
    const val MAX_CHECKPOINTS = 128
    const val MAX_PAGE_ITEMS = 32
    const val MAX_PAGE_JSON_CHARACTERS = 64 * 1_024
}

internal data class AgentSessionHistoryManifest(
    val sessionId: String,
    val actionPageIds: List<String>,
    val actionPageItemCounts: List<Int>,
    val checkpointPageIds: List<String>,
    val checkpointPageItemCounts: List<Int>
) {
    val actionCount: Int
        get() = actionPageItemCounts.sum()

    val checkpointCount: Int
        get() = checkpointPageItemCounts.sum()

    fun encode(): JSONObject = JSONObject()
        .put("version", VERSION)
        .put("session_id", sessionId)
        .put("action_pages", JSONArray(actionPageIds))
        .put("action_page_counts", JSONArray(actionPageItemCounts))
        .put("checkpoint_pages", JSONArray(checkpointPageIds))
        .put("checkpoint_page_counts", JSONArray(checkpointPageItemCounts))

    companion object {
        private const val VERSION = 1

        fun decode(json: JSONObject?): AgentSessionHistoryManifest? {
            if (json == null || json.optInt("version") != VERSION) return null
            val actionPageIds = json.stringList("action_pages")
            val actionPageCounts = json.positiveIntList("action_page_counts")
            val checkpointPageIds = json.stringList("checkpoint_pages")
            val checkpointPageCounts = json.positiveIntList("checkpoint_page_counts")
            if (actionPageIds.size != actionPageCounts.size ||
                checkpointPageIds.size != checkpointPageCounts.size
            ) return null
            return AgentSessionHistoryManifest(
                sessionId = json.optString("session_id"),
                actionPageIds = actionPageIds,
                actionPageItemCounts = actionPageCounts,
                checkpointPageIds = checkpointPageIds,
                checkpointPageItemCounts = checkpointPageCounts
            )
        }

        private fun JSONObject.stringList(key: String): List<String> {
            val array = optJSONArray(key) ?: return emptyList()
            return buildList(array.length()) {
                for (index in 0 until array.length()) {
                    array.optString(index).takeIf(String::isNotBlank)?.let(::add)
                }
            }
        }

        private fun JSONObject.positiveIntList(key: String): List<Int> {
            val array = optJSONArray(key) ?: return emptyList()
            return buildList(array.length()) {
                for (index in 0 until array.length()) {
                    val value = array.optInt(index, -1)
                    if (value <= 0) return emptyList()
                    add(value)
                }
            }
        }
    }
}

internal data class AgentSessionHistoryPage<T>(
    val items: List<T>,
    val pageIndex: Int,
    val pageCount: Int,
    val totalItems: Int,
    val available: Boolean
) {
    val hasOlderPage: Boolean
        get() = pageIndex > 0

    val hasNewerPage: Boolean
        get() = pageIndex + 1 < pageCount
}

/**
 * Stores the long task ledger in immutable encrypted pages. The small root checkpoint points to
 * content-addressed pages and is committed only after every new page is durable.
 */
internal class AgentSessionHistoryPersistence(
    private val storage: AgentSessionCheckpointStorage,
    private val storageKey: String,
    private val encodeAction: (AgentAction) -> JSONObject,
    private val decodeAction: (JSONObject) -> AgentAction,
    private val encodeCheckpoint: (AgentExecutionCheckpoint) -> JSONObject,
    private val decodeCheckpoint: (JSONObject) -> AgentExecutionCheckpoint?
) {
    private var cachedSessionId = ""
    private var cachedActions: List<AgentAction>? = null
    private var cachedCheckpoints: List<AgentExecutionCheckpoint>? = null

    @Synchronized
    fun save(
        sessionId: String,
        actions: List<AgentAction>,
        checkpoints: List<AgentExecutionCheckpoint>,
        writeRoot: (AgentSessionHistoryManifest) -> Unit
    ) {
        val existingManifest = readManifest()
            ?.takeIf { manifest -> manifest.sessionId == sessionId }
        val previousActions = existingActions(sessionId, existingManifest)
        val previousCheckpoints = existingCheckpoints(sessionId, existingManifest)
        val mergedActions = latestActions(previousActions + actions)
            .takeLast(AgentLongTaskPersistenceLimits.MAX_ACTIONS)
        val mergedCheckpoints = latestCheckpoints(previousCheckpoints + checkpoints)
            .takeLast(AgentLongTaskPersistenceLimits.MAX_CHECKPOINTS)
        val actionPages = encodePages(ACTION_KIND, mergedActions, encodeAction)
        val checkpointPages = encodePages(CHECKPOINT_KIND, mergedCheckpoints, encodeCheckpoint)
        val manifest = AgentSessionHistoryManifest(
            sessionId = sessionId,
            actionPageIds = actionPages.map(EncodedPage::id),
            actionPageItemCounts = actionPages.map(EncodedPage::itemCount),
            checkpointPageIds = checkpointPages.map(EncodedPage::id),
            checkpointPageItemCounts = checkpointPages.map(EncodedPage::itemCount)
        )
        val createdKeys = mutableListOf<String>()
        try {
            (actionPages + checkpointPages).forEach { page ->
                val key = pageKey(page.kind, page.id)
                if (storage.encodedValueLength(key) == 0) {
                    storage.writeString(key, page.value)
                    createdKeys += key
                }
            }
            writeRoot(manifest)
        } catch (error: Throwable) {
            createdKeys.forEach(storage::remove)
            throw error
        }
        cachedSessionId = sessionId
        cachedActions = mergedActions
        cachedCheckpoints = mergedCheckpoints
        removeUnreferencedPages(manifest)
    }

    @Synchronized
    fun actionPage(pageIndex: Int): AgentSessionHistoryPage<AgentAction> {
        val manifest = readManifest()
            ?: return unavailablePage(pageIndex)
        return readPage(
            kind = ACTION_KIND,
            pageIndex = pageIndex,
            pageIds = manifest.actionPageIds,
            pageItemCounts = manifest.actionPageItemCounts,
            decoder = decodeAction
        )
    }

    @Synchronized
    fun checkpointPage(pageIndex: Int): AgentSessionHistoryPage<AgentExecutionCheckpoint> {
        val manifest = readManifest()
            ?: return unavailablePage(pageIndex)
        return readPage(
            kind = CHECKPOINT_KIND,
            pageIndex = pageIndex,
            pageIds = manifest.checkpointPageIds,
            pageItemCounts = manifest.checkpointPageItemCounts,
            decoder = decodeCheckpoint
        )
    }

    @Synchronized
    fun manifest(): AgentSessionHistoryManifest? = readManifest()

    @Synchronized
    fun clear() {
        storage.keys()
            .filter { key -> key.startsWith(pageKeyPrefix()) }
            .forEach(storage::remove)
        cachedSessionId = ""
        cachedActions = null
        cachedCheckpoints = null
    }

    private fun existingActions(
        sessionId: String,
        manifest: AgentSessionHistoryManifest?
    ): List<AgentAction> {
        if (cachedSessionId == sessionId) cachedActions?.let { return it }
        return manifest?.let { readAll(ACTION_KIND, it.actionPageIds, decodeAction) }.orEmpty()
    }

    private fun existingCheckpoints(
        sessionId: String,
        manifest: AgentSessionHistoryManifest?
    ): List<AgentExecutionCheckpoint> {
        if (cachedSessionId == sessionId) cachedCheckpoints?.let { return it }
        return manifest?.let {
            readAll(CHECKPOINT_KIND, it.checkpointPageIds, decodeCheckpoint)
        }.orEmpty()
    }

    private fun latestActions(actions: List<AgentAction>): List<AgentAction> =
        AgentProjectHistoryRetentionPolicy.latestSnapshots(actions)

    private fun latestCheckpoints(
        checkpoints: List<AgentExecutionCheckpoint>
    ): List<AgentExecutionCheckpoint> {
        if (checkpoints.size < 2) return checkpoints
        val retained = ArrayList<AgentExecutionCheckpoint>(checkpoints.size)
        val seenIds = hashSetOf<String>()
        checkpoints.asReversed().forEach { checkpoint ->
            if (checkpoint.id.isBlank() || seenIds.add(checkpoint.id)) retained += checkpoint
        }
        retained.reverse()
        return retained
    }

    private fun <T> encodePages(
        kind: String,
        items: List<T>,
        encoder: (T) -> JSONObject
    ): List<EncodedPage> {
        if (items.isEmpty()) return emptyList()
        val pages = mutableListOf<EncodedPage>()
        var current = mutableListOf<JSONObject>()

        fun flush() {
            if (current.isEmpty()) return
            pages += encodedPage(kind, current)
            current = mutableListOf()
        }

        items.forEach { item ->
            val encoded = boundedItem(encoder(item))
            val candidate = current + encoded
            val candidateValue = pageValue(kind, candidate)
            if (current.isNotEmpty() && (
                    current.size >= AgentLongTaskPersistenceLimits.MAX_PAGE_ITEMS ||
                        candidateValue.length > AgentLongTaskPersistenceLimits.MAX_PAGE_JSON_CHARACTERS
                    )
            ) {
                flush()
            }
            current += encoded
            check(pageValue(kind, current).length <= AgentLongTaskPersistenceLimits.MAX_PAGE_JSON_CHARACTERS) {
                "Agent session history item exceeds the page persistence budget"
            }
        }
        flush()
        return pages
    }

    private fun boundedItem(item: JSONObject): JSONObject {
        if (singleItemPageLength(item) <= AgentLongTaskPersistenceLimits.MAX_PAGE_JSON_CHARACTERS) {
            return item
        }
        for (stringLimit in listOf(1_024, 512, 256, 128, 64)) {
            val compact = compactObject(item, stringLimit)
            if (singleItemPageLength(compact) <= AgentLongTaskPersistenceLimits.MAX_PAGE_JSON_CHARACTERS) {
                return compact
            }
        }
        error("Agent session history item exceeds the page persistence budget")
    }

    private fun singleItemPageLength(item: JSONObject): Int = pageValue("item", listOf(item)).length

    private fun compactObject(source: JSONObject, stringLimit: Int): JSONObject = JSONObject().also { target ->
        source.keys().forEach { key -> target.put(key, compactValue(source.opt(key), stringLimit)) }
    }

    private fun compactValue(value: Any?, stringLimit: Int): Any? = when (value) {
        is String -> value.take(stringLimit)
        is JSONObject -> compactObject(value, stringLimit)
        is JSONArray -> JSONArray().also { target ->
            for (index in 0 until value.length()) {
                target.put(compactValue(value.opt(index), stringLimit))
            }
        }
        else -> value
    }

    private fun encodedPage(kind: String, items: List<JSONObject>): EncodedPage {
        val value = pageValue(kind, items)
        return EncodedPage(
            kind = kind,
            id = sha256(value),
            itemCount = items.size,
            value = value
        )
    }

    private fun pageValue(kind: String, items: List<JSONObject>): String = JSONObject()
        .put("version", PAGE_VERSION)
        .put("kind", kind)
        .put("items", JSONArray().also { array -> items.forEach(array::put) })
        .toString()

    private fun <T : Any> readPage(
        kind: String,
        pageIndex: Int,
        pageIds: List<String>,
        pageItemCounts: List<Int>,
        decoder: (JSONObject) -> T?
    ): AgentSessionHistoryPage<T> {
        val pageCount = pageIds.size
        val totalItems = pageItemCounts.sum()
        if (pageIndex !in pageIds.indices) {
            return AgentSessionHistoryPage(emptyList(), pageIndex, pageCount, totalItems, false)
        }
        val items = decodePage(kind, pageIds[pageIndex], decoder)
        val available = items != null && items.size == pageItemCounts[pageIndex]
        return AgentSessionHistoryPage(
            items = items.orEmpty(),
            pageIndex = pageIndex,
            pageCount = pageCount,
            totalItems = totalItems,
            available = available
        )
    }

    private fun <T : Any> readAll(
        kind: String,
        pageIds: List<String>,
        decoder: (JSONObject) -> T?
    ): List<T> = buildList {
        pageIds.forEach { pageId -> decodePage(kind, pageId, decoder)?.let(::addAll) }
    }

    private fun <T : Any> decodePage(
        kind: String,
        pageId: String,
        decoder: (JSONObject) -> T?
    ): List<T>? = runCatching<List<T>?> {
        val key = pageKey(kind, pageId)
        val encodedLength = storage.encodedValueLength(key)
        if (encodedLength <= 0 || AgentSessionPersistencePolicy.shouldDiscardEncodedValue(encodedLength)) {
            return@runCatching null
        }
        val raw = storage.readString(key, "")
        if (raw.isBlank() || sha256(raw) != pageId) return@runCatching null
        val root = JSONObject(raw)
        if (root.optInt("version") != PAGE_VERSION || root.optString("kind") != kind) {
            return@runCatching null
        }
        val array = root.optJSONArray("items") ?: return@runCatching emptyList<T>()
        buildList<T> {
            for (index in 0 until array.length()) {
                array.optJSONObject(index)?.let(decoder)?.let(::add)
            }
        }
    }.getOrNull()

    private fun readManifest(): AgentSessionHistoryManifest? {
        val rootLength = storage.encodedValueLength(storageKey)
        if (rootLength <= 0 || AgentSessionPersistencePolicy.shouldDiscardEncodedValue(rootLength)) return null
        val raw = storage.readString(storageKey, "")
        return runCatching {
            AgentSessionHistoryManifest.decode(JSONObject(raw).optJSONObject(MANIFEST_KEY))
        }.getOrNull()
    }

    private fun removeUnreferencedPages(manifest: AgentSessionHistoryManifest) {
        val retained = buildSet {
            manifest.actionPageIds.forEach { add(pageKey(ACTION_KIND, it)) }
            manifest.checkpointPageIds.forEach { add(pageKey(CHECKPOINT_KIND, it)) }
        }
        storage.keys()
            .filter { key -> key.startsWith(pageKeyPrefix()) && key !in retained }
            .forEach(storage::remove)
    }

    private fun pageKey(kind: String, pageId: String): String = "${pageKeyPrefix()}$kind:$pageId"

    private fun pageKeyPrefix(): String = "$PAGE_KEY_PREFIX$storageKey:"

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

    private fun <T> unavailablePage(pageIndex: Int): AgentSessionHistoryPage<T> =
        AgentSessionHistoryPage(emptyList(), pageIndex, 0, 0, false)

    private data class EncodedPage(
        val kind: String,
        val id: String,
        val itemCount: Int,
        val value: String
    )

    companion object {
        internal const val MANIFEST_KEY = "history_pages"
        private const val PAGE_KEY_PREFIX = "session_history_page:"
        private const val PAGE_VERSION = 1
        private const val ACTION_KIND = "actions"
        private const val CHECKPOINT_KIND = "checkpoints"
    }
}
