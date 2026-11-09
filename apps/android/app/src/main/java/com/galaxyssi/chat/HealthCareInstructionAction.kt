package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject

/** A confirmed transcription reference, not a medical recommendation or clinician attestation. */
internal data class HealthCareInstructionActionRef(val instructionId: String, val revision: Int,
    val encounterId: String, val documentId: String, val original: HealthCareDocumentRef, val invalidated: Boolean = false) {
    init { require(listOf(instructionId, encounterId, documentId).all(HealthProfilePolicy::uuid) && revision > 1 && original.page != null) }
    fun json() = JSONObject().put("instruction", instructionId).put("revision", revision).put("encounter", encounterId)
        .put("document", documentId).put("original", original.json()).put("invalidated", invalidated)
    fun matches(value: HealthCareInstruction) = !invalidated && instructionId == value.id && revision == value.revision &&
        encounterId == value.encounterId && documentId == value.source.documentId && original == value.source.original
    companion object {
        fun from(j: JSONObject) = HealthCareInstructionActionRef(j.getString("instruction"), j.getInt("revision"),
            j.getString("encounter"), j.getString("document"), HealthCareDocumentRef.from(j.getJSONObject("original")), j.getBoolean("invalidated"))
        fun of(value: HealthCareInstruction) = HealthCareInstructionActionRef(value.id, value.revision, value.encounterId,
            value.source.documentId, value.source.original)
    }
}

internal object HealthCareInstructionActionPolicy {
    fun eligible(value: HealthCareInstruction): Boolean {
        val draft = value.draft
        if (!draft.reviewed) return false
        val explicit = if (draft.kind == HealthCareInstructionKind.MEDICATION) draft.required else
            setOf(HealthCareInstructionField.NAME, HealthCareInstructionField.DETAILS)
        return explicit.all { draft.fields[it]?.review == HealthCareFieldReview.TRANSCRIBED }
    }
    fun actionId(value: HealthCareInstruction) = UUID.nameUUIDFromBytes(
        "clinical-instruction:${value.id}:${value.revision}".toByteArray(Charsets.UTF_8)).toString()

    fun confirm(issue: HealthCareConcern, value: HealthCareInstruction, now: Long): HealthCareAction {
        require(now > 0 && eligible(value))
        if (value.concernId != issue.id || issue.stage in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED)) throw HealthCareConflict()
        return HealthCareAction(actionId(value), HealthCareActionKind.CLINICAL_INSTRUCTION,
            value.draft.fields.getValue(HealthCareInstructionField.NAME).text,
            value.draft.fields.getValue(HealthCareInstructionField.DETAILS).text,
            "user_transcribed", HealthCareActionState.CONFIRMED, confirmedAt = now, basis = HealthCareFollowUpPolicy.basis(issue),
            instruction = HealthCareInstructionActionRef.of(value))
    }

    fun invalidate(issue: HealthCareConcern, predicate: (HealthCareInstructionActionRef) -> Boolean): HealthCareConcern =
        issue.copy(actions = issue.actions.map { action ->
            val ref = action.instruction
            if (ref != null && !ref.invalidated && predicate(ref)) action.copy(instruction = ref.copy(invalidated = true)) else action
        })
}
