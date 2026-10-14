package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentArtifactCompletionEvidenceTest {
    private val source = "a".repeat(64)
    private val output = "b".repeat(64)
    private val requirement = AgentArtifactRequirement("outputs/edited.png", source)

    private fun receipt(hash: String, exit: Int = 0, path: String = requirement.path) = AgentAction(
        id = "export", kind = AgentActionKind.CALL_NATIVE_TOOL, target = AgentOnDeviceRuntimeTools.EXECUTE,
        risk = AgentRisk.LOW, status = AgentActionStatus.COMPLETED, description = "Export result",
        evidence = """{"exit_code":$exit,"artifacts":[{"relative_path":"$path","sha256":"$hash","size_bytes":123}]}""")

    @Test fun unchangedCopyIsNotAnEditedArtifact() {
        assertTrue(AgentArtifactCompletionEvidence.missing(listOf(requirement), listOf(receipt(source))).single().contains("unchanged"))
        assertTrue(AgentArtifactCompletionEvidence.missing(listOf(requirement), listOf(receipt(output))).isEmpty())
    }

    @Test fun missingFailedWrongPathAndUnverifiedArtifactsCannotComplete() {
        for (history in listOf(emptyList(), listOf(receipt(output, exit = 1)),
            listOf(receipt(output, path = "other.png")), listOf(receipt("claimed")),
            listOf(receipt(output).copy(status = AgentActionStatus.FAILED)))) {
            assertEquals(1, AgentArtifactCompletionEvidence.missing(listOf(requirement), history).size)
        }
    }

    @Test fun latestExportWinsAndUnchangedFilesAreValidWhenNoEditWasRequested() {
        assertEquals(1, AgentArtifactCompletionEvidence.missing(listOf(requirement), listOf(receipt(output), receipt(source))).size)
        assertTrue(AgentArtifactCompletionEvidence.missing(listOf(requirement.copy(sourceSha256 = "")), listOf(receipt(source))).isEmpty())
        assertTrue(AgentArtifactCompletionEvidence.missing(emptyList(), emptyList()).isEmpty())
    }

    @Test fun artifactRequirementsRoundTripAndCannotSilentlyDisappear() {
        val value = AgentCompletionRequirements(AgentPublicationRequirement.NONE, true, artifacts = listOf(requirement))
        assertEquals(value, AgentCompletionRequirements.parse(value.toJson()))
        assertFalse(value.copy(artifacts = emptyList()).canReplace(value))
        for (path in listOf("../escape", "/absolute", "C:/desktop/file", "outputs/../file")) {
            assertNull(AgentArtifactRequirement.parse(JSONObject().put("path", path)))
        }
        assertNull(AgentArtifactRequirement.parse(JSONObject().put("path", "output.png").put("source_sha256", "bad")))
    }
}
