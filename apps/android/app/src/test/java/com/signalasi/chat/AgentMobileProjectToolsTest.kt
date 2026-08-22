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
    fun partialRepositoryIsPresentButNotReadyForModelPlanning() {
        val value = AgentProjectRepositorySnapshot(
            workspaceId = "partial-project",
            repositoryUrl = "https://github.com/signalasi/SignalASI",
            branch = "feature/unborn",
            headCommit = "",
            clean = true,
            staged = emptyList(),
            modified = emptyList(),
            untracked = emptyList(),
            conflicting = emptyList(),
            workingTreeInspected = false,
            state = AgentProjectRepositoryState.PARTIAL
        ).publicValue()

        assertEquals(true, value["repository_present"])
        assertEquals(false, value["repository_ready"])
        assertEquals(false, value["head_present"])
        assertEquals(true, value["recovery_required"])
        assertTrue(value["recovery_hint"].toString().contains("Fetch the remote refs"))
        assertEquals("partial", value["repository_state"])
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
        assertEquals(
            "compare:main...feature/mobile-answer",
            repository.diff(
                workspaceId = "conversation-project",
                maxCharacters = 64 * 1024,
                baseRef = "main",
                headRef = "feature/mobile-answer"
            )
        )
        assertTrue(
            repository.log("conversation-project", "HEAD", maxEntries = 5, maxCharacters = 64 * 1024)
                .contains("Add mobile answer")
        )

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
    fun publicRepositoryCanFetchLatestRefsWithoutAGitHubToken() {
        val publicRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "" },
            repositoryPolicy = { true },
            gitBackend = TestJGitBackend(projects)
        )
        publicRepository.clone(
            workspaceId = "public-project",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )

        val refs = publicRepository.fetch(
            workspaceId = "public-project",
            remote = "origin",
            ref = "",
            cancellationToken = AgentNativeToolCancellationToken.NONE
        )

        assertTrue(refs.any { it.endsWith("/main") })
    }

    @Test
    fun commitAndPullUseThePersistentRepositoryHeadWhenLinuxOutputIsNotCaptured() {
        repository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "local-test-token" },
            repositoryPolicy = { true },
            gitBackend = TestJGitBackend(projects, omitCommitOutput = true)
        )
        repository.clone(
            workspaceId = "quiet-linux-output",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        repository.pull(
            workspaceId = "quiet-linux-output",
            remote = "origin",
            branch = "main",
            cancellationToken = AgentNativeToolCancellationToken.NONE
        ).also { result ->
            assertEquals(40, result.headCommit.length)
        }

        repository.checkoutBranch("quiet-linux-output", "feature/quiet-linux", create = true)
        File(projects, "quiet-linux-output/result.txt").writeText("phone linux\n")
        repository.commit(
            workspaceId = "quiet-linux-output",
            message = "Verify quiet Linux output",
            authorName = "SignalASI",
            authorEmail = "signalasi@hotmail.com"
        ).also { result ->
            assertEquals(40, result.commit.length)
        }
    }

    @Test
    fun linuxCloneAllowsRuntimeManagedEntriesButRejectsProjectFiles() {
        val calls = mutableListOf<String>()
        val linuxRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "" },
            repositoryPolicy = { true },
            gitBackend = TestJGitBackend(projects, onClone = { workspaceId -> calls += workspaceId })
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
    fun completeDocumentationDiffVerifiesDocumentationOnlyCommit() {
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
            workspaceId = "documentation-project",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        guardedRepository.checkoutBranch("documentation-project", "docs/phone-agent", create = true)
        File(projects, "documentation-project/README.md").appendText("\nPhone Agent documentation.\n")

        guardedRepository.diff("documentation-project", 64 * 1024)
        val commit = guardedRepository.commit(
            "documentation-project",
            "Document the phone Agent",
            "SignalASI",
            "signalasi@hotmail.com"
        )

        assertEquals("docs/phone-agent", commit.branch)
        assertEquals(listOf("README.md"), commit.changedFiles)
        assertTrue(tickets["documentation-project"]?.requestId.orEmpty().startsWith("documentation-diff:"))
    }

    @Test
    fun documentationDiffCannotVerifySourceChanges() {
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
            workspaceId = "source-project",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        File(projects, "source-project/src/Main.kt").apply {
            parentFile?.mkdirs()
            writeText("fun main() = Unit\n")
        }

        guardedRepository.diff("source-project", 64 * 1024)

        assertFalse(tickets.containsKey("source-project"))
        assertTrue(runCatching {
            guardedRepository.commit("source-project", "Add source", "SignalASI", "signalasi@hotmail.com")
        }.isFailure)
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
    fun guestGitPointerAcceptsVerificationAndDetectsLaterWorkspaceChanges() {
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
        val workspaceId = "guest-git-project"
        val workspace = File(projects, workspaceId).apply { mkdirs() }
        File(workspace, ".git").writeText("gitdir: /var/lib/signalasi/git/$workspaceId\n")
        val source = File(workspace, "src/result.kt").apply {
            requireNotNull(parentFile).mkdirs()
            writeText("fun result() = 1\n")
        }
        File(workspace, ".signalasi-stdout").writeText("runtime output")
        File(workspace, ".signalasi-runtime/main.sh").apply {
            parentFile?.mkdirs()
            writeText("echo runtime")
        }
        File(workspace, ".signalasi-inputs/request.txt").apply {
            parentFile?.mkdirs()
            writeText("temporary input")
        }
        File(workspace, ".signalasi-tools/bin/python").apply {
            parentFile?.mkdirs()
            writeText("temporary tool")
        }

        guard.recordVerification(successfulVerificationReceipt(workspaceId, "guest-verification"))

        assertTrue(tickets.containsKey(workspaceId))
        assertTrue(runCatching { guard.requireVerified(workspaceId) }.isSuccess)
        File(workspace, ".signalasi-stdout").writeText("new runtime output")
        assertTrue(runCatching { guard.requireVerified(workspaceId) }.isSuccess)
        File(workspace, ".signalasi-runtime").deleteRecursively()
        File(workspace, ".signalasi-inputs").deleteRecursively()
        File(workspace, ".signalasi-tools").deleteRecursively()
        assertTrue(runCatching { guard.requireVerified(workspaceId) }.isSuccess)
        source.writeText("fun result() = 2\n")
        assertTrue(runCatching { guard.requireVerified(workspaceId) }.isFailure)
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
    private val onClone: (String) -> Unit = {},
    private val omitCommitOutput: Boolean = false
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

    override fun inspect(workspaceId: String): AgentProjectRepositorySnapshot =
        Git.open(File(projectRoot, workspaceId)).use { git ->
            val status = git.status().call()
            AgentProjectRepositorySnapshot(
                workspaceId = workspaceId,
                repositoryUrl = git.repository.config.getString("remote", "origin", "url").orEmpty(),
                branch = git.repository.branch.orEmpty(),
                headCommit = git.repository.resolve("HEAD")?.name.orEmpty(),
                clean = status.isClean,
                staged = (status.added + status.changed + status.removed).sorted(),
                modified = (status.modified + status.missing).sorted(),
                untracked = status.untracked.sorted(),
                conflicting = status.conflicting.sorted()
            )
        }

    override fun diff(workspaceId: String, maxCharacters: Int): String =
        Git.open(File(projectRoot, workspaceId)).use { git ->
            val unstaged = git.diff().call().joinToString("\n") { it.toString() }
            val staged = git.diff().setCached(true).call().joinToString("\n") { it.toString() }
            "$unstaged\n$staged".take(maxCharacters)
        }

    override fun diffRefs(
        workspaceId: String,
        baseRef: String,
        headRef: String,
        maxCharacters: Int
    ): String = "compare:$baseRef...$headRef".take(maxCharacters)

    override fun log(workspaceId: String, ref: String, maxEntries: Int, maxCharacters: Int): String =
        Git.open(File(projectRoot, workspaceId)).use { git ->
            git.log().add(git.repository.resolve(ref)).setMaxCount(maxEntries).call()
                .joinToString("\n") { commit ->
                    "${commit.name}\t${commit.authorIdent.name}\t${commit.fullMessage.trim()}"
                }
                .take(maxCharacters)
        }

    override fun remoteUrl(workspaceId: String, remote: String): String =
        Git.open(File(projectRoot, workspaceId)).use { git ->
            git.repository.config.getString("remote", remote, "url").orEmpty()
        }

    override fun checkoutBranch(workspaceId: String, branch: String, create: Boolean) {
        checkoutBranchAt(workspaceId, branch, create, "")
    }

    override fun checkoutBranchAt(workspaceId: String, branch: String, create: Boolean, baseRef: String) {
        Git.open(File(projectRoot, workspaceId)).use { git ->
            val checkout = git.checkout().setName(branch).setCreateBranch(create)
            if (create && baseRef.isNotBlank()) checkout.setStartPoint(baseRef)
            checkout.call()
        }
    }

    override fun fetch(
        workspaceId: String,
        remote: String,
        ref: String,
        cancellationToken: AgentNativeToolCancellationToken
    ): List<String> = Git.open(File(projectRoot, workspaceId)).use { git ->
        val command = git.fetch().setRemote(remote)
        if (ref.isNotBlank()) command.setRefSpecs(ref)
        command.call()
        git.repository.refDatabase.getRefsByPrefix("refs/remotes/$remote/")
            .map { it.name.removePrefix("refs/remotes/") }
    }

    override fun commit(workspaceId: String, message: String, authorName: String, authorEmail: String): String {
        val commit = Git.open(File(projectRoot, workspaceId)).use { git ->
            git.add().addFilepattern(".").call()
            git.add().setUpdate(true).addFilepattern(".").call()
            git.commit().setMessage(message).setAuthor(authorName, authorEmail)
                .setCommitter(authorName, authorEmail).call().name
        }
        return if (omitCommitOutput) "" else commit
    }

    override fun pull(
        workspaceId: String,
        remote: String,
        branch: String,
        cancellationToken: AgentNativeToolCancellationToken
    ): String {
        val head = Git.open(File(projectRoot, workspaceId)).use { git ->
        git.pull().setRemote(remote).setRemoteBranchName(branch).call()
        git.repository.resolve("HEAD").name
        }
        return if (omitCommitOutput) "" else head
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
