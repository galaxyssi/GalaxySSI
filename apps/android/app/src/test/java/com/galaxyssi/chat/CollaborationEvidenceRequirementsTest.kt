package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationEvidenceRequirementsTest {
    private fun requirement(origin: String = "desktop_codex_tool", tool: String = "commandExecution") =
        JSONObject().put("origin", origin).put("tool", tool)
    private fun criterion(vararg items: JSONObject) = JSONObject().put("id", "doc")
        .put(CollaborationEvidenceRequirements.FIELD, JSONArray(items.toList()))

    @Test fun sourceRequirementsCanBeStrengthenedButNotDroppedOrReplaced() {
        val original = criterion(requirement())
        assertFalse(CollaborationEvidenceRequirements.preserved(original, JSONObject()))
        assertFalse(CollaborationEvidenceRequirements.preserved(original, criterion(requirement(tool = "collaboration_recall"))))
        assertFalse(CollaborationEvidenceRequirements.preserved(original, null))
        assertTrue(CollaborationEvidenceRequirements.preserved(original, criterion(
            requirement("android_native_tool", "verify"), requirement())))
    }

    @Test fun malformedOrUnknownSourceDoesNotBecomeAnEmptyRequirement() {
        listOf(criterion(requirement("model_says_so")), criterion(requirement(tool = "")),
            criterion(requirement().put("optional", true)), JSONObject().put(CollaborationEvidenceRequirements.FIELD, "none")).forEach {
            assertThrows(IllegalArgumentException::class.java) { CollaborationEvidenceRequirements.required(it) }
        }
    }

    @Test fun failedAndAssessmentReceiptsCannotSatisfyAnOriginalRequirement() {
        val observed = requirement().put("status", "returned").put("observation_kind", "tool_output_recorded")
        CollaborationEvidenceRequirements.validate(criterion(requirement()), listOf(observed))
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationEvidenceRequirements.validate(criterion(requirement()), listOf(JSONObject(observed.toString()).put("status", "failed")))
        }
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationEvidenceRequirements.validate(criterion(requirement()), listOf(JSONObject(observed.toString())
                .put("observation_kind", "member_assessment_recorded")))
        }
    }

    @Test fun successfulRecallReceiptCannotReplaceTheOriginalExecutionSource() {
        val readReceipt = requirement("android_cloud_tool", "collaboration_recall")
            .put("status", "returned").put("observation_kind", "tool_output_recorded")
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationEvidenceRequirements.validate(criterion(requirement()), listOf(readReceipt))
        }
        val original = requirement().put("status", "returned").put("observation_kind", "tool_output_recorded")
        CollaborationEvidenceRequirements.validate(criterion(requirement()), listOf(readReceipt, original))
    }
}
