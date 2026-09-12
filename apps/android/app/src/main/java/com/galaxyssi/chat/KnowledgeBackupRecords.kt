package com.galaxyssi.chat

import org.json.JSONObject

/** Portable source records, not device-bound vectors, keys, or derived indexes. */
internal object KnowledgeBackupRecords {
    fun export(snapshot: KnowledgeBackupSnapshot, writer: BackupRecordStream.Writer) {
        writer.json("knowledge", "begin", JSONObject().put("schema", 1))
        var count = 0L
        for (item in snapshot.items()) {
            writer.json("knowledge-row", key(item.id), AgentKnowledgeCodec.encodeItem(item))
            count = Math.addExact(count, 1)
        }
        snapshot.checkActive()
        writer.json("knowledge", "end", JSONObject().put("rows", count))
    }
    fun key(id: String): String = AgentNativeJsonCodec.sha256(id)
    fun decode(json: JSONObject): AgentKnowledgeItem {
        require(json.getString("id").isNotBlank()) { "Knowledge backup has no stable ID" }
        val item = requireNotNull(AgentKnowledgeCodec.decodeItem(json)) { "Invalid knowledge backup item" }
        require(json.getString("kind") == item.kind.name && json.getString("cloud_access") == item.cloudAccess.name &&
            json.getString("agent_access") == item.agentAccess.name) { "Unsupported knowledge backup policy" }
        require(json.getInt("chunk_index") == item.chunkIndex && json.getInt("chunk_count") == item.chunkCount)
        require(json.getLong("updated_at_millis") == item.updatedAtMillis)
        return item
    }
}
