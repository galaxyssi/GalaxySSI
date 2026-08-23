package com.signalasi.chat

import java.io.File
import java.nio.file.Files
import java.util.Base64
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.storage.file.FileRepositoryBuilder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

class AgentLinuxProjectCloneTest {
    @Test
    fun stateFingerprintUsesGitChangesWithoutRequestingAProjectMutation() {
        lateinit var captured: AgentRuntimeExecutionRequest
        val expected = "b".repeat(64)
        val runtime = object : AgentProjectLinuxRuntime {
            override fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse {
                captured = request
                return AgentRuntimeExecutionResponse(0, "$expected\n", "", 5)
            }

            override fun rollback(workspaceId: String, checkpointId: String) = Unit
        }

        val actual = AgentLinuxProjectGitBackend(runtime, AgentProjectCredentialProvider { "" })
            .stateFingerprint("phone-project")

        assertEquals(expected, actual)
        assertFalse(captured.workspaceMutationExpected)
        assertTrue(captured.source.contains("git status --porcelain=v2"))
        assertTrue(captured.source.contains("git diff --no-ext-diff --binary HEAD"))
        assertTrue(captured.source.contains("git ls-files --others --exclude-standard -z"))
        assertTrue(captured.source.contains("xargs -0 -r"))
        assertTrue(captured.source.contains("hash-object --no-filters"))
        assertFalse(captured.source.contains("find ."))
    }

    @Test
    fun metadataInspectionDoesNotScanTheLargePhoneWorkingTree() {
        lateinit var captured: AgentRuntimeExecutionRequest
        val metadata = listOf(
            "__SIGNALASI_STATE__:cmVhZHk=",
            "__SIGNALASI_REMOTE__:aHR0cHM6Ly9naXRodWIuY29tL3NpZ25hbGFzaS9TaWduYWxBU0k=",
            "__SIGNALASI_BRANCH__:ZmVhdHVyZS90ZXN0",
            "__SIGNALASI_HEAD__:${"a".repeat(40).toByteArray().let(Base64.getEncoder()::encodeToString)}"
        ).joinToString("\n")
        val runtime = object : AgentProjectLinuxRuntime {
            override fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse {
                captured = request
                return AgentRuntimeExecutionResponse(0, metadata, "", 5)
            }

            override fun rollback(workspaceId: String, checkpointId: String) = Unit
        }

        val snapshot = AgentLinuxProjectGitBackend(runtime, AgentProjectCredentialProvider { "" })
            .inspectMetadata("phone-project")

        assertFalse(snapshot.workingTreeInspected)
        assertEquals("feature/test", snapshot.branch)
        assertFalse(captured.workspaceMutationExpected)
        assertFalse(captured.source.contains("git diff --name-only"))
        assertFalse(captured.source.contains("git ls-files --others"))
        assertEquals(null, snapshot.publicValue()["clean"])
    }

    @Test
    fun repositoryObservationReturnsStatusDiffAndLogFromOneLinuxExecution() {
        var executionCount = 0
        lateinit var captured: AgentRuntimeExecutionRequest
        fun encoded(value: String) = Base64.getEncoder().encodeToString(value.toByteArray())
        val output = listOf(
            "__SIGNALASI_STATE__:${encoded("ready")}",
            "__SIGNALASI_REMOTE__:${encoded("https://github.com/signalasi/SignalASI.git")}",
            "__SIGNALASI_BRANCH__:${encoded("feature/observe")}",
            "__SIGNALASI_HEAD__:${encoded("e".repeat(40))}",
            "__SIGNALASI_FINGERPRINT__:${encoded("f".repeat(64))}",
            "__SIGNALASI_MODIFIED__:${encoded("apps/android/App.kt")}",
            "__SIGNALASI_DIFF__:${encoded("diff --git a/App.kt b/App.kt")}",
            "__SIGNALASI_DIFF_TRUNCATED__:${encoded("false")}",
            "__SIGNALASI_LOG__:${encoded("${"e".repeat(40)}\tSignalASI\t2026-08-23T00:00:00Z\tImprove app")}",
            "__SIGNALASI_LOG_TRUNCATED__:${encoded("false")}"
        ).joinToString("\n")
        val runtime = object : AgentProjectLinuxRuntime {
            override fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse {
                executionCount += 1
                captured = request
                return AgentRuntimeExecutionResponse(0, output, "", 18)
            }

            override fun rollback(workspaceId: String, checkpointId: String) = Unit
        }

        val observation = AgentLinuxProjectGitBackend(runtime, AgentProjectCredentialProvider { "" }).observe(
            workspaceId = "phone-project",
            includeWorkingTree = true,
            includeDiff = true,
            includeLog = true,
            logRef = "HEAD",
            maxLogEntries = 20,
            maxDiffCharacters = 64 * 1024,
            maxLogCharacters = 64 * 1024
        )

        assertEquals(1, executionCount)
        assertEquals("feature/observe", observation.repository.branch)
        assertEquals("f".repeat(64), observation.projectFingerprint)
        assertEquals(listOf("apps/android/App.kt"), observation.repository.modified)
        assertTrue(observation.diff.startsWith("diff --git"))
        assertTrue(observation.recentCommits.contains("Improve app"))
        assertFalse(observation.diffTruncated)
        assertFalse(observation.recentCommitsTruncated)
        assertFalse(captured.workspaceMutationExpected)
        assertTrue(captured.requestId.startsWith("linux-git-observe-"))
        assertTrue(captured.source.contains("git diff --no-ext-diff --binary"))
        assertTrue(captured.source.contains("git log --date=iso-strict"))
        assertTrue(captured.source.contains("if [ -n \"${'$'}head\" ]"))
        assertTrue(captured.source.contains("emit_bounded_file"))
        assertEquals(2L * 1024L * 1024L, captured.resourceLimits.maxOutputBytes)
    }

    @Test
    fun cloneReturnsRepositoryMetadataWithoutASecondLinuxExecution() {
        lateinit var captured: AgentRuntimeExecutionRequest
        var executionCount = 0
        val metadata = listOf(
            "__SIGNALASI_STATE__:${Base64.getEncoder().encodeToString("ready".toByteArray())}",
            "__SIGNALASI_REMOTE__:${Base64.getEncoder().encodeToString("https://github.com/signalasi/SignalASI.git".toByteArray())}",
            "__SIGNALASI_BRANCH__:${Base64.getEncoder().encodeToString("main".toByteArray())}",
            "__SIGNALASI_HEAD__:${Base64.getEncoder().encodeToString("a".repeat(40).toByteArray())}"
        ).joinToString("\n")
        val runtime = object : AgentProjectLinuxRuntime {
            override fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse {
                executionCount += 1
                captured = request
                return AgentRuntimeExecutionResponse(exitCode = 0, stdout = metadata, stderr = "", durationMillis = 20)
            }

            override fun rollback(workspaceId: String, checkpointId: String) = Unit
        }
        val backend = AgentLinuxProjectGitBackend(
            runtime = runtime,
            credentialProvider = AgentProjectCredentialProvider { "private-token" }
        )

        val snapshot = backend.cloneAndInspect(
            workspaceId = "phone-project",
            repositoryUrl = "https://github.com/signalasi/SignalASI.git",
            branch = "main",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )

        assertEquals(1, executionCount)
        assertEquals(AgentProjectRepositoryState.READY, snapshot.state)
        assertEquals("https://github.com/signalasi/SignalASI.git", snapshot.repositoryUrl)
        assertEquals("main", snapshot.branch)
        assertEquals("a".repeat(40), snapshot.headCommit)
        assertFalse(snapshot.workingTreeInspected)
        assertEquals(AgentRuntimeLanguage.SHELL, captured.language)
        assertTrue(captured.networkEnabled)
        assertFalse(captured.discoverBuildArtifacts)
        assertTrue("github.com" in captured.allowedNetworkDomains)
        val shellSource = captured.source
        assertTrue("git -c credential.helper= fetch --depth 1 origin" in shellSource)
        assertTrue("git checkout -q -B" in shellSource)
        assertTrue("if git rev-parse --git-dir" in shellSource)
        assertTrue("preserve_worktree_changes" in shellSource)
        assertFalse("cp -a" in shellSource)
        assertFalse("dpkg" in shellSource)
        assertTrue("git -c safe.directory=\"${'$'}PWD\"" in shellSource)
        assertTrue("repair_partial_repository" in shellSource)
        assertTrue("--separate-git-dir=\"${'$'}git_metadata_dir\"" in shellSource)
        assertTrue("SIGNALASI_GIT_METADATA_ROOT:-/var/lib/signalasi/git" in shellSource)
        assertTrue("git rev-parse --git-path info/exclude" in shellSource)
        assertTrue("replace_existing=false" in shellSource)
        assertTrue("__SIGNALASI_STAGE__:install_git" in shellSource)
        assertTrue("apt-get install -y --no-install-recommends git openssh-client ca-certificates" in shellSource)
        assertTrue("__SIGNALASI_REMOTE__:" in shellSource)
        assertTrue("__SIGNALASI_BRANCH__:" in shellSource)
        assertTrue("__SIGNALASI_HEAD__:" in shellSource)
        assertFalse("safe.directory '*'" in shellSource)
        assertFalse("git config --global" in shellSource)
        assertTrue("! -name '.signalasi-tools'" in shellSource)
        assertTrue("! -name '.signalasi-inputs'" in shellSource)
        assertTrue(".signalasi-runtime/git-askpass.sh" !in shellSource)
        assertFalse("private-token" in captured.source)
        assertEquals("private-token", captured.secretEnvironment["SIGNALASI_GITHUB_TOKEN"])
    }

    @Test
    fun prepareUpdatesBaseAndChecksOutFeatureBranchInOneLinuxExecution() {
        lateinit var captured: AgentRuntimeExecutionRequest
        var executionCount = 0
        val metadata = listOf(
            "__SIGNALASI_STATE__:${Base64.getEncoder().encodeToString("ready".toByteArray())}",
            "__SIGNALASI_REMOTE__:${Base64.getEncoder().encodeToString("https://github.com/signalasi/SignalASI.git".toByteArray())}",
            "__SIGNALASI_BRANCH__:${Base64.getEncoder().encodeToString("improve/phone-loop".toByteArray())}",
            "__SIGNALASI_HEAD__:${Base64.getEncoder().encodeToString("d".repeat(40).toByteArray())}"
        ).joinToString("\n")
        val runtime = object : AgentProjectLinuxRuntime {
            override fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse {
                executionCount += 1
                captured = request
                return AgentRuntimeExecutionResponse(0, metadata, "", 20)
            }

            override fun rollback(workspaceId: String, checkpointId: String) = Unit
        }

        val snapshot = AgentLinuxProjectGitBackend(
            runtime = runtime,
            credentialProvider = AgentProjectCredentialProvider { "private-token" }
        ).prepareAndInspect(
            workspaceId = "phone-project",
            repositoryUrl = "https://github.com/signalasi/SignalASI.git",
            baseBranch = "main",
            featureBranch = "improve/phone-loop",
            depth = 1,
            replaceExisting = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            progress = { _, _, _ -> }
        )

        assertEquals(1, executionCount)
        assertEquals(AgentProjectRepositoryState.READY, snapshot.state)
        assertEquals("improve/phone-loop", snapshot.branch)
        assertTrue(captured.source.contains("git -c credential.helper= fetch --depth 50 origin"))
        assertTrue(captured.source.contains("feature_branch='improve/phone-loop'"))
        assertTrue(captured.source.contains("__SIGNALASI_STAGE__:checkout_feature_branch"))
        assertTrue(captured.source.contains("git merge --no-edit FETCH_HEAD"))
        assertTrue(captured.source.contains("git checkout -q -b \"${'$'}feature_branch\" FETCH_HEAD"))
        assertFalse(captured.source.contains("private-token"))
        assertEquals("private-token", captured.secretEnvironment["SIGNALASI_GITHUB_TOKEN"])
    }

    @Test
    fun commitReturnsRepositoryMetadataWithoutASecondLinuxExecution() {
        lateinit var captured: AgentRuntimeExecutionRequest
        var executionCount = 0
        val head = "c".repeat(40)
        val committedFingerprint = "d".repeat(64)
        val expectedFingerprint = "e".repeat(64)
        val metadata = listOf(
            "__SIGNALASI_STATE__:${Base64.getEncoder().encodeToString("ready".toByteArray())}",
            "__SIGNALASI_REMOTE__:${Base64.getEncoder().encodeToString("https://github.com/signalasi/SignalASI.git".toByteArray())}",
            "__SIGNALASI_BRANCH__:${Base64.getEncoder().encodeToString("feature/phone".toByteArray())}",
            "__SIGNALASI_HEAD__:${Base64.getEncoder().encodeToString(head.toByteArray())}",
            "__SIGNALASI_FINGERPRINT__:${Base64.getEncoder().encodeToString(committedFingerprint.toByteArray())}"
        ).joinToString("\n")
        val runtime = object : AgentProjectLinuxRuntime {
            override fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse {
                executionCount += 1
                captured = request
                return AgentRuntimeExecutionResponse(0, metadata, "", 12)
            }

            override fun rollback(workspaceId: String, checkpointId: String) = Unit
        }

        val result = AgentLinuxProjectGitBackend(runtime, AgentProjectCredentialProvider { "" })
            .commitAndInspect(
                workspaceId = "phone-project",
                message = "Improve phone development",
                authorName = "SignalASI",
                authorEmail = "signalasi@hotmail.com",
                expectedFingerprint = expectedFingerprint
            )

        assertEquals(1, executionCount)
        assertEquals(head, result.commit)
        assertEquals("feature/phone", result.repository.branch)
        assertEquals(AgentProjectRepositoryState.READY, result.repository.state)
        assertEquals(committedFingerprint, result.projectFingerprint)
        assertFalse(result.repository.workingTreeInspected)
        assertTrue(captured.source.contains("git commit -q -m"))
        assertTrue(captured.source.contains("__SIGNALASI_BRANCH__:"))
        assertTrue(captured.source.contains("__SIGNALASI_HEAD__:"))
        assertTrue(captured.source.contains("expected_fingerprint='$expectedFingerprint'"))
        assertTrue(captured.source.contains("changed after verification"))
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
    fun successfulLinuxGitMutationMayOmitCommitFromCapturedStdout() {
        val runtime = object : AgentProjectLinuxRuntime {
            override fun execute(request: AgentRuntimeExecutionRequest) = AgentRuntimeExecutionResponse(
                exitCode = 0,
                stdout = "",
                stderr = "",
                durationMillis = 20
            )

            override fun rollback(workspaceId: String, checkpointId: String) = Unit
        }
        val backend = AgentLinuxProjectGitBackend(runtime, AgentProjectCredentialProvider { "" })

        assertEquals(
            "",
            backend.pull(
                workspaceId = "phone-project",
                remote = "origin",
                branch = "main",
                cancellationToken = AgentNativeToolCancellationToken.NONE
            )
        )
        assertEquals(
            "",
            backend.commit(
                workspaceId = "phone-project",
                message = "Update project",
                authorName = "SignalASI",
                authorEmail = "signalasi@hotmail.com"
            )
        )
    }

    @Test
    fun fetchPublishesFetchHeadAsAStableBaseReference() {
        lateinit var captured: AgentRuntimeExecutionRequest
        val runtime = object : AgentProjectLinuxRuntime {
            override fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse {
                captured = request
                return AgentRuntimeExecutionResponse(
                    exitCode = 0,
                    stdout = "FETCH_HEAD:${"a".repeat(40)}\n",
                    stderr = "",
                    durationMillis = 20
                )
            }

            override fun rollback(workspaceId: String, checkpointId: String) = Unit
        }

        val refs = AgentLinuxProjectGitBackend(runtime, AgentProjectCredentialProvider { "" }).fetch(
            workspaceId = "phone-project",
            remote = "origin",
            ref = "main",
            cancellationToken = AgentNativeToolCancellationToken.NONE
        )

        assertEquals(
            listOf("FETCH_HEAD:${"a".repeat(40)}", "refs/remotes/origin/main"),
            refs
        )
        assertTrue(captured.source.contains("git rev-parse --verify FETCH_HEAD"))
        assertTrue(captured.source.contains("sed 's/^/FETCH_HEAD:/'"))
        assertTrue(captured.source.contains("+refs/heads/main:refs/remotes/origin/main"))
        assertTrue(captured.workspaceMutationExpected)
    }

    @Test
    fun branchCheckoutEstablishesHeadForAPartialRepository() {
        lateinit var captured: AgentRuntimeExecutionRequest
        val runtime = object : AgentProjectLinuxRuntime {
            override fun execute(request: AgentRuntimeExecutionRequest): AgentRuntimeExecutionResponse {
                captured = request
                return AgentRuntimeExecutionResponse(0, "", "", 5)
            }

            override fun rollback(workspaceId: String, checkpointId: String) = Unit
        }

        AgentLinuxProjectGitBackend(runtime, AgentProjectCredentialProvider { "" }).checkoutBranchAt(
            workspaceId = "phone-project",
            branch = "feature/context",
            create = true,
            baseRef = "refs/remotes/origin/main"
        )

        assertFalse(captured.source.contains("git reset"))
        assertTrue(captured.source.contains("__SIGNALASI_STAGE__:remove_stale_git_lock"))
        assertTrue(captured.source.contains("rm -f -- \"${'$'}index_lock\""))
        assertTrue(captured.source.contains("git checkout -q -B 'feature/context' 'refs/remotes/origin/main'"))
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
                    assertEquals(AgentRuntimeLanguage.SHELL, request.language)
                    val sourceFile = File(root, "git-launcher.sh").apply { writeText(request.source) }
                    val processBuilder = ProcessBuilder(requireNotNull(bash).absolutePath, sourceFile.absolutePath)
                        .directory(workspace)
                        .redirectErrorStream(false)
                    processBuilder.environment()["HOME"] = File(root, "git-home").apply { mkdirs() }.absolutePath
                    processBuilder.environment()["SIGNALASI_GIT_METADATA_ROOT"] =
                        File(root, "linux-git-metadata").absolutePath
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
            backend.inspect("smoke").also { snapshot ->
                assertEquals(AgentProjectRepositoryState.EMPTY, snapshot.state)
                assertTrue(snapshot.clean)
                assertTrue(snapshot.repositoryUrl.isBlank())
            }
            Git.init().setDirectory(workspace).call().close()
            backend.inspect("smoke").also { snapshot ->
                assertEquals(AgentProjectRepositoryState.PARTIAL, snapshot.state)
                assertTrue(snapshot.repositoryUrl.isBlank())
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

            assertEquals("# Linux clone smoke test", File(workspace, "README.md").readText().trim())
            assertTrue(File(workspace, ".git").isFile)
            assertTrue(File(root, "linux-git-metadata/workspace/objects").isDirectory)
            assertFalse(File(workspace, ".git/objects").exists())
            assertFalse(File(workspace, ".signalasi-runtime/repository").exists())
            assertFalse(File(workspace, ".signalasi-runtime/git-askpass.sh").exists())
            assertTrue(runtimeFiles.all(File::isFile))
            assertTrue(runtimeTemp.isDirectory)
            assertFalse(File(root, "git-home/.gitconfig").exists())
            backend.inspect("smoke").also { snapshot ->
                assertEquals(AgentProjectRepositoryState.READY, snapshot.state)
                assertEquals(remoteUrl, snapshot.repositoryUrl)
                assertEquals("main", snapshot.branch)
                assertTrue(snapshot.clean)
                assertTrue(Regex("[0-9a-f]{40}").matches(snapshot.headCommit))
            }
            val cleanFingerprint = backend.stateFingerprint("smoke")
            assertTrue(Regex("[0-9a-f]{64}").matches(cleanFingerprint))
            File(workspace, ".signalasi-stdout").writeText("runtime output changed")
            assertEquals(cleanFingerprint, backend.stateFingerprint("smoke"))
            val detachToUnborn = ProcessBuilder(
                requireNotNull(bash).absolutePath,
                "-lc",
                "git -c safe.directory=\"${'$'}PWD\" symbolic-ref HEAD refs/heads/feature/unborn"
            ).directory(workspace).start()
            assertEquals(detachToUnborn.errorStream.bufferedReader().readText(), 0, detachToUnborn.waitFor())
            backend.inspectMetadata("smoke").also { snapshot ->
                assertEquals(AgentProjectRepositoryState.PARTIAL, snapshot.state)
                assertEquals("feature/unborn", snapshot.branch)
                assertTrue(snapshot.headCommit.isBlank())
                assertFalse(snapshot.workingTreeInspected)
            }
            val restoreMain = ProcessBuilder(
                requireNotNull(bash).absolutePath,
                "-lc",
                "git -c safe.directory=\"${'$'}PWD\" symbolic-ref HEAD refs/heads/main"
            ).directory(workspace).start()
            assertEquals(restoreMain.errorStream.bufferedReader().readText(), 0, restoreMain.waitFor())
            assertEquals(remoteUrl, backend.remoteUrl("smoke", "origin"))

            File(workspace, "README.md").writeText("# Local Linux diff\n")
            assertFalse(cleanFingerprint == backend.stateFingerprint("smoke"))
            backend.inspect("smoke").also { snapshot ->
                assertFalse(snapshot.clean)
                assertEquals(listOf("README.md"), snapshot.modified)
            }
            assertTrue(backend.diff("smoke", 16 * 1024).contains("Local Linux diff"))
            val restore = ProcessBuilder(
                requireNotNull(bash).absolutePath,
                "-lc",
                "git -c safe.directory=\"${'$'}PWD\" checkout -- README.md"
            ).directory(workspace).start()
            assertEquals(restore.errorStream.bufferedReader().readText(), 0, restore.waitFor())

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

            backend.prepareAndInspect(
                workspaceId = "smoke",
                repositoryUrl = remoteUrl,
                baseBranch = "main",
                featureBranch = "improve/atomic-prepare",
                depth = 1,
                replaceExisting = false,
                cancellationToken = AgentNativeToolCancellationToken.NONE,
                progress = { _, _, _ -> }
            ).also { snapshot ->
                assertEquals("improve/atomic-prepare", snapshot.branch)
                assertEquals(AgentProjectRepositoryState.READY, snapshot.state)
            }
            File(workspace, "atomic.txt").writeText("preserved feature work\n")
            backend.commit(
                workspaceId = "smoke",
                message = "Create feature work",
                authorName = "SignalASI",
                authorEmail = "signalasi@hotmail.com"
            )
            assertEquals("preserved feature work", File(workspace, "atomic.txt").readText().trim())

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

            val replacementSource = File(root, "replacement-source")
            val replacementRemote = File(root, "replacement.git")
            Git.init().setDirectory(replacementSource).setInitialBranch("main").call().use { git ->
                File(replacementSource, "REPLACED.md").writeText("# Replacement repository\n")
                git.add().addFilepattern(".").call()
                git.commit()
                    .setMessage("Create replacement fixture")
                    .setAuthor("SignalASI", "signalasi@hotmail.com")
                    .setCommitter("SignalASI", "signalasi@hotmail.com")
                    .call()
            }
            Git.cloneRepository()
                .setURI(replacementSource.toURI().toString())
                .setDirectory(replacementRemote)
                .setBare(true)
                .call()
                .close()
            val replacementUrl = if (File.separatorChar == '\\') {
                "file:///${replacementRemote.canonicalPath.replace('\\', '/')}"
            } else {
                replacementRemote.toURI().toString()
            }
            val rejected = runCatching {
                backend.clone(
                    workspaceId = "smoke",
                    repositoryUrl = replacementUrl,
                    branch = "main",
                    depth = 1,
                    replaceExisting = false,
                    cancellationToken = AgentNativeToolCancellationToken.NONE,
                    progress = { _, _, _ -> }
                )
            }.exceptionOrNull()
            assertTrue(rejected?.message.orEmpty().contains("different repository"))
            assertTrue(File(workspace, "README.md").isFile)

            backend.clone(
                workspaceId = "smoke",
                repositoryUrl = replacementUrl,
                branch = "main",
                depth = 1,
                replaceExisting = true,
                cancellationToken = AgentNativeToolCancellationToken.NONE,
                progress = { _, _, _ -> }
            )
            assertTrue(File(workspace, "REPLACED.md").isFile)
            assertFalse(File(workspace, "README.md").exists())
            assertEquals(replacementUrl, backend.inspect("smoke").repositoryUrl)
        } finally {
            root.deleteRecursively()
        }
    }

}
