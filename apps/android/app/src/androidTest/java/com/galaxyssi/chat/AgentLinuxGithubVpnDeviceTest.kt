package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in real-device proof that the phone Linux guest reaches GitHub through Android networking. */
@RunWith(AndroidJUnit4::class)
class AgentLinuxGithubVpnDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private lateinit var project: File

    @Before
    fun setUp() {
        assumeTrue(
            InstrumentationRegistry.getArguments().getString(LIVE_GITHUB_ARGUMENT) == "true"
        )
        project = File(
            context.filesDir,
            "agent-native-workspaces/linux-github-vpn-${UUID.randomUUID()}"
        ).apply {
            check(mkdirs() || isDirectory)
        }
    }

    @After
    fun tearDown() {
        if (::project.isInitialized) project.deleteRecursively()
    }

    @Test
    fun clonesPublicGithubRepositoryInsidePhoneLinuxGuest() {
        val runtime = AgentOnDeviceRuntimeLifecycle.ensureRunning(context)
        assertEquals(runtime.reason, AgentRuntimeLifecyclePhase.READY, runtime.phase)
        val workspaceId = project.name
        val manager = AgentOnDeviceRuntimeManager(context)
        val repository = AgentMobileProjectRepository(
            projectRoot = requireNotNull(project.parentFile),
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
            repositoryUrl = PUBLIC_REPOSITORY,
            branch = "master",
            depth = 1,
            replaceExisting = true,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )

        assertEquals("master", cloned.branch)
        assertTrue(cloned.clean)
        assertTrue(cloned.headCommit.matches(Regex("[0-9a-f]{40}")))
        assertTrue(File(project, "README").isFile)
        assertTrue(File(project, ".git").isDirectory)
        assertFalse(File(project, ".galaxyssi-runtime").exists())
    }

    private companion object {
        const val LIVE_GITHUB_ARGUMENT = "galaxyssi.liveGithub"
        const val PUBLIC_REPOSITORY = "https://github.com/octocat/Hello-World.git"
    }
}
