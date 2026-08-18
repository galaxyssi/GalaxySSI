package com.signalasi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.storage.file.FileRepositoryBuilder
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Real-device coverage for app-private Git projects and trusted GitHub access. */
@RunWith(AndroidJUnit4::class)
class AgentMobileProjectDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var root: File
    private val persistentWorkspaces = mutableListOf<File>()

    @Before
    fun setUp() {
        root = File(context.cacheDir, "mobile-project-device-${UUID.randomUUID()}").apply {
            check(mkdirs() || isDirectory)
        }
    }

    @After
    fun tearDown() {
        root.deleteRecursively()
        persistentWorkspaces.forEach(File::deleteRecursively)
    }

    @Test
    fun completesPrivateCloneBranchCommitAndPushLifecycle() {
        val source = File(root, "source")
        val remote = File(root, "remote.git")
        val projects = File(root, "projects")
        Git.init().setDirectory(source).setInitialBranch("main").call().use { git ->
            File(source, "README.md").writeText("# Phone project fixture\n")
            git.add().addFilepattern(".").call()
            git.commit()
                .setMessage("Create phone fixture")
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
        val repository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "device-local-fixture-token" },
            repositoryPolicy = { true }
        )

        val cloned = repository.clone(
            workspaceId = "phone-private-project",
            repositoryUrl = remote.toURI().toString(),
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        assertEquals("main", cloned.branch)
        assertTrue(cloned.clean)

        repository.checkoutBranch("phone-private-project", "feature/phone-answer", create = true)
        val runtime = AgentRuntimeWorkspaceManager(File(root, "runtime"), projects, forTesting = true)
        val prepared = runtime.prepare(runtimeRequest("phone-private-project"))
        val candidate = File(prepared.directory, "src/PhoneAnswer.kt").apply {
            requireNotNull(parentFile).mkdirs()
            writeText("fun phoneAnswer() = 42\n")
        }
        assertTrue(candidate.isFile)
        runtime.commitProject(
            prepared = prepared,
            byteLimit = 8L * 1024L * 1024L,
            checkpointId = "before-phone-answer"
        )
        assertFalse(File(projects, "phone-private-project/.signalasi-runtime").exists())
        assertFalse(File(projects, "phone-private-project/main.sh").exists())
        assertFalse(repository.inspect("phone-private-project").clean)
        val commit = repository.commit(
            workspaceId = "phone-private-project",
            message = "Add phone answer",
            authorName = "SignalASI",
            authorEmail = "signalasi@hotmail.com"
        )
        repository.push(
            workspaceId = "phone-private-project",
            remote = "origin",
            branch = commit.branch,
            force = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE
        )

        FileRepositoryBuilder().setGitDir(remote).setBare().build().use { bare ->
            assertEquals(commit.commit, bare.resolve("refs/heads/feature/phone-answer")?.name)
        }
    }

    @Test
    fun shallowClonesTrustedGithubRepository() {
        val projects = File(root, "github-projects")
        val repository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "" }
        )

        val snapshot = repository.clone(
            workspaceId = "github-network-project",
            repositoryUrl = "https://github.com/octocat/Hello-World.git",
            branch = "",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )

        assertTrue(snapshot.clean)
        assertTrue(snapshot.headCommit.matches(Regex("[0-9a-f]{40}")))
        assertEquals("https://github.com/octocat/Hello-World.git", snapshot.repositoryUrl)
        assertTrue(File(projects, "github-network-project/README").isFile)
    }

    @Test
    fun clonesRepositoryDirectlyInsideThePersistentPhoneLinuxRuntime() {
        val runtime = AgentOnDeviceRuntimeLifecycle.ensureRunning(context)
        assertEquals(runtime.reason, AgentRuntimeLifecyclePhase.READY, runtime.phase)
        val workspaceId = "linux-clone-${UUID.randomUUID()}"
        val projects = File(context.filesDir, "agent-native-workspaces")
        val project = File(projects, workspaceId).apply {
            check(mkdirs() || isDirectory)
            persistentWorkspaces += this
        }
        val source = File(root, "linux-clone-source")
        Git.init().setDirectory(source).setInitialBranch("main").call().use { git ->
            File(source, "README.md").writeText("# Cloned by phone Linux\n")
            git.add().addFilepattern(".").call()
            git.commit()
                .setMessage("Create Linux clone fixture")
                .setAuthor("SignalASI", "signalasi@hotmail.com")
                .setCommitter("SignalASI", "signalasi@hotmail.com")
                .call()
        }
        Git.cloneRepository()
            .setURI(source.toURI().toString())
            .setDirectory(File(project, "fixture.git"))
            .setBare(true)
            .call()
            .close()
        val manager = AgentOnDeviceRuntimeManager(context)
        val repository = AgentMobileProjectRepository(
            projectRoot = projects,
            credentialProvider = AgentProjectCredentialProvider { "" },
            repositoryPolicy = { true },
            gitBackend = AgentLinuxProjectCloneBackend(
                runtime = object : AgentProjectLinuxRuntime {
                    override fun execute(request: AgentRuntimeExecutionRequest) = manager.execute(request)

                    override fun rollback(workspaceId: String, checkpointId: String) {
                        manager.rollbackWorkspace(workspaceId, checkpointId)
                    }
                },
                credentialProvider = AgentProjectCredentialProvider { "" }
            )
        )

        val cloned = repository.clone(
            workspaceId = workspaceId,
            repositoryUrl = "fixture.git",
            branch = "main",
            depth = 1,
            replaceExisting = true,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )

        assertEquals("main", cloned.branch)
        assertTrue(cloned.clean)
        assertEquals("# Cloned by phone Linux\n", File(project, "README.md").readText())
        assertTrue(File(project, ".git").isDirectory)
        assertFalse(File(project, "fixture.git").exists())
        assertFalse(File(project, ".signalasi-runtime").exists())
    }

    private fun runtimeRequest(workspaceId: String) = AgentRuntimeExecutionRequest(
        language = AgentRuntimeLanguage.SHELL,
        source = "printf '42\\n' > verification.txt",
        arguments = emptyList(),
        timeoutMillis = 1_000L,
        networkEnabled = false,
        artifactPaths = listOf("verification.txt"),
        workspaceId = workspaceId,
        requestId = "runtime-change",
        resourceLimits = AgentRuntimeResourceLimits(
            wallClockMillis = 1_000L,
            cpuMillis = 750L,
            memoryBytes = 64L * 1024L * 1024L,
            diskBytes = 8L * 1024L * 1024L,
            maxProcesses = 8,
            maxOutputBytes = 64L * 1024L,
            maxArtifactBytes = 4L * 1024L * 1024L
        )
    )
}
