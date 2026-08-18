package com.signalasi.chat

import java.io.File
import java.nio.file.Files
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.storage.file.FileRepositoryBuilder
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class AgentMobileProjectToolsTest {
    private lateinit var root: File
    private lateinit var projects: File
    private lateinit var source: File
    private lateinit var remote: File
    private lateinit var repository: AgentMobileProjectRepository

    @Before
    fun setUp() {
        root = Files.createTempDirectory("signalasi-mobile-project-").toFile()
        projects = File(root, "projects")
        source = File(root, "source")
        remote = File(root, "remote.git")
        Git.init().setDirectory(source).setInitialBranch("main").call().use { git ->
            File(source, "README.md").writeText("# Fixture\n")
            git.add().addFilepattern(".").call()
            git.commit()
                .setMessage("Initial fixture")
                .setAuthor("SignalASI", "signalasi@hotmail.com")
                .setCommitter("SignalASI", "signalasi@hotmail.com")
                .call()
        }
        Git.cloneRepository()
            .setURI(source.toURI().toString())
            .setDirectory(remote)
            .setBare(true)
            .call()
            .close()
        repository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "local-test-token" },
            repositoryPolicy = { true },
            gitBackend = TestJGitBackend(projects)
        )
    }

    @After
    fun tearDown() {
        root.deleteRecursively()
    }

    @Test
    fun clonesInspectsDiffsBranchesCommitsAndPushesAProject() {
        val cloned = repository.clone(
            workspaceId = "conversation-project",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )

        assertEquals("main", cloned.branch)
        assertTrue(cloned.clean)
        assertTrue(File(projects, "conversation-project/README.md").isFile)

        val candidate = File(projects, "conversation-project/src/answer.kt")
        requireNotNull(candidate.parentFile).mkdirs()
        candidate.writeText("fun answer() = 42\n")
        val dirty = repository.inspect("conversation-project")
        assertFalse(dirty.clean)
        assertEquals(listOf("src/answer.kt"), dirty.untracked)

        repository.checkoutBranch("conversation-project", "feature/mobile-answer", create = true)
        val commit = repository.commit(
            workspaceId = "conversation-project",
            message = "Add mobile answer",
            authorName = "SignalASI",
            authorEmail = "signalasi@hotmail.com"
        )
        assertEquals("feature/mobile-answer", commit.branch)
        assertTrue("src/answer.kt" in commit.changedFiles)
        assertEquals(40, commit.commit.length)

        val pushed = repository.push(
            workspaceId = "conversation-project",
            remote = "origin",
            branch = "feature/mobile-answer",
            force = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE
        )
        assertEquals("feature/mobile-answer", pushed.branch)
        FileRepositoryBuilder().setGitDir(remote).setBare().build().use { bare ->
            assertEquals(commit.commit, bare.resolve("refs/heads/feature/mobile-answer")?.name)
        }
    }

    @Test
    fun cloneFailureDoesNotDestroyTheExistingPhoneProject() {
        val existing = File(projects, "safe-project").apply { mkdirs() }
        File(existing, "keep.txt").writeText("stable")

        val failed = runCatching {
            repository.clone(
                workspaceId = "safe-project",
                repositoryUrl = File(root, "missing.git").toURI().toString(),
                branch = "main",
                depth = 1,
                replaceExisting = true,
                cancellationToken = AgentNativeToolCancellationToken.NONE,
                progress = { _, _, _ -> }
            )
        }

        assertTrue(failed.isFailure)
        assertEquals("stable", File(existing, "keep.txt").readText())
    }

    @Test
    fun cloneWithoutBranchUsesTheRemoteDefaultBranch() {
        val trunkSource = File(root, "trunk-source")
        val trunkRemote = File(root, "trunk-remote.git")
        Git.init().setDirectory(trunkSource).setInitialBranch("trunk").call().use { git ->
            File(trunkSource, "README.md").writeText("# Trunk fixture\n")
            git.add().addFilepattern(".").call()
            git.commit()
                .setMessage("Initial trunk fixture")
                .setAuthor("SignalASI", "signalasi@hotmail.com")
                .setCommitter("SignalASI", "signalasi@hotmail.com")
                .call()
        }
        Git.cloneRepository()
            .setURI(trunkSource.toURI().toString())
            .setDirectory(trunkRemote)
            .setBare(true)
            .call()
            .close()

        val cloned = repository.clone(
            workspaceId = "default-branch-project",
            repositoryUrl = trunkRemote.toURI().toString(),
            branch = "",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )

        assertEquals("trunk", cloned.branch)
        assertTrue(cloned.clean)
    }

    @Test
    fun linuxCloneAllowsRuntimeManagedEntriesButRejectsProjectFiles() {
        val calls = mutableListOf<String>()
        val linuxRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "" },
            repositoryPolicy = { true },
            gitBackend = TestJGitBackend(projects) { workspaceId -> calls += workspaceId }
        )
        val managedWorkspace = File(projects, "managed-only").apply { mkdirs() }
        File(managedWorkspace, ".signalasi-tools/bin").mkdirs()
        File(managedWorkspace, ".signalasi-checkpoint.json").writeText("{}")

        linuxRepository.clone(
            workspaceId = "managed-only",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        assertEquals(listOf("managed-only"), calls)

        val occupiedWorkspace = File(projects, "occupied").apply { mkdirs() }
        File(occupiedWorkspace, ".signalasi-tools/bin").mkdirs()
        File(occupiedWorkspace, "user-notes.txt").writeText("keep")
        val failure = runCatching {
            linuxRepository.clone(
                workspaceId = "occupied",
                repositoryUrl = remote.toURI().toString(),
                branch = "main",
                depth = 1,
                replaceExisting = false,
                cancellationToken = AgentNativeToolCancellationToken.NONE,
                progress = { _, _, _ -> }
            )
        }

        assertTrue(failure.isFailure)
        assertTrue(failure.exceptionOrNull()?.message.orEmpty().contains("workspace is not empty"))
        assertEquals("keep", File(occupiedWorkspace, "user-notes.txt").readText())
    }

    @Test
    fun verifiedProjectMustRemainUnchangedThroughCommitPushAndPullRequest() {
        val tickets = mutableMapOf<String, AgentProjectVerificationTicket>()
        val guard = AgentProjectPublicationPolicy(
            projectRoot = projects,
            ticketStore = object : AgentProjectVerificationTicketStore {
                override fun read(workspaceId: String): AgentProjectVerificationTicket? = tickets[workspaceId]

                override fun write(ticket: AgentProjectVerificationTicket) {
                    tickets[ticket.workspaceId] = ticket
                }

                override fun remove(workspaceId: String) {
                    tickets.remove(workspaceId)
                }
            }
        )
        val guardedRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "local-test-token" },
            repositoryPolicy = { true },
            publicationGuard = guard,
            gitBackend = TestJGitBackend(projects)
        )
        guardedRepository.clone(
            workspaceId = "verified-project",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        guardedRepository.checkoutBranch("verified-project", "feature/verified", create = true)
        val candidate = File(projects, "verified-project/src/result.kt").apply {
            requireNotNull(parentFile).mkdirs()
            writeText("fun result() = 1\n")
        }

        assertTrue(runCatching {
            guardedRepository.commit("verified-project", "Unverified", "SignalASI", "signalasi@hotmail.com")
        }.isFailure)

        guard.recordVerification(successfulVerificationReceipt("verified-project", "verification-1"))
        candidate.writeText("fun result() = 2\n")
        assertTrue(runCatching {
            guardedRepository.commit("verified-project", "Stale verification", "SignalASI", "signalasi@hotmail.com")
        }.isFailure)

        guard.recordVerification(successfulVerificationReceipt("verified-project", "verification-2"))
        val commit = guardedRepository.commit(
            "verified-project",
            "Add verified result",
            "SignalASI",
            "signalasi@hotmail.com"
        )
        val push = guardedRepository.push(
            workspaceId = "verified-project",
            remote = "origin",
            branch = commit.branch,
            force = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE
        )
        assertEquals(commit.branch, push.branch)
        assertTrue(runCatching { guard.requirePullRequestReady("verified-project", commit.branch) }.isSuccess)

        candidate.writeText("fun result() = 3\n")
        assertTrue(runCatching { guard.requirePullRequestReady("verified-project", commit.branch) }.isFailure)
    }

    @Test
    fun verificationReceiptDoesNotFailForPlainLinuxWorkspace() {
        val tickets = mutableMapOf<String, AgentProjectVerificationTicket>()
        val guard = AgentProjectPublicationPolicy(
            projectRoot = projects,
            ticketStore = object : AgentProjectVerificationTicketStore {
                override fun read(workspaceId: String): AgentProjectVerificationTicket? = tickets[workspaceId]

                override fun write(ticket: AgentProjectVerificationTicket) {
                    tickets[ticket.workspaceId] = ticket
                }

                override fun remove(workspaceId: String) {
                    tickets.remove(workspaceId)
                }
            }
        )
        File(projects, "plain-workspace").apply {
            mkdirs()
            resolve("result.txt").writeText("verified")
        }

        guard.recordVerification(successfulVerificationReceipt("plain-workspace", "verification-plain"))

        assertFalse(tickets.containsKey("plain-workspace"))
    }

    @Test
    fun validatesPublicRepositoryAndRefBoundaries() {
        assertTrue(AgentMobileProjectRepository.isTrustedRepositoryUrl("https://github.com/signalasi/SignalASI.git"))
        assertFalse(AgentMobileProjectRepository.isTrustedRepositoryUrl("http://github.com/signalasi/SignalASI.git"))
        assertFalse(AgentMobileProjectRepository.isTrustedRepositoryUrl("https://token@github.com/signalasi/SignalASI.git"))
        assertFalse(AgentMobileProjectRepository.isTrustedRepositoryUrl("https://example.com/signalasi/SignalASI.git"))
        assertTrue(runCatching { AgentMobileProjectRepository.validateRefName("feature/mobile-agent") }.isSuccess)
        assertTrue(runCatching { AgentMobileProjectRepository.validateRefName("../main") }.isFailure)
    }

    @Test
    fun refusesRepositoryMutationWithoutPhoneLinuxGitBackend() {
        val repositoryWithoutLinux = AgentMobileProjectRepository(
            projectRoot = File(root, "projects-without-linux"),
            credentialProvider = AgentProjectCredentialProvider { "local-test-token" },
            repositoryPolicy = { true }
        )

        val failure = runCatching {
            repositoryWithoutLinux.clone(
                workspaceId = "missing-linux-backend",
                repositoryUrl = remote.toURI().toString(),
                branch = "main",
                depth = 1,
                replaceExisting = false,
                cancellationToken = AgentNativeToolCancellationToken.NONE,
                progress = { _, _, _ -> }
            )
        }.exceptionOrNull()

        assertTrue(failure?.message.orEmpty().contains("Phone Linux Git backend is required"))
        assertFalse(File(root, "projects-without-linux/missing-linux-backend/.git").exists())
    }

    @Test
    fun catalogDefinesBoundedProjectToolsAndPublicationRisk() {
        val definitions = AgentMobileProjectNativeTools.definitions(repository)
        assertEquals(AgentMobileProjectNativeTools.toolIds, definitions.map { it.descriptor.id }.toSet())
        assertEquals(AgentNativeToolRisk.HIGH, definitions.first { it.descriptor.id == AgentMobileProjectNativeTools.PUSH }.descriptor.risk)
        assertEquals(
            AgentMobileProjectNativeTools.PUBLISH_CONSENT,
            definitions.first { it.descriptor.id == AgentMobileProjectNativeTools.CREATE_PULL_REQUEST }
                .descriptor.requiredConsents.single().id
        )
        definitions.forEach { definition ->
            assertTrue(definition.descriptor.requiredPermissions.any {
                it.id == AgentPhoneNativeToolCatalog.WORKSPACE_PRIVATE_PERMISSION
            })
        }
    }

    private fun successfulVerificationReceipt(
        workspaceId: String,
        requestId: String
    ) = AgentRuntimeExecutionReceipt(
        requestId = requestId,
        workspaceId = workspaceId,
        language = AgentRuntimeLanguage.SHELL,
        sourceSha256 = "a".repeat(64),
        verificationKind = AgentRuntimeVerificationKind.TEST,
        packVersions = mapOf("linux-base" to "1.0.0"),
        networkEnabled = false,
        allowedNetworkDomains = emptyList(),
        limits = AgentRuntimeResourceLimits(),
        status = AgentRuntimeReceiptStatus.COMPLETED,
        exitCode = 0,
        stdoutSha256 = "b".repeat(64),
        stderrSha256 = "c".repeat(64),
        workspaceDisposition = AgentRuntimeWorkspaceDisposition.COMMITTED,
        createdAtMillis = 1_000L,
        completedAtMillis = 1_100L
    )

}

private class TestJGitBackend(
    private val projectRoot: File,
    private val onClone: (String) -> Unit = {}
) : AgentProjectGitBackend {
    override fun clone(
        workspaceId: String,
        repositoryUrl: String,
        branch: String,
        depth: Int,
        replaceExisting: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        progress: (String, String, Int?) -> Unit
    ) {
        onClone(workspaceId)
        val workspace = File(projectRoot, workspaceId)
        val staging = File(projectRoot, ".$workspaceId-test-clone").apply { deleteRecursively() }
        try {
            val command = Git.cloneRepository()
                .setURI(repositoryUrl)
                .setDirectory(staging)
                .setDepth(depth)
            if (branch.isNotBlank()) command.setBranch(branch)
            command.call().close()
            workspace.mkdirs()
            if (replaceExisting) {
                workspace.listFiles().orEmpty()
                    .filterNot { it.name in RUNTIME_ENTRIES }
                    .forEach(File::deleteRecursively)
            }
            staging.listFiles().orEmpty().forEach { source ->
                source.copyRecursively(File(workspace, source.name), overwrite = true)
            }
        } finally {
            staging.deleteRecursively()
        }
    }

    override fun checkoutBranch(workspaceId: String, branch: String, create: Boolean) {
        Git.open(File(projectRoot, workspaceId)).use { git ->
            git.checkout().setName(branch).setCreateBranch(create).call()
        }
    }

    override fun commit(workspaceId: String, message: String, authorName: String, authorEmail: String): String =
        Git.open(File(projectRoot, workspaceId)).use { git ->
            git.add().addFilepattern(".").call()
            git.add().setUpdate(true).addFilepattern(".").call()
            git.commit().setMessage(message).setAuthor(authorName, authorEmail)
                .setCommitter(authorName, authorEmail).call().name
        }

    override fun pull(
        workspaceId: String,
        remote: String,
        branch: String,
        cancellationToken: AgentNativeToolCancellationToken
    ): String = Git.open(File(projectRoot, workspaceId)).use { git ->
        git.pull().setRemote(remote).setRemoteBranchName(branch).call()
        git.repository.resolve("HEAD").name
    }

    override fun push(
        workspaceId: String,
        remote: String,
        branch: String,
        force: Boolean,
        cancellationToken: AgentNativeToolCancellationToken
    ): List<String> = Git.open(File(projectRoot, workspaceId)).use { git ->
        git.push().setRemote(remote).setForce(force).add(branch).call()
            .flatMap { result -> result.remoteUpdates.map { update -> "${update.remoteName}: ${update.status}" } }
    }

    private companion object {
        val RUNTIME_ENTRIES = setOf(
            ".signalasi-tools",
            ".signalasi-runtime",
            ".signalasi-inputs",
            ".tmp",
            "request.json",
            "status.json",
            ".signalasi-checkpoint.json",
            ".signalasi-stdout",
            ".signalasi-stderr",
            ".signalasi-main"
        )
    }
}
