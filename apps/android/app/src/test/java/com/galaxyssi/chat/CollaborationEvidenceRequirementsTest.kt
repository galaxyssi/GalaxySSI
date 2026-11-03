package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationEvidenceRequirementsTest {
    @Test fun desktopAdmissionUsesTheSameNamesAsTheAuthenticatedImporter() {
        assertEquals(CollaborationRemoteEvidenceProtocol.RECORDED_TOOLS,
            CollaborationRemoteEvidenceProtocol.TYPES.map(CollaborationRemoteEvidenceProtocol::recordedTool).toSet())
        for (tool in CollaborationRemoteEvidenceProtocol.RECORDED_TOOLS)
            CollaborationEvidenceRequirements.validateAdmission(JSONArray(), JSONArray().put(criterion(requirement(tool = tool))))
        assertThrows(IllegalArgumentException::class.java) { CollaborationRemoteEvidenceProtocol.recordedTool("exec_command") }
    }

    @Test fun callableNamesAreRejectedBeforeFreezingWithoutRewritingTheDraft() {
        for (tool in listOf("exec_command", "commandExecution", "codex.exec_command", "codex.commandExecution ")) {
            val proposed = JSONArray().put(criterion(requirement(tool = tool)))
            val original = proposed.toString()
            val error = assertThrows(CollaborationAssessmentValidation.Failure::class.java) {
                CollaborationEvidenceRequirements.validateAdmission(JSONArray(), proposed)
            }
            assertEquals("$.criteria[0].required_observations[0].tool", error.path)
            assertEquals("unknown_recorded_tool", error.code)
            assertTrue(error.expected.contains("codex.commandExecution"))
            assertEquals(original, proposed.toString())
        }
    }

    @Test fun savedUnknownBindingRemainsReadableAndDoesNotBecomeAnAlias() {
        val saved = criterion(requirement(tool = "exec_command"))
        val prior = JSONArray().put(saved)
        CollaborationEvidenceRequirements.validateAdmission(prior, JSONArray(prior.toString()))
        assertTrue(CollaborationEvidenceRequirements.required(saved).contains("desktop_codex_tool" to "exec_command"))
        val actual = requirement(tool = "codex.commandExecution").put("status", "returned")
            .put("observation_kind", "tool_output_recorded")
        assertThrows(IllegalArgumentException::class.java) { CollaborationEvidenceRequirements.validate(saved, listOf(actual)) }
        assertFalse(CollaborationEvidenceRequirements.preserved(saved, criterion(requirement(tool = "codex.commandExecution"))))
    }

    @Test fun newConstraintsAreCheckedWithoutRestrictingOtherEvidenceOrigins() {
        val prior = JSONArray().put(criterion(requirement(tool = "codex.commandExecution")))
        assertThrows(CollaborationAssessmentValidation.Failure::class.java) {
            CollaborationEvidenceRequirements.validateAdmission(prior,
                JSONArray().put(criterion(requirement(tool = "codex.commandExecution"), requirement(tool = "exec_command"))))
        }
        for (origin in listOf("android_cloud_tool", "android_native_tool"))
            CollaborationEvidenceRequirements.validateAdmission(JSONArray(), JSONArray().put(criterion(requirement(origin, "exec_command"))))
    }

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
