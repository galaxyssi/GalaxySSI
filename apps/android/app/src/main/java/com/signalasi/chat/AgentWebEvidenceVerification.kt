package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.security.MessageDigest
import java.util.Locale

internal data class AgentWebCitationValidation(
    val status: String,
    val evidenceItemCount: Int,
    val verifiedEvidenceItemCount: Int,
    val citedUrls: List<String>,
    val invalidCitationUrls: List<String>
) {
    val valid: Boolean
        get() = status == "verified"

    val requiresRepair: Boolean
        get() = evidenceItemCount > 0 && !valid
}

/** Deterministic integrity, correlation, conflict-candidate, and final-citation checks. */
internal object AgentWebEvidenceVerification {
    private val SHA256 = Regex("[a-f0-9]{64}")
    private val CITATION_ID = Regex("[a-f0-9]{24}")
    private val MARKDOWN_LINK = Regex("\\[[^]\\n]{0,300}]\\((https?://[^\\s)]+)(?:\\s+[^)]*)?\\)", RegexOption.IGNORE_CASE)
    private val SENTENCE_BREAK = Regex("[\\n.!?;。！？；]+")
    private val NUMBER_VALUE = Regex(
        "(?iu)(?<![\\p{L}\\p{N}])[+-]?\\d+(?:[.,]\\d+)*(?:\\s*(?:%|‰|°[cf]?|ms|s|sec|seconds?|" +
            "minutes?|hours?|days?|kb|mb|gb|tb|kib|mib|gib|tib|hz|khz|mhz|ghz|w|kw|mw|v|mv|a|ma|" +
            "usd|eur|cny|rmb|元|美元|欧元|秒|分钟|小时|天|年|月|日))?"
    )
    private val SKELETON_SPACE = Regex("[^\\p{L}\\p{N}<>]+")

    fun attach(pack: AgentNativeJsonObject): AgentNativeJsonObject {
        val enriched = LinkedHashMap(pack)
        val conflicts = conflictReview(objectList(pack["items"]))
        enriched["verification"] = verify(enriched)
        enriched["conflict_review"] = conflicts
        val contract = stringMap(pack["synthesis_contract"]).toMutableMap()
        contract.putAll(
            linkedMapOf(
                "detect_material_conflicts" to true,
                "surface_uncertainty" to true,
                "never_invent_citations" to true,
                "allowed_citation_urls" to "evidence_pack_items_only",
                "compare_independent_retrieved_bodies" to true,
                "host_conflict_candidates_require_model_review" to true
            )
        )
        enriched["synthesis_contract"] = contract
        return enriched
    }

    fun verify(pack: Map<*, *>): AgentNativeJsonObject {
        val protocolValid = pack["protocol"] == AGENT_WEB_EVIDENCE_PACK_PROTOCOL
        val items = objectList(pack["items"])
        val invalid = mutableListOf<AgentNativeJsonObject>()
        val valid = mutableListOf<AgentNativeJsonObject>()
        val seenUrls = linkedSetOf<String>()
        val seenIds = linkedSetOf<String>()
        items.forEachIndexed { index, item ->
            val reasons = mutableListOf<String>()
            val rawUrl = item["url"]?.toString().orEmpty().trim()
            val canonical = canonical(rawUrl)
            val contentSha = item["content_sha256"]?.toString().orEmpty().lowercase(Locale.ROOT)
            val citationId = item["citation_id"]?.toString().orEmpty().lowercase(Locale.ROOT)
            val rank = nonNegativeLong(item["rank"]).toInt()
            if (!isWebUrl(canonical) || canonical != rawUrl) reasons += "invalid_or_noncanonical_url"
            if (!SHA256.matches(contentSha)) reasons += "invalid_content_sha256"
            if (!CITATION_ID.matches(citationId)) reasons += "invalid_citation_id"
            if (rank != index + 1) reasons += "invalid_rank"
            if (canonical.isNotBlank() && !seenUrls.add(canonical)) reasons += "duplicate_url"
            if (citationId.isNotBlank() && !seenIds.add(citationId)) reasons += "duplicate_citation_id"
            if (canonical.isNotBlank() && SHA256.matches(contentSha)) {
                val expected = AgentWebIntelligenceText.citationId(canonical, contentSha)
                if (citationId != expected) reasons += "citation_id_mismatch"
            }
            if (reasons.isEmpty()) {
                valid += linkedMapOf(
                    "citation_id" to citationId,
                    "url" to canonical,
                    "content_sha256" to contentSha
                )
            } else {
                invalid += linkedMapOf(
                    "index" to index,
                    "citation_id" to citationId.take(32),
                    "reasons" to reasons
                )
            }
        }
        val status = when {
            !protocolValid || (items.isNotEmpty() && valid.isEmpty()) -> "failed"
            invalid.isNotEmpty() -> "partial"
            else -> "verified"
        }
        val manifestValue = valid.joinToString("\n") {
            "${it["citation_id"]}\n${it["url"]}\n${it["content_sha256"]}"
        }
        return linkedMapOf(
            "status" to status,
            "protocol_valid" to protocolValid,
            "item_count" to items.size,
            "valid_item_count" to valid.size,
            "invalid_item_count" to invalid.size,
            "invalid_items" to invalid.take(12),
            "citation_manifest" to valid,
            "citation_manifest_sha256" to sha256Text(manifestValue),
            "verified_at_build_time" to true
        )
    }

    private fun sha256Text(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(Locale.ROOT, it.toInt() and 0xff) }

    fun validateAnswer(
        answer: String,
        encodedToolResults: List<Pair<String, String>>
    ): AgentWebCitationValidation {
        val packs = encodedToolResults.mapNotNull { (_, encoded) -> decodePack(encoded) }
        return validateAnswerPacks(answer, packs)
    }

    fun validateAnswerPacks(
        answer: String,
        packs: List<AgentNativeJsonObject>
    ): AgentWebCitationValidation {
        val allowed = linkedSetOf<String>()
        var evidenceItems = 0
        var verifiedItems = 0
        packs.forEach { pack ->
            val items = objectList(pack["items"])
            evidenceItems += items.size
            items.forEach { item ->
                val url = canonical(item["url"])
                val hash = item["content_sha256"]?.toString().orEmpty().lowercase(Locale.ROOT)
                val citationId = item["citation_id"]?.toString().orEmpty().lowercase(Locale.ROOT)
                if (isWebUrl(url) && SHA256.matches(hash) &&
                    citationId == AgentWebIntelligenceText.citationId(url, hash)
                ) {
                    allowed += url
                    verifiedItems += 1
                }
            }
        }
        val cited = MARKDOWN_LINK.findAll(answer)
            .map { canonical(it.groupValues[1].trimEnd('.', ',', ';')) }
            .filter(String::isNotBlank)
            .distinct()
            .toList()
        val invalid = cited.filterNot(allowed::contains)
        val status = when {
            evidenceItems == 0 -> "not_required"
            verifiedItems == 0 -> "evidence_unverified"
            cited.isEmpty() -> "missing_citations"
            invalid.isNotEmpty() -> "foreign_citations"
            else -> "verified"
        }
        return AgentWebCitationValidation(
            status = status,
            evidenceItemCount = evidenceItems,
            verifiedEvidenceItemCount = verifiedItems,
            citedUrls = cited,
            invalidCitationUrls = invalid
        )
    }

    fun repairPrompt(
        validation: AgentWebCitationValidation,
        encodedToolResults: List<Pair<String, String>>
    ): String {
        val allowed = encodedToolResults.mapNotNull { (_, encoded) -> decodePack(encoded) }
            .flatMap { pack -> objectList(pack["items"]) }
            .mapNotNull { item ->
                canonical(item["url"]).takeIf(String::isNotBlank)
            }
            .distinct()
            .take(12)
        return buildString {
            append("Your draft did not pass SignalASI citation verification (status=")
            append(validation.status).append("). Rewrite the complete user-facing answer once. ")
            append("Keep useful conclusions, compare material disagreement between independent retrieved bodies, ")
            append("state uncertainty, and place Markdown source links next to supported claims. ")
            append("Cite only these verified Evidence Pack URLs; do not invent or substitute links:\n")
            allowed.forEach { append("- ").append(it).append('\n') }
        }.take(8_000)
    }

    private fun conflictReview(items: List<AgentNativeJsonObject>): AgentNativeJsonObject {
        val retrieved = items.filter { it["evidence_level"] == "retrieved_body" }
        val domains = retrieved.mapNotNull { host(it["url"]?.toString().orEmpty()) }.toSet()
        val duplicates = retrieved.groupBy { it["content_sha256"]?.toString().orEmpty() }
            .filter { (hash, group) -> SHA256.matches(hash) && group.map { it["url"] }.distinct().size > 1 }
            .values
            .take(8)
            .map { group ->
                linkedMapOf(
                    "content_sha256" to group.first()["content_sha256"],
                    "citation_ids" to group.map { it["citation_id"] },
                    "urls" to group.map { it["url"] },
                    "independent_evidence" to false
                )
            }
        val claims = retrieved.flatMap(::numericClaims)
        val conflicts = claims.groupBy(NumericClaim::skeleton)
            .values
            .filter { group ->
                group.map(NumericClaim::domain).distinct().size > 1 &&
                    group.map(NumericClaim::values).distinct().size > 1
            }
            .take(8)
            .map { group ->
                linkedMapOf(
                    "kind" to "numeric_value_mismatch",
                    "confidence" to "high",
                    "requires_model_review" to true,
                    "claims" to group.take(4).map { claim ->
                        linkedMapOf(
                            "citation_id" to claim.citationId,
                            "url" to claim.url,
                            "text" to claim.text,
                            "values" to claim.values
                        )
                    }
                )
            }
        return linkedMapOf(
            "status" to if (conflicts.isEmpty()) "no_structural_conflict_detected" else "potential_conflict",
            "review_required" to (domains.size >= 2),
            "independent_retrieved_domain_count" to domains.size,
            "duplicate_content_groups" to duplicates,
            "potential_conflicts" to conflicts,
            "detector_scope" to "exact_cross_domain_numeric_claim_structure",
            "semantic_resolution" to "current_model_required"
        )
    }

    private fun numericClaims(item: AgentNativeJsonObject): List<NumericClaim> {
        val citationId = item["citation_id"]?.toString().orEmpty()
        val url = canonical(item["url"])
        val domain = host(url).orEmpty()
        if (citationId.isBlank() || domain.isBlank()) return emptyList()
        return SENTENCE_BREAK.split(item["excerpt"]?.toString().orEmpty())
            .asSequence()
            .map(String::trim)
            .filter { it.length in 12..500 }
            .mapNotNull { sentence ->
                val matches = NUMBER_VALUE.findAll(sentence).toList()
                if (matches.isEmpty()) return@mapNotNull null
                val values = matches.map { normalizeValue(it.value) }
                var skeleton = sentence.lowercase(Locale.ROOT)
                matches.asReversed().forEach { match ->
                    skeleton = skeleton.replaceRange(match.range, "<value>")
                }
                skeleton = SKELETON_SPACE.replace(skeleton, " ").trim()
                if (skeleton.length < 10) return@mapNotNull null
                NumericClaim(citationId, url, domain, sentence.take(280), values, skeleton)
            }
            .take(64)
            .toList()
    }

    private fun decodePack(encoded: String): AgentNativeJsonObject? = runCatching {
        JSONObject(encoded).optJSONObject("evidence_pack")?.toNativeMap()
    }.getOrNull()

    private fun JSONObject.toNativeMap(): AgentNativeJsonObject = linkedMapOf<String, Any?>().also { target ->
        keys().forEachRemaining { key -> target[key] = opt(key).toNativeValue() }
    }

    private fun JSONArray.toNativeList(): List<Any?> = (0 until length()).map { index ->
        opt(index).toNativeValue()
    }

    private fun Any?.toNativeValue(): Any? = when (this) {
        null, JSONObject.NULL -> null
        is JSONObject -> toNativeMap()
        is JSONArray -> toNativeList()
        else -> this
    }

    private fun objectList(value: Any?): List<AgentNativeJsonObject> = (value as? Iterable<*>)
        ?.mapNotNull { item -> (item as? Map<*, *>)?.let(::stringMap) }
        .orEmpty()

    private fun stringMap(value: Any?): AgentNativeJsonObject = (value as? Map<*, *>)
        ?.entries
        ?.mapNotNull { (key, item) -> (key as? String)?.let { it to item } }
        ?.toMap(LinkedHashMap())
        .orEmpty()

    private fun canonical(value: Any?): String = value?.toString().orEmpty().trim().let { url ->
        if (url.isBlank()) "" else runCatching { AgentWebIntelligenceText.canonicalUrl(url) }.getOrDefault("")
    }

    private fun isWebUrl(value: String): Boolean = runCatching {
        val uri = URI(value)
        uri.scheme?.lowercase(Locale.ROOT) in setOf("http", "https") && !uri.host.isNullOrBlank()
    }.getOrDefault(false)

    private fun host(value: String): String? = runCatching {
        URI(value).host?.lowercase(Locale.ROOT)?.removePrefix("www.")
    }.getOrNull()?.takeIf(String::isNotBlank)

    private fun normalizeValue(value: String): String = value.lowercase(Locale.ROOT)
        .replace(",", "")
        .replace(Regex("\\s+"), "")

    private fun nonNegativeLong(value: Any?): Long = when (value) {
        is Number -> value.toLong()
        else -> value?.toString()?.toLongOrNull() ?: 0L
    }.coerceAtLeast(0L)

    private data class NumericClaim(
        val citationId: String,
        val url: String,
        val domain: String,
        val text: String,
        val values: List<String>,
        val skeleton: String
    )
}
