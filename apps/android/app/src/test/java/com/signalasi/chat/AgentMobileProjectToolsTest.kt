package com.signalasi.chat

import java.io.File
import java.nio.file.Files
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.storage.file.FileRepositoryBuilder
import org.json.JSONObject
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
    fun repositoryUsesAtomicCheckoutResultWithoutASecondInspection() {
        val backend = TestJGitBackend(projects, atomicCheckoutObservation = true)
        val optimizedRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "local-test-token" },
            repositoryPolicy = { true },
            gitBackend = backend
        )
        optimizedRepository.clone(
            workspaceId = "atomic-checkout-project",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        backend.resetInspectionCounts()

        val snapshot = optimizedRepository.checkoutBranch(
            workspaceId = "atomic-checkout-project",
            branch = "feature/atomic-checkout",
            create = true,
            baseRef = "main"
        )

        assertEquals("feature/atomic-checkout", snapshot.branch)
        assertTrue(snapshot.clean)
        assertTrue(snapshot.workingTreeInspected)
        assertEquals(1, backend.atomicCheckoutCount)
        assertEquals(0, backend.fullInspectionCount)
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
    fun preparesAFeatureBranchBeforeTheModelStartsEditing() {
        val prepared = repository.prepare(
            workspaceId = "prepared-project",
            repositoryUrl = remote.toURI().toString(),
            baseBranch = "main",
            featureBranch = "improve/phone-agent",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )

        assertEquals(AgentProjectRepositoryState.READY, prepared.state)
        assertEquals("improve/phone-agent", prepared.branch)
        assertEquals(40, prepared.headCommit.length)
        assertTrue(File(projects, "prepared-project/README.md").isFile)
    }

    @Test
    fun observesRepositoryEvidenceThroughTheGenericBackendContract() {
        repository.clone(
            workspaceId = "observed-project",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        File(projects, "observed-project/README.md").appendText("Observed\n")

        val observation = repository.observe(
            workspaceId = "observed-project",
            includeWorkingTree = true,
            includeDiff = true,
            includeLog = true,
            logRef = "HEAD",
            maxLogEntries = 5,
            maxDiffCharacters = 64 * 1024,
            maxLogCharacters = 64 * 1024
        )

        assertFalse(observation.repository.clean)
        assertTrue(observation.repository.modified.contains("README.md"))
        assertTrue(observation.recentCommits.contains("Initial fixture"))
        assertFalse(observation.diffTruncated)
        assertFalse(observation.recentCommitsTruncated)
    }

    @Test
    fun commitAndPushUseMetadataOnlyAfterTheRequiredChangeScan() {
        val backend = TestJGitBackend(projects)
        val optimizedRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "local-test-token" },
            repositoryPolicy = { true },
            gitBackend = backend
        )
        optimizedRepository.clone(
            workspaceId = "metadata-project",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        assertEquals(0, backend.fullInspectionCount)
        assertEquals(1, backend.metadataInspectionCount)
        assertEquals(0, backend.remoteInspectionCount)
        File(projects, "metadata-project/change.txt").writeText("change\n")
        backend.resetInspectionCounts()

        val commit = optimizedRepository.commit(
            workspaceId = "metadata-project",
            message = "Exercise metadata path",
            authorName = "SignalASI",
            authorEmail = "signalasi@hotmail.com"
        )

        assertEquals(1, backend.fullInspectionCount)
        assertEquals(1, backend.metadataInspectionCount)
        backend.resetInspectionCounts()

        optimizedRepository.push(
            workspaceId = "metadata-project",
            remote = "origin",
            branch = commit.branch,
            force = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE
        )

        assertEquals(0, backend.fullInspectionCount)
        assertEquals(1, backend.metadataInspectionCount)
        assertEquals(0, backend.remoteInspectionCount)
    }

    @Test
    fun verifiedPhoneLinuxCommitReusesTheReceiptFingerprintInOneBackendOperation() {
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
        val backend = TestJGitBackend(projects, atomicCommitObservation = true)
        val optimizedRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "local-test-token" },
            repositoryPolicy = { true },
            publicationGuard = guard,
            gitBackend = backend
        )
        optimizedRepository.clone(
            workspaceId = "atomic-verified-commit",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        optimizedRepository.checkoutBranch("atomic-verified-commit", "feature/atomic-commit", create = true)
        File(projects, "atomic-verified-commit/src/Main.kt").apply {
            parentFile?.mkdirs()
            writeText("fun main() = Unit\n")
        }
        guard.recordVerification(successfulVerificationReceipt("atomic-verified-commit", "verification-atomic"))
        val verifiedDigest = requireNotNull(guard.verifiedProjectDigest("atomic-verified-commit"))
        backend.resetInspectionCounts()

        val result = optimizedRepository.commit(
            workspaceId = "atomic-verified-commit",
            message = "Commit through one phone Linux call",
            authorName = "SignalASI",
            authorEmail = "signalasi@hotmail.com"
        )

        assertEquals(listOf("src/Main.kt"), result.changedFiles)
        assertEquals(verifiedDigest, backend.lastExpectedCommitFingerprint)
        assertEquals(0, backend.fullInspectionCount)
        assertEquals(0, backend.metadataInspectionCount)
    }

    @Test
    fun verifiedOriginPushRechecksAndPublishesInOneBackendOperation() {
        val tickets = mutableMapOf<String, AgentProjectVerificationTicket>()
        val guard = AgentProjectPublicationPolicy(
            projectRoot = projects,
            ticketStore = inMemoryTicketStore(tickets)
        )
        val backend = TestJGitBackend(
            projectRoot = projects,
            atomicCommitObservation = true,
            atomicPushObservation = true
        )
        val optimizedRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "local-test-token" },
            repositoryPolicy = { true },
            publicationGuard = guard,
            gitBackend = backend
        )
        optimizedRepository.clone(
            workspaceId = "atomic-verified-push",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        optimizedRepository.checkoutBranch("atomic-verified-push", "feature/atomic-push", create = true)
        File(projects, "atomic-verified-push/result.txt").writeText("verified\n")
        guard.recordVerification(successfulVerificationReceipt("atomic-verified-push", "verification-push"))
        val commit = optimizedRepository.commit(
            workspaceId = "atomic-verified-push",
            message = "Publish through one phone Linux call",
            authorName = "SignalASI",
            authorEmail = "signalasi@hotmail.com"
        )
        backend.resetInspectionCounts()

        val pushed = optimizedRepository.push(
            workspaceId = "atomic-verified-push",
            remote = "origin",
            branch = commit.branch,
            force = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE
        )

        assertEquals("feature/atomic-push", pushed.branch)
        assertEquals(1, backend.atomicPushCount)
        assertEquals(0, backend.metadataInspectionCount)
        assertEquals(0, backend.fullInspectionCount)
        assertEquals(tickets.getValue("atomic-verified-push").projectDigest, backend.lastExpectedPushFingerprint)
        assertEquals(commit.commit, backend.lastExpectedPushHead)
        assertEquals(tickets.getValue("atomic-verified-push").repositoryUrl, backend.lastExpectedPushRepositoryUrl)
    }

    @Test
    fun verifiedChangesCommitPushAndCreatePullRequestThroughOneBackendOperation() {
        val workspaceId = "atomic-finalize-project"
        val repositoryUrl = "https://github.com/signalasi/SignalASI.git"
        val tickets = mutableMapOf<String, AgentProjectVerificationTicket>()
        val guard = AgentProjectPublicationPolicy(
            projectRoot = projects,
            ticketStore = inMemoryTicketStore(tickets)
        )
        val backend = TestJGitBackend(
            projectRoot = projects,
            atomicCommitObservation = true,
            atomicPushObservation = true,
            atomicCommitPushObservation = true,
            simulatePush = true
        )
        val requests = mutableListOf<Request>()
        val httpClient = OkHttpClient.Builder()
            .addInterceptor { chain ->
                requests += chain.request()
                Response.Builder()
                    .request(chain.request())
                    .protocol(Protocol.HTTP_1_1)
                    .code(201)
                    .message("Created")
                    .body(
                        """{"number":2358,"html_url":"https://github.com/signalasi/SignalASI/pull/2358","state":"open"}"""
                            .toResponseBody("application/json".toMediaType())
                    )
                    .build()
            }
            .build()
        val optimizedRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "github-token" },
            httpClient = httpClient,
            repositoryPolicy = { true },
            publicationGuard = guard,
            gitBackend = backend
        )
        optimizedRepository.clone(
            workspaceId = workspaceId,
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        optimizedRepository.checkoutBranch(workspaceId, "feature/atomic-finalize", create = true)
        File(projects, "$workspaceId/src/Main.kt").apply {
            parentFile?.mkdirs()
            writeText("fun main() = Unit\n")
        }
        Git.open(File(projects, workspaceId)).use { git ->
            git.repository.config.setString("remote", "origin", "url", repositoryUrl)
            git.repository.config.save()
        }
        guard.recordVerification(successfulVerificationReceipt(workspaceId, "verification-finalize"))
        val verifiedDigest = requireNotNull(guard.verifiedProjectDigest(workspaceId))
        backend.resetInspectionCounts()

        val result = optimizedRepository.finalizePullRequest(
            workspaceId = workspaceId,
            repositoryUrl = repositoryUrl,
            remote = "origin",
            branch = "feature/atomic-finalize",
            force = false,
            commitMessage = "Finalize verified phone work",
            authorName = "SignalASI",
            authorEmail = "signalasi@hotmail.com",
            title = "Finalize verified phone work",
            body = "Verified on the phone.",
            base = "main",
            cancellationToken = AgentNativeToolCancellationToken.NONE
        )

        assertEquals(1, backend.atomicCommitPushCount)
        assertEquals(0, backend.fullInspectionCount)
        assertEquals(0, backend.metadataInspectionCount)
        assertEquals(0, backend.remoteInspectionCount)
        assertEquals(verifiedDigest, backend.lastExpectedFinalizeFingerprint)
        assertEquals(repositoryUrl, backend.lastExpectedFinalizeRepositoryUrl)
        assertEquals(listOf("src/Main.kt"), result.changedFiles)
        assertEquals("feature/atomic-finalize", result.push.branch)
        assertEquals(2358L, result.pullRequest.number)
        assertEquals(result.commit, tickets.getValue(workspaceId).pushedCommit)
        assertEquals("feature/atomic-finalize", tickets.getValue(workspaceId).pushedBranch)
        assertEquals(1, requests.size)
        assertEquals("/repos/signalasi/SignalASI/pulls", requests.single().url.encodedPath)
    }

    @Test
    fun verifiedOriginPushRejectsARemoteChangedAfterCommit() {
        val tickets = mutableMapOf<String, AgentProjectVerificationTicket>()
        val guard = AgentProjectPublicationPolicy(
            projectRoot = projects,
            ticketStore = inMemoryTicketStore(tickets)
        )
        val backend = TestJGitBackend(
            projectRoot = projects,
            atomicCommitObservation = true,
            atomicPushObservation = true
        )
        val optimizedRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "local-test-token" },
            repositoryPolicy = { true },
            publicationGuard = guard,
            gitBackend = backend
        )
        optimizedRepository.clone(
            workspaceId = "changed-remote-push",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        optimizedRepository.checkoutBranch("changed-remote-push", "feature/changed-remote", create = true)
        File(projects, "changed-remote-push/result.txt").writeText("verified\n")
        guard.recordVerification(successfulVerificationReceipt("changed-remote-push", "verification-remote"))
        optimizedRepository.commit(
            workspaceId = "changed-remote-push",
            message = "Commit before remote mutation",
            authorName = "SignalASI",
            authorEmail = "signalasi@hotmail.com"
        )
        Git.open(File(projects, "changed-remote-push")).use { git ->
            git.repository.config.setString("remote", "origin", "url", "https://github.com/other/project.git")
            git.repository.config.save()
        }

        val failure = runCatching {
            optimizedRepository.push(
                workspaceId = "changed-remote-push",
                remote = "origin",
                branch = "feature/changed-remote",
                force = false,
                cancellationToken = AgentNativeToolCancellationToken.NONE
            )
        }

        assertTrue(failure.isFailure)
        assertTrue(failure.exceptionOrNull()?.message.orEmpty().contains("remote changed"))
        assertEquals(1, backend.atomicPushCount)
    }

    @Test
    fun customRemoteKeepsTheObservedPublicationFallback() {
        val tickets = mutableMapOf<String, AgentProjectVerificationTicket>()
        val guard = AgentProjectPublicationPolicy(
            projectRoot = projects,
            ticketStore = inMemoryTicketStore(tickets)
        )
        val backend = TestJGitBackend(
            projectRoot = projects,
            atomicCommitObservation = true,
            atomicPushObservation = true
        )
        val optimizedRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "local-test-token" },
            repositoryPolicy = { true },
            publicationGuard = guard,
            gitBackend = backend
        )
        optimizedRepository.clone(
            workspaceId = "custom-remote-push",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        optimizedRepository.checkoutBranch("custom-remote-push", "feature/custom-remote", create = true)
        File(projects, "custom-remote-push/result.txt").writeText("verified\n")
        guard.recordVerification(successfulVerificationReceipt("custom-remote-push", "verification-custom"))
        val commit = optimizedRepository.commit(
            workspaceId = "custom-remote-push",
            message = "Publish through a custom remote",
            authorName = "SignalASI",
            authorEmail = "signalasi@hotmail.com"
        )
        Git.open(File(projects, "custom-remote-push")).use { git ->
            git.repository.config.setString("remote", "backup", "url", remote.toURI().toString())
            git.repository.config.save()
        }
        backend.resetInspectionCounts()

        optimizedRepository.push(
            workspaceId = "custom-remote-push",
            remote = "backup",
            branch = commit.branch,
            force = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE
        )

        assertEquals(0, backend.atomicPushCount)
        assertEquals(1, backend.metadataInspectionCount)
        assertEquals(0, backend.fullInspectionCount)
        assertEquals(1, backend.remoteInspectionCount)
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
    fun fetchReusesTrustedPushEvidenceWithoutASeparateRemoteInspection() {
        val workspaceId = "trusted-fetch-project"
        val backend = TestJGitBackend(projects, atomicFetchObservation = true)
        val tickets = mutableMapOf<String, AgentProjectVerificationTicket>()
        val guard = AgentProjectPublicationPolicy(
            projectRoot = projects,
            ticketStore = inMemoryTicketStore(tickets)
        )
        val optimizedRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "local-test-token" },
            repositoryPolicy = { true },
            publicationGuard = guard,
            gitBackend = backend
        )
        val cloned = optimizedRepository.clone(
            workspaceId = workspaceId,
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        tickets[workspaceId] = AgentProjectVerificationTicket(
            workspaceId = workspaceId,
            verificationKind = AgentRuntimeVerificationKind.TEST,
            requestId = "verified-fetch",
            projectDigest = "a".repeat(64),
            stdoutSha256 = "b".repeat(64),
            completedAtMillis = 1_000L,
            pushedCommit = cloned.headCommit,
            pushedBranch = cloned.branch,
            pushedRepositoryUrl = cloned.repositoryUrl
        )
        backend.resetInspectionCounts()

        val refs = optimizedRepository.fetch(
            workspaceId = workspaceId,
            remote = "origin",
            ref = "main",
            cancellationToken = AgentNativeToolCancellationToken.NONE
        )

        assertTrue(refs.any { it.endsWith("/main") })
        assertEquals(1, backend.atomicFetchCount)
        assertEquals(cloned.repositoryUrl, backend.lastExpectedFetchRepositoryUrl)
        assertEquals(0, backend.remoteInspectionCount)
        assertTrue(tickets.containsKey(workspaceId))
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
    fun pullReusesOneMetadataSnapshotForTheDefaultBranchAndOrigin() {
        val backend = TestJGitBackend(projects)
        val optimizedRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "local-test-token" },
            repositoryPolicy = { true },
            gitBackend = backend
        )
        optimizedRepository.clone(
            workspaceId = "pull-metadata-project",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        backend.resetInspectionCounts()

        val result = optimizedRepository.pull(
            workspaceId = "pull-metadata-project",
            remote = "origin",
            branch = "",
            cancellationToken = AgentNativeToolCancellationToken.NONE
        )

        assertEquals(40, result.headCommit.length)
        assertEquals(0, backend.fullInspectionCount)
        assertEquals(1, backend.metadataInspectionCount)
        assertEquals(0, backend.remoteInspectionCount)
    }

    @Test
    fun pullReusesTrustedPushEvidenceInOneBackendOperation() {
        val workspaceId = "trusted-pull-project"
        val cloneUrl = remote.toURI().toString()
        val backend = TestJGitBackend(projects, atomicPullObservation = true)
        val tickets = mutableMapOf<String, AgentProjectVerificationTicket>()
        val guard = AgentProjectPublicationPolicy(
            projectRoot = projects,
            ticketStore = inMemoryTicketStore(tickets),
            stateReader = object : AgentProjectStateReader {
                override fun fingerprint(workspaceId: String): String? = error("Linux must not inspect before pull")
                override fun changedFiles(workspaceId: String): List<String> = error("Linux must not inspect before pull")
                override fun repositoryState(workspaceId: String): AgentProjectStateDigester.RepositoryState =
                    error("Linux must not inspect before pull")
                override fun usesGuestGitMetadata(workspaceId: String): Boolean = true
            }
        )
        val optimizedRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "local-test-token" },
            repositoryPolicy = { true },
            publicationGuard = guard,
            gitBackend = backend
        )
        val cloned = optimizedRepository.clone(
            workspaceId = workspaceId,
            repositoryUrl = cloneUrl,
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        tickets[workspaceId] = AgentProjectVerificationTicket(
            workspaceId = workspaceId,
            verificationKind = AgentRuntimeVerificationKind.TEST,
            requestId = "verified-pull",
            projectDigest = "a".repeat(64),
            stdoutSha256 = "b".repeat(64),
            completedAtMillis = 1_000L,
            pushedCommit = cloned.headCommit,
            pushedBranch = cloned.branch,
            pushedRepositoryUrl = cloned.repositoryUrl
        )
        backend.resetInspectionCounts()

        val result = optimizedRepository.pull(
            workspaceId = workspaceId,
            remote = "origin",
            branch = "",
            cancellationToken = AgentNativeToolCancellationToken.NONE
        )

        assertEquals(cloned.headCommit, result.headCommit)
        assertEquals(1, backend.atomicPullCount)
        assertEquals(cloned.repositoryUrl, backend.lastExpectedPullRepositoryUrl)
        assertEquals(0, backend.metadataInspectionCount)
        assertEquals(0, backend.remoteInspectionCount)
        assertTrue(tickets.isEmpty())
    }

    @Test
    fun pullRequestReusesOneMetadataSnapshotForHeadAndOrigin() {
        val backend = TestJGitBackend(projects)
        val httpClient = OkHttpClient.Builder()
            .addInterceptor { chain ->
                Response.Builder()
                    .request(chain.request())
                    .protocol(Protocol.HTTP_1_1)
                    .code(201)
                    .message("Created")
                    .body(
                        """{"number":42,"html_url":"https://github.com/signalasi/SignalASI/pull/42","state":"open"}"""
                            .toResponseBody("application/json".toMediaType())
                    )
                    .build()
            }
            .build()
        val optimizedRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "github-token" },
            httpClient = httpClient,
            repositoryPolicy = { true },
            gitBackend = backend
        )
        optimizedRepository.clone(
            workspaceId = "pull-request-metadata-project",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        Git.open(File(projects, "pull-request-metadata-project")).use { git ->
            git.repository.config.apply {
                setString("remote", "origin", "url", "https://github.com/signalasi/SignalASI.git")
                save()
            }
        }
        backend.resetInspectionCounts()

        val result = optimizedRepository.createPullRequest(
            workspaceId = "pull-request-metadata-project",
            title = "Improve phone development",
            body = "Validated on the phone.",
            base = "main",
            head = ""
        )

        assertEquals(42L, result.number)
        assertEquals("https://github.com/signalasi/SignalASI/pull/42", result.url)
        assertEquals(0, backend.fullInspectionCount)
        assertEquals(1, backend.metadataInspectionCount)
        assertEquals(0, backend.remoteInspectionCount)
    }

    @Test
    fun pullRequestReusesTrustedPushedEvidenceWithoutStartingLinux() {
        val workspaceId = "trusted-pushed-project"
        val digest = "a".repeat(64)
        val commit = "b".repeat(40)
        val branch = "feature/trusted-pr"
        val repositoryUrl = "https://github.com/signalasi/SignalASI.git"
        val tickets = mutableMapOf(
            workspaceId to AgentProjectVerificationTicket(
                workspaceId = workspaceId,
                verificationKind = AgentRuntimeVerificationKind.TEST,
                requestId = "verified-push",
                projectDigest = digest,
                stdoutSha256 = "c".repeat(64),
                completedAtMillis = 1_000L,
                commit = commit,
                branch = branch,
                repositoryUrl = repositoryUrl,
                pushedCommit = commit,
                pushedBranch = branch,
                pushedRepositoryUrl = repositoryUrl
            )
        )
        val guard = AgentProjectPublicationPolicy(
            projectRoot = projects,
            ticketStore = inMemoryTicketStore(tickets),
            stateReader = object : AgentProjectStateReader {
                override fun fingerprint(workspaceId: String): String? = error("Linux must not start")
                override fun changedFiles(workspaceId: String): List<String> = error("Linux must not start")
                override fun repositoryState(workspaceId: String): AgentProjectStateDigester.RepositoryState =
                    error("Linux must not start")
                override fun usesGuestGitMetadata(workspaceId: String): Boolean = true
            }
        )
        val backend = TestJGitBackend(projects)
        val requests = mutableListOf<Request>()
        val httpClient = OkHttpClient.Builder()
            .addInterceptor { chain ->
                requests += chain.request()
                Response.Builder()
                    .request(chain.request())
                    .protocol(Protocol.HTTP_1_1)
                    .code(201)
                    .message("Created")
                    .body(
                        """{"number":49,"html_url":"https://github.com/signalasi/SignalASI/pull/49","state":"open"}"""
                            .toResponseBody("application/json".toMediaType())
                    )
                    .build()
            }
            .build()
        val optimizedRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "github-token" },
            httpClient = httpClient,
            repositoryPolicy = { true },
            publicationGuard = guard,
            gitBackend = backend
        )

        val result = optimizedRepository.createPullRequest(
            workspaceId = workspaceId,
            title = "Create PR from trusted push",
            body = "No extra phone Linux startup.",
            base = "main",
            head = branch
        )

        assertEquals(49L, result.number)
        assertEquals(0, backend.metadataInspectionCount)
        assertEquals(0, backend.fullInspectionCount)
        assertEquals(1, requests.size)
        assertEquals("feature/trusted-pr", JSONObject(requests.single().body!!.let { body ->
            val buffer = okio.Buffer()
            body.writeTo(buffer)
            buffer.readUtf8()
        }).getString("head"))
    }

    @Test
    fun pullRequestCreationRecoversTheExistingRequestAfterALostResponse() {
        val backend = TestJGitBackend(projects)
        val requests = mutableListOf<Request>()
        val httpClient = OkHttpClient.Builder()
            .addInterceptor { chain ->
                requests += chain.request()
                if (chain.request().method == "POST") {
                    Response.Builder()
                        .request(chain.request())
                        .protocol(Protocol.HTTP_1_1)
                        .code(422)
                        .message("Unprocessable Entity")
                        .body(
                            """{"message":"Validation Failed"}"""
                                .toResponseBody("application/json".toMediaType())
                        )
                        .build()
                } else {
                    Response.Builder()
                        .request(chain.request())
                        .protocol(Protocol.HTTP_1_1)
                        .code(200)
                        .message("OK")
                        .body(
                            """[{"number":84,"html_url":"https://github.com/signalasi/SignalASI/pull/84","state":"open"}]"""
                                .toResponseBody("application/json".toMediaType())
                        )
                        .build()
                }
            }
            .build()
        val recoveringRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "github-token" },
            httpClient = httpClient,
            repositoryPolicy = { true },
            gitBackend = backend
        )
        recoveringRepository.clone(
            workspaceId = "existing-pull-request-project",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        Git.open(File(projects, "existing-pull-request-project")).use { git ->
            git.repository.config.apply {
                setString("remote", "origin", "url", "https://github.com/signalasi/SignalASI.git")
                save()
            }
        }

        val result = recoveringRepository.createPullRequest(
            workspaceId = "existing-pull-request-project",
            title = "Recover phone publication",
            body = "The first response was lost.",
            base = "main",
            head = "feature/recovered-publication"
        )

        assertEquals(84L, result.number)
        assertEquals("https://github.com/signalasi/SignalASI/pull/84", result.url)
        assertEquals(2, requests.size)
        assertEquals("POST", requests[0].method)
        assertEquals("GET", requests[1].method)
        assertEquals("all", requests[1].url.queryParameter("state"))
        assertEquals("signalasi:feature/recovered-publication", requests[1].url.queryParameter("head"))
        assertEquals("main", requests[1].url.queryParameter("base"))
        assertEquals("1", requests[1].url.queryParameter("per_page"))
    }

    @Test
    fun pullRequestCreationKeepsTheValidationFailureWhenNoExistingRequestMatches() {
        val httpClient = OkHttpClient.Builder()
            .addInterceptor { chain ->
                Response.Builder()
                    .request(chain.request())
                    .protocol(Protocol.HTTP_1_1)
                    .code(if (chain.request().method == "POST") 422 else 200)
                    .message(if (chain.request().method == "POST") "Unprocessable Entity" else "OK")
                    .body(
                        (if (chain.request().method == "POST") {
                            """{"message":"Validation Failed"}"""
                        } else {
                            "[]"
                        }).toResponseBody("application/json".toMediaType())
                    )
                    .build()
            }
            .build()
        val recoveringRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "github-token" },
            httpClient = httpClient,
            repositoryPolicy = { true },
            gitBackend = TestJGitBackend(projects)
        )
        recoveringRepository.clone(
            workspaceId = "missing-pull-request-project",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        Git.open(File(projects, "missing-pull-request-project")).use { git ->
            git.repository.config.apply {
                setString("remote", "origin", "url", "https://github.com/signalasi/SignalASI.git")
                save()
            }
        }

        val failure = runCatching {
            recoveringRepository.createPullRequest(
                workspaceId = "missing-pull-request-project",
                title = "Invalid publication",
                body = "No existing pull request.",
                base = "main",
                head = "feature/missing-publication"
            )
        }

        assertTrue(failure.isFailure)
        assertTrue(failure.exceptionOrNull()?.message.orEmpty().contains("Validation Failed"))
    }

    @Test
    fun atomicPublishPushesAndCreatesPullRequestFromOneMetadataSnapshot() {
        val delegate = TestJGitBackend(projects)
        val backend = object : AgentProjectGitBackend by delegate {
            override fun inspectMetadata(workspaceId: String): AgentProjectRepositorySnapshot =
                delegate.inspectMetadata(workspaceId).copy(
                    repositoryUrl = "https://github.com/signalasi/SignalASI.git"
                )

            override fun observe(
                workspaceId: String,
                includeWorkingTree: Boolean,
                includeDiff: Boolean,
                includeLog: Boolean,
                logRef: String,
                maxLogEntries: Int,
                maxDiffCharacters: Int,
                maxLogCharacters: Int
            ): AgentProjectRepositoryObservation = delegate.observe(
                workspaceId,
                includeWorkingTree,
                includeDiff,
                includeLog,
                logRef,
                maxLogEntries,
                maxDiffCharacters,
                maxLogCharacters
            ).let { observation ->
                observation.copy(
                    repository = observation.repository.copy(
                        repositoryUrl = "https://github.com/signalasi/SignalASI.git"
                    )
                )
            }

            override fun push(
                workspaceId: String,
                remote: String,
                branch: String,
                force: Boolean,
                cancellationToken: AgentNativeToolCancellationToken,
                expectedFingerprint: String,
                expectedHead: String
            ): List<String> = listOf("refs/heads/$branch: OK")
        }
        val requests = mutableListOf<Request>()
        val httpClient = OkHttpClient.Builder()
            .addInterceptor { chain ->
                requests += chain.request()
                Response.Builder()
                    .request(chain.request())
                    .protocol(Protocol.HTTP_1_1)
                    .code(201)
                    .message("Created")
                    .body(
                        """{"number":84,"html_url":"https://github.com/signalasi/SignalASI/pull/84","state":"open"}"""
                            .toResponseBody("application/json".toMediaType())
                    )
                    .build()
            }
            .build()
        val publishingRepository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "github-token" },
            httpClient = httpClient,
            repositoryPolicy = { true },
            gitBackend = backend
        )
        publishingRepository.clone(
            workspaceId = "atomic-publish-project",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        publishingRepository.checkoutBranch("atomic-publish-project", "improve/atomic-publish", create = true)
        delegate.resetInspectionCounts()

        val result = publishingRepository.publishPullRequest(
            workspaceId = "atomic-publish-project",
            remote = "origin",
            branch = "",
            force = false,
            title = "Publish from the phone",
            body = "Verified on the phone.",
            base = "main",
            cancellationToken = AgentNativeToolCancellationToken.NONE
        )

        assertEquals("improve/atomic-publish", result.push.branch)
        assertEquals(listOf("refs/heads/improve/atomic-publish: OK"), result.push.remoteMessages)
        assertEquals(84L, result.pullRequest.number)
        assertEquals("https://github.com/signalasi/SignalASI/pull/84", result.pullRequest.url)
        assertEquals(1, delegate.metadataInspectionCount)
        assertEquals(0, delegate.fullInspectionCount)
        assertEquals(1, requests.size)
        assertEquals("POST", requests.single().method)
        assertEquals("/repos/signalasi/SignalASI/pulls", requests.single().url.encodedPath)
        assertEquals("Bearer github-token", requests.single().header("Authorization"))
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
    fun linuxAuthoritativeFingerprintRefreshesAfterCommitWithoutHostTreeScan() {
        val tickets = mutableMapOf<String, AgentProjectVerificationTicket>()
        var fingerprint = "a".repeat(64)
        var fingerprintReads = 0
        val stateReader = object : AgentProjectStateReader {
            override fun fingerprint(workspaceId: String): String {
                fingerprintReads += 1
                return fingerprint
            }

            override fun changedFiles(workspaceId: String): List<String> = listOf("src/result.kt")

            override fun repositoryState(workspaceId: String) =
                AgentProjectStateDigester.RepositoryState("", "feature/phone", clean = false)

            override fun usesGuestGitMetadata(workspaceId: String): Boolean = true
        }
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
            },
            stateReader = stateReader
        )

        guard.recordVerification(successfulVerificationReceipt("linux-project", "verification-linux"))
        guard.requireVerified("linux-project")
        fingerprint = "b".repeat(64)
        assertTrue(runCatching { guard.requireVerified("linux-project") }.isFailure)

        fingerprint = "a".repeat(64)
        guard.requireVerified("linux-project")
        fingerprint = "c".repeat(64)
        guard.recordCommit("linux-project", "1".repeat(40), "feature/phone")
        assertTrue(runCatching { guard.requirePushable("linux-project", "feature/phone") }.isSuccess)
        assertEquals("c".repeat(64), tickets.getValue("linux-project").projectDigest)
        assertTrue(fingerprintReads >= 6)
    }

    @Test
    fun observedFingerprintsAvoidRepeatedLinuxPublicationStateReads() {
        val tickets = mutableMapOf<String, AgentProjectVerificationTicket>()
        var fingerprintReads = 0
        val stateReader = object : AgentProjectStateReader {
            override fun fingerprint(workspaceId: String): String {
                fingerprintReads += 1
                return "a".repeat(64)
            }

            override fun changedFiles(workspaceId: String): List<String> = listOf("src/result.kt")

            override fun repositoryState(workspaceId: String) =
                AgentProjectStateDigester.RepositoryState("", "feature/phone", clean = false)

            override fun usesGuestGitMetadata(workspaceId: String): Boolean = true
        }
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
            },
            stateReader = stateReader
        )

        guard.recordVerification(
            successfulVerificationReceipt("linux-project", "verification-linux").copy(
                projectFingerprint = "a".repeat(64),
                projectFingerprintChecked = true
            )
        )
        assertEquals(0, fingerprintReads)
        fingerprintReads = 0

        guard.requireVerified("linux-project", "a".repeat(64))
        guard.recordCommit(
            "linux-project",
            "1".repeat(40),
            "feature/phone",
            "c".repeat(64)
        )
        guard.requirePushable("linux-project", "feature/phone", "c".repeat(64))
        guard.recordPush("linux-project", "1".repeat(40), "feature/phone")
        guard.requirePullRequestReady("linux-project", "feature/phone", "c".repeat(64))

        assertEquals(0, fingerprintReads)
        assertEquals("c".repeat(64), tickets.getValue("linux-project").projectDigest)
    }

    @Test
    fun checkedGuestWithoutRepositoryDoesNotStartAnotherStateRead() {
        val tickets = mutableMapOf<String, AgentProjectVerificationTicket>()
        var fingerprintReads = 0
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
            },
            stateReader = object : AgentProjectStateReader {
                override fun fingerprint(workspaceId: String): String {
                    fingerprintReads += 1
                    return "a".repeat(64)
                }
                override fun changedFiles(workspaceId: String): List<String> = emptyList()
                override fun repositoryState(workspaceId: String) =
                    AgentProjectStateDigester.RepositoryState("", "", clean = true)
                override fun usesGuestGitMetadata(workspaceId: String): Boolean = true
            }
        )

        guard.recordVerification(
            successfulVerificationReceipt("plain-workspace", "verification-plain").copy(
                projectFingerprintChecked = true
            )
        )

        assertEquals(0, fingerprintReads)
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
        val prepareProperties = definitions
            .first { it.descriptor.id == AgentMobileProjectNativeTools.CLONE }
            .descriptor.inputSchema.document["properties"] as Map<*, *>
        assertTrue("feature_branch" in prepareProperties)
        assertEquals(
            AgentNativeToolRisk.HIGH,
            definitions.first { it.descriptor.id == AgentMobileProjectNativeTools.PUBLISH_PULL_REQUEST }.descriptor.risk
        )
        assertEquals(
            AgentNativeToolRisk.HIGH,
            definitions.first { it.descriptor.id == AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST }.descriptor.risk
        )
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

    private fun inMemoryTicketStore(
        tickets: MutableMap<String, AgentProjectVerificationTicket>
    ): AgentProjectVerificationTicketStore = object : AgentProjectVerificationTicketStore {
        override fun read(workspaceId: String): AgentProjectVerificationTicket? = tickets[workspaceId]
        override fun write(ticket: AgentProjectVerificationTicket) {
            tickets[ticket.workspaceId] = ticket
        }
        override fun remove(workspaceId: String) {
            tickets.remove(workspaceId)
        }
    }

}

private class TestJGitBackend(
    private val projectRoot: File,
    private val onClone: (String) -> Unit = {},
    private val omitCommitOutput: Boolean = false,
    private val atomicCommitObservation: Boolean = false,
    private val atomicPushObservation: Boolean = false,
    private val atomicCheckoutObservation: Boolean = false,
    private val atomicPullObservation: Boolean = false,
    private val atomicFetchObservation: Boolean = false,
    private val atomicCommitPushObservation: Boolean = false,
    private val simulatePush: Boolean = false
) : AgentProjectGitBackend {
    override val supportsAtomicCommitObservation: Boolean = atomicCommitObservation
    override val supportsAtomicPushObservation: Boolean = atomicPushObservation
    override val supportsAtomicCommitPushObservation: Boolean = atomicCommitPushObservation
    var fullInspectionCount: Int = 0
        private set
    var metadataInspectionCount: Int = 0
        private set
    var remoteInspectionCount: Int = 0
        private set
    var lastExpectedCommitFingerprint: String = ""
        private set
    var atomicPushCount: Int = 0
        private set
    var atomicCheckoutCount: Int = 0
        private set
    var atomicPullCount: Int = 0
        private set
    var lastExpectedPullRepositoryUrl: String = ""
        private set
    var atomicFetchCount: Int = 0
        private set
    var lastExpectedFetchRepositoryUrl: String = ""
        private set
    var atomicCommitPushCount: Int = 0
        private set
    var lastExpectedFinalizeFingerprint: String = ""
        private set
    var lastExpectedFinalizeRepositoryUrl: String = ""
        private set
    var lastExpectedPushFingerprint: String = ""
        private set
    var lastExpectedPushHead: String = ""
        private set
    var lastExpectedPushRepositoryUrl: String = ""
        private set

    fun resetInspectionCounts() {
        fullInspectionCount = 0
        metadataInspectionCount = 0
        remoteInspectionCount = 0
        atomicCommitPushCount = 0
    }

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

    override fun inspect(workspaceId: String): AgentProjectRepositorySnapshot {
        fullInspectionCount += 1
        return snapshot(workspaceId, includeWorkingTree = true)
    }

    override fun inspectMetadata(workspaceId: String): AgentProjectRepositorySnapshot {
        metadataInspectionCount += 1
        return snapshot(workspaceId, includeWorkingTree = false)
    }

    private fun snapshot(workspaceId: String, includeWorkingTree: Boolean): AgentProjectRepositorySnapshot =
        Git.open(File(projectRoot, workspaceId)).use { git ->
            val status = git.status().call()
            AgentProjectRepositorySnapshot(
                workspaceId = workspaceId,
                repositoryUrl = git.repository.config.getString("remote", "origin", "url").orEmpty(),
                branch = git.repository.branch.orEmpty(),
                headCommit = git.repository.resolve("HEAD")?.name.orEmpty(),
                clean = status.isClean,
                staged = if (includeWorkingTree) (status.added + status.changed + status.removed).sorted() else emptyList(),
                modified = if (includeWorkingTree) (status.modified + status.missing).sorted() else emptyList(),
                untracked = if (includeWorkingTree) status.untracked.sorted() else emptyList(),
                conflicting = if (includeWorkingTree) status.conflicting.sorted() else emptyList(),
                workingTreeInspected = includeWorkingTree
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

    override fun remoteUrl(workspaceId: String, remote: String): String {
        remoteInspectionCount += 1
        return Git.open(File(projectRoot, workspaceId)).use { git ->
            git.repository.config.getString("remote", remote, "url").orEmpty()
        }
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

    override fun checkoutBranchAndInspect(
        workspaceId: String,
        branch: String,
        create: Boolean,
        baseRef: String
    ): AgentProjectRepositorySnapshot {
        if (!atomicCheckoutObservation) {
            return super<AgentProjectGitBackend>.checkoutBranchAndInspect(
                workspaceId,
                branch,
                create,
                baseRef
            )
        }
        atomicCheckoutCount += 1
        checkoutBranchAt(workspaceId, branch, create, baseRef)
        return snapshot(workspaceId, includeWorkingTree = true)
    }

    override fun fetch(
        workspaceId: String,
        remote: String,
        ref: String,
        cancellationToken: AgentNativeToolCancellationToken
    ): List<String> = Git.open(File(projectRoot, workspaceId)).use { git ->
        val command = git.fetch().setRemote(remote)
        if (ref.isNotBlank()) {
            val refSpec = if (ref.contains(':')) {
                ref
            } else {
                val branch = ref.removePrefix("refs/heads/")
                "refs/heads/$branch:refs/remotes/$remote/$branch"
            }
            command.setRefSpecs(refSpec)
        }
        command.call()
        git.repository.refDatabase.getRefsByPrefix("refs/remotes/$remote/")
            .map { it.name.removePrefix("refs/remotes/") }
    }

    override fun fetchFromTrustedRemote(
        workspaceId: String,
        remote: String,
        ref: String,
        cancellationToken: AgentNativeToolCancellationToken,
        expectedRepositoryUrl: String
    ): List<String> {
        if (!atomicFetchObservation) {
            return super<AgentProjectGitBackend>.fetchFromTrustedRemote(
                workspaceId,
                remote,
                ref,
                cancellationToken,
                expectedRepositoryUrl
            )
        }
        atomicFetchCount += 1
        lastExpectedFetchRepositoryUrl = expectedRepositoryUrl
        return fetch(workspaceId, remote, ref, cancellationToken)
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

    override fun commitAndInspect(
        workspaceId: String,
        message: String,
        authorName: String,
        authorEmail: String,
        expectedFingerprint: String
    ): AgentProjectCommitBackendResult {
        if (!atomicCommitObservation) {
            return super<AgentProjectGitBackend>.commitAndInspect(
                workspaceId,
                message,
                authorName,
                authorEmail,
                expectedFingerprint
            )
        }
        lastExpectedCommitFingerprint = expectedFingerprint
        val before = snapshot(workspaceId, includeWorkingTree = true)
        val changed = (before.staged + before.modified + before.untracked + before.conflicting)
            .distinct()
            .sorted()
        val commit = commit(workspaceId, message, authorName, authorEmail)
        val repository = snapshot(workspaceId, includeWorkingTree = false)
        return AgentProjectCommitBackendResult(
            commit = commit.ifBlank { repository.headCommit },
            repository = repository,
            projectFingerprint = AgentProjectStateDigester.digest(projectRoot, workspaceId),
            changedFiles = changed
        )
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

    override fun pullAndInspect(
        workspaceId: String,
        remote: String,
        branch: String,
        cancellationToken: AgentNativeToolCancellationToken,
        expectedRepositoryUrl: String
    ): AgentProjectPullBackendResult {
        if (!atomicPullObservation) {
            return super<AgentProjectGitBackend>.pullAndInspect(
                workspaceId,
                remote,
                branch,
                cancellationToken,
                expectedRepositoryUrl
            )
        }
        atomicPullCount += 1
        lastExpectedPullRepositoryUrl = expectedRepositoryUrl
        val head = pull(workspaceId, remote, branch, cancellationToken)
        return AgentProjectPullBackendResult(head, snapshot(workspaceId, includeWorkingTree = false))
    }

    override fun push(
        workspaceId: String,
        remote: String,
        branch: String,
        force: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        expectedFingerprint: String,
        expectedHead: String
    ): List<String> = if (simulatePush) {
        listOf("refs/heads/$branch: OK")
    } else {
        Git.open(File(projectRoot, workspaceId)).use { git ->
            git.push().setRemote(remote).setForce(force).add(branch).call()
                .flatMap { result -> result.remoteUpdates.map { update -> "${update.remoteName}: ${update.status}" } }
        }
    }

    override fun pushAndInspect(
        workspaceId: String,
        remote: String,
        branch: String,
        force: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        expectedFingerprint: String,
        expectedHead: String,
        expectedRepositoryUrl: String
    ): AgentProjectPushBackendResult {
        if (!atomicPushObservation) {
            return super<AgentProjectGitBackend>.pushAndInspect(
                workspaceId,
                remote,
                branch,
                force,
                cancellationToken,
                expectedFingerprint,
                expectedHead,
                expectedRepositoryUrl
            )
        }
        atomicPushCount += 1
        lastExpectedPushFingerprint = expectedFingerprint
        lastExpectedPushHead = expectedHead
        lastExpectedPushRepositoryUrl = expectedRepositoryUrl
        val before = snapshot(workspaceId, includeWorkingTree = false)
        check(before.repositoryUrl == expectedRepositoryUrl) {
            "The phone project remote changed before publishing"
        }
        check(before.headCommit == expectedHead) {
            "The phone project HEAD changed before publishing"
        }
        check(AgentProjectStateDigester.digest(projectRoot, workspaceId) == expectedFingerprint) {
            "The phone project changed after commit; verify and commit it before publishing"
        }
        val messages = push(
            workspaceId,
            remote,
            branch,
            force,
            cancellationToken,
            expectedFingerprint,
            expectedHead
        )
        return AgentProjectPushBackendResult(
            repository = snapshot(workspaceId, includeWorkingTree = false),
            projectFingerprint = AgentProjectStateDigester.digest(projectRoot, workspaceId),
            remoteMessages = messages
        )
    }

    override fun commitPushAndInspect(
        workspaceId: String,
        message: String,
        authorName: String,
        authorEmail: String,
        remote: String,
        branch: String,
        force: Boolean,
        cancellationToken: AgentNativeToolCancellationToken,
        expectedFingerprint: String,
        expectedRepositoryUrl: String
    ): AgentProjectCommitPushBackendResult {
        if (!atomicCommitPushObservation) {
            return super<AgentProjectGitBackend>.commitPushAndInspect(
                workspaceId,
                message,
                authorName,
                authorEmail,
                remote,
                branch,
                force,
                cancellationToken,
                expectedFingerprint,
                expectedRepositoryUrl
            )
        }
        atomicCommitPushCount += 1
        lastExpectedFinalizeFingerprint = expectedFingerprint
        lastExpectedFinalizeRepositoryUrl = expectedRepositoryUrl
        val before = snapshot(workspaceId, includeWorkingTree = true)
        check(before.repositoryUrl == expectedRepositoryUrl) {
            "The phone project remote changed before publishing"
        }
        check(before.branch == branch) { "The phone project branch changed before publishing" }
        check(AgentProjectStateDigester.digest(projectRoot, workspaceId) == expectedFingerprint) {
            "The phone project changed after verification; run verification again before publishing"
        }
        val changed = (before.staged + before.modified + before.untracked + before.conflicting)
            .distinct()
            .sorted()
        val commit = commit(workspaceId, message, authorName, authorEmail)
        val committedFingerprint = AgentProjectStateDigester.digest(projectRoot, workspaceId)
        val messages = push(
            workspaceId,
            remote,
            branch,
            force,
            cancellationToken,
            expectedFingerprint,
            commit
        )
        return AgentProjectCommitPushBackendResult(
            commit = commit,
            repository = snapshot(workspaceId, includeWorkingTree = false),
            verifiedProjectFingerprint = expectedFingerprint,
            projectFingerprint = committedFingerprint,
            changedFiles = changed,
            remoteMessages = messages
        )
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
