package com.galaxyssi.chat

import java.security.MessageDigest
import java.util.TreeSet

/** Folds sorted source bodies without retaining them; fingerprints match the existing observation format. */
internal class KnowledgeSourceObservation {
    private var first: AgentKnowledgeItem? = null
    private var last: KnowledgeOrderKey? = null
    private var summary = ""
    private var count = 0
    private var finished = false
    private val digest = MessageDigest.getInstance("SHA-256")
    private val tags = TreeSet<String>()
    private val kinds = TreeSet<String>()
    // Preserve the exact existing ACL fingerprint. This metadata set is not a fixed-size cache.
    private val agents = TreeSet<String>()
    private var cloud = AgentKnowledgeCloudAccess.FULL
    private var agent = AgentKnowledgeAgentAccess.ANY_PAIRED_AGENT

    fun add(item: AgentKnowledgeItem) {
        check(!finished)
        val key = KnowledgeOrderKey(item.chunkIndex, item.id)
        last?.let { check(it < key) { "Source observations require unique sorted identities" } }
        first?.let { check(it.source == item.source) } ?: run { first = item.copy(content = "") }
        last = key
        if (count > 0) digest.update('|'.code.toByte())
        val fields = listOf(item.id, item.kind.name, item.title, item.content, item.summary,
            item.tags.joinToString("|"), item.chunkIndex.toString(), item.chunkCount.toString())
        digest.update(hex(MessageDigest.getInstance("SHA-256").digest(fields.joinToString("\u0000")
            .toByteArray(Charsets.UTF_8))).toByteArray(Charsets.UTF_8))
        count = Math.addExact(count, 1)
        if (summary.isBlank()) summary = item.summary.replace(Regex("\\s+"), " ").trim().take(640)
        item.tags.forEach { value ->
            val tag = value.replace(Regex("\\s+"), " ").trim()
            if (tag.isNotBlank()) { tags.add(tag); if (tags.size > 12) tags.pollLast() }
        }
        kinds.add(item.kind.name)
        agents.addAll(item.allowedAgentIds)
        cloud = when {
            cloud == AgentKnowledgeCloudAccess.DENY || item.cloudAccess == AgentKnowledgeCloudAccess.DENY -> AgentKnowledgeCloudAccess.DENY
            cloud == AgentKnowledgeCloudAccess.SUMMARY_ONLY || item.cloudAccess == AgentKnowledgeCloudAccess.SUMMARY_ONLY -> AgentKnowledgeCloudAccess.SUMMARY_ONLY
            else -> AgentKnowledgeCloudAccess.FULL
        }
        agent = when {
            agent == AgentKnowledgeAgentAccess.LOCAL_ONLY || item.agentAccess == AgentKnowledgeAgentAccess.LOCAL_ONLY -> AgentKnowledgeAgentAccess.LOCAL_ONLY
            agent == AgentKnowledgeAgentAccess.SELECTED_AGENTS || item.agentAccess == AgentKnowledgeAgentAccess.SELECTED_AGENTS -> AgentKnowledgeAgentAccess.SELECTED_AGENTS
            else -> AgentKnowledgeAgentAccess.ANY_PAIRED_AGENT
        }
    }

    fun finish(): GlobalPersistentContextObservationExtractor.KnowledgeSourceSnapshot? {
        check(!finished)
        finished = true
        val item = first ?: return null
        val sourceKey = GlobalPersistentContextObservationExtractor.knowledgeSourceKey(item)
        val title = item.title.replace(Regex("\\s+\\[\\d+/\\d+]$"), "").replace(Regex("\\s+"), " ")
            .trim().take(180).ifBlank { "Knowledge source" }
        val content = GlobalAgentText.stableKey(title, summary, tags.joinToString("|"), hex(digest.digest()))
        val access = GlobalAgentText.stableKey(cloud.name, agent.name, agents.joinToString("|"))
        return GlobalPersistentContextObservationExtractor.KnowledgeSourceSnapshot(
            sourceKey, "knowledge-root:$sourceKey", "knowledge:$sourceKey:${GlobalAgentText.stableKey(content, access)}",
            title, summary, kinds.joinToString(","), GlobalPersistentContextObservationExtractor.sourceKind(item.source),
            count, cloud, agent, agents.size,
            if (cloud != AgentKnowledgeCloudAccess.DENY && agent == AgentKnowledgeAgentAccess.ANY_PAIRED_AGENT)
                GlobalWorldContextVisibility.SHAREABLE else GlobalWorldContextVisibility.LOCAL_ONLY,
            content, access, tags.toList())
    }

    private fun hex(bytes: ByteArray): String = buildString(bytes.size * 2) {
        for (byte in bytes) { append("0123456789abcdef"[(byte.toInt() and 255) ushr 4]); append("0123456789abcdef"[byte.toInt() and 15]) }
    }
}
