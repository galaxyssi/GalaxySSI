package com.signalasi.chat

import java.io.File
import java.nio.file.Files
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.storage.file.FileRepositoryBuilder
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
        val backend = AgentLinuxProjectGitBackend(
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

        assertEquals(AgentRuntimeLanguage.PYTHON, captured.language)
        assertTrue(captured.networkEnabled)
        assertTrue("github.com" in captured.allowedNetworkDomains)
        val shellSource = decodedShellSource(captured.source)
        assertTrue("git -c credential.helper= fetch --depth 1 origin" in shellSource)
        assertTrue("git checkout -q -B" in shellSource)
        assertTrue("if [ -d .git ]" in shellSource)
        assertTrue("preserve_worktree_changes" in shellSource)
        assertFalse("cp -a" in shellSource)
        assertFalse("apt-get" in shellSource)
        assertFalse("dpkg" in shellSource)
        assertTrue("SignalASI linux-base does not contain Git" in shellSource)
        assertTrue("git -c safe.directory=\"${'$'}PWD\"" in shellSource)
        assertFalse("safe.directory '*'" in shellSource)
        assertFalse("git config --global" in shellSource)
        assertTrue("! -name '.signalasi-tools'" in shellSource)
        assertTrue("! -name '.signalasi-inputs'" in shellSource)
        assertTrue(".signalasi-runtime/git-askpass.sh" !in shellSource)
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
            AgentLinuxProjectGitBackend(runtime, AgentProjectCredentialProvider { "" }).clone(
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
        val backend = AgentLinuxProjectGitBackend(runtime, AgentProjectCredentialProvider { "" })

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
                    val sourceFile = File(root, "git-launcher.py").apply { writeText(request.source) }
                    val processBuilder = ProcessBuilder("python", sourceFile.absolutePath)
                        .directory(workspace)
                        .redirectErrorStream(false)
                    processBuilder.environment()["HOME"] = File(root, "git-home").apply { mkdirs() }.absolutePath
                    processBuilder.environment()["SIGNALASI_BASE_GUEST_SHELL"] = requireNotNull(bash).absolutePath
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
            val backend = AgentLinuxProjectGitBackend(runtime, AgentProjectCredentialProvider { "" })
            backend.clone(
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
            assertFalse(File(root, "git-home/.gitconfig").exists())

            Git.open(source).use { git ->
                File(source, "README.md").writeText("# Updated without copying\n")
                git.add().addFilepattern("README.md").call()
                git.commit()
                    .setMessage("Update fixture")
                    .setAuthor("SignalASI", "signalasi@hotmail.com")
                    .setCommitter("SignalASI", "signalasi@hotmail.com")
                    .call()
                git.push().setRemote(remoteUrl).add("refs/heads/main:refs/heads/main").call()
            }
            backend.clone(
                workspaceId = "smoke",
                repositoryUrl = remoteUrl,
                branch = "main",
                depth = 1,
                replaceExisting = false,
                cancellationToken = AgentNativeToolCancellationToken.NONE,
                progress = { _, _, _ -> }
            )
            assertEquals("# Updated without copying", File(workspace, "README.md").readText().trim())

            val localOnly = File(workspace, "local-only.txt").apply { writeText("preserve me") }
            backend.clone(
                workspaceId = "smoke",
                repositoryUrl = remoteUrl,
                branch = "main",
                depth = 1,
                replaceExisting = true,
                cancellationToken = AgentNativeToolCancellationToken.NONE,
                progress = { _, _, _ -> }
            )
            assertEquals("preserve me", localOnly.readText())

            backend.checkoutBranch("smoke", "feature/linux-git", create = true)
            File(workspace, "result.txt").writeText("phone linux\n")
            val commit = backend.commit(
                workspaceId = "smoke",
                message = "Verify Linux Git backend",
                authorName = "SignalASI",
                authorEmail = "signalasi@hotmail.com"
            )
            assertTrue(Regex("[0-9a-f]{40}").matches(commit))
            val push = backend.push(
                workspaceId = "smoke",
                remote = "origin",
                branch = "feature/linux-git",
                force = false,
                cancellationToken = AgentNativeToolCancellationToken.NONE
            )
            assertTrue(push.isNotEmpty())
            FileRepositoryBuilder().setGitDir(remote).setBare().build().use { bare ->
                val remoteCommit = bare.resolve("refs/heads/feature/linux-git")?.name
                assertEquals("push=$push refs=${bare.refDatabase.getRefsByPrefix("refs/heads/")}", commit, remoteCommit)
            }
        } finally {
            root.deleteRecursively()
        }
    }

    private fun decodedShellSource(pythonSource: String): String {
        val encoded = Regex("base64\\.b64decode\\(\"([^\"]+)\"\\)")
            .find(pythonSource)?.groupValues?.get(1)
            ?: error("Linux Git launcher payload is missing")
        return String(java.util.Base64.getDecoder().decode(encoded), Charsets.UTF_8)
    }
}
