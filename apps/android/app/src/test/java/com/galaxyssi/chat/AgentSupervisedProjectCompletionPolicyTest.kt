package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentSupervisedProjectCompletionPolicyTest {
    private val local = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false)
    private val commit = local.copy(publication = AgentPublicationRequirement.COMMIT)
    private val push = local.copy(publication = AgentPublicationRequirement.PUSH)
    private val pr = local.copy(publication = AgentPublicationRequirement.PULL_REQUEST)
    private val linux = local.copy(phoneLinux = true)

    @Test fun missingDeclarationRequestsModelInterpretationNotPublication() {
        assertEquals(listOf("model-declared completion_requirements (publication and phone_linux)"),
            AgentSupervisedProjectCompletionPolicy.missingEvidence(null, emptyList()))
    }

    @Test fun declaredLocalOutcomeNeedsNoPublicationOrLinuxReceipt() {
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(local, emptyList()).isEmpty())
    }

    @Test fun publicationRequiresItsOwnVerifiedOutcome() {
        for ((requirements, tool) in publicationCases()) {
            assertEquals(1, AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements, emptyList()).size)
            assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements, listOf(completed(tool))).isEmpty())
            for (status in listOf(AgentActionStatus.FAILED, AgentActionStatus.PENDING_CONFIRMATION)) {
                assertEquals(1, AgentSupervisedProjectCompletionPolicy.missingEvidence(
                    requirements, listOf(completed(tool).copy(status = status))).size)
            }
        }
        assertEquals(listOf("a successfully created pull request with its URL"),
            AgentSupervisedProjectCompletionPolicy.missingEvidence(pr,
                listOf(completed(AgentMobileProjectNativeTools.COMMIT), completed(AgentMobileProjectNativeTools.PUSH))))
    }

    @Test fun phoneLinuxRequiresSuccessfulGuestExecutionNotHostFileOperations() {
        assertEquals(listOf("a successful galaxyssi.runtime.execute receipt from the phone Linux guest"),
            AgentSupervisedProjectCompletionPolicy.missingEvidence(linux,
                listOf(completed(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT))))
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(linux,
            listOf(completed(AgentOnDeviceRuntimeTools.EXECUTE))).isEmpty())
        assertEquals(2, AgentSupervisedProjectCompletionPolicy.missingEvidence(pr.copy(phoneLinux = true), emptyList()).size)
    }

    @Test fun statusOnlyOrMalformedEvidenceCannotSatisfyDeclarations() {
        val cases = listOf(
            Triple(linux, AgentOnDeviceRuntimeTools.EXECUTE, "executor_success"),
            Triple(linux, AgentOnDeviceRuntimeTools.EXECUTE, """{"exit_code":1}"""),
            Triple(commit, AgentMobileProjectNativeTools.COMMIT, """{"commit":"not-a-hash"}"""),
            Triple(push, AgentMobileProjectNativeTools.PUSH, "{}"),
            Triple(pr, AgentMobileProjectNativeTools.CREATE_PULL_REQUEST, """{"number":2241}"""),
            Triple(pr, AgentMobileProjectNativeTools.CREATE_PULL_REQUEST,
                """{"number":2241,"url":"https://example.com/pull/2241"}"""),
            Triple(pr, AgentMobileProjectNativeTools.PUBLISH_PULL_REQUEST, """{"pull_request_number":2241}"""),
            Triple(pr, AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST,
                """{"pull_request_number":2241,"pull_request_url":"https://github.com/galaxyssi/GalaxySSI/pull/2241"}""")
        )
        for ((requirements, tool, evidence) in cases) {
            assertEquals(tool, 1, AgentSupervisedProjectCompletionPolicy.missingEvidence(
                requirements, listOf(completed(tool).copy(evidence = evidence))).size)
        }
    }

    @Test fun publicationToolsCloseOnlyDeclaredVerifiedTerminalOutcomes() {
        for ((requirements, tool) in publicationCases()) {
            val action = completed(tool)
            val receipt = nativeResult(tool, action.evidence)
            val accepted = outcome(requirements, action, receipt)
            assertNotNull(tool, accepted)
            assertEquals(tool, accepted?.terminalToolId)
            assertEquals(action.evidence, accepted?.evidence)
            assertNull(outcome(null, action, receipt))
            assertNull(outcome(local, action, receipt))
            assertNull(outcome(requirements, action, receipt.copy(success = false)))
            assertNull(outcome(requirements, action, receipt.copy(metadata = receipt.metadata + ("awaiting_response" to "true"))))
            assertNull(outcome(requirements, action, receipt.copy(metadata = receipt.metadata - "invocation_id")))
            assertNull(outcome(requirements, action, receipt.copy(metadata = receipt.metadata + ("native_tool_id" to "different"))))
            assertNull(outcome(requirements, action.copy(parameters = action.parameters +
                (AgentSupervisedProjectCompletionPolicy.MODEL_TERMINAL_OUTCOME_PARAMETER to "false")), receipt))
            assertNull(AgentSupervisedProjectCompletionPolicy.verifiedTerminalOutcome(
                "Public test", emptyList(), action, receipt, requirements))
            assertNull(outcome(requirements, action, nativeResult(tool, "{}")))
        }
    }

    @Test fun genericReceiptsAlwaysNeedModelObservationEvenWhenMarkedTerminal() {
        for (tool in listOf(AgentOnDeviceRuntimeTools.EXECUTE, AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT_BATCH)) {
            val action = completed(tool)
            assertNull(outcome(local, action, nativeResult(tool, action.evidence)
                .copy(message = "Workspace operation completed; invocation_id=internal")))
        }
    }

    @Test fun publicationMessagesUseStructuredReceiptsAndGoalOnlyForLanguage() {
        val action = completed(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST)
        assertEquals("GitHub PR #2241 was created and is open: https://github.com/galaxyssi/GalaxySSI/pull/2241",
            outcome(pr, action, nativeResult(action.target, action.evidence))?.message)
        val chinese = AgentSupervisedProjectCompletionPolicy.verifiedTerminalOutcome(
            "\u8bf7\u63d0\u4ea4 PR", listOf(action), action, nativeResult(action.target, action.evidence), pr)
        assertEquals("GitHub PR #2241 \u5df2\u521b\u5efa\u5e76\u5904\u4e8e open \u72b6\u6001\uff1ahttps://github.com/galaxyssi/GalaxySSI/pull/2241",
            chinese?.message)
        val pushed = completed(AgentMobileProjectNativeTools.PUSH)
        assertEquals("Branch feature/test was pushed and verified.", outcome(push, pushed,
            nativeResult(pushed.target, pushed.evidence))?.message)
        val committed = completed(AgentMobileProjectNativeTools.COMMIT)
        assertEquals("Commit 1234abc was created and verified.", outcome(commit, committed,
            nativeResult(committed.target, committed.evidence))?.message)
    }

    private fun publicationCases() = listOf(commit to AgentMobileProjectNativeTools.COMMIT,
        push to AgentMobileProjectNativeTools.PUSH, pr to AgentMobileProjectNativeTools.CREATE_PULL_REQUEST,
        pr to AgentMobileProjectNativeTools.PUBLISH_PULL_REQUEST, pr to AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST)

    private fun outcome(requirements: AgentCompletionRequirements?, action: AgentAction, result: AgentActionResult) =
        AgentSupervisedProjectCompletionPolicy.verifiedTerminalOutcome("Public test", listOf(action), action, result, requirements)

    private fun completed(tool: String) = AgentAction(id = tool, kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = tool, risk = AgentRisk.LOW, status = AgentActionStatus.COMPLETED, description = tool,
        parameters = mapOf("tool_id" to tool, AgentSupervisedProjectCompletionPolicy.MODEL_TERMINAL_OUTCOME_PARAMETER to "true"),
        evidence = when (tool) {
            AgentOnDeviceRuntimeTools.EXECUTE -> """{"exit_code":0}"""
            AgentMobileProjectNativeTools.COMMIT -> """{"commit":"1234abc"}"""
            AgentMobileProjectNativeTools.PUSH -> """{"branch":"feature/test"}"""
            AgentMobileProjectNativeTools.CREATE_PULL_REQUEST ->
                """{"number":2241,"url":"https://github.com/galaxyssi/GalaxySSI/pull/2241","state":"open"}"""
            AgentMobileProjectNativeTools.PUBLISH_PULL_REQUEST, AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST ->
                """{"commit":"1234abc","pull_request_number":2241,"pull_request_url":"https://github.com/galaxyssi/GalaxySSI/pull/2241","pull_request_state":"open"}"""
            else -> """{"text":"public test data"}"""
        })

    private fun nativeResult(tool: String, output: String) = AgentActionResult(tool, true, "Operation completed",
        mapOf("native_tool_id" to tool, "native_tool_status" to "succeeded", "native_tool_output" to output,
            "invocation_id" to "public-test-invocation"))
}
