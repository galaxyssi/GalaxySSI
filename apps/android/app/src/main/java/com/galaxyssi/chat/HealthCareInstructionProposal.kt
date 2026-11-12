package com.galaxyssi.chat

import org.json.JSONObject

internal data class HealthCareInstructionScope(val id: String, val revision: Int, val sourceHash: String) {
    init { require(HealthProfilePolicy.uuid(id) && revision > 1 && sourceHash.matches(Regex("[0-9a-f]{64}"))) }
    fun matches(value: HealthCareInstruction) = this == of(value)
    fun json() = JSONObject().put("id", id).put("revision", revision).put("source_hash", sourceHash)
    companion object {
        fun of(value: HealthCareInstruction) = HealthCareInstructionScope(value.id, value.revision,
            AgentNativeJsonCodec.sha256(value.source.json().toString()))
        fun from(j: JSONObject) = HealthCareInstructionScope(j.getString("id"), j.getInt("revision"), j.getString("source_hash"))
    }
}

internal enum class HealthCareExtractionCertainty { QUOTED, UNCERTAIN, NOT_FOUND }
internal enum class HealthCareInstructionProposalState { PENDING, APPLIED, DISMISSED }
internal data class HealthCareExtractedField(val quote: String, val certainty: HealthCareExtractionCertainty) {
    init {
        require(quote == quote.trim() && quote.length <= 1000)
        require((certainty == HealthCareExtractionCertainty.NOT_FOUND) == quote.isEmpty())
    }
    fun json() = JSONObject().put("quote", quote).put("certainty", certainty.name)
    companion object { fun from(j: JSONObject) = HealthCareExtractedField(j.getString("quote"), HealthCareExtractionCertainty.valueOf(j.getString("certainty"))) }
}

/** Model classification of exact source text is never a field review or clinician verification. */
internal data class HealthCareInstructionProposal(val grant: HealthCareDiscussionGrant, val encounterId: String,
    val kind: HealthCareInstructionKind, val fields: Map<HealthCareInstructionField, HealthCareExtractedField>,
    val createdAt: Long, val state: HealthCareInstructionProposalState = HealthCareInstructionProposalState.PENDING) {
    val id get() = grant.turnId
    val scope get() = requireNotNull(grant.instruction)
    val draft get() = HealthCareInstructionDraft(kind, fields.mapValues { HealthCareInstructionValue(it.value.quote) })
    init {
        require(grant.instruction != null && grant.researchAuthorizationId.isEmpty() && HealthProfilePolicy.uuid(encounterId) && createdAt > 0)
        require(fields.keys == HealthCareInstructionDraft(kind).required && fields.values.any { it.quote.isNotEmpty() })
    }
    fun json() = JSONObject().put("grant", grant.json()).put("encounter", encounterId).put("kind", kind.name)
        .put("fields", JSONObject(fields.mapKeys { it.key.name }.mapValues { it.value.json() }))
        .put("created", createdAt).put("state", state.name)
    companion object {
        fun from(j: JSONObject) = HealthCareInstructionProposal(HealthCareDiscussionGrant.from(j.getJSONObject("grant")),
            j.getString("encounter"), HealthCareInstructionKind.valueOf(j.getString("kind")), j.getJSONObject("fields").let { f ->
                f.keys().asSequence().associate { HealthCareInstructionField.valueOf(it) to HealthCareExtractedField.from(f.getJSONObject(it)) }
            }, j.getLong("created"), HealthCareInstructionProposalState.valueOf(j.getString("state")))
        fun parse(grant: HealthCareDiscussionGrant, value: HealthCareInstruction, input: AgentNativeJsonObject, now: Long): HealthCareInstructionProposal {
            require(input.keys == setOf("kind", "fields"))
            if (grant.concernId != value.concernId || grant.instruction?.matches(value) != true || !eligible(value)) throw HealthCareConflict()
            val j = JSONObject(input)
            val kind = HealthCareInstructionKind.valueOf(j.getString("kind"))
            val source = j.getJSONObject("fields")
            val fields = source.keys().asSequence().associate { key ->
                val field = source.getJSONObject(key)
                require(field.keys().asSequence().toSet() == setOf("quote", "certainty"))
                val extracted = HealthCareExtractedField.from(field)
                require(extracted.quote.isEmpty() || value.source.quote.contains(extracted.quote))
                HealthCareInstructionField.valueOf(key) to if (value.source.blurry && extracted.quote.isNotEmpty())
                    extracted.copy(certainty = HealthCareExtractionCertainty.UNCERTAIN) else extracted
            }
            return HealthCareInstructionProposal(grant, value.encounterId, kind, fields, now)
        }
        fun eligible(value: HealthCareInstruction) = value.draft.fields.values.all { it.review == HealthCareFieldReview.UNREVIEWED }
    }
}
