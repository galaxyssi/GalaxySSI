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
            repositoryPolicy = { true }
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
    fun validatesPublicRepositoryAndRefBoundaries() {
        assertTrue(AgentMobileProjectRepository.isTrustedRepositoryUrl("https://github.com/signalasi/SignalASI.git"))
        assertFalse(AgentMobileProjectRepository.isTrustedRepositoryUrl("http://github.com/signalasi/SignalASI.git"))
        assertFalse(AgentMobileProjectRepository.isTrustedRepositoryUrl("https://token@github.com/signalasi/SignalASI.git"))
        assertFalse(AgentMobileProjectRepository.isTrustedRepositoryUrl("https://example.com/signalasi/SignalASI.git"))
        assertTrue(runCatching { AgentMobileProjectRepository.validateRefName("feature/mobile-agent") }.isSuccess)
        assertTrue(runCatching { AgentMobileProjectRepository.validateRefName("../main") }.isFailure)
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
}
