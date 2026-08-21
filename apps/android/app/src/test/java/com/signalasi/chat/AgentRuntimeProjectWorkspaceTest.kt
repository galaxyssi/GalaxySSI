package com.signalasi.chat

import java.io.File
import java.nio.file.Files
import java.util.zip.ZipFile
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class AgentRuntimeProjectWorkspaceTest {
    private lateinit var root: File
    private lateinit var runtimeRoot: File
    private lateinit var projectRoot: File
    private lateinit var manager: AgentRuntimeWorkspaceManager

    @Before
    fun setUp() {
        root = Files.createTempDirectory("signalasi-runtime-project-").toFile()
        runtimeRoot = File(root, "runtime")
        projectRoot = File(root, "projects")
        manager = AgentRuntimeWorkspaceManager(runtimeRoot, projectRoot, forTesting = true)
    }

    @After
    fun tearDown() {
        root.deleteRecursively()
    }

    @Test
    fun persistsProjectFilesAcrossIsolatedRuntimeRequests() {
        val project = File(projectRoot, "workspace-one").apply { mkdirs() }
        File(project, "README.md").writeText("first")

        val first = manager.prepare(request("run-one", "print('one')"))
        assertEquals("first", File(first.directory, "README.md").readText())
        File(first.directory, "result.txt").writeText("generated")
        File(first.directory, ".signalasi-stdout").writeText("private runtime output")
        val sync = manager.syncProject(first, 8L * 1024L * 1024L)

        assertTrue(sync.fileCount >= 2)
        assertEquals("generated", File(project, "result.txt").readText())
        assertFalse(File(project, "main.py").exists())
        assertFalse(File(project, ".signalasi-runtime").exists())
        assertFalse(File(project, "request.json").exists())
        assertFalse(File(project, ".signalasi-stdout").exists())

        val second = manager.prepare(request("run-two", "print('two')"))
        assertEquals("generated", File(second.directory, "result.txt").readText())
        assertEquals("first", File(second.directory, "README.md").readText())
        assertEquals("print('two')", second.sourceFile.readText())
        assertTrue(second.importedProjectBytes > 0L)
    }

    @Test
    fun productionRuntimeUsesOneStableProjectWithoutCopyingTheRepository() {
        val direct = AgentRuntimeWorkspaceManager(
            runtimeRoot = runtimeRoot,
            projectRoot = projectRoot,
            directExecution = true
        )
        val project = File(projectRoot, "workspace-one").apply { mkdirs() }
        File(project, ".git/info").mkdirs()
        File(project, ".git/refs/heads/main").apply {
            parentFile?.mkdirs()
            writeText("0123456789abcdef0123456789abcdef01234567\n")
        }
        File(project, ".git/HEAD").writeText("ref: refs/heads/main\n")
        File(project, "README.md").writeText("stable")

        val prepared = direct.prepare(request("run-direct", "print('direct')"))

        assertEquals(project.canonicalFile, prepared.directory.canonicalFile)
        assertEquals("/workspace/workspace-one", prepared.guestPath)
        assertEquals(0L, prepared.importedProjectBytes)
        assertTrue(prepared.direct)
        assertTrue(File(project, ".git/info/exclude").readText().contains("/.signalasi-runtime/"))
        assertTrue(
            File(prepared.metadataDirectory, "git-checkpoint.json").readText()
                .contains("0123456789abcdef0123456789abcdef01234567")
        )

        File(prepared.directory, "generated.txt").writeText("kept")
        val commit = direct.commitProject(prepared, 8L * 1024L * 1024L, "direct-checkpoint")
        assertEquals("kept", File(project, "generated.txt").readText())
        assertEquals(null, commit.checkpoint)

        direct.markFinished(prepared, AgentRuntimeReceiptStatus.COMPLETED)
        assertFalse(File(project, ".signalasi-runtime").exists())
        assertFalse(File(project, ".signalasi-inputs").exists())
        assertFalse(File(project, ".signalasi-tools").exists())
        assertTrue(File(prepared.metadataDirectory, "status.json").isFile)
    }

    @Test
    fun runtimeDriverCannotOverwriteOrPolluteAProjectEntrypoint() {
        val project = File(projectRoot, "workspace-one").apply { mkdirs() }
        File(project, "main.py").writeText("print('project entrypoint')")

        val prepared = manager.prepare(request("run-driver", "print('runtime driver')"))

        assertEquals("print('project entrypoint')", File(prepared.directory, "main.py").readText())
        assertEquals("print('runtime driver')", prepared.sourceFile.readText())
        assertTrue(prepared.sourceFile.relativeTo(prepared.directory).invariantSeparatorsPath.startsWith(".signalasi-runtime/"))
        File(prepared.directory, "generated.txt").writeText("candidate")
        manager.commitProject(
            prepared = prepared,
            byteLimit = 8L * 1024L * 1024L,
            checkpointId = "before-driver"
        )

        assertEquals("print('project entrypoint')", File(project, "main.py").readText())
        assertEquals("candidate", File(project, "generated.txt").readText())
        assertFalse(File(project, ".signalasi-runtime").exists())
    }

    @Test
    fun stagesHostInputsForOneRunWithoutPersistingThemInTheProject() {
        val archive = File(root, "project.tar.gz").apply { writeText("archive payload") }
        val prepared = manager.prepare(
            request("run-host-input", "print('import')").copy(
                hostInputFiles = listOf(
                    AgentRuntimeHostInput(archive, "archives/project.tar.gz")
                )
            )
        )

        val staged = File(prepared.directory, ".signalasi-inputs/archives/project.tar.gz")
        assertEquals("archive payload", staged.readText())
        File(prepared.directory, "imported.txt").writeText("project file")
        manager.syncProject(prepared, 8L * 1024L * 1024L)

        assertEquals("project file", File(projectRoot, "workspace-one/imported.txt").readText())
        assertFalse(File(projectRoot, "workspace-one/.signalasi-inputs").exists())
    }

    @Test
    fun rejectsUnsafeHostInputPaths() {
        val archive = File(root, "project.tar.gz").apply { writeText("archive payload") }
        val result = runCatching {
            manager.prepare(
                request("run-unsafe-input", "print('import')").copy(
                    hostInputFiles = listOf(AgentRuntimeHostInput(archive, "../project.tar.gz"))
                )
            )
        }

        assertTrue(result.isFailure)
    }

    @Test(expected = IllegalStateException::class)
    fun rejectsProjectSnapshotsThatExceedTheRuntimeQuota() {
        val prepared = manager.prepare(request("run-quota", "print('quota')"))
        File(prepared.directory, "large.bin").writeBytes(ByteArray(32 * 1024))
        manager.syncProject(prepared, 8 * 1024L)
    }

    @Test
    fun conversationScopeIsStableAndCannotBeOverriddenByToolArguments() {
        val first = AgentWorkspaceScope.id("conversation-a", "session-a")
        val repeated = AgentWorkspaceScope.id("conversation-a", "session-b")
        val other = AgentWorkspaceScope.id("conversation-b", "session-a")
        assertEquals(first, repeated)
        assertNotEquals(first, other)

        val bound = AgentWorkspaceScope.bindToolInput(
            AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
            mapOf("workspace_id" to "attacker", "path" to "notes.txt"),
            first
        )
        assertEquals(first, bound["workspace_id"])
        assertEquals("notes.txt", bound["path"])
    }

    @Test
    fun repositoryCloneCanonicalizesCommonModelUrlAliasesBeforeValidation() {
        listOf("url", "repo_url", "repository").forEach { alias ->
            val bound = AgentWorkspaceScope.bindToolInput(
                AgentMobileProjectNativeTools.CLONE,
                mapOf(alias to "https://github.com/signalasi/SignalASI", "workspace_id" to "attacker"),
                "conversation-project"
            )

            assertEquals("conversation-project", bound["workspace_id"])
            assertEquals("https://github.com/signalasi/SignalASI", bound["repository_url"])
            assertFalse(bound.containsKey(alias))
        }
    }

    @Test
    fun runtimeExecutionCanonicalizesCommonShellAliasesBeforeValidation() {
        val bound = AgentWorkspaceScope.bindToolInput(
            AgentOnDeviceRuntimeTools.EXECUTE,
            mapOf(
                "workspace_id" to "current",
                "language" to "bash",
                "command" to "node tools/dev/check-repo.js",
                "timeout_ms" to 300_000L,
                "verification_kind" to "test"
            ),
            "conversation-project"
        )

        assertEquals("shell", bound["language"])
        assertEquals("node tools/dev/check-repo.js", bound["source"])
        assertFalse(bound.containsKey("command"))
        assertFalse(bound.containsKey("workspace_id"))
    }

    @Test
    fun packagesMultipleFilesAndDirectoriesAsOneProjectArchive() {
        val request = request(
            requestId = "run-project",
            source = "print('project')",
            artifactPaths = listOf("src", "README.md")
        )
        val prepared = manager.prepare(request)
        File(prepared.directory, "src/lib").mkdirs()
        File(prepared.directory, "src/main.py").writeText("print('hello')")
        File(prepared.directory, "src/lib/value.py").writeText("VALUE = 7")
        File(prepared.directory, "README.md").writeText("# Sample")
        manager.syncProject(prepared, 8L * 1024L * 1024L)

        val artifact = manager.collectArtifacts(prepared, request).single()
        assertEquals("project_archive", artifact["artifact_kind"])
        assertEquals(3, artifact["file_count"])
        val archive = File(artifact.getValue("host_path").toString())
        assertTrue(archive.isFile)
        ZipFile(archive).use { zip ->
            assertEquals(
                setOf("src/main.py", "src/lib/value.py", "README.md"),
                zip.entries().asSequence().map { it.name }.toSet()
            )
        }
    }

    @Test
    fun discoversNewAndroidApkWhenModelOmitsArtifactPaths() {
        val request = request("run-apk", "./gradlew assembleDebug", emptyList())
        val prepared = manager.prepare(request)
        val apk = File(prepared.directory, "app/build/outputs/apk/debug/app-debug.apk").apply {
            requireNotNull(parentFile).mkdirs()
            writeBytes(byteArrayOf(1, 2, 3, 4))
        }

        val artifacts = manager.collectArtifacts(prepared, request)

        assertEquals(1, artifacts.size)
        assertEquals("app/build/outputs/apk/debug/app-debug.apk", artifacts.single()["relative_path"])
        assertEquals(apk.absolutePath, artifacts.single()["host_path"])
    }

    @Test
    fun doesNotDeliverUnchangedApkFromAnEarlierRun() {
        File(projectRoot, "workspace-one/app/build/outputs/apk/debug/app-debug.apk").apply {
            requireNotNull(parentFile).mkdirs()
            writeBytes(byteArrayOf(1, 2, 3, 4))
        }
        val request = request("run-stale-apk", "echo unchanged", emptyList())
        val prepared = manager.prepare(request)

        assertTrue(manager.collectArtifacts(prepared, request).isEmpty())
    }

    @Test
    fun explicitArtifactRemainsAuthoritativeWhenBuildOutputsAlsoChange() {
        val request = request("run-explicit", "echo report", listOf("report.txt"))
        val prepared = manager.prepare(request)
        File(prepared.directory, "report.txt").writeText("verified")
        File(prepared.directory, "app/build/outputs/apk/debug/app-debug.apk").apply {
            requireNotNull(parentFile).mkdirs()
            writeBytes(byteArrayOf(9, 8, 7))
        }

        val artifacts = manager.collectArtifacts(prepared, request)

        assertEquals(listOf("report.txt"), artifacts.map { it["relative_path"] })
    }

    @Test
    fun checkpointsAndAtomicallyRestoresTheDurableProject() {
        val project = File(projectRoot, "workspace-one").apply { mkdirs() }
        File(project, "README.md").writeText("stable")
        val checkpoint = manager.checkpoint(
            workspaceId = "workspace-one",
            checkpointId = "before-change",
            byteLimit = 8L * 1024L * 1024L
        )

        val prepared = manager.prepare(request("run-change", "print('change')"))
        File(prepared.directory, "README.md").writeText("changed")
        File(prepared.directory, "generated.txt").writeText("candidate")
        manager.syncProject(prepared, 8L * 1024L * 1024L)
        assertEquals("changed", File(project, "README.md").readText())
        assertTrue(File(project, "generated.txt").isFile)

        val restored = manager.rollback(
            workspaceId = "workspace-one",
            checkpointId = checkpoint.checkpointId,
            byteLimit = 8L * 1024L * 1024L
        )

        assertEquals(1, restored.fileCount)
        assertEquals("stable", File(project, "README.md").readText())
        assertFalse(File(project, "generated.txt").exists())
        assertFalse(File(project, "main.py").exists())
        val status = manager.workspaceStatus("workspace-one")
        assertEquals(1, status.fileCount)
        assertEquals(listOf("before-change"), status.checkpoints.map { it.checkpointId })
        assertFalse(status.publicValue().toString().contains(root.absolutePath))
    }

    @Test
    fun commitsCandidateAndPromotesPreviousProjectToARecoveryCheckpoint() {
        val project = File(projectRoot, "workspace-one").apply { mkdirs() }
        File(project, "value.txt").writeText("stable")
        val prepared = manager.prepare(request("run-commit", "print('candidate')"))
        File(prepared.directory, "value.txt").writeText("candidate")
        File(prepared.directory, "new.txt").writeText("created")

        val commit = manager.commitProject(
            prepared = prepared,
            byteLimit = 8L * 1024L * 1024L,
            checkpointId = "pre-run-commit"
        )

        assertEquals("candidate", File(project, "value.txt").readText())
        assertEquals("created", File(project, "new.txt").readText())
        val checkpoint = requireNotNull(commit.checkpoint)
        assertEquals("pre-run-commit", checkpoint.checkpointId)
        assertEquals(1, checkpoint.fileCount)
        assertTrue(commit.project.fileCount >= 2)

        manager.rollback(
            workspaceId = "workspace-one",
            checkpointId = checkpoint.checkpointId,
            byteLimit = 8L * 1024L * 1024L
        )
        assertEquals("stable", File(project, "value.txt").readText())
        assertFalse(File(project, "new.txt").exists())
        assertFalse(File(project, "main.py").exists())
    }

    @Test
    fun checkpointCannotBeRestoredIntoAnotherConversationWorkspace() {
        File(projectRoot, "workspace-one").apply {
            mkdirs()
            File(this, "private.txt").writeText("workspace one")
        }
        manager.checkpoint(
            workspaceId = "workspace-one",
            checkpointId = "private-checkpoint",
            byteLimit = 8L * 1024L * 1024L
        )

        val rejected = runCatching {
            manager.rollback(
                workspaceId = "workspace-two",
                checkpointId = "private-checkpoint",
                byteLimit = 8L * 1024L * 1024L
            )
        }

        assertTrue(rejected.isFailure)
        assertFalse(File(projectRoot, "workspace-two/private.txt").exists())
    }

    private fun request(
        requestId: String,
        source: String,
        artifactPaths: List<String> = listOf("result.txt")
    ) = AgentRuntimeExecutionRequest(
        language = AgentRuntimeLanguage.PYTHON,
        source = source,
        arguments = emptyList(),
        timeoutMillis = 1_000L,
        networkEnabled = false,
        artifactPaths = artifactPaths,
        workspaceId = "workspace-one",
        requestId = requestId,
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
