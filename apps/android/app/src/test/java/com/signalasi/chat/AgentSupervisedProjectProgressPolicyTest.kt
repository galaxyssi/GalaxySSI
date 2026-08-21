package com.signalasi.chat

import org.json.JSONObject
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectProgressPolicyTest {
    @Test
    fun `rejects repeated successful pull without an intervening mutation`() {
        val pull = toolAction(AgentMobileProjectNativeTools.PULL, "pull-1")

        val violation = AgentSupervisedProjectProgressPolicy.violation(
            pull.copy(id = "pull-2", status = AgentActionStatus.PENDING_CONFIRMATION),
            listOf(pull)
        )

        assertTrue(violation.orEmpty().contains("baseline was already synchronized"))
    }

    @Test
    fun `allows another observation after a verified project mutation`() {
        val inspect = toolAction(AgentMobileProjectNativeTools.INSPECT, "inspect-1")
        val branch = toolAction(
            AgentMobileProjectNativeTools.CHECKOUT_BRANCH,
            "branch",
            input = """{"workspace_id":"current","branch":"feature/test","create":true}"""
        )

        assertNull(
            AgentSupervisedProjectProgressPolicy.violation(
                inspect.copy(id = "inspect-2", status = AgentActionStatus.PENDING_CONFIRMATION),
                listOf(inspect, branch)
            )
        )
    }

    @Test
    fun `read only runtime inspection does not justify another baseline pull`() {
        val pull = toolAction(AgentMobileProjectNativeTools.PULL, "pull-1")
        val shellInspect = toolAction(
            AgentOnDeviceRuntimeTools.EXECUTE,
            "inspect-files",
            input = """{"workspace_id":"current","language":"shell","source":"ls -la"}"""
        )

        val violation = AgentSupervisedProjectProgressPolicy.violation(
            pull.copy(id = "pull-2", status = AgentActionStatus.PENDING_CONFIRMATION),
            listOf(pull, shellInspect)
        )

        assertTrue(violation.orEmpty().contains("baseline was already synchronized"))
    }

    @Test
    fun `clone cannot replay after it completed`() {
        val clone = toolAction(AgentMobileProjectNativeTools.CLONE, "clone-1")

        val violation = AgentSupervisedProjectProgressPolicy.violation(
            clone.copy(id = "clone-2", status = AgentActionStatus.PENDING_CONFIRMATION),
            listOf(clone, toolAction(AgentMobileProjectNativeTools.PULL, "pull"))
        )

        assertTrue(violation.orEmpty().contains("clone already completed"))
    }

    @Test
    fun `prompt ledger exposes tool ids and bounded observations`() {
        val block = AgentSupervisedProjectProgressPolicy.promptBlock(
            listOf(
                toolAction(AgentMobileProjectNativeTools.PULL, "pull").copy(
                    result = "head_commit=abc123 merge_status=updated"
                )
            )
        ).orEmpty()

        assertTrue(block.contains("tool=${AgentMobileProjectNativeTools.PULL}"))
        assertTrue(block.contains("head_commit=abc123"))
        assertTrue(block.contains("Do not replay a successful action"))
    }

    @Test
    fun `prompt lifecycle does not mistake a clean feature branch for committed work`() {
        val block = AgentSupervisedProjectProgressPolicy.promptBlock(
            listOf(
                toolAction(AgentMobileProjectNativeTools.PULL, "pull"),
                toolAction(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, "branch")
            )
        ).orEmpty()

        assertTrue(block.contains("dedicated_branch=true"))
        assertTrue(block.contains("source_mutation=false"))
        assertTrue(block.contains("commit=false"))
        assertTrue(block.contains("A clean branch created at the baseline contains no implemented change"))
    }

    @Test
    fun `successful fetch publishes the canonical partial repository recovery base`() {
        val block = AgentSupervisedProjectProgressPolicy.promptBlock(
            listOf(
                partialInspect(),
                toolAction(
                    AgentMobileProjectNativeTools.FETCH,
                    "fetch",
                    input = """{"workspace_id":"current","remote":"origin","ref":"main"}"""
                ).copy(evidence = """{"remote_refs":[]}""")
            )
        ).orEmpty()

        assertTrue(block.contains("fetched_base_ref=refs/remotes/origin/main"))
        assertTrue(block.contains("next_required=branch_checkout_from_fetched_base"))
        assertTrue(block.contains("Do not clone the repository"))
    }

    @Test
    fun `rejects clone after partial repository fetch even when tool output omitted refs`() {
        val history = listOf(
            partialInspect(),
            toolAction(
                AgentMobileProjectNativeTools.FETCH,
                "fetch",
                input = """{"workspace_id":"current","remote":"origin","ref":"main"}"""
            ).copy(evidence = """{"remote_refs":[]}""")
        )

        val violation = AgentSupervisedProjectProgressPolicy.violation(
            toolAction(AgentMobileProjectNativeTools.CLONE, "clone")
                .copy(status = AgentActionStatus.PENDING_CONFIRMATION),
            history
        )

        assertTrue(violation.orEmpty().contains("successful fetch receipt"))
        assertTrue(violation.orEmpty().contains("refs/remotes/origin/main"))
    }

    @Test
    fun `partial repository recovery requires checkout from fetched base`() {
        val history = listOf(
            partialInspect(),
            toolAction(
                AgentMobileProjectNativeTools.FETCH,
                "fetch",
                input = """{"workspace_id":"current","remote":"origin","ref":"main"}"""
            )
        )
        val invalidCheckout = toolAction(
            AgentMobileProjectNativeTools.CHECKOUT_BRANCH,
            "branch",
            input = """{"workspace_id":"current","branch":"feature/test","create":true}"""
        ).copy(status = AgentActionStatus.PENDING_CONFIRMATION)

        val violation = AgentSupervisedProjectProgressPolicy.violation(invalidCheckout, history)

        assertTrue(violation.orEmpty().contains("base_ref=refs/remotes/origin/main"))
    }

    @Test
    fun `read only inspect after fetch does not erase recovery receipt`() {
        val history = listOf(
            partialInspect(),
            toolAction(
                AgentMobileProjectNativeTools.FETCH,
                "fetch",
                input = """{"workspace_id":"current","remote":"origin","ref":"main"}"""
            ),
            partialInspect().copy(id = "inspect-after-fetch")
        )

        val violation = AgentSupervisedProjectProgressPolicy.violation(
            partialInspect().copy(id = "inspect-again", status = AgentActionStatus.PENDING_CONFIRMATION),
            history
        )

        assertTrue(violation.orEmpty().contains("Repeating inspection cannot create HEAD"))
        assertTrue(violation.orEmpty().contains("refs/remotes/origin/main"))
    }

    @Test
    fun `stale clone plan is canonicalized to fetched branch checkout`() {
        val history = listOf(
            partialInspect(),
            toolAction(
                AgentMobileProjectNativeTools.FETCH,
                "fetch",
                input = """{"workspace_id":"current","remote":"origin","ref":"main"}"""
            )
        )
        val clone = toolAction(
            AgentMobileProjectNativeTools.CLONE,
            "clone-signalasi",
            input = """{"workspace_id":"current","repository_url":"https://github.com/signalasi/SignalASI.git","branch":"main"}"""
        ).copy(status = AgentActionStatus.PENDING_CONFIRMATION)

        val canonical = AgentSupervisedProjectProgressPolicy.canonicalize(clone, history)
        val input = JSONObject(canonical.parameters.getValue("input_json"))

        assertTrue(canonical.target == AgentMobileProjectNativeTools.CHECKOUT_BRANCH)
        assertTrue(canonical.parameters["tool_id"] == AgentMobileProjectNativeTools.CHECKOUT_BRANCH)
        assertTrue(input.optBoolean("create"))
        assertTrue(input.optString("base_ref") == "refs/remotes/origin/main")
        assertTrue(input.optString("branch").startsWith("signalasi/phone-"))
    }

    @Test
    fun `checkout plan with stale base is repaired without changing its feature branch`() {
        val history = listOf(
            partialInspect(),
            toolAction(
                AgentMobileProjectNativeTools.FETCH,
                "fetch",
                input = """{"workspace_id":"current","remote":"origin","ref":"main"}"""
            )
        )
        val checkout = toolAction(
            AgentMobileProjectNativeTools.CHECKOUT_BRANCH,
            "checkout",
            input = """{"workspace_id":"current","branch":"feature/context","create":false,"base_ref":"main"}"""
        ).copy(status = AgentActionStatus.PENDING_CONFIRMATION)

        val canonical = AgentSupervisedProjectProgressPolicy.canonicalize(checkout, history)
        val input = JSONObject(canonical.parameters.getValue("input_json"))

        assertTrue(input.optString("branch") == "feature/context")
        assertTrue(input.optBoolean("create"))
        assertTrue(input.optString("base_ref") == "refs/remotes/origin/main")
    }

    @Test
    fun `rejects push before a verified mutation and commit`() {
        val history = listOf(
            toolAction(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, "branch"),
            toolAction(AgentMobileProjectNativeTools.INSPECT, "inspect")
        )

        val violation = AgentSupervisedProjectProgressPolicy.violation(
            toolAction(AgentMobileProjectNativeTools.PUSH, "push")
                .copy(status = AgentActionStatus.PENDING_CONFIRMATION),
            history
        )

        assertTrue(violation.orEmpty().contains("no successful commit"))
    }

    @Test
    fun `allows pull request after process restore when durable publication evidence is valid`() {
        val pullRequest = toolAction(
            AgentMobileProjectNativeTools.CREATE_PULL_REQUEST,
            "pull-request",
            input = """{"workspace_id":"current","base":"main","head":"feature/test"}"""
        ).copy(status = AgentActionStatus.PENDING_CONFIRMATION)

        assertNull(
            AgentSupervisedProjectProgressPolicy.violation(
                pullRequest,
                history = emptyList(),
                durablePullRequestEvidence = true
            )
        )
    }

    @Test
    fun `still rejects pull request without current or durable publication evidence`() {
        val pullRequest = toolAction(
            AgentMobileProjectNativeTools.CREATE_PULL_REQUEST,
            "pull-request",
            input = """{"workspace_id":"current","base":"main","head":"feature/test"}"""
        ).copy(status = AgentActionStatus.PENDING_CONFIRMATION)

        assertTrue(
            AgentSupervisedProjectProgressPolicy.violation(
                pullRequest,
                history = emptyList(),
                durablePullRequestEvidence = false
            ).orEmpty().contains("no verified dedicated feature branch")
        )
    }

    @Test
    fun `rejects commit before a verified mutation`() {
        val violation = AgentSupervisedProjectProgressPolicy.violation(
            toolAction(AgentMobileProjectNativeTools.COMMIT, "commit")
                .copy(status = AgentActionStatus.PENDING_CONFIRMATION),
            listOf(toolAction(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, "branch"))
        )

        assertTrue(violation.orEmpty().contains("no verified source or documentation mutation"))
    }

    @Test
    fun `allows commit when restored diff evidence proves a working tree mutation`() {
        val history = listOf(
            toolAction(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, "branch"),
            toolAction(AgentMobileProjectNativeTools.DIFF, "diff").copy(
                result = "Repository diff captured",
                evidence = """{"diff":"diff --git a/tools/dev/check-repo.js b/tools/dev/check-repo.js\n+const limit = 10;"}"""
            )
        )

        val violation = AgentSupervisedProjectProgressPolicy.violation(
            toolAction(AgentMobileProjectNativeTools.COMMIT, "commit")
                .copy(status = AgentActionStatus.PENDING_CONFIRMATION),
            history
        )

        assertNull(violation)
    }

    @Test
    fun `allows commit after a verified phone linux source mutation`() {
        val history = listOf(
            toolAction(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, "branch"),
            toolAction(
                AgentOnDeviceRuntimeTools.EXECUTE,
                "edit",
                shell("node -e 'writeFileSync(\"README.md\", \"updated\")'")
            )
        )

        val violation = AgentSupervisedProjectProgressPolicy.violation(
            toolAction(AgentMobileProjectNativeTools.COMMIT, "commit")
                .copy(status = AgentActionStatus.PENDING_CONFIRMATION),
            history
        )

        assertNull(violation)
    }

    @Test
    fun `does not treat a phone linux test command as a source mutation`() {
        val history = listOf(
            toolAction(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, "branch"),
            toolAction(
                AgentOnDeviceRuntimeTools.EXECUTE,
                "test",
                shell("node --test tools/dev/android-elf-page-normalizer.test.mjs")
            )
        )

        val violation = AgentSupervisedProjectProgressPolicy.violation(
            toolAction(AgentMobileProjectNativeTools.COMMIT, "commit")
                .copy(status = AgentActionStatus.PENDING_CONFIRMATION),
            history
        )

        assertTrue(violation.orEmpty().contains("no verified source or documentation mutation"))
    }

    @Test
    fun `rejects prolonged read only discovery after branch checkout`() {
        val branch = toolAction(
            AgentMobileProjectNativeTools.CHECKOUT_BRANCH,
            "branch",
            input = """{"workspace_id":"current","branch":"feature/test","create":true}"""
        )
        val history = listOf(
            branch,
            toolAction(AgentOnDeviceRuntimeTools.EXECUTE, "list-1", shell("ls -la")),
            toolAction(AgentMobileProjectNativeTools.INSPECT, "inspect-1"),
            toolAction(AgentOnDeviceRuntimeTools.EXECUTE, "list-2", shell("find . -maxdepth 2 -type f")),
            toolAction(AgentMobileProjectNativeTools.INSPECT, "inspect-2")
        )

        val violation = AgentSupervisedProjectProgressPolicy.violation(
            toolAction(AgentPhoneNativeToolCatalog.WORKSPACE_LIST, "list-3")
                .copy(status = AgentActionStatus.PENDING_CONFIRMATION),
            history
        )

        assertTrue(violation.orEmpty().contains("read-only discovery actions"))
    }

    @Test
    fun `rejects prolonged discovery after process restore observes a dedicated branch`() {
        val restoredBranch = toolAction(AgentMobileProjectNativeTools.INSPECT, "restored-branch").copy(
            result = """{"repository_state":"ready","branch":"signalasi/phone-safe-improvement","clean":true}"""
        )
        val history = listOf(
            restoredBranch,
            toolAction(AgentPhoneNativeToolCatalog.WORKSPACE_LIST, "list-1"),
            toolAction(AgentMobileProjectNativeTools.DIFF, "diff-1"),
            toolAction(AgentMobileProjectNativeTools.INSPECT, "inspect-2"),
            toolAction(AgentPhoneNativeToolCatalog.WORKSPACE_STAT, "stat-1")
        )

        val violation = AgentSupervisedProjectProgressPolicy.violation(
            toolAction(AgentPhoneNativeToolCatalog.WORKSPACE_LIST, "list-2")
                .copy(status = AgentActionStatus.PENDING_CONFIRMATION),
            history
        )

        assertTrue(violation.orEmpty().contains("read-only discovery actions"))
    }

    @Test
    fun `allows concrete edit after prolonged discovery`() {
        val history = listOf(
            toolAction(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, "branch"),
            toolAction(AgentMobileProjectNativeTools.INSPECT, "inspect-1"),
            toolAction(AgentOnDeviceRuntimeTools.EXECUTE, "list-1", shell("ls -la")),
            toolAction(AgentMobileProjectNativeTools.INSPECT, "inspect-2"),
            toolAction(AgentOnDeviceRuntimeTools.EXECUTE, "list-2", shell("find . -maxdepth 2 -type f"))
        )
        val edit = toolAction(
            AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH,
            "edit",
            input = """{"workspace_id":"current","path":"README.md","expected_text":"old","replacement_text":"new"}"""
        ).copy(status = AgentActionStatus.PENDING_CONFIRMATION)

        assertNull(AgentSupervisedProjectProgressPolicy.violation(edit, history))
    }

    private fun shell(source: String): String =
        JSONObject(mapOf("workspace_id" to "current", "language" to "shell", "source" to source)).toString()

    private fun partialInspect(): AgentAction = toolAction(
        AgentMobileProjectNativeTools.INSPECT,
        "inspect"
    ).copy(
        evidence = """{"repository_state":"partial","repository_url":"https://github.com/signalasi/SignalASI.git","head_present":false}"""
    )

    private fun toolAction(
        toolId: String,
        id: String,
        input: String = """{"workspace_id":"current"}"""
    ): AgentAction = AgentAction(
        id = id,
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = toolId,
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = toolId,
        parameters = mapOf("tool_id" to toolId, "input_json" to input),
        requiresConfirmation = false
    )
}
