package com.galaxyssi.chat

import android.content.Context
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

/** Trusted storage adapter: commit and removePrefix must be atomic and durable. */
internal interface CollaborationGoalContractRows {
    fun read(key: String): String?
    fun commit(values: Map<String, String>)
    fun removePrefix(prefix: String)
}

/** Host input only. Neither publication, access identities nor delivery receipts are model tools. */
internal class CollaborationGoalContractStore(
    private val rows: CollaborationGoalContractRows,
    private val authorized: (CollaborationWorkspaceAccess) -> Boolean,
    private val maxPageBytes: Int = DEFAULT_PAGE_BYTES
) {
    init { require(maxPageBytes in MIN_PAGE_BYTES..MAX_PAGE_BYTES) }

    constructor(context: Context) : this(EncryptedRows(context), androidAuthorization(context))

    /** The caller supplies the original host goal and preserved criteria, never a member's report. */
    fun publish(access: CollaborationWorkspaceAccess, goal: String, criteria: String,
                contextSections: Map<String, String> = emptyMap()): JSONObject = guarded {
        authorize(access)
        if (!validUnicode(goal) || goal.isBlank()) reject("invalid_goal")
        val contexts = contextSections.toSortedMap()
        if (contexts.any { (key, value) -> key.isBlank() || !validUnicode(key) || !validUnicode(value) }) reject("invalid_context")
        val parsed = try {
            parseCriteria(criteria)
        } catch (_: Exception) { reject("invalid_criteria") }
        catch (_: StackOverflowError) { reject("invalid_criteria") }
        val criteriaHash = try { CollaborationSemanticGoalCoverage.criteriaHash(parsed) }
            catch (_: Exception) { reject("invalid_criteria") }
        val source = CollaborationSemanticGoalCoverage.source(goal)
        val segments = source.getJSONArray("segments")
        val pages = pack(sequence {
            yieldAll(fragments("goal", "", goal))
            yieldAll(fragments("criteria", "", criteria))
            repeat(segments.length()) { index ->
                val segment = segments.getJSONObject(index)
                yieldAll(fragments("source", segment.getString("id"), segment.getString("text")))
            }
            contexts.entries.forEachIndexed { index, (name, text) ->
                val inlineName = name.takeIf { bytes(JSONObject.quote(it)) <= INLINE_CONTEXT_NAME_BYTES }
                if (inlineName == null) yieldAll(fragments("context_name", "", name, index, null))
                yieldAll(fragments("context", "", text, index, inlineName))
            }
        })
        val directory = JSONArray()
        for (name in contexts.keys) {
            val candidate = JSONArray(directory.toString()).put(name)
            if (directory.length() == CONTEXT_DIRECTORY_KEYS || bytes(candidate.toString()) > CONTEXT_DIRECTORY_BYTES) break
            directory.put(name)
        }
        val manifest = JSONObject().put("format", FORMAT).put("group_id", access.groupId)
            .put("run_id", access.runId).put("turn_id", access.turnId)
            .put("goal_sha256", source.getString("goal_sha256"))
            .put("criteria_sha256", criteriaHash).put("criteria_json_sha256", digest(criteria))
            .put("source_format", source.getString("format"))
            .put("source_segment_count", segments.length()).put("page_count", pages.size)
            .put("context_section_count", contexts.size).put("context_keys", directory)
            .put("context_keys_complete", directory.length() == contexts.size)
            .put("section_pages", CollaborationGoalContractSections.index(pages))
            .put("max_page_bytes", maxPageBytes).put("page_hashes", JSONArray(pages.map(::digest)))
        val raw = encode(manifest)
        val id = digest(raw)
        val base = snapshotPrefix(access.groupId, id)
        val secretKey = groupPrefix(access.groupId) + "cursor-key"
        val existing = rows.read(base + "manifest")
        if (existing != null) {
            if (existing != raw) reject("snapshot_corrupt")
            secret(access.groupId).fill(0)
            pages.forEachIndexed { index, page ->
                if (rows.read(base + "page:$index") != page) reject("snapshot_corrupt")
            }
        } else {
            val writes = linkedMapOf<String, String>()
            if (rows.read(secretKey) == null) {
                writes[secretKey] = Base64.getEncoder().encodeToString(ByteArray(32).also(SecureRandom()::nextBytes))
            } else secret(access.groupId).fill(0)
            pages.forEachIndexed { index, page -> writes[base + "page:$index"] = page }
            writes[base + "manifest"] = raw
            rows.commit(writes)
        }
        descriptor(manifest, id)
    }

    /** Host-only, immutable dispatch assignment. Publication alone does not authorize a snapshot for a reader. */
    fun bind(access: CollaborationWorkspaceAccess, snapshotId: String): JSONObject = guarded {
        val manifest = manifest(access, snapshotId)
        val prior = binding(access)
        if (prior != null && prior != snapshotId) reject("access_already_bound")
        if (prior == null) {
            val body = bindingBody(access, snapshotId)
            val signature = Base64.getEncoder().encodeToString(mac(access.groupId, encode(body)))
            rows.commit(mapOf(bindingKey(access) to encode(body.put("signature", signature))))
        }
        descriptor(manifest, snapshotId)
    }

    fun lookup(access: CollaborationWorkspaceAccess): JSONObject = guarded {
        authorize(access)
        val id = binding(access) ?: reject("access_not_bound")
        descriptor(manifest(access, id), id)
    }

    /** Access comes from the host execution context, never from model selectors. */
    fun read(access: CollaborationWorkspaceAccess, cursor: String = ""): JSONObject = guarded {
        authorize(access)
        val id = binding(access) ?: reject("access_not_bound")
        page(access, id, manifest(access, id), cursorIndex(access, id, cursor))
    }

    fun readSection(access: CollaborationWorkspaceAccess, section: String, cursor: String = ""): JSONObject = guarded {
        authorize(access)
        val id = binding(access) ?: reject("access_not_bound")
        val manifest = manifest(access, id)
        val range = sectionRange(access, id, manifest, section)
        val index = if (cursor.isEmpty()) range.first else cursorIndex(access, id, cursor, section)
        page(access, id, manifest, index, section, range)
    }

    /** Explicit-ID host compatibility path; knowing another snapshot hash cannot bypass the binding. */
    fun read(access: CollaborationWorkspaceAccess, snapshotId: String, cursor: String): JSONObject = guarded {
        val manifest = boundManifest(access, snapshotId)
        page(access, snapshotId, manifest, cursorIndex(access, snapshotId, cursor))
    }

    /** Call only after the exact returned JSON was successfully delivered by a tool transport. */
    fun recordDelivery(access: CollaborationWorkspaceAccess, snapshotId: String, cursor: String,
                       deliveredPage: JSONObject, section: String = ""): JSONObject = guarded {
        val manifest = boundManifest(access, snapshotId)
        val index = if (section.isNotEmpty() && cursor.isEmpty()) sectionRange(access, snapshotId, manifest, section).first
            else cursorIndex(access, snapshotId, cursor, section)
        register(access, snapshotId, manifest, listOf(index to deliveredPage), "tool", section)
    }

    /** Separate host hook for exact pages actually included inline; a descriptor is not a page. */
    fun recordInlineDelivery(access: CollaborationWorkspaceAccess, snapshotId: String,
                             deliveredPages: List<JSONObject>): JSONObject = guarded {
        val manifest = boundManifest(access, snapshotId)
        register(access, snapshotId, manifest, deliveredPages.map { it.getInt("page_index") to it }, "inline")
    }

    fun delivery(access: CollaborationWorkspaceAccess, snapshotId: String): JSONObject = guarded {
        val manifest = boundManifest(access, snapshotId)
        var delivered = 0
        var missing: Int? = null
        repeat(manifest.getInt("page_count")) { index ->
            if (receipt(access, snapshotId, manifest, index) != null) delivered++
            else if (missing == null) missing = index
        }
        JSONObject().put("status", "ok").put("snapshot_id", snapshotId)
            .put("page_count", manifest.getInt("page_count")).put("delivered_page_count", delivered)
            .put("all_pages_delivered", missing == null)
            .put("next_undelivered_cursor", missing?.let { cursor(access, snapshotId, it) } ?: JSONObject.NULL)
            .put("trust", "delivery_only_not_comprehension")
    }

    /** Host group-removal hook; removes snapshots, cursor secrets and all per-member receipts. */
    fun remove(groupId: String) = synchronized(LOCK) { rows.removePrefix(groupPrefix(groupId)) }

    private fun binding(access: CollaborationWorkspaceAccess): String? {
        val raw = rows.read(bindingKey(access)) ?: return null
        val value = JSONObject(raw)
        val id = value.getString("snapshot_id")
        if (!HASH.matches(id)) reject("binding_corrupt")
        val expected = bindingBody(access, id)
        val signature = Base64.getEncoder().encodeToString(mac(access.groupId, encode(expected)))
        if (encode(expected.put("signature", signature)) != raw) reject("binding_corrupt")
        return id
    }

    private fun bindingKey(access: CollaborationWorkspaceAccess) = groupPrefix(access.groupId) + "binding:${reader(access)}"
    private fun bindingBody(access: CollaborationWorkspaceAccess, id: String) =
        JSONObject().put("binding_format", "goal-contract-access-v1").put("reader_sha256", reader(access)).put("snapshot_id", id)
            .put("round", access.round).put("dependencies", JSONArray(access.dependencyNodes.sorted())).apply {
                if (access.pinnedReads.isNotEmpty()) put("pinned_reads", JSONArray(access.pinnedReads.sorted()))
            }

    private fun boundManifest(access: CollaborationWorkspaceAccess, id: String): JSONObject {
        authorize(access)
        val bound = binding(access) ?: reject("access_not_bound")
        if (bound != id) reject("snapshot_not_bound")
        return manifest(access, id)
    }

    private fun manifest(access: CollaborationWorkspaceAccess, id: String): JSONObject {
        authorize(access)
        if (!HASH.matches(id)) reject("invalid_snapshot")
        val raw = rows.read(snapshotPrefix(access.groupId, id) + "manifest") ?: reject("snapshot_unavailable")
        if (digest(raw) != id) reject("snapshot_corrupt")
        val value = JSONObject(raw)
        if (value.getString("format") != FORMAT || value.getString("group_id") != access.groupId ||
            value.getString("run_id") != access.runId || value.getString("turn_id") != access.turnId) reject("scope_mismatch")
        if (value.getInt("page_count") <= 0 || value.getJSONArray("page_hashes").length() != value.getInt("page_count") ||
            value.getInt("max_page_bytes") !in MIN_PAGE_BYTES..MAX_PAGE_BYTES) reject("snapshot_corrupt")
        return value
    }

    private fun sectionRange(access: CollaborationWorkspaceAccess, id: String, manifest: JSONObject, section: String): IntRange {
        if (!CollaborationGoalContractSections.valid(section) || !validUnicode(section)) reject("invalid_section")
        // Older pinned snapshots remain immutable; derive their index from verified originals on demand.
        val directory = manifest.optJSONObject("section_pages") ?: CollaborationGoalContractSections.index(
            (0 until manifest.getInt("page_count")).map { pageRaw(access, id, manifest, it) })
        val range = directory.optJSONArray(CollaborationGoalContractSections.key(section)) ?: reject("section_unavailable")
        val first = range.getInt(0)
        val last = range.getInt(1)
        if (range.length() != 2 || first < 0 || last < first || last >= manifest.getInt("page_count")) reject("snapshot_corrupt")
        return first..last
    }

    private fun pageRaw(access: CollaborationWorkspaceAccess, id: String, manifest: JSONObject, index: Int): String {
        val raw = rows.read(snapshotPrefix(access.groupId, id) + "page:$index") ?: reject("snapshot_corrupt")
        if (digest(raw) != manifest.getJSONArray("page_hashes").getString(index)) reject("snapshot_corrupt")
        return raw
    }

    private fun page(access: CollaborationWorkspaceAccess, id: String, manifest: JSONObject, index: Int,
                     section: String = "", range: IntRange? = null): JSONObject {
        val count = manifest.getInt("page_count")
        if (index !in 0 until count || range != null && index !in range) reject("invalid_cursor")
        val raw = pageRaw(access, id, manifest, index)
        val hash = manifest.getJSONArray("page_hashes").getString(index)
        val result = JSONObject().put("status", "ok").put("format", PAGE_FORMAT)
            .put("snapshot_id", id).put("snapshot_sha256", id).put("reader_sha256", reader(access))
            .put("page_index", index).put("page_count", count).put("page_sha256", hash)
            .put("fragments", JSONObject(raw).getJSONArray("fragments"))
            .put("next_cursor", if (index < (range?.last ?: count - 1)) cursor(access, id, index + 1, section) else JSONObject.NULL)
        if (range != null) result.put("section_sha256", CollaborationGoalContractSections.key(section))
            .put("section_first_page", range.first).put("section_last_page", range.last)
        if (bytes(result.toString()) > manifest.getInt("max_page_bytes")) reject("page_budget_exceeded")
        return result
    }

    private fun descriptor(manifest: JSONObject, id: String) = JSONObject().put("status", "ok").put("format", FORMAT)
        .put("snapshot_id", id).put("snapshot_sha256", id).apply {
            listOf("goal_sha256", "criteria_sha256", "criteria_json_sha256", "source_format",
                "source_segment_count", "page_count", "max_page_bytes", "context_section_count",
                "context_keys", "context_keys_complete").forEach { put(it, manifest.get(it)) }
        }.put("first_cursor", "")

    private fun authorize(access: CollaborationWorkspaceAccess) {
        if (listOf(access.groupId, access.runId, access.turnId, access.nodeId, access.personId)
                .any { it.isBlank() || !validUnicode(it) } ||
            !authorized(access)) reject("access_denied")
    }

    private fun cursor(access: CollaborationWorkspaceAccess, id: String, index: Int, section: String = ""): String {
        if (index == 0) return ""
        val position = ByteBuffer.allocate(8).putLong(index.toLong()).array()
        val tag = mac(access.groupId, cursorBinding(access, id, index, section))
        return Base64.getUrlEncoder().withoutPadding().encodeToString(position + tag)
    }

    private fun cursorIndex(access: CollaborationWorkspaceAccess, id: String, token: String, section: String = ""): Int {
        if (token.isEmpty()) return 0
        if (!CURSOR.matches(token)) reject("invalid_cursor")
        val decoded = Base64.getUrlDecoder().decode(token)
        if (decoded.size != 40 || Base64.getUrlEncoder().withoutPadding().encodeToString(decoded) != token) reject("invalid_cursor")
        val index = ByteBuffer.wrap(decoded, 0, 8).long
        if (index !in 1..Int.MAX_VALUE.toLong() ||
            !MessageDigest.isEqual(decoded.copyOfRange(8, 40), mac(access.groupId, cursorBinding(access, id, index.toInt(), section)))) {
            reject("invalid_cursor")
        }
        return index.toInt()
    }

    private fun cursorBinding(access: CollaborationWorkspaceAccess, id: String, index: Int, section: String) =
        AgentNativeJsonCodec.stringify(listOf(if (section.isEmpty()) "goal-contract-cursor-v1" else "goal-contract-section-cursor-v1",
            access.groupId, access.runId, access.turnId, access.nodeId, access.personId, id, index) +
            if (section.isEmpty()) emptyList() else listOf(section))

    private fun secret(group: String): ByteArray {
        val value = rows.read(groupPrefix(group) + "cursor-key") ?: reject("snapshot_corrupt")
        return Base64.getDecoder().decode(value).also { if (it.size != 32) reject("snapshot_corrupt") }
    }

    private fun mac(group: String, value: String): ByteArray {
        val key = secret(group)
        return try {
            Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(key, "HmacSHA256")) }
                .doFinal(value.toByteArray(Charsets.UTF_8))
        } finally { key.fill(0) }
    }

    private fun register(access: CollaborationWorkspaceAccess, id: String, manifest: JSONObject,
                         pages: List<Pair<Int, JSONObject>>, channel: String, section: String = ""): JSONObject {
        if (pages.isEmpty() || pages.map { it.first }.toSet().size != pages.size) reject("invalid_delivery")
        val writes = linkedMapOf<String, String>()
        pages.forEach { (index, supplied) ->
            val range = if (section.isEmpty()) null else sectionRange(access, id, manifest, section)
            val expected = page(access, id, manifest, index, section, range)
            if (encode(supplied) != encode(expected)) reject("invalid_delivery")
            if (receipt(access, id, manifest, index) == null) {
                val body = receiptBody(access, id, index, expected.getString("page_sha256"), channel)
                val signature = Base64.getEncoder().encodeToString(mac(access.groupId, encode(body)))
                writes[receiptKey(access, id, index)] = encode(body.put("signature", signature))
            }
        }
        rows.commit(writes)
        return JSONObject().put("status", "recorded").put("snapshot_id", id)
            .put("trust", "delivery_only_not_comprehension")
    }

    private fun receipt(access: CollaborationWorkspaceAccess, id: String, manifest: JSONObject, index: Int): JSONObject? {
        val raw = rows.read(receiptKey(access, id, index)) ?: return null
        val value = JSONObject(raw)
        val channel = value.getString("channel")
        if (channel !in setOf("tool", "inline")) reject("delivery_corrupt")
        val expected = receiptBody(access, id, index, manifest.getJSONArray("page_hashes").getString(index), channel)
        val signature = Base64.getEncoder().encodeToString(mac(access.groupId, encode(expected)))
        if (encode(expected.put("signature", signature)) != raw) reject("delivery_corrupt")
        return value
    }

    private fun receiptBody(access: CollaborationWorkspaceAccess, id: String, index: Int, hash: String, channel: String) =
        JSONObject().put("snapshot_id", id).put("reader_sha256", reader(access)).put("page_index", index)
            .put("page_sha256", hash).put("channel", channel)

    private fun receiptKey(access: CollaborationWorkspaceAccess, id: String, index: Int) =
        snapshotPrefix(access.groupId, id) + "delivery:${reader(access)}:$index"

    // Reserve envelope bytes, including two snapshot hashes, the reader binding and a 54-byte cursor.
    private fun fragments(kind: String, sourceId: String, text: String,
                          contextIndex: Int? = null, contextName: String? = null): Sequence<JSONObject> = sequence {
        val budget = maxPageBytes - ENVELOPE_RESERVE - 2
        var start = 0
        var part = 0
        do {
            fun fragment(end: Int) = JSONObject().put("stream", kind).put("source_id", sourceId)
                .put("part", part).put("last", end == text.length).put("start_utf16", start)
                .put("end_utf16", end).put("text", text.substring(start, end)).apply {
                    if (contextIndex != null) put("kind", kind).put("id", contextName ?: JSONObject.NULL)
                        .put("context_index", contextIndex)
                }
            var low = 0
            var high = minOf(text.length - start, budget)
            var best = -1
            while (low <= high) {
                val middle = low + (high - low) / 2
                var end = start + middle
                if (end > start && end < text.length && text[end - 1].isHighSurrogate() && text[end].isLowSurrogate()) end--
                if (bytes(fragment(end).toString()) <= budget) { best = end; low = middle + 1 }
                else high = middle - 1
            }
            if (best < start || best == start && start < text.length) reject("page_budget_exceeded")
            yield(fragment(best))
            start = best
            part++
        } while (start < text.length)
    }

    private fun pack(fragments: Sequence<JSONObject>): List<String> {
        val pages = mutableListOf<String>()
        var current = JSONArray()
        var size = 2
        fun flush() {
            if (current.length() > 0) pages += encode(JSONObject().put("fragments", current))
            current = JSONArray()
            size = 2
        }
        fragments.forEach { fragment ->
            val length = bytes(fragment.toString())
            if (size + length + (if (current.length() == 0) 0 else 1) > maxPageBytes - ENVELOPE_RESERVE) flush()
            size += length + if (current.length() == 0) 0 else 1
            current.put(fragment)
        }
        flush()
        return pages
    }

    private fun guarded(block: () -> JSONObject): JSONObject = synchronized(LOCK) {
        try { block() }
        catch (failure: Rejected) { JSONObject().put("status", "rejected").put("reason", failure.code) }
        catch (_: Exception) { JSONObject().put("status", "rejected").put("reason", "storage_or_integrity_failure") }
    }

    private class Rejected(val code: String) : RuntimeException()

    private class EncryptedRows(context: Context) : CollaborationGoalContractRows {
        private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)
        override fun read(key: String): String? {
            if (!database.contains(key)) return null
            return database.readString(key, "").also { check(it.isNotEmpty()) { "Goal contract storage integrity failure" } }
        }
        override fun commit(values: Map<String, String>) = database.mutateStrings(values)
        override fun removePrefix(prefix: String) = database.mutateStrings(emptyMap(), database.keys(prefix))
    }

    companion object {
        const val DEFAULT_PAGE_BYTES = 8192
        const val MIN_PAGE_BYTES = 1024
        const val MAX_PAGE_BYTES = 65536
        const val FORMAT = "galaxyssi.goal-contract.v1"
        const val PAGE_FORMAT = CloudGoalPageProtocol.FORMAT
        private const val ENVELOPE_RESERVE = 704
        private const val INLINE_CONTEXT_NAME_BYTES = 64
        private const val CONTEXT_DIRECTORY_KEYS = 8
        private const val CONTEXT_DIRECTORY_BYTES = 256
        private const val DATABASE = "galaxyssi_collaboration_goal_contract_v1"
        private val LOCK = Any()
        private val HASH = Regex("[a-f0-9]{64}")
        private val CURSOR = Regex("[A-Za-z0-9_-]{54}")

        fun remove(context: Context, groupId: String) = synchronized(LOCK) {
            EncryptedRows(context).removePrefix(groupPrefix(groupId))
        }

        private fun androidAuthorization(context: Context): (CollaborationWorkspaceAccess) -> Boolean {
            val groups = CollaborationGroupStore(context.applicationContext)
            val ledger = CollaborationEvidenceLedger(context.applicationContext)
            return { access ->
                val group = groups.load(access.groupId)
                group?.members?.any { it.id == access.personId } == true && ledger.authorizes(access)
            }
        }

        private fun reject(code: String): Nothing = throw Rejected(code)
        private fun digest(value: String) = AgentResultRecoveryClient.sha256(value.toByteArray(Charsets.UTF_8))
        private fun bytes(value: String) = value.toByteArray(Charsets.UTF_8).size
        private fun groupPrefix(group: String) = "group:${digest(group)}:"
        private fun snapshotPrefix(group: String, id: String) = groupPrefix(group) + "snapshot:$id:"
        private fun reader(access: CollaborationWorkspaceAccess) = digest(AgentNativeJsonCodec.stringify(
            listOf(access.groupId, access.runId, access.turnId, access.nodeId, access.personId)))
        private fun encode(value: Any?): String = AgentNativeJsonCodec.stringify(native(value))
        private fun native(value: Any?): Any? = when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> value.keys().asSequence().associateWith { native(value.get(it)) }
            is JSONArray -> (0 until value.length()).map { native(value.get(it)) }
            else -> value
        }

        private fun validUnicode(value: String): Boolean {
            var index = 0
            while (index < value.length) {
                val character = value[index++]
                if (character.isHighSurrogate()) {
                    if (index == value.length || !value[index++].isLowSurrogate()) return false
                } else if (character.isLowSurrogate()) return false
            }
            return true
        }

        private fun validateStrings(value: Any?) {
            when (value) {
                is String -> require(validUnicode(value))
                is JSONArray -> repeat(value.length()) { validateStrings(value.get(it)) }
                is JSONObject -> value.keys().asSequence().forEach { validateStrings(it); validateStrings(value.get(it)) }
            }
        }

        /** Android JSONTokener is lenient. Validate syntax first, then use its structured parser. */
        internal fun parseCriteria(raw: String): JSONArray = strictCriteria(raw).also {
            validateStrings(it)
            CollaborationSemanticGoalCoverage.criteriaHash(it)
        }

        private fun strictCriteria(raw: String): JSONArray = parseJson(raw) as JSONArray

        internal fun parseJson(raw: String): Any {
            require(validUnicode(raw))
            var index = 0
            fun whitespace() { while (index < raw.length && raw[index] in " \t\r\n") index++ }
            fun string(): String {
                val start = index++
                while (index < raw.length) {
                    val character = raw[index++]
                    if (character == '"') return JSONTokener(raw.substring(start, index)).nextValue() as String
                    require(character.code >= 0x20)
                    if (character == '\\') {
                        require(index < raw.length)
                        val escape = raw[index++]
                        if (escape == 'u') {
                            repeat(4) { require(index < raw.length && raw[index++].digitToIntOrNull(16) != null) }
                        } else require(escape in "\"\\/bfnrt")
                    }
                }
                error("Unterminated JSON string")
            }
            // Iterative container grammar has no depth or total-input policy cap.
            data class Frame(val objectValue: Boolean, var state: Int = 0, val keys: MutableSet<String> = hashSetOf())
            val stack = java.util.ArrayDeque<Frame>()
            var rootRead = false
            while (true) {
                whitespace()
                if (stack.isEmpty() && rootRead) { require(index == raw.length); break }
                val frame = stack.peekLast()
                require(index < raw.length)
                if (frame != null) {
                    if (frame.state == 0 && raw[index] == (if (frame.objectValue) '}' else ']')) {
                        index++; stack.removeLast(); continue
                    }
                    if (frame.objectValue && frame.state in setOf(0, 1)) {
                        require(raw[index] == '"' && frame.keys.add(string()))
                        whitespace(); require(index < raw.length && raw[index++] == ':')
                        frame.state = 2; continue
                    }
                    if (frame.state == 3) {
                        val character = raw[index++]
                        if (character == (if (frame.objectValue) '}' else ']')) stack.removeLast()
                        else { require(character == ','); frame.state = 1 }
                        continue
                    }
                    frame.state = 3
                } else rootRead = true
                when (raw[index]) {
                    '{', '[' -> stack.addLast(Frame(raw[index++] == '{'))
                    '"' -> string()
                    else -> {
                        val start = index
                        while (index < raw.length && raw[index] !in " \t\r\n,]}") index++
                        val token = raw.substring(start, index)
                        require(token in setOf("true", "false", "null") || JSON_NUMBER.matches(token))
                    }
                }
            }
            return JSONTokener(raw).nextValue()
        }

        private val JSON_NUMBER = Regex("-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?")
    }
}
