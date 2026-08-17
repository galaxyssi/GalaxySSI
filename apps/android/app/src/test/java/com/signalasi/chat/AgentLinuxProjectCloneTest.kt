package com.signalasi.chat

import java.io.File
import java.nio.file.Files
import org.eclipse.jgit.api.Git
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

class AgentLinuxProjectCloneTest {
    @Test
    fun clonesInsidePhoneLinuxAndKeepsTheCredentialOutOfSource() {
        lateinit var captured: AgentRuntimeExecutionRequest
        val runtime = object : AgentProjectLinuxRuntime {
            override fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse {
                captured = request
                return AgentRuntimeExecutionResponse(exitCode = 0, stdout = "## main", stderr = "", durationMillis = 20)
            }

            override fun rollback(workspaceId: String, checkpointId: String) = Unit
        }
        val backend = AgentLinuxProjectCloneBackend(
            runtime = runtime,
            credentialProvider = AgentProjectCredentialProvider { "private-token" }
        )

        backend.clone(
            workspaceId = "phone-project",
            repositoryUrl = "https://github.com/signalasi/SignalASI.git",
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )

        assertEquals(AgentRuntimeLanguage.SHELL, captured.language)
        assertTrue(captured.networkEnabled)
        assertTrue("github.com" in captured.allowedNetworkDomains)
        assertTrue("git -c credential.helper= fetch --depth 1 origin 'refs/heads/main'" in captured.source)
        assertTrue("git checkout -q -B 'main' FETCH_HEAD" in captured.source)
        assertFalse("cp -a" in captured.source)
        assertTrue("apt-get -o DPkg::Lock::Timeout=300 install" in captured.source)
        assertTrue("dpkg --configure -a" in captured.source)
        assertEquals(2, Regex("if ! git_runtime_ready; then").findAll(captured.source).count())
        assertTrue("ca-certificates.crt" in captured.source)
        assertTrue("mkdir -p /root/.cache/tmp" in captured.source)
        assertTrue(".signalasi-runtime/git-askpass.sh" !in captured.source)
        assertFalse("private-token" in captured.source)
        assertEquals("private-token", captured.secretEnvironment["SIGNALASI_GITHUB_TOKEN"])
    }

    @Test
    fun reportsCertificateRecoveryGuidanceAfterAnUnrecoverableTlsFailure() {
        val runtime = object : AgentProjectLinuxRuntime {
            override fun execute(request: AgentRuntimeExecutionRequest) = AgentRuntimeExecutionResponse(
                exitCode = 128,
                stdout = "",
                stderr = "fatal: Problem with the SSL CA cert (path? access rights?)",
                durationMillis = 50
            )

            override fun rollback(workspaceId: String, checkpointId: String) = Unit
        }

        val failure = runCatching {
            AgentLinuxProjectCloneBackend(runtime, AgentProjectCredentialProvider { "" }).clone(
                workspaceId = "phone-project",
                repositoryUrl = "https://github.com/signalasi/SignalASI.git",
                branch = "main",
                depth = 1,
                replaceExisting = true,
                cancellationToken = AgentNativeToolCancellationToken.NONE,
                progress = { _, _, _ -> }
            )
        }.exceptionOrNull()

        assertTrue(failure?.message.orEmpty().contains("certificate store"))
    }

    @Test
    fun reportsVpnGuidanceAndRestoresThePreviousProjectAfterNetworkFailure() {
        val rollbacks = mutableListOf<Pair<String, String>>()
        val runtime = object : AgentProjectLinuxRuntime {
            override fun execute(request: AgentRuntimeExecutionRequest) = AgentRuntimeExecutionResponse(
                exitCode = 128,
                stdout = "",
                stderr = "fatal: unable to access repository: Could not resolve host: github.com",
                durationMillis = 50,
                checkpointId = "before-clone"
            )

            override fun rollback(workspaceId: String, checkpointId: String) {
                rollbacks += workspaceId to checkpointId
            }
        }
        val backend = AgentLinuxProjectCloneBackend(runtime, AgentProjectCredentialProvider { "" })

        val failure = runCatching {
            backend.clone(
                workspaceId = "phone-project",
                repositoryUrl = "https://github.com/signalasi/SignalASI.git",
                branch = "",
                depth = 1,
                replaceExisting = true,
                cancellationToken = AgentNativeToolCancellationToken.NONE,
                progress = { _, _, _ -> }
            )
        }.exceptionOrNull()

        assertTrue(failure?.message.orEmpty().contains("phone VPN includes SignalASI"))
        assertEquals(listOf("phone-project" to "before-clone"), rollbacks)
    }

    @Test
    fun generatedLinuxCloneScriptProducesAUsableRepository() {
        val bash = listOf(
            File("/bin/bash"),
            File("C:/Program Files/Git/bin/bash.exe"),
            File("C:/msys64/usr/bin/bash.exe")
        ).firstOrNull(File::isFile)
        assumeTrue("A Bash runtime is required for the clone script smoke test", bash != null)
        val root = Files.createTempDirectory("signalasi-linux-clone-").toFile()
        try {
            val source = File(root, "source")
            val remote = File(root, "remote.git")
            val workspace = File(root, "workspace").apply { mkdirs() }
            Git.init().setDirectory(source).setInitialBranch("main").call().use { git ->
                File(source, "README.md").writeText("# Linux clone smoke test\n")
                git.add().addFilepattern(".").call()
                git.commit()
                    .setMessage("Create fixture")
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
            val remoteUrl = if (File.separatorChar == '\\') {
                "file:///${remote.canonicalPath.replace('\\', '/')}"
            } else {
                remote.toURI().toString()
            }
            val runtimeFiles = listOf(
                "request.json",
                "status.json",
                ".signalasi-checkpoint.json",
                ".signalasi-stdout",
                ".signalasi-stderr",
                ".signalasi-main"
            ).map { name -> File(workspace, name).apply { writeText(name) } }
            val runtimeTemp = File(workspace, ".tmp").apply { mkdirs() }
            val runtime = object : AgentProjectLinuxRuntime {
                override fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse {
                    val processBuilder = ProcessBuilder(requireNotNull(bash).absolutePath, "-c", request.source)
                        .directory(workspace)
                        .redirectErrorStream(false)
                    processBuilder.environment()["HOME"] = File(root, "git-home").apply { mkdirs() }.absolutePath
                    val process = processBuilder.start()
                    val stdout = process.inputStream.bufferedReader().readText()
                    val stderr = process.errorStream.bufferedReader().readText()
                    return AgentRuntimeExecutionResponse(
                        exitCode = process.waitFor(),
                        stdout = stdout,
                        stderr = stderr,
                        durationMillis = 0
                    )
                }

                override fun rollback(workspaceId: String, checkpointId: String) = Unit
            }
            AgentLinuxProjectCloneBackend(runtime, AgentProjectCredentialProvider { "" }).clone(
                workspaceId = "smoke",
                repositoryUrl = remoteUrl,
                branch = "main",
                depth = 1,
                replaceExisting = false,
                cancellationToken = AgentNativeToolCancellationToken.NONE,
                progress = { _, _, _ -> }
            )

            assertEquals("# Linux clone smoke test", File(workspace, "README.md").readText().trim())
            assertTrue(File(workspace, ".git").isDirectory)
            assertFalse(File(workspace, ".signalasi-runtime/repository").exists())
            assertFalse(File(workspace, ".signalasi-runtime/git-askpass.sh").exists())
            assertTrue(runtimeFiles.all(File::isFile))
            assertTrue(runtimeTemp.isDirectory)
            val gitConfig = File(root, "git-home/.gitconfig").readText()
            assertTrue(gitConfig.contains("[safe]"))
            assertTrue(gitConfig.contains("directory = "))
            assertFalse(gitConfig.contains("directory = *"))
        } finally {
            root.deleteRecursively()
        }
    }
}
