package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

internal data class AgentFileKey(val chat: String, val turn: String, val item: String) {
    val digest get() = AgentNativeJsonCodec.sha256(item)
}

/** Transport and the model's own report are independent observations. Neither implies the other. */
internal object AgentFileReceipt {
    private val observers = mutableMapOf<Pair<String, String>, MutableSet<() -> Unit>>()
    fun watch(chat: String, turn: String, listener: () -> Unit): () -> Unit {
        val id = chat to turn
        synchronized(observers) { observers.getOrPut(id) { mutableSetOf() }.add(listener) }
        return { synchronized(observers) {
            observers[id]?.let { it.remove(listener); if (it.isEmpty()) observers.remove(id) }
        } }
    }
    fun notifyRow(chat: String, turn: String) {
        val snapshot = synchronized(observers) { observers[chat to turn]?.toList() }.orEmpty()
        if (snapshot.isNotEmpty()) android.os.Handler(android.os.Looper.getMainLooper()).post { snapshot.forEach { it() } }
    }
    private fun group(row: JSONObject) = row.optJSONObject("file_receipts") ?: JSONObject().also { row.put("file_receipts", it) }
    fun item(row: JSONObject, key: AgentFileKey): JSONObject? = row.optJSONObject("file_receipts")?.optJSONObject(key.digest)
    fun fold(row: JSONObject, key: AgentFileKey, transfer: String, state: String, fingerprint: String = ""): Boolean {
        if (key.chat.isBlank() || key.turn.isBlank() || key.item.isBlank() || transfer.length != 64) return false
        val entries = row.optJSONObject("file_receipts") ?: if (state == "uploading") group(row) else return false
        val current = entries.optJSONObject(key.digest) ?: if (state == "uploading" && entries.length() < 10) JSONObject() else return false
        if (current.has("transfer") && current.optString("transfer") != transfer) return false
        if (state == "uploading" && current.has("wire") || current.optString("wire") in setOf("closed", "stored")) return false
        if (state == "retrying" && current.optString("wire") != "failed") return false
        if (state !in setOf("uploading", "retrying", "failed", "stored", "closed")) return false
        current.put("wire", state).put("transfer", transfer)
        if (state == "uploading") current.put("peer", fingerprint)
        entries.put(key.digest, current)
        return true
    }
    private fun ensureItem(row: JSONObject, key: AgentFileKey): JSONObject? {
        val entries = group(row)
        return entries.optJSONObject(key.digest) ?: if (entries.length() < 10)
            JSONObject().also { entries.put(key.digest, it) } else null
    }
    fun startRead(row: JSONObject, key: AgentFileKey, child: String) {
        ensureItem(row, key)?.put("read_turn", child)?.put("read_started", System.currentTimeMillis())?.remove("reading")
    }
    fun reading(row: JSONObject, key: AgentFileKey, reporter: String, understood: Boolean): Boolean {
        val current = ensureItem(row, key) ?: return false
        if (reporter != current.optString("read_turn", key.turn)) return false
        current.put("reading", if (understood) "recognized" else "unreadable")
        return true
    }
    fun originals(entry: AgentTranscriptEntry): List<AgentRichBlock> {
        if (entry.role != AgentTranscriptRole.USER || entry.sourceConversationId.isNotBlank() ||
            entry.conversationId.isBlank() || entry.turnId.isBlank()) return emptyList()
        val blocks = AgentRichContentCodec.decode(entry.richOutputJson)
            .filter { it.metadata["source"] == "user_attachment" && it.id.isNotBlank() &&
                it.type in setOf(AgentRichBlockType.IMAGE, AgentRichBlockType.FILE) }
        return blocks.takeIf { it.size in 1..10 && it.distinctBy(AgentRichBlock::id).size == it.size }.orEmpty()
    }
    fun report(c: Context, chat: String, turn: String, ordinal: Int, understood: Boolean): Boolean {
        val store = AgentTranscriptStore(c)
        fun inputs(t: String) = store.entriesForTurn(t).singleOrNull {
            it.role == AgentTranscriptRole.USER && it.conversationId == chat && it.sourceConversationId.isBlank()
        }?.let(::originals).orEmpty()
        val blocks = inputs(turn)
        val selected = blocks.getOrNull(ordinal - 1) ?: return false
        val child = AgentTurnReceipt.fileRow(c, chat, turn)
        val parent = child.optString("file_source_turn")
        val key = AgentFileKey(chat, parent.ifBlank { turn }, selected.id)
        if (parent.isEmpty() && blocks.size < 2) return false
        if (parent.isNotEmpty() && (blocks.size != 1 || child.optString("file_source_digest") != key.digest ||
                inputs(parent).let { it.size < 2 || it.none { b -> b.id == selected.id } })) return false
        // Recheck the generation on the receipt writer so a late observation cannot overwrite a newer attempt.
        if ((AgentTurnReceipt.fileInfo(c, key)?.optString("read_turn", key.turn) ?: key.turn) != turn) return false
        AgentTurnReceipt.fileChange(c, key) { reading(it, key, turn, understood) }
        return true
    }
    fun queued(c: Context, files: List<AgentPreparedOutboundAttachment>, fingerprint: String) {
        if (files.size < 2 || fingerprint.isBlank()) return
        files.forEach { f -> update(c, f, "uploading", fingerprint) }
    }
    fun update(c: Context, f: AgentPreparedOutboundAttachment, state: String, fingerprint: String = "") {
        val key = AgentFileKey(f.scope.conversationId, f.scope.turnId, f.attachmentId)
        AgentTurnReceipt.fileChange(c, key) { fold(it, key, f.transferId, state, fingerprint) }
    }
    fun isBound(c: Context, file: AgentPreparedOutboundAttachment, fp: String): Boolean {
        val key = AgentFileKey(file.scope.conversationId, file.scope.turnId, file.attachmentId)
        val receipt = AgentTurnReceipt.fileInfo(c, key) ?: return false
        return fp.isNotBlank() && receipt.optString("peer") == fp && receipt.optString("transfer") == file.transferId
    }
}
