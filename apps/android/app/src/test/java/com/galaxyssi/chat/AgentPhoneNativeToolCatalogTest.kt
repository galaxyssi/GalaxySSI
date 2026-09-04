package com.galaxyssi.chat

import java.nio.file.Files
import java.nio.file.Path
import java.util.Comparator
import java.util.concurrent.atomic.AtomicInteger
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class AgentPhoneNativeToolCatalogTest {
    private lateinit var storageRoot: Path
    private lateinit var fileTools: AgentWorkspaceFileTools

    @Before
    fun setUp() {
        storageRoot = Files.createTempDirectory("agent-phone-native-catalog-")
        fileTools = AgentWorkspaceFileTools(storageRoot)
    }

    @After
    fun tearDown() {
        if (!::storageRoot.isInitialized || !Files.exists(storageRoot)) return
        Files.walk(storageRoot).use { paths ->
            paths.sorted(Comparator.reverseOrder()).forEach { Files.deleteIfExists(it) }
        }
    }

    @Test
    fun registersTheStableDefaultCatalogIds() {
        val registry = registry()
        val expected = setOf(
            "galaxyssi.workspace.initialize",
            "galaxyssi.workspace.directory.create",
            "galaxyssi.workspace.directory.list",
            "galaxyssi.workspace.file.stat",
            "galaxyssi.workspace.file.read.text",
            "galaxyssi.workspace.files.read.text.batch",
            "galaxyssi.workspace.file.read.bytes",
            "galaxyssi.workspace.file.write.text",
            "galaxyssi.workspace.files.write.text.batch",
            "galaxyssi.workspace.file.create.text",
            "galaxyssi.workspace.file.append.text",
            "galaxyssi.workspace.file.write.bytes",
            "galaxyssi.workspace.file.create.bytes",
            "galaxyssi.workspace.file.append.bytes",
            "galaxyssi.workspace.entry.move",
            "galaxyssi.workspace.entry.copy",
            "galaxyssi.workspace.entry.delete",
            "galaxyssi.workspace.file.search.text",
            "galaxyssi.workspace.files.search.text.batch",
            "galaxyssi.workspace.file.patch.exact",
            "galaxyssi.workspace.files.patch.exact.batch",
            "galaxyssi.workspace.file.diff.summary",
            "galaxyssi.workspace.file.sha256",
            "galaxyssi.workspace.zip.create",
            "galaxyssi.workspace.zip.list",
            "galaxyssi.workspace.zip.extract",
            "galaxyssi.agent_action.read.screen",
            "galaxyssi.agent_action.tap",
            "galaxyssi.agent_action.type.text",
            "galaxyssi.agent_action.swipe",
            "galaxyssi.agent_action.long.press",
            "galaxyssi.agent_action.delete.text",
            "galaxyssi.agent_action.paste.text",
            "galaxyssi.agent_action.copy.screen.text",
            "galaxyssi.agent_action.back",
            "galaxyssi.agent_action.home",
            "galaxyssi.agent_action.recents",
            "galaxyssi.agent_action.lock.screen",
            "galaxyssi.agent_action.open.app",
            "galaxyssi.agent_action.open.url",
            "galaxyssi.agent_action.set.alarm",
            "galaxyssi.agent_action.reply.notification"
        )

        assertEquals(expected, AgentPhoneNativeToolCatalog.toolIds)
        assertEquals(expected, registry.descriptors().map { it.id }.toSet())
        assertEquals(expected.size, registry.descriptors().size)
    }

    @Test
    fun exposesCompleteDefaultIdsWithoutBuildingAndroidExecutors() {
        val expected = linkedSetOf<String>().apply {
            addAll(AgentPhoneNativeToolCatalog.toolIds)
            addAll(AgentWebMediaNativeTools.toolIds)
            addAll(AgentWebIntelligenceNativeTools.toolIds)
            addAll(AgentHardwareNativeTools.toolIds)
            addAll(AgentVisibleCaptureNativeTools.toolIds)
            addAll(AgentNotificationNativeTools.toolIds)
            addAll(AgentAndroidSystemNativeTools.toolIds)
            addAll(AgentSystemEvidenceNativeTools.toolIds)
            addAll(AgentMcpNativeTools.toolIds)
            addAll(AgentMobileProjectArchiveTools.toolIds)
            addAll(AgentMobileProjectNativeTools.toolIds)
            addAll(AgentOnDeviceRuntimeTools.toolIds)
            addAll(AgentLinuxSoftwareNativeTools.toolIds)
            addAll(AgentSelfEvolutionNativeTools.toolIds)
            addAll(AgentDesktopRemoteNativeTools.toolIds)
        }

        assertEquals(expected, AgentPhoneNativeToolCatalog.defaultToolIds)
    }

    @Test
    fun probesPhoneCapabilitiesOncePerCatalogSnapshot() {
        val probes = AtomicInteger()
        val statuses = readyCapabilityStatuses()
        val registry = AgentPhoneNativeToolCatalog.createRegistry(
            workspaceFileTools = fileTools,
            actionExecutor = successfulActionExecutor(),
            screenProvider = { ScreenContext("GalaxySSI", pageTitle = "Agent") },
            capabilityStatusProvider = {
                probes.incrementAndGet()
                statuses
            }
        )

        registry.descriptors()
        registry.descriptors()

        assertEquals(1, probes.get())
    }

    @Test
    fun everyDefinitionCarriesCompletePolicyAndProvenance() {
        val registry = registry()

        registry.descriptors().forEach { descriptor ->
            assertTrue(descriptor.id, descriptor.inputSchema.document.isNotEmpty())
            assertTrue(descriptor.id, descriptor.outputSchema.document.isNotEmpty())
            assertTrue(descriptor.id, descriptor.capabilities.isNotEmpty())
            assertTrue(descriptor.id, descriptor.requiredPermissions.isNotEmpty())
            assertTrue(descriptor.id, descriptor.requiredConsents.isNotEmpty())
            assertTrue(descriptor.id, descriptor.timeoutMillis in 1..30_000)
            assertNotNull(descriptor.availability)

            val definition = registry.lookup(descriptor.id)
            assertNotNull(descriptor.id, definition)
            assertTrue(descriptor.id, definition!!.executorId.isNotBlank())
            assertTrue(descriptor.id, definition.provenanceMetadata.isNotEmpty())
        }
    }

    @Test
    fun onlyWorkspaceReadOperationsDeclareParallelExecution() {
        val registry = registry()
        val parallelIds = registry.descriptors()
            .filter { it.concurrency == AgentNativeToolConcurrency.PARALLEL_READ_ONLY }
            .mapTo(linkedSetOf()) { it.id }

        assertEquals(
            linkedSetOf(
                AgentPhoneNativeToolCatalog.WORKSPACE_LIST,
                AgentPhoneNativeToolCatalog.WORKSPACE_STAT,
                AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
                AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT_BATCH,
                AgentPhoneNativeToolCatalog.WORKSPACE_READ_BYTES,
                AgentPhoneNativeToolCatalog.WORKSPACE_SEARCH_TEXT,
                AgentPhoneNativeToolCatalog.WORKSPACE_SEARCH_TEXT_BATCH,
                AgentPhoneNativeToolCatalog.WORKSPACE_DIFF_SUMMARY,
                AgentPhoneNativeToolCatalog.WORKSPACE_SHA256,
                AgentPhoneNativeToolCatalog.WORKSPACE_ZIP_LIST
            ),
            parallelIds
        )
        assertEquals(
            AgentNativeToolConcurrency.SERIAL,
            registry.lookup(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT)?.descriptor?.concurrency
        )
        assertEquals(
            AgentNativeToolConcurrency.SERIAL,
            registry.lookup(AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH)?.descriptor?.concurrency
        )
    }

    @Test
    fun executesBoundedWorkspaceFileAndZipToolsThroughRegistry() {
        val registry = registry()

        val initialized = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_INITIALIZE,
            mapOf("workspace_id" to "task-7"),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_CONSENT)
        )
        assertTrue(initialized.toJson(), initialized.isSuccess)

        val written = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
            mapOf(
                "workspace_id" to "task-7",
                "path" to "docs/note.txt",
                "text" to "hello phone registry",
                "create_parents" to true
            ),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_CONSENT)
        )
        assertTrue(written.toJson(), written.isSuccess)
        assertEquals("write", written.output["kind"])
        assertEquals("galaxyssi.workspace_file_tools", written.provenance.executorId)
        assertEquals("app_private", written.provenance.metadata["storage_scope"])

        val deniedRead = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
            mapOf("workspace_id" to "task-7", "path" to "docs/note.txt"),
            AgentNativeToolInvocationContext(
                grantedPermissions = setOf(AgentPhoneNativeToolCatalog.WORKSPACE_PRIVATE_PERMISSION)
            )
        )
        assertTrue(deniedRead.toJson(), deniedRead.isSuccess)
        assertEquals("hello phone registry", deniedRead.output["text"])

        val read = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
            mapOf("workspace_id" to "task-7", "path" to "docs/note.txt"),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_READ_CONSENT)
        )
        assertTrue(read.toJson(), read.isSuccess)
        assertEquals("hello phone registry", read.output["text"])
        assertEquals(64, (read.output["sha256"] as String).length)

        registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
            mapOf(
                "workspace_id" to "task-7",
                "path" to "docs/range.txt",
                "text" to "one\ntwo\nthree\nfour\n",
                "create_parents" to true
            ),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_CONSENT)
        )
        val ranged = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
            mapOf(
                "workspace_id" to "task-7",
                "path" to "docs/range.txt",
                "start_line" to 2,
                "max_lines" to 2
            ),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_READ_CONSENT)
        )
        assertTrue(ranged.toJson(), ranged.isSuccess)
        assertEquals("two\nthree\n", ranged.output["text"])
        assertEquals(2, ranged.output["start_line"])
        assertEquals(3, ranged.output["end_line"])
        assertEquals(4, ranged.output["total_lines"])
        assertEquals(true, ranged.output["truncated_before"])
        assertEquals(true, ranged.output["truncated_after"])

        val batchRead = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT_BATCH,
            mapOf(
                "workspace_id" to "task-7",
                "files" to listOf(
                    mapOf("path" to "docs/note.txt"),
                    mapOf("path" to "docs/range.txt", "start_line" to 3, "max_lines" to 1)
                )
            ),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_READ_CONSENT)
        )
        assertTrue(batchRead.toJson(), batchRead.isSuccess)
        assertEquals(2, batchRead.output["file_count"])
        assertEquals(2, batchRead.output["changed_file_count"])
        assertEquals(0, batchRead.output["unchanged_file_count"])
        assertTrue((batchRead.output["scanned_bytes"] as Long) > 0L)
        val batchFiles = batchRead.output["files"] as List<*>
        assertEquals("hello phone registry", (batchFiles[0] as Map<*, *>)["text"])
        assertEquals("three\n", (batchFiles[1] as Map<*, *>)["text"])

        val conditionalBatch = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT_BATCH,
            mapOf(
                "workspace_id" to "task-7",
                "files" to batchFiles.mapIndexed { index, raw ->
                    val file = raw as Map<*, *>
                    buildMap<String, Any?> {
                        put("path", file["path"])
                        put("known_sha256", file["sha256"])
                        if (index == 1) {
                            put("start_line", 3)
                            put("max_lines", 1)
                        }
                    }
                }
            ),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_READ_CONSENT)
        )
        assertTrue(conditionalBatch.toJson(), conditionalBatch.isSuccess)
        assertEquals(0, conditionalBatch.output["changed_file_count"])
        assertEquals(2, conditionalBatch.output["unchanged_file_count"])
        assertEquals(0L, conditionalBatch.output["returned_bytes"])
        val conditionalFiles = conditionalBatch.output["files"] as List<*>
        assertTrue(conditionalFiles.all { (it as Map<*, *>)["unchanged"] == true })
        assertTrue(conditionalFiles.all { (it as Map<*, *>)["text"] == "" })

        val firstListingPage = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_LIST,
            mapOf(
                "workspace_id" to "task-7",
                "path" to "docs",
                "recursive" to true,
                "max_entries" to 1
            ),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_READ_CONSENT)
        )
        assertTrue(firstListingPage.toJson(), firstListingPage.isSuccess)
        assertEquals(true, firstListingPage.output["truncated"])
        assertEquals("docs/note.txt", firstListingPage.output["next_cursor"])
        assertEquals(0, firstListingPage.output["skipped_directories"])

        val secondListingPage = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_LIST,
            mapOf(
                "workspace_id" to "task-7",
                "path" to "docs",
                "recursive" to true,
                "max_entries" to 1,
                "cursor" to firstListingPage.output["next_cursor"]
            ),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_READ_CONSENT)
        )
        assertTrue(secondListingPage.toJson(), secondListingPage.isSuccess)
        assertEquals(false, secondListingPage.output["truncated"])
        assertEquals("", secondListingPage.output["next_cursor"])

        val searched = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_SEARCH_TEXT,
            mapOf(
                "workspace_id" to "task-7",
                "path" to "docs",
                "query" to "three",
                "include_generated" to true
            ),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_READ_CONSENT)
        )
        assertTrue(searched.toJson(), searched.isSuccess)
        assertEquals(0, searched.output["skipped_directories"])
        assertEquals(1, (searched.output["matches"] as List<*>).size)

        val batchSearched = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_SEARCH_TEXT_BATCH,
            mapOf(
                "workspace_id" to "task-7",
                "path" to "docs",
                "queries" to listOf(
                    mapOf("query" to "three", "max_results" to 10),
                    mapOf("query" to "missing", "max_results" to 10)
                ),
                "include_generated" to true
            ),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_READ_CONSENT)
        )
        assertTrue(batchSearched.toJson(), batchSearched.isSuccess)
        assertEquals(2, batchSearched.output["scanned_files"])
        assertEquals(1, batchSearched.output["total_matches"])
        val batchResults = batchSearched.output["results"] as List<*>
        assertEquals(2, batchResults.size)
        assertEquals(1, ((batchResults[0] as Map<*, *>)["matches"] as List<*>).size)
        assertTrue(((batchResults[1] as Map<*, *>)["matches"] as List<*>).isEmpty())

        val zipped = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_ZIP_CREATE,
            mapOf(
                "workspace_id" to "task-7",
                "archive_path" to "artifacts/docs.zip",
                "source_paths" to listOf("docs"),
                "create_parents" to true
            ),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_CONSENT, "zip-create-1")
        )
        assertTrue(zipped.toJson(), zipped.isSuccess)
        assertTrue((zipped.output["entries"] as List<*>).isNotEmpty())

        val listed = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_ZIP_LIST,
            mapOf("workspace_id" to "task-7", "archive_path" to "artifacts/docs.zip"),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_READ_CONSENT)
        )
        assertTrue(listed.toJson(), listed.isSuccess)
        assertEquals("artifacts/docs.zip", listed.output["archive_path"])

        val extracted = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_ZIP_EXTRACT,
            mapOf(
                "workspace_id" to "task-7",
                "archive_path" to "artifacts/docs.zip",
                "destination_path" to "restored"
            ),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_CONSENT, "zip-extract-1")
        )
        assertTrue(extracted.toJson(), extracted.isSuccess)
        assertTrue((extracted.output["extracted_entries"] as Number).toInt() > 0)

        val restored = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
            mapOf("workspace_id" to "task-7", "path" to "restored/docs/note.txt"),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_READ_CONSENT)
        )
        assertEquals("hello phone registry", restored.output["text"])
    }

    @Test
    fun writesACompleteTextProjectInOneBoundedToolCall() {
        val registry = registry()
        val result = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT_BATCH,
            mapOf(
                "workspace_id" to "android-project",
                "files" to listOf(
                    mapOf("path" to "settings.gradle.kts", "text" to "rootProject.name = \"PhoneApp\""),
                    mapOf("path" to "app/build.gradle.kts", "text" to "plugins { id(\"com.android.application\") }")
                ),
                "overwrite" to true
            ),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_CONSENT)
        )

        assertTrue(result.toJson(), result.isSuccess)
        assertEquals(2, result.output["affected_entries"])
        assertEquals(
            "rootProject.name = \"PhoneApp\"",
            String(Files.readAllBytes(storageRoot.resolve("android-project/settings.gradle.kts")), Charsets.UTF_8)
        )
        assertTrue(Files.exists(storageRoot.resolve("android-project/app/build.gradle.kts")))
    }

    @Test
    fun appliesIndependentProjectEditsInOneAtomicToolCall() {
        val registry = registry()
        listOf("one.kt" to "val one = 1", "two.kt" to "val two = 2").forEach { (path, text) ->
            val created = registry.invoke(
                AgentPhoneNativeToolCatalog.WORKSPACE_CREATE_TEXT,
                mapOf("workspace_id" to "patch-project", "path" to path, "text" to text),
                workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_CONSENT, "create-$path")
            )
            assertTrue(created.toJson(), created.isSuccess)
        }

        val result = registry.invoke(
            AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH_BATCH,
            mapOf(
                "workspace_id" to "patch-project",
                "patches" to listOf(
                    mapOf("path" to "one.kt", "expected_text" to "one = 1", "replacement_text" to "one = 10"),
                    mapOf(
                        "path" to "two.kt",
                        "expected_text" to "two = 2",
                        "replacement_text" to "two = 20",
                        "expected_occurrences" to 1
                    )
                )
            ),
            workspaceContext(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_CONSENT, "patch-batch-1")
        )

        assertTrue(result.toJson(), result.isSuccess)
        assertEquals(2, result.output["affected_entries"])
        assertEquals(2, (result.output["patches"] as List<*>).size)
        assertEquals(
            "val one = 10",
            String(Files.readAllBytes(storageRoot.resolve("patch-project/one.kt")), Charsets.UTF_8)
        )
        assertEquals(
            "val two = 20",
            String(Files.readAllBytes(storageRoot.resolve("patch-project/two.kt")), Charsets.UTF_8)
        )
    }

    @Test
    fun adaptsExistingActionExecutorAndBoundsItsResult() {
        var captured: AgentAction? = null
        val longMessage = "m".repeat(3_000)
        val executor = object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                captured = action
                return AgentActionResult(
                    actionId = action.id,
                    success = true,
                    message = longMessage,
                    metadata = (1..50).associate { "key-$it" to "v".repeat(2_000) }
                )
            }
        }
        val registry = registry(executor, readyCapabilityStatuses())
        val toolId = AgentNativeToolAgentActionAdapter.defaultToolId(AgentActionKind.READ_SCREEN)
        val descriptor = registry.lookup(toolId)!!.descriptor
        val result = registry.invoke(
            toolId,
            mapOf("target" to "current screen", "parameters" to emptyMap<String, String>()),
            AgentNativeToolInvocationContext(
                invocationId = "screen-read-1",
                grantedPermissions = descriptor.requiredPermissions.filter { it.required }.mapTo(mutableSetOf()) { it.id },
                grantedConsents = descriptor.requiredConsents.filter { it.required }.mapTo(mutableSetOf()) { it.id }
            )
        )

        assertTrue(result.toJson(), result.isSuccess)
        assertEquals(AgentActionKind.READ_SCREEN, captured?.kind)
        assertFalse(captured?.requiresConfirmation == true)
        assertEquals(2_048, result.message.length)
        assertEquals(32, (result.output["metadata"] as Map<*, *>).size)
        assertTrue((result.output["metadata"] as Map<*, *>).values.all { it.toString().length <= 1_024 })
        assertEquals("galaxyssi.android_agent_action", result.provenance.executorId)
        assertEquals("READ_SCREEN", result.provenance.metadata["legacy_action_kind"])
    }

    private fun registry(
        executor: AgentActionExecutor = successfulActionExecutor(),
        statuses: List<AgentPhoneCapabilityStatus>? = null
    ): AgentNativeToolRegistry = AgentPhoneNativeToolCatalog.createRegistry(
        workspaceFileTools = fileTools,
        actionExecutor = executor,
        screenProvider = { ScreenContext("GalaxySSI", pageTitle = "Agent") },
        capabilityStatusProvider = statuses?.let { captured -> { captured } }
            ?: { AgentPhoneCapabilityCatalog.capabilities.map { boundary ->
                AgentPhoneCapabilityStatus(boundary, boundary.availability, boundary.limitation)
            } }
    )

    private fun workspaceContext(
        consent: String,
        idempotencyKey: String? = null
    ) = AgentNativeToolInvocationContext(
        idempotencyKey = idempotencyKey,
        grantedPermissions = setOf(AgentPhoneNativeToolCatalog.WORKSPACE_PRIVATE_PERMISSION),
        grantedConsents = setOf(consent)
    )

    private fun successfulActionExecutor() = object : AgentActionExecutor {
        override fun execute(action: AgentAction, screen: ScreenContext) = AgentActionResult(
            actionId = action.id,
            success = true,
            message = "Executed"
        )
    }

    private fun readyCapabilityStatuses() = AgentPhoneCapabilityCatalog.capabilities.map { boundary ->
        AgentPhoneCapabilityStatus(
            boundary = boundary,
            availability = AgentPhoneCapabilityAvailability.READY,
            evidence = "Ready for test"
        )
    }
}
