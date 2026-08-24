package com.signalasi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
    fun `initial working set delays publication without hiding preparation or runtime tools`() {
        val blocked = AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(emptyList())

        assertTrue(AgentMobileProjectNativeTools.COMMIT in blocked)
        assertTrue(AgentMobileProjectNativeTools.PUSH in blocked)
        assertTrue(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST in blocked)
        assertFalse(AgentMobileProjectNativeTools.CLONE in blocked)
        assertFalse(AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT in blocked)
        assertFalse(AgentOnDeviceRuntimeTools.EXECUTE in blocked)
    }

    @Test
    fun `atomic preparation focuses the next turn while retaining source and runtime capabilities`() {
        val blocked = AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(
            listOf(atomicPreparedClone())
        )

        assertTrue(AgentMobileProjectNativeTools.CLONE in blocked)
        assertTrue(AgentMobileProjectNativeTools.INSPECT in blocked)
        assertTrue(AgentMobileProjectNativeTools.FETCH in blocked)
        assertTrue(AgentMobileProjectNativeTools.PULL in blocked)
        assertTrue(AgentMobileProjectNativeTools.CHECKOUT_BRANCH in blocked)
        assertTrue(AgentMobileProjectNativeTools.COMMIT in blocked)
        assertFalse(AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT in blocked)
        assertFalse(AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH in blocked)
        assertFalse(AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH_BATCH in blocked)
        assertFalse(AgentOnDeviceRuntimeTools.EXECUTE in blocked)
    }

    @Test
    fun `publication tools reappear only when verified lifecycle evidence permits them`() {
        val branch = atomicPreparedClone()
        val mutation = toolAction(
            AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
            "edit",
            input = """{"workspace_id":"current","path":"README.md","text":"updated"}"""
        )
        val afterMutation = AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(
            listOf(branch, mutation)
        )
        assertTrue(AgentMobileProjectNativeTools.COMMIT in afterMutation)
        assertTrue(AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST in afterMutation)
        assertTrue(AgentMobileProjectNativeTools.PUSH in afterMutation)
        assertTrue(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST in afterMutation)

        val verification = toolAction(
            AgentOnDeviceRuntimeTools.EXECUTE,
            "test",
            input = shell("./gradlew test", verificationKind = "test")
        )
        val afterVerification = AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(
            listOf(branch, mutation, verification)
        )
        assertFalse(AgentMobileProjectNativeTools.COMMIT in afterVerification)
        assertFalse(AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST in afterVerification)
        assertTrue(AgentMobileProjectNativeTools.PUSH in afterVerification)
        assertTrue(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST in afterVerification)

        val commit = toolAction(AgentMobileProjectNativeTools.COMMIT, "commit")
        val afterCommit = AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(
            listOf(branch, mutation, verification, commit)
        )
        assertTrue(AgentMobileProjectNativeTools.COMMIT in afterCommit)
        assertTrue(AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST in afterCommit)
        assertFalse(AgentMobileProjectNativeTools.PUSH in afterCommit)
        assertFalse(AgentMobileProjectNativeTools.PUBLISH_PULL_REQUEST in afterCommit)
        assertTrue(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST in afterCommit)

        val push = toolAction(AgentMobileProjectNativeTools.PUSH, "push")
        val afterPush = AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(
            listOf(branch, mutation, verification, commit, push)
        )
        assertTrue(AgentMobileProjectNativeTools.PUSH in afterPush)
        assertFalse(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST in afterPush)
    }

    @Test
    fun `atomic finalization closes commit push and pull request phases together`() {
        val branch = atomicPreparedClone()
        val mutation = toolAction(
            AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
            "edit",
            input = """{"workspace_id":"current","path":"README.md","text":"updated"}"""
        )
        val finalize = toolAction(
            AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST,
            "finalize"
        )
        val verification = toolAction(
            AgentOnDeviceRuntimeTools.EXECUTE,
            "test",
            input = shell("./gradlew test", verificationKind = "test")
        )

        assertTrue(
            AgentSupervisedProjectProgressPolicy.violation(
                finalize.copy(status = AgentActionStatus.PENDING_CONFIRMATION),
                listOf(branch, mutation)
            ).orEmpty().contains("no successful verification")
        )
        assertNull(
            AgentSupervisedProjectProgressPolicy.violation(
                finalize.copy(status = AgentActionStatus.PENDING_CONFIRMATION),
                listOf(branch, mutation, verification)
            )
        )
        val blocked = AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(
            listOf(branch, mutation, verification, finalize)
        )
        assertTrue(AgentMobileProjectNativeTools.COMMIT in blocked)
        assertTrue(AgentMobileProjectNativeTools.PUSH in blocked)
        assertTrue(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST in blocked)
        assertTrue(AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST in blocked)
    }

    @Test
    fun `final code diff after successful verification does not invalidate it`() {
        val branch = atomicPreparedClone()
        val mutation = toolAction(
            AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
            "edit",
            input = """{"workspace_id":"current","path":"src/main.kt","text":"updated"}"""
        )
        val verification = toolAction(
            AgentOnDeviceRuntimeTools.EXECUTE,
            "test",
            input = shell("./gradlew test", verificationKind = "test")
        )
        val finalDiff = toolAction(AgentMobileProjectNativeTools.DIFF, "diff").copy(
            evidence = """{"diff":"diff --git a/src/main.kt b/src/main.kt\n+++ b/src/main.kt\n+updated"}"""
        )

        val blocked = AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(
            listOf(branch, mutation, verification, finalDiff)
        )

        assertFalse(AgentMobileProjectNativeTools.COMMIT in blocked)
        assertFalse(AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST in blocked)
    }

    @Test
    fun `source edit after successful verification requires another verification`() {
        val branch = atomicPreparedClone()
        val firstMutation = toolAction(
            AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
            "edit-1",
            input = """{"workspace_id":"current","path":"src/main.kt","text":"first"}"""
        )
        val verification = toolAction(
            AgentOnDeviceRuntimeTools.EXECUTE,
            "test",
            input = shell("./gradlew test", verificationKind = "test")
        )
        val secondMutation = toolAction(
            AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
            "edit-2",
            input = """{"workspace_id":"current","path":"src/main.kt","text":"second"}"""
        )

        val blocked = AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(
            listOf(branch, firstMutation, verification, secondMutation)
        )

        assertTrue(AgentMobileProjectNativeTools.COMMIT in blocked)
        assertTrue(AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST in blocked)
    }

    @Test
    fun `failed tools remain visible for a corrected model retry`() {
        val failedClone = toolAction(AgentMobileProjectNativeTools.CLONE, "clone-failed")
            .copy(status = AgentActionStatus.FAILED, result = "Network unavailable")

        val blocked = AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(
            listOf(failedClone)
        )

        assertFalse(AgentMobileProjectNativeTools.CLONE in blocked)
    }

    @Test
    fun `detailed working set keeps common phone development schemas precise`() {
        val detailed = AgentSupervisedProjectProgressPolicy.detailedToolIds(emptyList())

        assertTrue(AgentMobileProjectNativeTools.CLONE in detailed)
        assertTrue(AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT_BATCH in detailed)
        assertTrue(AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH_BATCH in detailed)
        assertTrue(AgentOnDeviceRuntimeTools.EXECUTE in detailed)
        assertFalse(AgentLinuxSoftwareNativeTools.REMOVE in detailed)
    }

    @Test
    fun `failed runtime expands dependency recovery schemas`() {
        val failedRuntime = toolAction(AgentOnDeviceRuntimeTools.EXECUTE, "runtime-failed")
            .copy(
                status = AgentActionStatus.FAILED,
                evidence = """{"failure_diagnosis":{"kind":"missing_executable","missing_executables":["java"],"recovery_candidates":[{"search_software":{"tool_id":"${AgentLinuxSoftwareNativeTools.SEARCH}"}}]}}"""
            )

        val detailed = AgentSupervisedProjectProgressPolicy.detailedToolIds(listOf(failedRuntime))

        assertTrue(AgentLinuxSoftwareNativeTools.SEARCH in detailed)
        assertTrue(AgentLinuxSoftwareNativeTools.INSPECT in detailed)
        assertTrue(AgentLinuxSoftwareNativeTools.INSTALL in detailed)
        assertFalse(AgentLinuxSoftwareNativeTools.REMOVE in detailed)
        assertFalse(AgentOnDeviceRuntimeTools.WORKSPACE_ROLLBACK in detailed)
    }

    @Test
    fun `ordinary runtime failure does not expose dependency installation schemas`() {
        val failedRuntime = toolAction(AgentOnDeviceRuntimeTools.EXECUTE, "runtime-failed")
            .copy(status = AgentActionStatus.FAILED, result = "Tests failed")

        val detailed = AgentSupervisedProjectProgressPolicy.detailedToolIds(listOf(failedRuntime))

        assertTrue(AgentOnDeviceRuntimeTools.EXECUTE in detailed)
        assertFalse(AgentOnDeviceRuntimeTools.INSTALL_PACK in detailed)
        assertFalse(AgentLinuxSoftwareNativeTools.SEARCH in detailed)
        assertFalse(AgentLinuxSoftwareNativeTools.INSTALL in detailed)
    }

    @Test
    fun `successful runtime collapses resolved dependency recovery schemas`() {
        val failedRuntime = toolAction(AgentOnDeviceRuntimeTools.EXECUTE, "runtime-failed")
            .copy(
                status = AgentActionStatus.FAILED,
                evidence = """{"failure_diagnosis":{"kind":"missing_executable","missing_executables":["java"],"recovery_candidates":[{"search_software":{"tool_id":"${AgentLinuxSoftwareNativeTools.SEARCH}"}}]}}"""
            )
        val successfulRuntime = toolAction(AgentOnDeviceRuntimeTools.EXECUTE, "runtime-recovered")

        val detailed = AgentSupervisedProjectProgressPolicy.detailedToolIds(
            listOf(failedRuntime, successfulRuntime)
        )

        assertFalse(AgentOnDeviceRuntimeTools.INSTALL_PACK in detailed)
        assertFalse(AgentLinuxSoftwareNativeTools.INSTALL in detailed)
    }

    @Test
    fun `verification and commit expand publication schemas by phase`() {
        val branch = atomicPreparedClone()
        val mutation = toolAction(
            AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH_BATCH,
            "edit",
            input = """{"workspace_id":"current","patches":[]}"""
        )
        val afterMutation = AgentSupervisedProjectProgressPolicy.detailedToolIds(listOf(branch, mutation))
        assertFalse(AgentMobileProjectNativeTools.COMMIT in afterMutation)
        assertFalse(AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST in afterMutation)
        assertFalse(AgentMobileProjectNativeTools.PUSH in afterMutation)

        val verification = toolAction(
            AgentOnDeviceRuntimeTools.EXECUTE,
            "test",
            input = shell("./gradlew test", verificationKind = "test")
        )
        val afterVerification = AgentSupervisedProjectProgressPolicy.detailedToolIds(
            listOf(branch, mutation, verification)
        )
        assertTrue(AgentMobileProjectNativeTools.COMMIT in afterVerification)
        assertTrue(AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST in afterVerification)
        assertFalse(AgentMobileProjectNativeTools.PUSH in afterVerification)

        val commit = toolAction(AgentMobileProjectNativeTools.COMMIT, "commit")
        val afterCommit = AgentSupervisedProjectProgressPolicy.detailedToolIds(
            listOf(branch, mutation, verification, commit)
        )
        assertTrue(AgentMobileProjectNativeTools.PUSH in afterCommit)
        assertTrue(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST in afterCommit)
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
    fun `prompt ledger collapses consecutive equivalent observations`() {
        val toolId = AgentMobileProjectNativeTools.FETCH
        val repeated = (1..3).map { index ->
            toolAction(toolId, "fetch-$index")
                .copy(status = AgentActionStatus.FAILED, result = "Network unavailable")
        }

        val block = AgentSupervisedProjectProgressPolicy.promptBlock(repeated).orEmpty()

        assertEquals(1, block.split("tool=$toolId").size - 1)
        assertTrue(block.contains("repeat_count=3"))
        assertTrue(block.contains("Network unavailable"))
    }

    @Test
    fun `prompt ledger projects the latest nonconsecutive state`() {
        val toolId = AgentMobileProjectNativeTools.FETCH
        val first = toolAction(toolId, "fetch-1")
            .copy(status = AgentActionStatus.FAILED, result = "Network unavailable")
        val changed = first.copy(id = "fetch-2", result = "Authentication failed")
        val inspection = toolAction(AgentMobileProjectNativeTools.INSPECT, "inspect")
        val repeatedLater = first.copy(id = "fetch-3")

        val block = AgentSupervisedProjectProgressPolicy.promptBlock(
            listOf(first, changed, inspection, repeatedLater)
        ).orEmpty()

        assertEquals(1, block.split("tool=$toolId").size - 1)
        assertTrue(block.contains("Network unavailable"))
        assertFalse(block.contains("Authentication failed"))
        assertTrue(block.contains("repeat_count=2"))
        assertTrue(block.contains("Superseded observations and resolved failures are omitted"))
    }

    @Test
    fun `successful retry removes its resolved failure from model context`() {
        val toolId = AgentMobileProjectNativeTools.INSPECT
        val input = """{"workspace_id":"current","path":"README.md"}"""
        val failed = toolAction(toolId, "inspect-failed", input)
            .copy(status = AgentActionStatus.FAILED, result = "File temporarily unavailable")
        val recovered = toolAction(toolId, "inspect-recovered", input)
            .copy(result = "README contents loaded")

        val block = AgentSupervisedProjectProgressPolicy.promptBlock(
            listOf(failed, recovered)
        ).orEmpty()

        assertEquals(1, block.split("tool=$toolId").size - 1)
        assertFalse(block.contains("File temporarily unavailable"))
        assertTrue(block.contains("README contents loaded"))
    }

    @Test
    fun `latest failure keeps the last successful lifecycle evidence`() {
        val toolId = AgentMobileProjectNativeTools.FETCH
        val input = """{"workspace_id":"current","remote":"origin","ref":"main"}"""
        val fetched = toolAction(toolId, "fetch-complete", input)
            .copy(result = "Fetched origin main at abc123")
        val laterFailure = toolAction(toolId, "fetch-failed", input)
            .copy(status = AgentActionStatus.FAILED, result = "Network unavailable")

        val block = AgentSupervisedProjectProgressPolicy.promptBlock(
            listOf(fetched, laterFailure)
        ).orEmpty()

        assertEquals(2, block.split("tool=$toolId").size - 1)
        assertTrue(block.contains("Fetched origin main at abc123"))
        assertTrue(block.contains("Network unavailable"))
    }

    @Test
    fun `current state projection removes stale repeated reads without a fixed action window`() {
        val observations = (1..40).map { index ->
            val slot = index % 4
            toolAction(
                AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
                "read-$index",
                input = """{"workspace_id":"current","path":"module-$slot.kt"}"""
            ).copy(result = "module-$slot revision-$index")
        }

        val block = AgentSupervisedProjectProgressPolicy.promptBlock(observations).orEmpty()

        assertEquals(
            4,
            block.split("tool=${AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT}").size - 1
        )
        assertFalse(block.contains("revision-1"))
        assertTrue(block.contains("revision-37"))
        assertTrue(block.contains("revision-40"))
        assertTrue(block.length < 4_000)
    }

    @Test
    fun `prompt ledger keeps more than eight short observations when they fit the context budget`() {
        val observations = (1..10).map { index ->
            toolAction(
                AgentMobileProjectNativeTools.INSPECT,
                "inspect-$index",
                input = """{"workspace_id":"current","path":"module-$index"}"""
            ).copy(result = "inspection-$index")
        }

        val block = AgentSupervisedProjectProgressPolicy.promptBlock(observations).orEmpty()

        assertEquals(
            10,
            block.split("tool=${AgentMobileProjectNativeTools.INSPECT}").size - 1
        )
        assertTrue(block.contains("inspection-1"))
        assertTrue(block.contains("inspection-10"))
    }

    @Test
    fun `long project ledger retains lifecycle milestones failures and newest observation`() {
        val branch = toolAction(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, "branch")
            .copy(result = "milestone-dedicated-branch")
        val mutation = toolAction(
            AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
            "edit",
            input = """{"workspace_id":"current","path":"README.md","text":"updated"}"""
        ).copy(result = "milestone-source-mutation")
        val verification = toolAction(
            AgentOnDeviceRuntimeTools.EXECUTE,
            "test",
            input = shell("./gradlew test", verificationKind = "test")
        ).copy(result = "milestone-runtime-verification")
        val failure = toolAction(AgentMobileProjectNativeTools.FETCH, "failed-fetch")
            .copy(status = AgentActionStatus.FAILED, result = "important-network-failure")
        val laterObservations = (1..24).map { index ->
            toolAction(
                AgentMobileProjectNativeTools.INSPECT,
                "inspect-$index",
                input = """{"workspace_id":"current","path":"large-module-$index"}"""
            ).copy(result = "recent-inspection-$index:" + "x".repeat(580))
        }

        val block = AgentSupervisedProjectProgressPolicy.promptBlock(
            listOf(branch, mutation, verification, failure) + laterObservations
        ).orEmpty()

        assertTrue(block.contains("milestone-dedicated-branch"))
        assertTrue(block.contains("milestone-source-mutation"))
        assertTrue(block.contains("milestone-runtime-verification"))
        assertTrue(block.contains("important-network-failure"))
        assertTrue(block.contains("recent-inspection-24"))
        assertTrue(
            block.split("tool=${AgentMobileProjectNativeTools.INSPECT}").size - 1 < laterObservations.size
        )
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
    fun `prompt lifecycle keeps older branch state outside the visible ledger window`() {
        val branch = toolAction(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, "branch")
        val laterInspections = (1..12).map { index ->
            toolAction(AgentMobileProjectNativeTools.INSPECT, "inspect-$index")
        }

        val block = AgentSupervisedProjectProgressPolicy.promptBlock(listOf(branch) + laterInspections).orEmpty()

        assertTrue(block.contains("dedicated_branch=true"))
        assertTrue(block.contains("source_mutation=false"))
    }

    @Test
    fun `atomic repository preparation establishes the dedicated branch lifecycle`() {
        val block = AgentSupervisedProjectProgressPolicy.promptBlock(
            listOf(atomicPreparedClone())
        ).orEmpty()

        assertTrue(block.contains("dedicated_branch=true"))
        assertTrue(block.contains("source_mutation=false"))
    }

    @Test
    fun `atomic repository preparation rejects immediate redundant repository probes`() {
        val history = listOf(atomicPreparedClone())

        listOf(
            AgentMobileProjectNativeTools.INSPECT,
            AgentMobileProjectNativeTools.FETCH,
            AgentMobileProjectNativeTools.PULL,
            AgentMobileProjectNativeTools.CHECKOUT_BRANCH
        ).forEach { toolId ->
            val violation = AgentSupervisedProjectProgressPolicy.violation(
                toolAction(toolId, "redundant-$toolId")
                    .copy(status = AgentActionStatus.PENDING_CONFIRMATION),
                history
            )

            assertTrue(violation.orEmpty().contains("atomic repository preparation"))
            assertTrue(violation.orEmpty().contains(toolId))
        }
    }

    @Test
    fun `atomic repository preparation still allows focused source inspection`() {
        val read = toolAction(
            AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
            "read-manifest",
            input = """{"workspace_id":"current","path":"README.md"}"""
        ).copy(status = AgentActionStatus.PENDING_CONFIRMATION)

        assertNull(
            AgentSupervisedProjectProgressPolicy.violation(read, listOf(atomicPreparedClone()))
        )
    }

    @Test
    fun `atomic pull request publication completes push and pull request lifecycle`() {
        val history = listOf(
            atomicPreparedClone(),
            toolAction(
                AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
                "edit",
                input = """{"workspace_id":"current","path":"README.md","text":"updated"}"""
            ),
            toolAction(AgentMobileProjectNativeTools.COMMIT, "commit"),
            toolAction(AgentMobileProjectNativeTools.PUBLISH_PULL_REQUEST, "publish").copy(
                evidence = """{"branch":"improve/phone-agent","pull_request_url":"https://github.com/signalasi/SignalASI/pull/1"}"""
            )
        )

        val block = AgentSupervisedProjectProgressPolicy.promptBlock(history).orEmpty()

        assertTrue(block.contains("commit=true"))
        assertTrue(block.contains("push=true"))
        assertTrue(block.contains("pull_request=true"))
    }

    @Test
    fun `atomic pull request publication requires a verified commit`() {
        val publish = toolAction(AgentMobileProjectNativeTools.PUBLISH_PULL_REQUEST, "publish")
            .copy(status = AgentActionStatus.PENDING_CONFIRMATION)

        val violation = AgentSupervisedProjectProgressPolicy.violation(
            publish,
            listOf(
                atomicPreparedClone(),
                toolAction(
                    AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
                    "edit",
                    input = """{"workspace_id":"current","path":"README.md","text":"updated"}"""
                )
            )
        )

        assertTrue(violation.orEmpty().contains("no successful commit"))
    }

    @Test
    fun `atomic pull request publication is allowed after mutation and commit`() {
        val history = listOf(
            atomicPreparedClone(),
            toolAction(
                AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
                "edit",
                input = """{"workspace_id":"current","path":"README.md","text":"updated"}"""
            ),
            toolAction(AgentMobileProjectNativeTools.COMMIT, "commit")
        )
        val publish = toolAction(AgentMobileProjectNativeTools.PUBLISH_PULL_REQUEST, "publish")
            .copy(status = AgentActionStatus.PENDING_CONFIRMATION)

        assertNull(AgentSupervisedProjectProgressPolicy.violation(publish, history))
    }

    @Test
    fun `clone without verified feature branch does not establish dedicated lifecycle`() {
        val clone = atomicPreparedClone().copy(
            evidence = """{"repository_state":"ready","branch":"main","head_commit":"abc123","clean":true}"""
        )

        val block = AgentSupervisedProjectProgressPolicy.promptBlock(listOf(clone)).orEmpty()

        assertTrue(block.contains("dedicated_branch=false"))
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
    fun `rejects commit when restored code diff has no verification`() {
        val history = listOf(
            toolAction(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, "branch"),
            toolAction(AgentMobileProjectNativeTools.DIFF, "diff").copy(
                result = "Repository diff captured",
                evidence = """{"diff":"diff --git a/tools/dev/check-repo.js b/tools/dev/check-repo.js\n+++ b/tools/dev/check-repo.js\n+const limit = 10;"}"""
            )
        )

        val violation = AgentSupervisedProjectProgressPolicy.violation(
            toolAction(AgentMobileProjectNativeTools.COMMIT, "commit")
                .copy(status = AgentActionStatus.PENDING_CONFIRMATION),
            history
        )

        assertTrue(violation.orEmpty().contains("no successful verification"))
    }

    @Test
    fun `allows complete documentation diff to verify documentation-only mutation`() {
        val history = listOf(
            toolAction(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, "branch"),
            toolAction(AgentMobileProjectNativeTools.DIFF, "diff").copy(
                evidence = """{"diff":"diff --git a/README.md b/README.md\n+++ b/README.md\n+Documented behavior."}"""
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
            ),
            toolAction(
                AgentOnDeviceRuntimeTools.EXECUTE,
                "test",
                shell("./gradlew test", verificationKind = "test")
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
    fun `does not treat a phone linux gradle build as a source mutation`() {
        val history = listOf(
            toolAction(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, "branch"),
            toolAction(
                AgentOnDeviceRuntimeTools.EXECUTE,
                "build",
                shell("./gradlew test", verificationKind = "test")
            )
        )

        val block = AgentSupervisedProjectProgressPolicy.promptBlock(history).orEmpty()

        assertTrue(block.contains("source_mutation=false"))
    }

    @Test
    fun `does not treat a phone linux package install as a source mutation`() {
        val history = listOf(
            toolAction(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, "branch"),
            toolAction(
                AgentOnDeviceRuntimeTools.EXECUTE,
                "install",
                shell("apt-get install -y unzip")
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
    fun `treats a phone linux file write as a source mutation`() {
        val history = listOf(
            toolAction(AgentMobileProjectNativeTools.CHECKOUT_BRANCH, "branch"),
            toolAction(
                AgentOnDeviceRuntimeTools.EXECUTE,
                "edit",
                shell("python -c \"from pathlib import Path; Path('README.md').write_text('updated')\"")
            )
        )

        val block = AgentSupervisedProjectProgressPolicy.promptBlock(history).orEmpty()

        assertTrue(block.contains("source_mutation=true"))
    }

    @Test
    fun `allows distinct read only discovery after branch checkout`() {
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

        assertNull(violation)
        assertFalse(
            AgentPhoneNativeToolCatalog.WORKSPACE_LIST in
                AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(history)
        )
        assertTrue(
            AgentSupervisedProjectProgressPolicy.promptBlock(history)
                .orEmpty()
                .contains("Further inspection remains available")
        )
    }

    @Test
    fun `allows distinct discovery after process restore observes a dedicated branch`() {
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

        assertNull(violation)
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

    @Test
    fun `atomic exact patch batch counts as one verified source mutation`() {
        val branch = atomicPreparedClone()
        val mutation = toolAction(
            AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH_BATCH,
            "batch-edit",
            input = """{"workspace_id":"current","patches":[{"path":"README.md","expected_text":"old","replacement_text":"new"}]}"""
        )

        val beforeVerification = AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(
            listOf(branch, mutation)
        )
        assertTrue(AgentMobileProjectNativeTools.COMMIT in beforeVerification)
        assertTrue(AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST in beforeVerification)

        val verification = toolAction(
            AgentOnDeviceRuntimeTools.EXECUTE,
            "test",
            input = shell("./gradlew test", verificationKind = "test")
        )
        val blocked = AgentSupervisedProjectProgressPolicy.temporarilyBlockedToolIds(
            listOf(branch, mutation, verification)
        )

        assertFalse(AgentMobileProjectNativeTools.COMMIT in blocked)
        assertFalse(AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST in blocked)
        assertTrue(AgentMobileProjectNativeTools.PUSH in blocked)
    }

    private fun shell(source: String, verificationKind: String = ""): String =
        JSONObject(
            mapOf(
                "workspace_id" to "current",
                "language" to "shell",
                "source" to source,
                "verification_kind" to verificationKind
            )
        ).toString()

    private fun partialInspect(): AgentAction = toolAction(
        AgentMobileProjectNativeTools.INSPECT,
        "inspect"
    ).copy(
        evidence = """{"repository_state":"partial","repository_url":"https://github.com/signalasi/SignalASI.git","head_present":false}"""
    )

    private fun atomicPreparedClone(): AgentAction = toolAction(
        AgentMobileProjectNativeTools.CLONE,
        "prepare",
        input = """{"workspace_id":"current","repository_url":"https://github.com/signalasi/SignalASI.git","branch":"main","feature_branch":"improve/phone-agent"}"""
    ).copy(
        evidence = """{"repository_state":"ready","repository_url":"https://github.com/signalasi/SignalASI.git","branch":"improve/phone-agent","head_commit":"abc123","clean":true}"""
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
