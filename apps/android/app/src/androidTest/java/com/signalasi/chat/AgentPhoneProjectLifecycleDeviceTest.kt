package com.signalasi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.zip.ZipFile
import org.eclipse.jgit.storage.file.FileRepositoryBuilder
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in real-device proof for the complete phone-native project lifecycle. */
@RunWith(AndroidJUnit4::class)
class AgentPhoneProjectLifecycleDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var project: File
    private lateinit var fixtureRoot: File

    @Before
    fun setUp() {
        assumeTrue(
            InstrumentationRegistry.getArguments().getString(LIVE_PROJECT_ARGUMENT) == "true"
        )
        val id = "phone-project-lifecycle-${UUID.randomUUID()}"
        project = File(context.filesDir, "agent-native-workspaces/$id").apply {
            check(mkdirs() || isDirectory)
        }
        fixtureRoot = File(context.cacheDir, id).apply {
            check(mkdirs() || isDirectory)
        }
    }

    @After
    fun tearDown() {
        if (::project.isInitialized) project.deleteRecursively()
        if (::fixtureRoot.isInitialized) fixtureRoot.deleteRecursively()
    }

    @Test
    fun clonesEditsVerifiesRecoversArchivesCommitsAndPushesOnPhone() {
        val bootstrap = AgentEmbeddedRuntimeBootstrap.ensureInstalled(context)
        assertTrue("The APK must contain the default phone Linux runtime", bootstrap.bundled)
        val lifecycle = AgentOnDeviceRuntimeLifecycle.ensureRunning(context)
        assertEquals(lifecycle.reason, AgentRuntimeLifecyclePhase.READY, lifecycle.phase)
        val workspaceId = project.name
        val manager = AgentOnDeviceRuntimeManager(context)
        val credentialProvider = AgentProjectCredentialProvider { "local-device-test-token" }
        val repository = AgentMobileProjectRepository(
            projectRoot = requireNotNull(project.parentFile),
            credentialProvider = credentialProvider,
            repositoryPolicy = { true },
            gitBackend = AgentLinuxProjectCloneBackend(
                runtime = object : AgentProjectLinuxRuntime {
                    override fun execute(request: AgentRuntimeExecutionRequest) = manager.execute(request)

                    override fun rollback(workspaceId: String, checkpointId: String) {
                        manager.rollbackWorkspace(workspaceId, checkpointId)
                    }
                },
                credentialProvider = credentialProvider
            )
        )
        val registry = AgentPhoneNativeToolCatalog.defaultRegistry(
            context = context,
            screenProvider = {
                ScreenContext(
                    foregroundApp = context.packageName,
                    pageTitle = "Phone project lifecycle test"
                )
            }
        )
        val bundledTools = invokeRuntime(
            registry = registry,
            workspaceId = workspaceId,
            language = AgentRuntimeLanguage.SHELL,
            source = """
                set -u
                missing=0
                for tool in git ssh curl wget zip unzip tar; do
                  if path="${'$'}(command -v "${'$'}tool" 2>/dev/null)"; then
                    printf '%s=%s\n' "${'$'}tool" "${'$'}path"
                  else
                    printf '%s=missing\n' "${'$'}tool"
                    missing=1
                  fi
                done
                if [ "${'$'}missing" -eq 0 ]; then git --version; fi
                exit "${'$'}missing"
            """.trimIndent(),
            artifacts = emptyList()
        )
        assertTrue("${bundledTools.message}: ${bundledTools.output}", bundledTools.isSuccess)
        assertTrue(bundledTools.output["stdout"].toString().contains("git version"))

        val cloned = repository.clone(
            workspaceId = workspaceId,
            repositoryUrl = PUBLIC_REPOSITORY,
            branch = "master",
            depth = 1,
            replaceExisting = true,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )
        assertTrue(cloned.clean)
        repository.checkoutBranch(workspaceId, TEST_BRANCH, create = true)

        val successful = invokeRuntime(
            registry = registry,
            workspaceId = workspaceId,
            source = """
                from pathlib import Path

                source = 'def answer(values):\n    return sum(values)\n\nif __name__ == "__main__":\n    print(answer([7, 11, 24]))\n'
                Path('phone_agent.py').write_text(source, encoding='utf-8')
                namespace = {}
                exec(compile(source, 'phone_agent.py', 'exec'), namespace)
                assert namespace['answer']([7, 11, 24]) == 42
                Path('verification.txt').write_text('verified=42\n', encoding='utf-8')
                print('verified=42')
            """.trimIndent(),
            artifacts = listOf("phone_agent.py", "verification.txt")
        )
        assertTrue(successful.message, successful.isSuccess)
        assertEquals("verified=42\n", successful.output["stdout"])
        assertProjectArchive(successful, setOf("phone_agent.py", "verification.txt"))

        val failed = invokeRuntime(
            registry = registry,
            workspaceId = workspaceId,
            source = """
                from pathlib import Path
                Path('failed-candidate.txt').write_text('preserve for replan', encoding='utf-8')
                raise RuntimeError('intentional lifecycle observation')
            """.trimIndent(),
            artifacts = emptyList()
        )
        assertEquals(AgentNativeToolResultStatus.FAILED, failed.status)
        assertEquals("persisted_with_failure", failed.output["workspace_disposition"])
        assertEquals("", failed.output["checkpoint_id"])
        assertTrue((failed.output["artifacts"] as? Iterable<*>)?.none() == true)
        assertEquals("preserve for replan", File(project, "failed-candidate.txt").readText())
        assertEquals("verified=42\n", File(project, "verification.txt").readText())
        File(project, "failed-candidate.txt").delete()

        val snapshot = repository.inspect(workspaceId)
        assertFalse(snapshot.clean)
        assertTrue("phone_agent.py" in snapshot.untracked)
        val commit = repository.commit(
            workspaceId = workspaceId,
            message = "Verify phone-native project lifecycle",
            authorName = "SignalASI",
            authorEmail = "signalasi@hotmail.com"
        )

        val bareRemote = File(project, ".signalasi-test-remote.git")
        File(project, ".git/info/exclude").appendText("\n.signalasi-test-remote.git/\n")
        val remoteSetup = invokeRuntime(
            registry = registry,
            workspaceId = workspaceId,
            language = AgentRuntimeLanguage.SHELL,
            source = """
                set -eu
                remote="${'$'}PWD/.signalasi-test-remote.git"
                git -c safe.directory="${'$'}PWD" init --bare "${'$'}remote"
                git --git-dir="${'$'}remote" config receive.shallowUpdate true
                git config --global --add safe.directory "${'$'}remote"
                git -c safe.directory="${'$'}PWD" remote set-url origin "${'$'}remote"
            """.trimIndent(),
            artifacts = emptyList()
        )
        assertTrue(remoteSetup.message, remoteSetup.isSuccess)
        repository.push(
            workspaceId = workspaceId,
            remote = "origin",
            branch = TEST_BRANCH,
            force = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE
        )
        invokeRuntime(
            registry = registry,
            workspaceId = workspaceId,
            language = AgentRuntimeLanguage.SHELL,
            source = "git config --global --unset-all safe.directory \"${'$'}PWD/.signalasi-test-remote.git\" || true",
            artifacts = emptyList()
        )
        FileRepositoryBuilder().setGitDir(bareRemote).setBare().build().use { remote ->
            assertEquals(commit.commit, remote.resolve("refs/heads/$TEST_BRANCH")?.name)
        }
    }

    private fun invokeRuntime(
        registry: AgentNativeToolRegistry,
        workspaceId: String,
        language: AgentRuntimeLanguage = AgentRuntimeLanguage.PYTHON,
        source: String,
        artifacts: List<String>
    ): AgentNativeToolResult {
        val descriptor = requireNotNull(registry.lookup(AgentOnDeviceRuntimeTools.EXECUTE)).descriptor
        return registry.invoke(
            AgentOnDeviceRuntimeTools.EXECUTE,
            mapOf(
                "language" to language.wireValue,
                "source" to source,
                "arguments" to emptyList<String>(),
                "timeout_ms" to 180_000L,
                "network_enabled" to false,
                "allowed_network_domains" to emptyList<String>(),
                "artifact_paths" to artifacts,
                "verification_kind" to "test"
            ),
            AgentNativeToolInvocationContext(
                invocationId = "lifecycle-${UUID.randomUUID()}",
                sessionId = workspaceId,
                conversationId = workspaceId,
                turnId = "turn-${UUID.randomUUID()}",
                idempotencyKey = "lifecycle-${UUID.randomUUID()}",
                grantedPermissions = descriptor.requiredPermissions.mapTo(linkedSetOf()) { it.id },
                grantedConsents = descriptor.requiredConsents.mapTo(linkedSetOf()) { it.id },
                attributes = mapOf("workspace_id" to workspaceId)
            )
        )
    }

    private fun assertProjectArchive(result: AgentNativeToolResult, expectedPaths: Set<String>) {
        val artifacts = result.output["artifacts"] as? Iterable<*> ?: emptyList<Any?>()
        val archive = artifacts.mapNotNull { it as? Map<*, *> }
            .singleOrNull { it["artifact_kind"] == "project_archive" }
        assertTrue("Missing project archive in $artifacts", archive != null)
        ZipFile(File(requireNotNull(archive)["host_path"].toString())).use { zip ->
            val names = zip.entries().asSequence().map { it.name }.toSet()
            assertTrue("Missing project files in $names", names.containsAll(expectedPaths))
        }
    }

    private companion object {
        const val LIVE_PROJECT_ARGUMENT = "signalasi.liveProjectLifecycle"
        const val PUBLIC_REPOSITORY = "https://github.com/octocat/Hello-World.git"
        const val TEST_BRANCH = "test/phone-native-lifecycle"
    }
}
