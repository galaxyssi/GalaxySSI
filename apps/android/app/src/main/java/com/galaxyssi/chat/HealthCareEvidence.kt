package com.galaxyssi.chat

import java.net.URI
import java.util.UUID
import org.json.JSONObject

/** A native read receipt proves provenance, never medical correctness or applicability. */
internal data class HealthCareEvidence(val id: String, val grant: HealthCareDiscussionGrant, val invocationId: String,
    val url: String, val title: String, val citationId: String, val contentHash: String, val excerpt: String,
    val retrievedAt: Long, val observedAt: Long) {
    init {
        require(HealthProfilePolicy.uuid(id) && invocationId.isNotBlank() && invocationId.length <= 256)
        val uri = URI(url)
        require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null && url.length <= 1000)
        require(title.isNotBlank() && title.length <= 512 && excerpt.length in 12..8000)
        require(contentHash.matches(Regex("[a-f0-9]{64}")) && citationId == AgentWebIntelligenceText.citationId(url, contentHash))
        require(retrievedAt > 0 && retrievedAt <= observedAt && observedAt >= grant.approvedAt)
    }
    fun json() = JSONObject().put("id", id).put("grant", grant.json()).put("invocation", invocationId)
        .put("url", url).put("title", title).put("citation", citationId).put("hash", contentHash).put("excerpt", excerpt)
        .put("retrieved", retrievedAt).put("observed", observedAt)
    fun output(): AgentNativeJsonObject = mapOf("evidence_id" to id, "url" to url, "title" to title,
        "citation_id" to citationId, "content_sha256" to contentHash, "excerpt" to excerpt,
        "retrieved_at_millis" to retrievedAt, "observed_at_millis" to observedAt,
        "verification_scope" to "native_retrieval_and_quote_only", "medical_applicability_verified" to false)
    companion object { fun from(j: JSONObject) = HealthCareEvidence(j.getString("id"),
        HealthCareDiscussionGrant.from(j.getJSONObject("grant")), j.getString("invocation"), j.getString("url"),
        j.getString("title"), j.getString("citation"), j.getString("hash"), j.getString("excerpt"),
        j.getLong("retrieved"), j.getLong("observed")) }
}

internal class HealthCareEvidenceMissing : IllegalArgumentException("Read the source body in this approved health turn before proposing a plan")

internal object HealthCareEvidencePolicy {
    private val whitespace = Regex("\\s+")
    private fun normalized(value: String) = value.replace('\u00a0', ' ').replace(whitespace, " ").trim()
    fun supports(evidence: HealthCareEvidence, grant: HealthCareDiscussionGrant, url: String, quote: String): Boolean =
        evidence.grant == grant && evidence.url == url && quote.length in 12..600 &&
            normalized(quote).length >= 12 && normalized(evidence.excerpt).contains(normalized(quote))

    fun read(output: AgentNativeJsonObject, grant: HealthCareDiscussionGrant, invocationId: String, now: Long): List<HealthCareEvidence> {
        if (output["status"] !in setOf("completed", "partial")) return emptyList()
        val pack = output["evidence_pack"] as? Map<*, *> ?: return emptyList()
        if (pack["protocol"] != AGENT_WEB_EVIDENCE_PACK_PROTOCOL) return emptyList()
        return (pack["items"] as? List<*>)?.take(12)?.mapNotNull { raw ->
            val item = raw as? Map<*, *> ?: return@mapNotNull null
            if (item["evidence_level"] != "retrieved_body" || item["source_kind"] != "document") return@mapNotNull null
            runCatching {
                val url = item["url"] as String
                val excerpt = item["excerpt"] as String
                val citation = item["citation_id"] as String
                val id = UUID.nameUUIDFromBytes(AgentNativeJsonCodec.sha256(mapOf("turn" to grant.turnId,
                    "invocation" to invocationId, "citation" to citation, "excerpt" to excerpt)).toByteArray(Charsets.UTF_8)).toString()
                HealthCareEvidence(id, grant, invocationId, url, item["title"] as String, citation,
                    item["content_sha256"] as String, excerpt, (item["retrieved_at_millis"] as Number).toLong(), now)
            }.getOrNull()
        }.orEmpty().distinctBy { it.id }
    }
}
